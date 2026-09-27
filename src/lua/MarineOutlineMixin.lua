-- ======= Copyright (c) 2013, Unknown Worlds Entertainment, Inc. All rights reserved. ==========
--
-- lua\MarineOutlineMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

MarineOutlineMixin = CreateMixin( MarineOutlineMixin )
MarineOutlineMixin.type = "MarineOutline"

MarineOutlineMixin.expectedMixins =
{
    Model = "For copying bonecoords and drawing model in view model render zone.",
}

function MarineOutlineMixin:__initmixin()
    
    PROFILE("MarineOutlineMixin:__initmixin")
    
    if Client then
        self.marineOutlineVisible = false
    end

end

if Client then

    function MarineOutlineMixin:OnDestroy()

        if self.marineOutlineVisible then
            local model = self:GetRenderModel()
            if model ~= nil then
                EquipmentOutline_RemoveModel( model )
            end
        end
        
    end

    function MarineOutlineMixin:OnModelChanged()
        self.marineOutlineVisible = false
    end

    local regenFieldOrigins = {}
    local numRegenFields = 0
    local regenFieldTeamNumber
    local regenOutlineColor
    local viewerIsCommander = false
    local timeRegenFieldsUpdated

    local function UpdateRegenFields(player, now)

        timeRegenFieldsUpdated = now
        numRegenFields = 0
        viewerIsCommander = player ~= nil and player:isa("MarineCommander")

        if viewerIsCommander then

            regenFieldTeamNumber = player:GetTeamNumber()
            for _, exo in ientitylist(Shared.GetEntitiesWithClassname("Exo")) do
                if exo.timeRegenFieldEnd > now and exo:GetTeamNumber() == regenFieldTeamNumber and exo:GetIsAlive() then
                    numRegenFields = numRegenFields + 1
                    regenFieldOrigins[numRegenFields] = exo:GetOrigin()
                end
            end

        elseif player and player.abilityModuleType == kExoModuleTypes.NanoRepair and player.timeRegenFieldEnd > now and player:GetIsAlive() then

            regenFieldTeamNumber = player:GetTeamNumber()
            numRegenFields = 1
            regenFieldOrigins[1] = player:GetOrigin()

        end

        if numRegenFields > 0 then
            regenOutlineColor = Client.GetOptionFloat(kColorBlindOptionsKey, 0) ~= 0 and kEquipmentOutlineColor.Orange or kEquipmentOutlineColor.Green
        end

    end

    local function GetIsInRegenField(self)

        if not self:isa("Marine") or self:GetTeamNumber() ~= regenFieldTeamNumber or not self:GetIsAlive() or self:GetHealth() >= self:GetMaxHealth() then
            return false
        end

        local origin = self:GetOrigin()
        local radiusSquared = kExoSupportRadius * kExoSupportRadius
        for i = 1, numRegenFields do
            if origin:GetDistanceSquared(regenFieldOrigins[i]) < radiusSquared then
                return true
            end
        end

        return false

    end

    function MarineOutlineMixin:OnUpdate(deltaTime)   
        PROFILE("MarineOutlineMixin:OnUpdate")
        local player = Client.GetLocalPlayer()
        
        local model = self:GetRenderModel()
        if model ~= nil then 

            local hasCatPackBoost = HasMixin(self, "CatPack") and self:GetHasCatPackBoost()

            local now = Shared.GetTime()
            if now ~= timeRegenFieldsUpdated then
                UpdateRegenFields(player, now)
            end

            local inRegenField = numRegenFields > 0 and not (viewerIsCommander and hasCatPackBoost) and GetIsInRegenField(self)
            local pilotCatalyst = hasCatPackBoost and player and player.abilityModuleType == kExoModuleTypes.CatPack and self:isa("Marine") and self:GetTeamNumber() == player:GetTeamNumber()
                                    and (self:GetOrigin() - player:GetOrigin()):GetLengthSquared() < kExoSupportRadius * kExoSupportRadius

            local outlineModel = Client.GetOutlinePlayers() and 
                                    ( Client.GetLocalClientTeamNumber() == kSpectatorIndex or
                                      viewerIsCommander and hasCatPackBoost or inRegenField or pilotCatalyst )
       
            local outlineColor
            if inRegenField then
                outlineColor = regenOutlineColor
            elseif hasCatPackBoost then
                outlineColor = kEquipmentOutlineColor.Fuchsia
            elseif HasMixin(self, "ParasiteAble") and self:GetIsParasited() then
                outlineColor = kEquipmentOutlineColor.Yellow
            else
                outlineColor = kEquipmentOutlineColor.TSFBlue
            end

            outlineModel = outlineModel == true
            if outlineModel ~= self.marineOutlineVisible or outlineModel and outlineColor ~= self.marineOutlineColor then

                EquipmentOutline_RemoveModel( model )
                if outlineModel then
                    EquipmentOutline_AddModel( model, outlineColor )
                    self.marineOutlineColor = outlineColor
                end

                self.marineOutlineVisible = outlineModel
            end

        end
            
    end

end