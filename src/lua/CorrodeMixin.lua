-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\CorrodeMixin.lua
--
--    Created by:   Andrew Spiering (andrew@unknownworlds.com) and
--                  Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

CorrodeMixin = CreateMixin( CorrodeMixin )
CorrodeMixin.type = "Corrode"

PrecacheAsset("cinematics/vfx_materials/bilebomb.surface_shader")
PrecacheAsset("cinematics/vfx_materials/bilebomb_exoview.surface_shader")

local kBilebombMaterial = PrecacheAsset("cinematics/vfx_materials/bilebomb.material")
local kBilebombExoMaterial = PrecacheAsset("cinematics/vfx_materials/bilebomb_exoview.material")

CorrodeMixin.networkVars =
{
    isCorroded = "boolean"
}

local kCorrodeShaderDuration = 4

function CorrodeMixin:CorrodeOnInfestation()

    if self:GetMaxArmor() == 0 then
        self.corrodeOnInfestationTimerActive = false
        return false
    end

    if self.updateInitialInfestationCorrodeState and GetIsPointOnInfestation(self:GetOrigin()) then
    
        self:SetGameEffectMask(kGameEffect.OnInfestation, true)
        self.updateInitialInfestationCorrodeState = false
        
    end

    if self:GetGameEffectMask(kGameEffect.OnInfestation) and self:GetCanTakeDamage() and (not HasMixin(self, "GhostStructure") or not self:GetIsGhostStructure()) then
        
        self:SetCorroded()

        -- No point in dealing armor only damage to a unit without armor left
        -- Stops spamming marine commanders with "Your base is under attack" alerts
        if self:GetArmor() > 0 then
            if self:isa("PowerPoint") then
                self:DoDamageLighting()
            end

            self:DeductHealth(kInfestationCorrodeDamagePerSecond, nil, nil, false, true, true)
        end
        
    end

    return true

end

function CorrodeMixin:__initmixin()
    if Server then
        PROFILE("CorrodeMixin:__initmixin")
        
        self.isCorroded = false
        self.timeCorrodeStarted = 0
        
        if not self:isa("Player") and not self:isa("MAC") and not self:isa("Exosuit") and kCorrodeMarineStructureArmorOnInfestation then
            self:StartCorrodeOnInfestation()
        end
        
    end
end

function CorrodeMixin:OnDestroy()
    
    if Client and self.corrodeMaterial then
        Client.DestroyRenderMaterial(self.corrodeMaterial)
        self.corrodeMaterial = nil
    end    
    
end

CorrodeMixin.kCorrodeDamageTypes = {
    [kDamageType.Corrode] = true,
    [kDamageType.ArmorOnly] = true
}

function CorrodeMixin:GetIsCorroded()
    return self.isCorroded
end

if Server then

    function CorrodeMixin:OnTakeDamage(damage, attacker, doer, point, direction)
        if doer and doer.GetDamageType and CorrodeMixin.kCorrodeDamageTypes[doer:GetDamageType()] then
            self:SetCorroded()
        end
    end

    function CorrodeMixin:StartCorrodeOnInfestation()

        self.corrodeOnInfestationTimerActive = true
        self.updateInitialInfestationCorrodeState = true

        self:AddTimedCallback(self.CorrodeOnInfestation, 1)
    end

    function CorrodeMixin:SetCorroded()
        self.isCorroded = true
        self.timeCorrodeStarted = Shared.GetTime()
    end

    function CorrodeMixin:SetMaxArmor(setMax)
        -- corrodeOnInfestationTimerActive == nil means that corrode on infestation is disabled for this entity
        if self.corrodeOnInfestationTimerActive == false and setMax > 0 then
            self:StartCorrodeOnInfestation()
        end
    end
    
end

local function UpdateCorrodeMaterial(self)

    if self._renderModel then
    
        if self.isCorroded and not self.corrodeMaterial then

            local material = Client.CreateRenderMaterial()
            material:SetMaterial(kBilebombMaterial)
            
            if self:isa("Player") then
                material:SetParameter("highlight", 1)
            end

            local viewMaterial = Client.CreateRenderMaterial()
            if self:isa("Exo") then
                viewMaterial:SetMaterial(kBilebombExoMaterial)
            else
                viewMaterial:SetMaterial(kBilebombMaterial)
            end
            
            self.corrodeEntities = {}
            self.corrodeMaterial = material
            self.corrodeMaterialViewMaterial = viewMaterial
            AddMaterialEffect(self, material, viewMaterial, self.corrodeEntities)
        
        elseif not self.isCorroded and self.corrodeMaterial then

            RemoveMaterialEffect(self.corrodeEntities, self.corrodeMaterial, self.corrodeMaterialViewMaterial)
            Client.DestroyRenderMaterial(self.corrodeMaterial)
            Client.DestroyRenderMaterial(self.corrodeMaterialViewMaterial)
            self.corrodeMaterial = nil
            self.corrodeMaterialViewMaterial = nil
            self.corrodeEntities = nil
            
        end
        
    end
    
end

local function CheckTunnelCorrode(self)

    if (not self.timeLastTunnelCorrodeCheck or self.timeLastTunnelCorrodeCheck + 1 < Shared.GetTime() ) and GetIsPointInGorgeTunnel(self:GetOrigin()) then
        
        -- drain armor only
        self:DeductHealth(kGorgeArmorTunnelDamagePerSecond, nil, nil, false, true)
        
        self.isCorroded = true
        self.timeCorrodeStarted = Shared.GetTime()
        self.timeLastTunnelCorrodeCheck = Shared.GetTime()

    end

end

local function SharedUpdate(self, deltaTime)
    PROFILE("CorrodeMixin:OnUpdate")
    
    if Server then
    
        if self.isCorroded and self.timeCorrodeStarted + kCorrodeShaderDuration < Shared.GetTime() then        
            self.isCorroded = false   
        end
        
        CheckTunnelCorrode(self)
        
    elseif Client then
        UpdateCorrodeMaterial(self)
    end
    
end


function CorrodeMixin:OnUpdate(deltaTime)   
    SharedUpdate(self, deltaTime)
end

function CorrodeMixin:OnProcessMove(input)   
    SharedUpdate(self, input.time)
end

if Server then

    function OnCommandCorrode(client)

        if Shared.GetCheatsEnabled() then
            
            local player = client:GetControllingPlayer()
            if player.SetCorroded then
                player:SetCorroded()
            end
            
        end

    end

    Event.Hook("Console_corrode",                 OnCommandCorrode)

end