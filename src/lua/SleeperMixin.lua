-- Todo: Remove/Rework
-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\SleeperMixin.lua
--
--    Created by:   Andreas Urwalek (a_urwa@sbox.tugraz.at)
--
--    Reduces amount of updates for unimportant entities
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

SleeperMixin = CreateMixin( SleeperMixin )
SleeperMixin.type = "Sleeper"

SleeperMixin.expectedCallbacks = {
    GetCanSleep = "Defines if an entity is in a state were it can go to sleep.",
}

SleeperMixin.optionalCallbacks = {
    GetMinimumAwakeTime = "Return a custom time the entity has to remain awake until it is allowed to sleep.",
    GetUpdatesRate = "Return the rate at which to set the OnUpdate rate at.",
    GetSleepUpdatesRate = "Return the rate at which to set the OnUpdate rate at when sleeping",
}

SleeperMixin.timeNextSleeperUpdate = {}
SleeperMixin.lastSleeperOrigin = {}

SleeperMixin.sleepers = unique_set()
SleeperMixin.sleepersDirty = unique_set()

SleeperMixin.timeLastCheckAll = 0
SleeperMixin.currentIndex = 1

-- a deltatime value that is experienced as "playable"
SleeperMixin.kDeltaTimeToleranz = 1 / 30

SleeperMixin.averageDeltaTime = 0.05
SleeperMixin.lastDeltaTimes = {}
SleeperMixin.currentDeltaTimeIndex = 1
SleeperMixin.kNumDeltaTimes = 12 -- store the last 10 deltaTimes and get average out of those

-- update this amount of sleepers at high tick rate. it would be better to save the actual computation time required and translate that to an entity amount
SleeperMixin.kNumUpdates = 25

SleeperMixin.kMinimumAwakeTime = 3

local function ComputerAverageDeltaTime(currentDeltaTime)

    PROFILE("SleeperMixin:ComputerAverageDeltaTime")

    if currentDeltaTime then

        if table.icount(SleeperMixin.lastDeltaTimes) < SleeperMixin.kNumDeltaTimes then
            table.insert(SleeperMixin.lastDeltaTimes, currentDeltaTime)
        else
            SleeperMixin.lastDeltaTimes[SleeperMixin.currentDeltaTimeIndex] = currentDeltaTime

            -- reset to 1 and overwrite old times if limit has been reached
            SleeperMixin.currentDeltaTimeIndex = ConditionalValue(SleeperMixin.currentDeltaTimeIndex + 1 <= 10, SleeperMixin.currentDeltaTimeIndex + 1, 1)
        end

        SleeperMixin.averageDeltaTime = 0

        for _, deltaTime in ipairs(SleeperMixin.lastDeltaTimes) do
            SleeperMixin.averageDeltaTime = SleeperMixin.averageDeltaTime + deltaTime
        end

        SleeperMixin.averageDeltaTime = SleeperMixin.averageDeltaTime / table.icount(SleeperMixin.lastDeltaTimes)

    end

end

local function InternalSleep(self)

    --Print("sleep %s", self:GetClassName())
    self:SetUpdates(false)
    self.sleeping = true

    SleeperMixin.sleepers:Insert(self:GetId())

    -- Todo make class instance var
    local rate = self.GetUpdatesRate and self:GetUpdatesRate() or kRealTimeUpdateRate
    SleeperMixin.timeNextSleeperUpdate[self:GetId()] = Shared.GetTime() + rate
    SleeperMixin.lastSleeperOrigin[self:GetId()] = self:GetOrigin()

end

local function InternalWakeUp(self)

    PROFILE("SleeperMixin:InternalWakeUp")

    --Print("wakeup %s", self:GetClassName())
    local rate = self.GetUpdatesRate and self:GetUpdatesRate() or kRealTimeUpdateRate
    self:SetUpdates(true, rate)
    self.sleeping = false
    self.timeLastWakeUp = Shared.GetTime()

    local id = self:GetId()
    SleeperMixin.sleepers:Remove(id)
    SleeperMixin.timeNextSleeperUpdate[id] = nil
    SleeperMixin.lastSleeperOrigin[id] = nil

end

local sleepingEnabled = true

local function InternalGetCanSleep(self)

    PROFILE("SleeperMixin:InternalGetCanSleep")

    local canSleep = sleepingEnabled and self.GetCanSleep

    if canSleep then
        -- Can only sleep if not moving
        local id = self:GetId()
        local lastOrig = SleeperMixin.lastSleeperOrigin[id]
        local hasMoved = lastOrig and lastOrig ~= self:GetOrigin()
        local isSelected = HasMixin(self, "Selectable") and self:GetIsSelected()
        local awakeTime = SleeperMixin.kMinimumAwakeTime

        canSleep = not hasMoved and not isSelected and self:GetCanSleep()
        if canSleep then
            if self.GetMinimumAwakeTime then
                awakeTime = self:GetMinimumAwakeTime()
            end

            canSleep = canSleep and (self.timeLastWakeUp + awakeTime < Shared.GetTime())
        end
    end

    return canSleep

end

function SleeperOnUpdateServer(deltaTime)

    PROFILE("SleeperMixin:OnUpdateServer")

    local now = Shared.GetTime()
    SleeperMixin.CheckDirtyTable()
    ComputerAverageDeltaTime(deltaTime)
    --Print("average deltaTime: %s", tostring(SleeperMixin.averageDeltaTime))

    if SleeperMixin.timeLastCheckAll + 2 < now then
        SleeperMixin.CheckAll()
        SleeperMixin.timeLastCheckAll = now
    end

    -- Change time slot to be based on total frame time
    local numMaxUpdates = math.ceil((SleeperMixin.kDeltaTimeToleranz / SleeperMixin.averageDeltaTime) * SleeperMixin.kNumUpdates)
    local numSleepers = SleeperMixin.sleepers:GetCount()
    local lastIndex = math.min(SleeperMixin.currentIndex + numMaxUpdates, numSleepers)

    --Print("num sleepers updated: %s", tostring(lastIndex - SleeperMixin.currentIndex))

    -- update sleepers from list
    for index = SleeperMixin.currentIndex, lastIndex do
    
        local entity = nil
        local entityId = SleeperMixin.sleepers:GetValueAtIndex(index)
        if SleeperMixin.timeNextSleeperUpdate[entityId] == nil then
            SleeperMixin.timeNextSleeperUpdate[entityId] = now
            SleeperMixin.lastSleeperOrigin[entityId] = Vector(0,0,0)
        end

        local entityDeltaTime = now - SleeperMixin.timeNextSleeperUpdate[entityId]

        if entityDeltaTime >= 0 then

            entity = Shared.GetEntity(entityId)
            if entity then

                local rate = entity.GetSleepUpdatesRate and entity:GetSleepUpdatesRate() or kUpdateIntervalLow

                --Log("Updating %s with a rate of %s", entity, rate)
                entity:OnUpdate(rate + entityDeltaTime)

                if not InternalGetCanSleep(entity) then
                    entity:WakeUp()
                end

                SleeperMixin.timeNextSleeperUpdate[entityId] = now + rate
                VectorCopy(entity:GetOrigin(), SleeperMixin.lastSleeperOrigin[entityId])

            else
                SleeperMixin.sleepersDirty:Insert(entityId)
            end
        end

    end

    if lastIndex >= numSleepers then
        SleeperMixin.timeLastUpdateCompleted = now
        SleeperMixin.currentIndex = 1
    else
        SleeperMixin.currentIndex = lastIndex + 1
    end

end

function SleeperMixin.CheckDirtyTable()

    PROFILE("SleeperMixin:CheckDirtyTable")

    for _, entityId in ipairs(SleeperMixin.sleepersDirty:GetList()) do
    
        local entity = Shared.GetEntity(entityId)

        if entity and entity.GetIsSleeping then
            if InternalGetCanSleep(entity) and entity:GetIsSleeping() then
                InternalSleep(entity)
            else

                if not entity:GetIsSleeping() then
                    InternalWakeUp(entity)
                end

            end
        else
            SleeperMixin.timeNextSleeperUpdate[entityId] = nil
            SleeperMixin.lastSleeperOrigin[entityId] = nil
            SleeperMixin.sleepers:Remove(entityId)
        end

    end
    
    SleeperMixin.sleepersDirty:Clear()

end

-- remove awake entities from list and add sleeping entities
function SleeperMixin.CheckAll()

    PROFILE("SleeperMixin:CheckAll")

    for _, entity in ipairs(GetEntitiesWithMixin("Sleeper")) do
    
        if InternalGetCanSleep(entity) then

            if not entity:GetIsSleeping() then
                InternalSleep(entity)
            end

        else

            if entity:GetIsSleeping() then
                InternalWakeUp(entity)
            end

        end

    end

end

function SleeperMixin:__initmixin()

    PROFILE("SleeperMixin:__initmixin")

    self.sleeping = false
    self.timeLastWakeUp = Shared.GetTime()

end

-- always wake up on damage
function SleeperMixin:OnTakeDamage()
    self:WakeUp()
end

-- wake up on destroy, so we get removed from the sleepers table
function SleeperMixin:OnDestroy()
    self:WakeUp()
end

function SleeperMixin:GetIsSleeping()
    return self.sleeping
end

function SleeperMixin:SetIsSleeping(sleeping)
    self.sleeping = sleeping
end

function SleeperMixin:WakeUp()

    -- store that even if we already are awake (refreshes the timer)
    self.timeLastWakeUp = Shared.GetTime()

    if self:GetIsSleeping() then
        self:SetIsSleeping(false)
        SleeperMixin.sleepersDirty:Insert(self:GetId())
    end

end

function SleeperMixin:Sleep(time)

    if not self:GetIsSleeping() then
        self:SetIsSleeping(true)
        SleeperMixin.sleepersDirty:Insert(self:GetId())
    end

    if time then
        self:AddTimedCallback(self.WakeUp, time)
    end
end

function OnCommandToggleSleeping(client)
    if (Shared.GetCheatsEnabled()) then
        sleepingEnabled = not sleepingEnabled
        Log("sleeping %s", sleepingEnabled and "enabled" or "disabled")
    end
end


Event.Hook("UpdateServer", SleeperOnUpdateServer)
Event.Hook("Console_sleeping", OnCommandToggleSleeping)
