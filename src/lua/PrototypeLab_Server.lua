-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\PrototypeLab.lua
--
--    Created by:   Andreas Urwalek (a_urwa@sbox.tugraz.at)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

local function OnDeploy(self)

    self.deployed = true
    return false
    
end

local kDeployTime = 5.5

-- Power loss aborts research (ResearchMixin:OnPowerOff), so restart it once powered again.
-- A commander cancel holds it instead: while researching, Cancel takes the Recycle button's slot.
local function UpdateExoLabUpgrade(self)

    if self:GetTechId() ~= kTechId.PrototypeLab then
        return false
    end

    if self:GetResearchingId() == kTechId.None and not self.exoUpgradeHeld and GetIsUnitActive(self) then

        local team = self:GetTeam()
        local techTree = team:GetTechTree()
        local techNode = techTree:GetTechNode(kTechId.UpgradeToExoPrototypeLab)
        self:SetResearching(techNode, team:GetCommander() or self)
        techNode:SetResearching()
        techTree:SetTechNodeChanged(techNode, "researching")

    end

    return true

end

function PrototypeLab:OnConstructionComplete()

    self:AddTimedCallback(OnDeploy, kDeployTime)

    if self:GetTechId() == kTechId.PrototypeLab then
        UpdateExoLabUpgrade(self)
        self:AddTimedCallback(UpdateExoLabUpgrade, 1)
    end

end

function PrototypeLab:OnResearchCancel(researchId)

    if researchId == kTechId.UpgradeToExoPrototypeLab then
        self.exoUpgradeHeld = self:GetIsPowered()
    end

end

function PrototypeLab:OnResearchComplete(researchId)

    if researchId ~= kTechId.UpgradeToExoPrototypeLab then
        return
    end

    self:SetTechId(kTechId.ExoPrototypeLab)
    if HasMixin(self, "MapBlip") then
        self:MarkBlipDirty()
    end

    local techTree = self:GetTeam():GetTechTree()
    local exosuitNode = techTree:GetTechNode(kTechId.ExosuitTech)
    if exosuitNode and not exosuitNode:GetResearched() then
        exosuitNode:SetResearchProgress(1)
        techTree:SetTechNodeChanged(exosuitNode, string.format("researchProgress = %.2f", 1))
        exosuitNode:SetResearched(true)
        techTree:QueueOnResearchComplete(kTechId.ExosuitTech, self)
    end

end

-- west/east = x/-x
-- north/south = -z/z
local indexToUseOrigin =
{
    -- West
    Vector(PrototypeLab.kResupplyUseRange, 0, 0), 
    -- North
    Vector(0, 0, -PrototypeLab.kResupplyUseRange),
    -- South
    Vector(0, 0, PrototypeLab.kResupplyUseRange),
    -- East
    Vector(-PrototypeLab.kResupplyUseRange, 0, 0)
}

function PrototypeLab:UpdateLoggedIn()

    -- Exo is not a Marine subclass, so collect both: an exo at the lab pulls the screens out too.
    local players = GetEntitiesForTeamWithinRange("Marine", self:GetTeamNumber(), self:GetOrigin(), 2 * PrototypeLab.kResupplyUseRange)
    local exos = GetEntitiesForTeamWithinRange("Exo", self:GetTeamNumber(), self:GetOrigin(), 2 * PrototypeLab.kResupplyUseRange + kExoStructureUseSlack)
    for i = 1, #exos do
        players[#players + 1] = exos[i]
    end
    local ptLabCoords = self:GetAngles():GetCoords()
    
    for i = 1, 4 do
    
        local newState = false
        
        if GetIsUnitActive(self) and self.deployed then
        
            local worldUseOrigin = self:GetModelOrigin() + ptLabCoords:TransformVector(indexToUseOrigin[i])
            
            for playerIndex, player in ipairs(players) do
            
                -- See if player is nearby
                local useRange = PrototypeLab.kResupplyUseRange + (player:isa("Exo") and kExoStructureUseSlack or 0)
                if player:GetIsAlive() and (player:GetModelOrigin() - worldUseOrigin):GetLength() < useRange then
                
                    newState = true
                    break
                    
                end
                
            end
            
        end
        
        if newState ~= self.loggedInArray[i] then
        
            if newState then
                self:TriggerEffects("prototypelab_open")
            else
                self:TriggerEffects("prototypelab_close")
            end
            
            self.loggedInArray[i] = newState
            
        end
        
    end
    
    -- Copy data to network variables (arrays not supported)
    self.loggedInWest = self.loggedInArray[1]
    self.loggedInNorth = self.loggedInArray[2]
    self.loggedInSouth = self.loggedInArray[3]
    self.loggedInEast = self.loggedInArray[4]
    
    return true
    
end
