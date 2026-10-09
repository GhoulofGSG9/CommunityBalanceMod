-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\PropDynamic.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/ScriptActor.lua")
Script.Load("lua/Mixins/ModelMixin.lua")
Script.Load("lua/Mixins/SignalEmitterMixin.lua")
Script.Load("lua/PowerConsumerMixin.lua")
Script.Load("lua/OnShadowOptionMixin.lua")

class 'PropDynamic' (ScriptActor)

local networkVars = { }

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ModelMixin, networkVars)
AddMixinNetworkVars(PowerConsumerMixin, networkVars)

function PropDynamic:OnCreate()

    ScriptActor.OnCreate(self)
    
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ModelMixin)
    InitMixin(self, SignalEmitterMixin)
    InitMixin(self, PowerConsumerMixin)

    if Client then

        InitMixin(self, OnShadowOptionMixin)
        self.hidden = self:UpdateHiddenState()
    end

    if Server then
        self:SetUpdates(true, kRealTimeUpdateRate)
    end
    
    self.emitChannel = 0
    
end

function PropDynamic:GetRequiresPower()
    return true
end

function PropDynamic:GetCanBeUsed(player, useSuccessTable)
    useSuccessTable.useSuccess = false
end

if Server then

    -- A looping prop (fan blades) only needs its collision pose refreshed at this rate.
    local kLoopingPhysicsInterval = 0.1

    function PropDynamic:GetCanSkipPhysics()

        local settled, looping = self:GetAnimationSettled()
        if settled then
            return true
        end

        return looping and (self.lastPhysicsUpdateTime or 0) + kLoopingPhysicsInterval > Shared.GetTime()

    end

    function PropDynamic:OnInitialized()

        ScriptActor.OnInitialized(self)

        self.modelName = self.model
        self.propScale = self.scale
        self.decalsOn = self.decalsEnabled
        self.avHighlightEnabled = self.avHighlight

        if self.modelName ~= nil and GetFileExists(self.modelName) then

            Shared.PrecacheModel(self.modelName)

            local graphName = string.gsub(self.modelName, ".model", ".animation_graph")
            Shared.PrecacheAnimationGraph(graphName)

            self:SetModel(self.modelName, graphName)
            self:SetAnimationInput("animation", self.animation)

        else
            Shared.Message("Missing or invalid dynamic prop!")
        end

        -- Don't collide when commanding if not full alpha
        self.commAlpha = GetAndCheckValue(self.commAlpha, 0, 1, "commAlpha", 1, true)

        -- Test against false so that the default is true
        if self.collidable ~= false then
            self:SetPhysicsType(PhysicsType.None)
        else

            if self.dynamic then
                self:SetPhysicsType(PhysicsType.DynamicServer)
                self:SetPhysicsGroup(PhysicsGroup.RagdollGroup)
            else
                self:SetPhysicsType(PhysicsType.Kinematic)
            end

            -- Make it not block selection and structure placement (GetCommanderPickTarget)
            if self.commAlpha < 1 then
                self:SetPhysicsGroup(PhysicsGroup.CommanderPropsGroup)
            end

        end

        self:SetIsVisible(true)

        self:UpdateRelevancyMask()

    end

    function PropDynamic:UpdateRelevancyMask()

        local mask = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToReadyRoom)
        if self.commAlpha == 1 then
            mask = bit.bor(mask, kRelevantToTeam1Commander, kRelevantToTeam2Commander)
        end

        self:SetExcludeRelevancyMask( mask )
        self:SetRelevancyDistance( kMaxRelevancyDistance )

    end

end

if Client then

    -- prop dynamics are commonly associated with dramatic shadows, so
    -- they must not be physics culled when shadows are on
    function PropDynamic:OnShadowOptionChanged(shadowOption)
        self:SetPhysicsCullable(not shadowOption)
    end

    --[[
        TODO(Salads): PropDynamic client-side hiding (MapParticles Option NS2+)

        Currently uses OnUpdateRender because the server will sync up the model index, causing the hidden state to revert.
        Hiding the model every render frame is kinda gross, though.
    ]]--
    function PropDynamic:OnUpdateRender() --FIXME Use buffered-state instead of every frame

        if self:GetRenderModel() ~= nil then

            if not self.hidden then
                local active = ConditionalValue(self.powered, 0, 1)
                self:GetRenderModel():SetMaterialParameter("hiddenAmount", active ) --Emissive shader
                self:GetRenderModel():SetMaterialParameter("emissiveMod", active )  --Others (model, model_emissive, etc)
            else
                self:SetModel(nil)
                self.hiddenModel = true -- There's a small window where commAlpha is nil
            end

        -- BaseModelMixin would revert the hidden state from netvars, but we need to update the commander alpha stuff.
        elseif self.hiddenModel and not self.hidden then

            local animationGraph = ConditionalValue(self.animationGraphIndex > 0, self.animationGraphIndex, nil)
            local model = ConditionalValue(self.modelIndex > 0, self.modelIndex, nil)

            if model then
                model = Shared.GetModelName(model)
            end

            if animationGraph then
                animationGraph = Shared.GetAnimationGraphName(animationGraph)
            end

            self:SetModel(model, animationGraph)
            local player = Client.GetLocalPlayer()
            if player and self.commAlpha < 1 then
                self:SetIsVisible(not player:isa("Commander"))
            end

            self.hiddenModel = false
        end
    end

    -- Server calls OnCreate, then OnInitialized right after in one go of it, so the model index should be set by this time.
    function PropDynamic:OnInitialized()
        self:UpdateHiddenState()
    end

    function PropDynamic:UpdateHiddenState()
        self.hidden = (not Client.kMapParticlesEnabled) and MapParticlesOption_IsPropnameBlockable(Shared.GetModelName(self.modelIndex))
    end

end

--
-- Emit all animation tags out as signals to possibly affect other entities.
--
function PropDynamic:OnTag(tagName)
    PROFILE("PropDynamic:OnTag")
    self:EmitSignal(self.emitChannel, tagName)
end

Shared.LinkClassToMap("PropDynamic", "prop_dynamic", networkVars)