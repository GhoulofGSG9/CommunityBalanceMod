-- ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. ============
--
-- lua\TriggerMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

--
-- TriggerMixin has callbacks for when another entity enters or exits a volume.
--
TriggerMixin = { }
TriggerMixin.type = "Trigger"

TriggerMixin.optionalCallbacks =
{
    OnTriggerEntered = "First parameter is the entity that entered the trigger, second is self",
    OnTriggerExited = "First parameter is the entity that exited the trigger, second is self",
    GetTrackEntity = "Filter entities which enter the trigger but are not interesting to us. Return false to ignore the entity.",
    OnTriggerListChanged = "Called whenever the trigger list has changed (entity entered/exited the trigger)"
}

TriggerMixin.optionalConstants =
{
    kPhysicsGroup = "Pass physics groups.",
    kFilterMask = "Pass filter mask."
}

function TriggerMixin:__initmixin()
    
    PROFILE("TriggerMixin:__initmixin")
    
    self.insideTriggerEntities = unique_set()
end

local function DestroyTrigger(self)

    if self.triggerBody then
    
        Shared.DestroyCollisionObject(self.triggerBody)
        self.triggerBody = nil
        
    end
    
end

function TriggerMixin:SetSphere(setRadius)

    DestroyTrigger(self)
    
    local coords = self:GetCoords()
    
    self.triggerBody = Shared.CreatePhysicsSphereBody(false, setRadius, 0, coords)
    self.triggerBody:SetTriggerEnabled(true)
    self.triggerBody:SetCollisionEnabled(true)
    
    if self:GetMixinConstants().kPhysicsGroup then
        --Print("set trigger physics group to %s", EnumToString(PhysicsGroup, self:GetMixinConstants().kPhysicsGroup))
        self.triggerBody:SetGroup(self:GetMixinConstants().kPhysicsGroup)
    end
    
    if self:GetMixinConstants().kFilterMask then
        --Print("set trigger filter mask to %s", EnumToString(PhysicsMask, self:GetMixinConstants().kFilterMask))
        self.triggerBody:SetGroupFilterMask(self:GetMixinConstants().kFilterMask)
    end
    
    self.triggerBody:SetEntity(self)
    
end

function TriggerMixin:SetBox(setExtents)

    DestroyTrigger(self)
    
    --[[
    Why multiply the extents by 0.2395?
    
    The editor uses a model and scales that for the triggers. The game takes the scale and assumes the
    model is a certain size, the problem before was that this assumed value caused big overlapping
    between entities, causing some issues in a few maps. We're going to use a more accurate value now.
    
    If we scale the location entity to a 1x1x1 meter box the scaling comes back as 2.089896 2.089893
    2.089889. Therefore, the extents size is (approx) 0.4785 for each side (they are not exactly equal in
    all sides). To make the extents accurate, we'd have to multiply by 0.23925, but we're going to make
    it overlap it slightly to cover potential issues.
    
    This "magic value" is also used in Location.lua for the Commander VFX for powered areas.
    
    Previously the game was using 0.25 for the volume size, and 0.23 for the visual representation.
    --]]
    
    local extents = setExtents * 0.2395
    local coords = self:GetAngles():GetCoords()
    coords.origin = Vector(self:GetOrigin())
    -- The physics origin is at it's center
    coords.origin.y = coords.origin.y + extents.y
    
    self.worldToObjCoords = coords
    self.worldToObjCoords.xAxis = self.worldToObjCoords.xAxis * extents.x
    self.worldToObjCoords.yAxis = self.worldToObjCoords.yAxis * extents.y
    self.worldToObjCoords.zAxis = self.worldToObjCoords.zAxis * extents.z
    self.worldToObjCoords = self.worldToObjCoords:GetInverse()
    
    self.triggerBody = Shared.CreatePhysicsBoxBody(false, extents, 0, coords)
    self.triggerBody:SetTriggerEnabled(true)
    self.triggerBody:SetCollisionEnabled(false)
    
    if self:GetMixinConstants().kPhysicsGroup then
        --Print("set trigger physics group to %s", EnumToString(PhysicsGroup, self:GetMixinConstants().kPhysicsGroup))
        self.triggerBody:SetGroup(self:GetMixinConstants().kPhysicsGroup)
    end
    
    if self:GetMixinConstants().kFilterMask then
        --Print("set trigger filter mask to %s", EnumToString(PhysicsMask, self:GetMixinConstants().kFilterMask))
        self.triggerBody:SetGroupFilterMask(self:GetMixinConstants().kFilterMask)
    end
    
    self.triggerBody:SetEntity(self)
    
end

function TriggerMixin:OnDestroy()

    DestroyTrigger(self)
    
    self.insideTriggerEntities = nil
    
end

function TriggerMixin:SetTriggerCollisionEnabled(setEnabled)
    self.triggerBody:SetCollisionEnabled(setEnabled)
end

-- local count = 0
-- local stats = {0,0,0,0,0,0}

--[[ Stats to do condition reordering

-- Stats from an idle marine in main
Client  : 178.415985 : {2 = "151,817",  5 = "415,256",  6 = "614,080",  3 = "877,303",  1 = "911,319",  4 = "940,000"}
Server  : 178.034836 : {1 = "216,318",  6 = "239,198",  5 = "356,211",  2 = "382,363",  4 = "519,494",  3 = "514,004"}

-- Stats from a 10v10 bot pregame for a few minutes
Server  : 107.210785 : {6 = "1,851,859",1 = "1,922,344",2 = "2,441,450",5 = "2,534,710",3 = "3,634,752",4 = "3,728,937",}

--]]
function TriggerMixin:GetIsPointInside(point)
    
    --PROFILE("TriggerMixin:GetIsPointInside") -- Cannot measure without that, but if it is like assert it's a 10-15ns gain
    
    --assert(self.worldToObjCoords) -> Went from 85ns to 72ns commenting this

    local worldToObj = self.worldToObjCoords
    local localSpacePt = worldToObj:TransformPoint(point)

--[[
    stats[1] = stats[1] + (localSpacePt.x >= -1 and 1 or 0)
    stats[2] = stats[2] + (localSpacePt.x < 1.0 and 1 or 0)
    stats[3] = stats[3] + (localSpacePt.y >= -1 and 1 or 0)
    stats[4] = stats[4] + (localSpacePt.y < 1.0 and 1 or 0)
    stats[5] = stats[5] + (localSpacePt.z >= -1 and 1 or 0)
    stats[6] = stats[6] + (localSpacePt.z < 1.0 and 1 or 0)
    count = count + 1
    if (count % 10000 == 0) then
        Log("%s", stats)
    end
    
    return  localSpacePt.x >= -1 and localSpacePt.x < 1.0 and
            localSpacePt.y >= -1 and localSpacePt.y < 1.0 and
            localSpacePt.z >= -1 and localSpacePt.z < 1.0
    -]]

    -- --> Went from 72ns to 64ns with the condition reordering
    local x = localSpacePt.x
    local y = localSpacePt.y
    local z = localSpacePt.z
    -- Reordered checks according to our benchmark above of who fails the most first
    return z < 1.0 and x >= -1 and x < 1.0 and z >= -1 and y >= -1 and y < 1.0
end

function TriggerMixin:GetNumberOfEntitiesInTrigger()
    return self.insideTriggerEntities:GetCount()
end

function TriggerMixin:GetEntitiesInTrigger()

    local entities = { }

    for entId in self.insideTriggerEntities:Iterate() do
        local ent = Shared.GetEntity(entId)
        if ent then
            table.insert(entities, ent)
        end
    end
    
    return entities
    
end

function TriggerMixin:GetEntityIdsInTrigger()
    return self.insideTriggerEntities:GetList()
end

function TriggerMixin:ForEachEntityInTrigger(callFunc)
    
    -- iterate backwards b/c sometimes callFunc can result in the entity being destroyed.
    for entId in self.insideTriggerEntities:IterateBackwards()  do
        local ent = Shared.GetEntity(entId)
        if ent then
            callFunc(self, ent)
        end
    end
    
end

function TriggerMixin:OnEntityChange(oldId, newId)

    self.insideTriggerEntities:Remove(oldId)
    
end

function TriggerMixin:OnTriggerEntered(enterEntity)

    if self.GetTrackEntity then
    
        -- Filter entity?
        if not self:GetTrackEntity(enterEntity) then
            return
        end
        
    end
    
    if self.insideTriggerEntities:Insert(enterEntity:GetId()) then
    
        if self.OnTriggerListChanged then
            self:OnTriggerListChanged(enterEntity, true)
        end
    
    end
    
end

function TriggerMixin:OnTriggerExited(exitEntity)

    local exitEntId = exitEntity:GetId()
    if self.insideTriggerEntities:Remove(exitEntId) then
        
        if self.OnTriggerListChanged then
            self:OnTriggerListChanged(exitEntity, false)
        end
        
    end
    
end
