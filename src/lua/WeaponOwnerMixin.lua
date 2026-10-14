-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\WeaponOwnerMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

WeaponOwnerMixin = CreateMixin(WeaponOwnerMixin)
WeaponOwnerMixin.type = "WeaponOwner"

WeaponOwnerMixin.optionalCallbacks =
{
    OnWeaponAdded = "Will be called right after a weapon is added with the weapon as the only parameter."
}

WeaponOwnerMixin.expectedCallbacks =
{
    Drop = "Called when new weapon takes current weapon's slot."
}

WeaponOwnerMixin.expectedConstants =
{
    kStowedWeaponWeightScalar = "How much a stowed weapon influences the total weight."
}

-- lets assume you can't carry more than 20 rifles in weight. Seems reasonable
WeaponOwnerMixin.kMaxWeaponsWeight = 20 * kRifleWeight

-- workaround for there being no way to detect client-side when a weapon is added/removed.
-- polling number of children would fail if a weapon is swapped within a single update.
-- any time a weapon is added or removed, we add 1 to this counter, wrapping around to 0.
-- then on the client, we just poll this value, and compare to our client-only value to see
-- if it has changed.
local kMaxInventoryUpdatesCount = 8

WeaponOwnerMixin.networkVars =
{
    processMove = "boolean",
    activeWeaponId = "entityid",
    activeWeaponMapName = "string (31)",
    timeOfLastWeaponSwitch = "time",
    weaponsWeight = "float (0 to " .. WeaponOwnerMixin.kMaxWeaponsWeight .. " by 0.01)",
    quickSwitchSlot = "integer (0 to 10)",
    inventoryUpdateId = "integer (0 to "..(kMaxInventoryUpdatesCount-1)..")",

    -- A weapon switch that was requested while GetCanChangeWeapon() was false (e.g. mid-stomp).
    -- It is applied from ProcessMoveOnWeapons as soon as switching is allowed again.
    -- Networked so the predicting client and the server always agree on it.
    queuedWeaponId = "private entityid",
    queuedWeaponTime = "private time",
    queuedWeaponKeepQuickSwitch = "private boolean",
}

-- A queued switch older than this is discarded, so it can't fire unexpectedly long after the request.
local kQueuedWeaponSwitchMaxAge = 3

local function ClearQueuedWeaponSwitch(self)
    self.queuedWeaponId = Entity.invalidId
    self.queuedWeaponTime = 0
    self.queuedWeaponKeepQuickSwitch = false
end

local function QueueWeaponSwitch(self, weapon, keepQuickSwitchSlot)
    self.queuedWeaponId = weapon:GetId()
    self.queuedWeaponTime = Shared.GetTime()
    self.queuedWeaponKeepQuickSwitch = keepQuickSwitchSlot == true
end

function WeaponOwnerMixin:__initmixin()
    
    PROFILE("WeaponOwnerMixin:__initmixin")
    
    self.processMove = true
    self.activeWeaponId = Entity.invalidId
    self.activeWeaponMapName = ""
    self.timeOfLastWeaponSwitch = 0
    self.weaponsWeight = 0
    self.quickSwitchSlot = 1
    self.inventoryUpdateId = 0
    ClearQueuedWeaponSwitch(self)
    
end

function WeaponOwnerMixin:GetHasQueuedWeaponSwitch()
    return self.queuedWeaponId ~= Entity.invalidId
end

function WeaponOwnerMixin:GetWeaponsWeight()
    return self.weaponsWeight
end

function WeaponOwnerMixin:GetWeapons()

    local weapons = {}

    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        if child:isa("Weapon") then
        
            table.insert(weapons, child)
            
        end
    
    end
    
    return weapons

end

local function UpdateWeaponsWeight(self)

    -- Loop through all weapons, getting weight of each one
    local totalWeight = 0
    
    local activeWeapon = self:GetActiveWeapon()
    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        if child:isa("Weapon") then
        
            -- Active items count full, count less when stowed.
            local weaponIsActive = activeWeapon and (child:GetId() == activeWeapon:GetId())
            local weaponWeight = (weaponIsActive and child:GetWeight()) or (child:GetWeight() * self:GetMixinConstants().kStowedWeaponWeightScalar)
            totalWeight = totalWeight + weaponWeight
            
        end
    
    end
    
    self.weaponsWeight = Clamp(totalWeight, 0, 1)

end

function WeaponOwnerMixin:SetWeaponsProcessMove(processMove)
    self.processMove = processMove
end

-- Applies a switch that was requested while weapon changes were blocked, once they are allowed again.
local function ProcessQueuedWeaponSwitch(self)

    if self.queuedWeaponId == Entity.invalidId then
        return
    end

    local weapon = Shared.GetEntity(self.queuedWeaponId)
    local expired = Shared.GetTime() - self.queuedWeaponTime > kQueuedWeaponSwitchMaxAge
    local dead = self.GetIsAlive and not self:GetIsAlive()

    -- Weapon was dropped/destroyed, we died, or the request is stale: forget it.
    if not weapon or weapon:GetParent() ~= self or expired or dead then
        ClearQueuedWeaponSwitch(self)
        return
    end

    -- Still blocked, keep waiting.
    if self.GetCanChangeWeapon and not self:GetCanChangeWeapon() then
        return
    end

    -- Clear first, SetActiveWeapon would otherwise treat the request as superseded anyway.
    local keepQuickSwitchSlot = self.queuedWeaponKeepQuickSwitch
    ClearQueuedWeaponSwitch(self)
    self:SetActiveWeapon(weapon:GetMapName(), keepQuickSwitchSlot)

end

function WeaponOwnerMixin:ProcessMoveOnWeapons(input)

    -- Don't update weapon if set to false (commander mode).
    if self.processMove then
        
        -- Call ProcessMove on only the active weapon.
        local activeWeapon = self:GetActiveWeapon()
        if activeWeapon then
        
            if activeWeapon.ProcessMoveOnWeapon then
                activeWeapon:ProcessMoveOnWeapon(self, input)
            end
            
            activeWeapon:ProcessMoveOnModel(input.time)
            
        end

        -- Some weapons own entities (e.g. stomp shockwaves) that must keep simulating while holstered.
        -- This is the single place they get ticked, once per move, for every weapon that opts in.
        if Server then

            for i = 0, self:GetNumChildren() - 1 do

                local child = self:GetChildAtIndex(i)
                if child:isa("Weapon") and child.ProcessMoveOnOwnedEntities then
                    child:ProcessMoveOnOwnedEntities(input.time)
                end

            end

        end

        ProcessQueuedWeaponSwitch(self)
        
    end
    
end

--
-- Sorter used in WeaponOwnerMixin:GetHUDOrderedWeaponList().
--
local function WeaponSorter(weapon1, weapon2)
    return weapon2:GetHUDSlot() > weapon1:GetHUDSlot()
end

function WeaponOwnerMixin:GetHUDOrderedWeaponList()

    PROFILE("WeaponOwnerMixin:GetHUDOrderedWeaponList")
    
    local hudOrderedWeaponList = { }
    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        if child:isa("Weapon") and child:GetHUDSlot() ~= kNoWeaponSlot then
            table.insert(hudOrderedWeaponList, child)
        end
        
    end
    
    table.sort(hudOrderedWeaponList, WeaponSorter)
    
    return hudOrderedWeaponList
    
end

-- Returns true if we switched to weapon or if weapon is already active. Returns false if we
-- don't have that weapon.
function WeaponOwnerMixin:SetActiveWeapon(weaponMapName, keepQuickSwitchSlot)
    
    local foundWeapon
    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        if child:isa("Weapon") and child:GetMapName() == weaponMapName then
        
            foundWeapon = child
            break
            
        end
        
    end
    
    if foundWeapon then
        
        local newWeapon = foundWeapon
        local activeWeapon = self:GetActiveWeapon()

        if activeWeapon and self.GetCanChangeWeapon and not self:GetCanChangeWeapon() then

            if activeWeapon == newWeapon then
                ClearQueuedWeaponSwitch(self)
            else
                QueueWeaponSwitch(self, newWeapon, keepQuickSwitchSlot)
            end

            return false

        end

        ClearQueuedWeaponSwitch(self)
        
        if newWeapon.OnSetActive then
            newWeapon:OnSetActive()
        end
        
        if activeWeapon == nil or activeWeapon:GetMapName() ~= weaponMapName then
        
            local previousWeaponName = ""
            
            if activeWeapon then
            
                activeWeapon:OnHolster(self)
                activeWeapon:SetIsVisible(false)
                previousWeaponName = activeWeapon:GetMapName()
                local hudSlot = activeWeapon:GetHUDSlot()

                if keepQuickSwitchSlot == nil then
                    keepQuickSwitchSlot = false
                end

                if hudSlot > 0 and not keepQuickSwitchSlot then
                    self.quickSwitchSlot = hudSlot
                end
                
            end
            
            -- Set active first so proper anim plays
            self.activeWeaponId = newWeapon:GetId()
            self.activeWeaponMapName = newWeapon:GetMapName()
            
            newWeapon:OnDraw(self, previousWeaponName)
            
            self.timeOfLastWeaponSwitch = Shared.GetTime()
            
            UpdateWeaponsWeight(self)
            
            return true
            
        end
        
    end
    
    local activeWeapon = self:GetActiveWeapon()
    if activeWeapon ~= nil and activeWeapon:GetMapName() == weaponMapName then
    
        UpdateWeaponsWeight(self)
        return true
        
    end
    
    Print("%s:SetActiveWeapon(%s) failed", self:GetClassName(), weaponMapName or "No Weapon")
    
    UpdateWeaponsWeight(self)
    
    return false

end

function WeaponOwnerMixin:SetQuickSwitchTarget(weaponMapName)

    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        if child:isa("Weapon") and child:GetMapName() == weaponMapName then

            self.quickSwitchSlot = child:GetHUDSlot()
            return
            
        end
        
    end

    Print("ERROR: Could not find weapon %s", weaponMapName)

end

function WeaponOwnerMixin:QuickSwitchWeapon()
    --DebugPrint("switching to hud slot %d", self.quickSwitchSlot)
    self:SwitchWeapon(self.quickSwitchSlot)
end

function WeaponOwnerMixin:GetActiveWeapon()
    return (Shared.GetEntity(self.activeWeaponId))
end

function WeaponOwnerMixin:GetTimeOfLastWeaponSwitch()
    return self.timeOfLastWeaponSwitch
end

function WeaponOwnerMixin:SwitchWeapon(hudSlot)

    local foundWeapon
    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
    
        if child:isa("Weapon") and child:GetHUDSlot() == hudSlot then
        
            foundWeapon = child
            break
            
        end
        
    end

    local success = false
    if foundWeapon then
        success = self:SetActiveWeapon(foundWeapon:GetMapName())
    end
    
    return success
    
end

function WeaponOwnerMixin:SelectNextWeaponInDirection(direction)

    local weaponList = self:GetHUDOrderedWeaponList()
    local activeWeapon = self:GetActiveWeapon()
    local activeIndex = 1
    for i, weapon in ipairs(weaponList) do
    
        if weapon == activeWeapon then
        
            activeIndex = i
            break
            
        end
        
    end
    
    local numWeapons = table.icount(weaponList)
    if numWeapons > 0 then
    
        local newIndex = activeIndex + direction
        -- Handle wrap around.
        if newIndex > numWeapons then
            newIndex = 1
        elseif newIndex < 1 then
            newIndex = numWeapons
        end
        
        self:SetActiveWeapon(weaponList[newIndex]:GetMapName())
        
    end
    
end

-- TODO: Use this on all the places in the code where we fetch the weapon instead (faster)
function WeaponOwnerMixin:GetActiveWeaponName()

    return self.activeWeaponMapName
--[[
    local activeWeaponName = ""
    local activeWeapon = self:GetActiveWeapon()
    
    if activeWeapon ~= nil then
        activeWeaponName = activeWeapon:GetClassName()
    end
    
    return activeWeaponName
    --]]
end

function WeaponOwnerMixin:GetActiveWeaponId()
    return self.activeWeaponId
end

--
-- Checks to see if self already has a weapon with the passed in map name.
-- Returns this weapon if it exists, nil otherwise.
--
function WeaponOwnerMixin:GetWeapon(weaponMapName)

    local found
    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
    
        if child:isa("Weapon") and child:GetMapName() == weaponMapName then
        
            found = child
            break
            
        end
    
    end
    
    return found

end

--
-- Checks to see if self already has a weapon in the passed in HUD slot.
-- Returns this weapon if it exists, nil otherwise.
--
function WeaponOwnerMixin:GetWeaponInHUDSlot(slot)

    for i = 0, self:GetNumChildren() - 1 do
    
        local child = self:GetChildAtIndex(i)
        
        if child:isa("Weapon") and child:GetHUDSlot() == slot then
            return child
        end
    
    end
    
    return nil
    
end

function WeaponOwnerMixin:SetHUDSlotActive(slot)

    local weapon = self:GetWeaponInHUDSlot(slot)
    if weapon then
        self:SetActiveWeapon(weapon:GetMapName())
    else

        local orderedList = self:GetHUDOrderedWeaponList()
        if #orderedList > 0 then
            self:SetActiveWeapon(orderedList[1]:GetMapName())
        end
        
    end

end

function WeaponOwnerMixin:AddWeapon(weapon, setActive)
    
    assert(weapon:GetParent() ~= self)

    -- Remove any existing weapon that shares the HUD slot to the
    -- incoming weapon.
    local hasWeapon = self:GetWeaponInHUDSlot(weapon:GetHUDSlot())
    if hasWeapon then
    
        local success = self:Drop(hasWeapon, true, true)
        assert(success == true)
        
    end
    
    assert(self:GetWeaponInHUDSlot(weapon:GetHUDSlot()) == nil)

    weapon:SetParent(self)
    weapon:SetOrigin(Vector.origin)

    -- The weapon no longer belongs to the world once a weapon owner has it.
    if Server then
        weapon:SetWeaponWorldState(false)
    end
    
    if setActive then
    
        self:SetActiveWeapon(weapon:GetMapName())
        
    else
    
        UpdateWeaponsWeight(self)
        
    end
    
    if self.OnWeaponAdded then
        self:OnWeaponAdded(weapon)
    end
    
    self.inventoryUpdateId = (self.inventoryUpdateId + 1) % kMaxInventoryUpdatesCount

    if Server and HasMixin(self, "Team") then
        TeamInfo_SetUserTrackersDirty(self:GetTeamNumber())
    end
    
    return hasWeapon
    
end

function WeaponOwnerMixin:RemoveWeapon(weapon)

    assert(weapon:GetParent() == self)
    
    -- Switch weapons if we're dropping our current weapon
    local activeWeapon = self:GetActiveWeapon()
    local removingActive = weapon == activeWeapon

    if self.queuedWeaponId == weapon:GetId() then
        ClearQueuedWeaponSwitch(self)
    end

    weapon:SetParent(nil)
    
    if removingActive then
    
        self.activeWeaponId = Entity.invalidId
        self.activeWeaponMapName = ""
        self:SelectNextWeaponInDirection(1)
        
    end
    
    UpdateWeaponsWeight(self)
    
    self.inventoryUpdateId = (self.inventoryUpdateId + 1) % kMaxInventoryUpdatesCount

    if Server and HasMixin(self, "Team") then
        TeamInfo_SetUserTrackersDirty(self:GetTeamNumber())
    end
    
end

function WeaponOwnerMixin:DestroyWeapons()

    self.activeWeaponId = Entity.invalidId
    self.activeWeaponMapName = ""
    ClearQueuedWeaponSwitch(self)

    for _, weapon in ipairs(self:GetWeapons()) do
        DestroyEntity(weapon)
    end

    if Server and HasMixin(self, "Team") then
        TeamInfo_SetUserTrackersDirty(self:GetTeamNumber())
    end

end

function WeaponOwnerMixin:UpdateClientEffects(deltaTime, isLocal)

    if not self.lastActiveWeaponId then
        self.lastActiveWeaponId =  self:GetActiveWeaponId()
    end
    
    -- There is currently no way for the client to be notified about changes in children.
    -- So we poll for differences in a stored, arbitrary "inventoryUpdateId", which changes
    -- server-side whenever a weapon is added/removed.
    if isLocal and self.inventoryUpdateId ~= self.inventoryUpdateIdClient then
        self.inventoryUpdateIdClient = self.inventoryUpdateId
        HelpScreen_ForceUpdate()
    end
    
    local activeWeaponId = self:GetActiveWeaponId()
    if activeWeaponId ~= self.lastActiveWeaponId then
    
        if activeWeaponId and self.lastActiveWeaponId ~= Entity.invalidId then
        
            local weapon = Shared.GetEntity(self.lastActiveWeaponId)
            if weapon then
                weapon:OnHolsterClient(self)
            end
            
            local activeWeapon = self:GetActiveWeapon()
            if activeWeapon then
                activeWeapon:OnDrawClient()
            end
            
        end
        
        self.lastActiveWeaponId = activeWeaponId
        
    end
    
end

function WeaponOwnerMixin:OnDestroy()

    if Client then
    
        local activeWeapon = self:GetActiveWeapon()
        if activeWeapon then
            activeWeapon:OnHolsterClient()
        end
    
    end

end
