-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\InfestationTrackerMixin.lua
--
-- Created by: Mats Olsson (mats.olsson@matsotech.se)
--
-- Tracks infested state for entities.
-- Cooperates with the Infestation to update the infestation state of entities.
-- Listens for changes in location for self, adding itself to the dirty table, which
-- is cleaned out regularly.
-- In addition, an infestation that changes its radius will also cause all entities in the
-- changed radius to be marked as dirty
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

InfestationTrackerMixin = CreateMixin( InfestationTrackerMixin )
InfestationTrackerMixin.type = "InfestationTracker"

-- Listen on the state that infested state depends on - ie where we are
InfestationTrackerMixin.expectedCallbacks = {
    SetOrigin = "Sets the location of an entity",
    SetCoords = "Sets both both location and angles",
}

InfestationTrackerMixin.expectedMixins =
{
    GameEffects = "Required for on infestation state."
}

-- What entities have become dirty.
-- A unique_set, so an entity that moves several times in the same tick is only
-- recorded (and updated) once, and marking it dirty stays O(1).
-- Flushed in the UpdateServer hook by InfestationTrackerMixin.OnUpdateServer
InfestationTrackerMixin.dirtyTable = unique_set()

-- Second set, swapped with dirtyTable on each flush. Entities marked dirty *during*
-- the flush land in the fresh set and are handled on the next tick, so we never
-- mutate the set we are iterating and never silently drop a late arrival.
local spareSet = unique_set()

-- Call all dirty entities
function InfestationTrackerMixin.OnUpdateServer()

    PROFILE("InfestationTrackerMixin:OnUpdateServer")

    local dirty = InfestationTrackerMixin.dirtyTable

    -- Nothing moved this tick
    if dirty:GetCount() == 0 then
        return
    end

    InfestationTrackerMixin.dirtyTable = spareSet
    spareSet = dirty

    local GetEntity = Shared.GetEntity
    for entityId in dirty:Iterate() do

        local entity = GetEntity(entityId)
        if entity then

            local updateInfestedState = entity.UpdateInfestedState
            if updateInfestedState then
                updateInfestedState(entity)
            else
                Print("warning: %s has no implementation of UpdateInfestedState()", entity:GetClassName())
            end

        end

    end

    dirty:Clear()

end

function InfestationTrackerMixin:SetOrigin(_)
    InfestationTrackerMixin.dirtyTable:Insert(self:GetId())
end

function InfestationTrackerMixin:SetCoords(_)
    InfestationTrackerMixin.dirtyTable:Insert(self:GetId())
end

function InfestationTrackerMixin:__initmixin()
    assert(Server)
end

function InfestationTrackerMixin:UpdateInfestedState(onInfestation)

    local now = Shared.GetTime()
    if self.infestedUpdateTime == now then return end

    self.infestedUpdateTime = now

    if onInfestation then
        self:SetInfestationState(true)
    else
        UpdateInfestationMask(self)
    end

end

function InfestationTrackerMixin:SetInfestationState(onInfestation)

    -- Normalise to a real boolean so nil and false don't read as a state change
    onInfestation = ( onInfestation == true )

    if self:GetGameEffectMask(kGameEffect.OnInfestation) ~= onInfestation then

        self:SetGameEffectMask(kGameEffect.OnInfestation, onInfestation)

        local callback = onInfestation and self.OnTouchInfestation or self.OnLeaveInfestation
        if callback then
            callback(self)
        end

    end

end

function InfestationTrackerMixin:InfestationNeedsUpdate()
    InfestationTrackerMixin.dirtyTable:Insert(self:GetId())
end

Event.Hook("UpdateServer", InfestationTrackerMixin.OnUpdateServer)
