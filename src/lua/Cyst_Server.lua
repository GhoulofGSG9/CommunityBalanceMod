--=============================================================================
--
-- lua\Cyst_Server.lua
--
-- Created by Mats Olsson (mats.olsson@matsotech.se) and
-- Charlie Cleveland (charlie@unknownworlds.com)
--
-- Copyright (c) 2011, Unknown Worlds Entertainment, Inc.
--
--============================================================================

Cyst.kThinkTime = 1.2

-- How long we can be without a confirmation impulse before we disconnect
Cyst.kImpulseDisconnectTime = 15
Cyst.kTouchRange = 0.9 -- Max model extents for "touch" uncloaking

function Cyst:SetCystParent(parent)

    assert(parent ~= self)
    
    self.parentId = parent:GetId()
    parent:AddChildCyst(self)

    local distanceToHive = parent:GetDistanceToHive()
    if distanceToHive then
        local isReachable, path = CreateBetweenEntities(self, parent)

        if isReachable then
            self:SetDistanceToHive(distanceToHive + GetPointDistance(path))
            return true
        end
    end
    return false
end

function Cyst:GetCanAutoBuild()
    return false
end

--
-- Return true if we are ACTUALLY connected, ie our ultimate parent is a Hive.
--
-- Note: this is valid only on the server, as the client may not (probably does not)
-- have all the entities in the chain to the hive loaded.
--
-- the GetIsConnected() method used the connect bit, which may not reflect the actual connection status.
--
function Cyst:GetIsActuallyConnected()
  
    PROFILE("Cyst:GetIsActuallyConnected")

    -- Always in dev mode, for making movies and testing
    if Shared.GetDevMode() then
        return true
    end
    
    local parent = self:GetCystParent()
    if parent then
    
        if parent:isa("Hive") then
            return true
        end
        return parent:GetIsActuallyConnected()
        
    end
    
    return false
    
end

-- NOTE: Cysts entities are destroyed here yet, otherwise infestation would immediately vanish.
-- InfestationMixin handles allowing the entity to be destroyed, which is then handled in
-- Cyst:OnUpdate(). -Beige
function Cyst:OnKill()

    self:TriggerEffects("death")
    self.connected = false
    self:SetModel(nil)

    -- Report killed cyst
    StatsUI_AddExportBuilding(self:GetTeamNumber(),
        self.GetTechId and self:GetTechId(),
        self:GetId(),
        self:GetOrigin(),
        StatsUI_kLifecycle.Destroyed,
        self:GetIsBuilt())
    
    for id in self.children:Iterate() do
    
        local cyst = Shared.GetEntity(id)
        if cyst then
            cyst.parentId = Entity.invalidId
        end
    
    end

    self.children:Clear()
    
end   

function Cyst:GetSendDeathMessageOverride()
    return false
end

function Cyst:OnEntityChange(entityId, newEntityId)
    
    if self.parentId == entityId then
        self.parentId = newEntityId or Entity.invalidId
    end

end

--
-- If we can track to our new parent, use it instead
--
function Cyst:TryNewCystParent(parent)

    local isReachable, path = CreateBetweenEntities(self, parent)
    
    -- Note: Ensure Cyst_Server.lua is using the same check as Cyst.lua for if a cyst is connected
    if isReachable and path then
    
        local pathLength = GetPointDistance(path)
        if pathLength <= parent:GetCystParentRange() then
        
            return self:ChangeParent(parent)
            
        end
    
    end
    
    return false
    
end

--
-- Try to find an actually connected parent. Connect to the closest entity (but bias hives).
--
function Cyst:TryToFindABetterParent()

    local teamNumber = self:GetTeamNumber()
    local parent, path = GetCystParentFromPoint(self:GetOrigin(), self:GetCoords().yAxis, "GetIsActuallyConnected", self, teamNumber)
    
    if parent and path then
    
        self:ChangeParent(parent)
        return true
        
    end
    
    return false
    
end

--
-- Reconnect any other cysts to me
--
function Cyst:ReconnectOthers()

    local cysts = GetEntitiesWithinRange("Cyst", self:GetOrigin(), self:GetCystParentRange())

    for _, cyst in ipairs(cysts) do
    
        -- when working on the server side, always use the actually connected rather than the connected bit
        -- the connected
        if not cyst:GetIsActuallyConnected() then
            cyst:TryNewCystParent(self)
        end
        
    end
    
end

function Cyst:GetMaturityRate()
    return kCystMaturationTime
end

function Cyst:GetStarvationMaturityRate()
    return Cyst.kMaturityLossTime
end

function Cyst:ChangeParent(newParent)

    -- Only change parents if the newer parent is closer to a hive than the old one
    local oldParent = self:GetCystParent()
    local oldDistance = oldParent and oldParent:GetDistanceToHive() or math.huge
    local newDistance = newParent and newParent:GetDistanceToHive() or math.huge
    local newParentId = newParent and newParent:GetId() or nil
    if not newParent or (oldDistance < newDistance and oldParent and oldParent:GetIsActuallyConnected()) then
        return false
    end

    -- Parent can't be a child at the same time !!!
    self.children:Remove(newParentId)

    if self:SetCystParent(newParent) then

        if oldParent and oldParent.ChangeParent then
            return oldParent:ChangeParent(self)
        end
        return true
    end
    return false
    
end

function Cyst:FireImpulses(now)

    for id in self.children:IterateBackwards() do
        local child = Shared.GetEntity(id)
        if child == nil then
            self.children:Remove(id)
        else
            -- We ask the children to trigger the impulse to themselves
            if child.TriggerImpulse then
                child:TriggerImpulse(now)
            end
        end
    end
    
end

--
-- Trigger an impulse to us along the track.
--
function Cyst:TriggerImpulse(now)

    if not self.impulseActive then
    
        self.impulseStartTime = now
        self.impulseActive = true   
        
    end
    
end

function Cyst:AddChildCyst(child)
    self.children:Insert(child:GetId())
end

function Cyst:OnTakeDamage(damage, attacker, doer, point)

    -- When we take disconnection damage, don't play alerts or effects, just expire silently
    if doer ~= self and damage > 0 then
        local team = self:GetTeam()
        if team.TriggerAlert then
            team:TriggerAlert(kTechId.AlienAlertStructureUnderAttack, self)
        end
    end

end

function Cyst:SetDistanceToHive(distance, ids)

    --detect loops
    ids = ids or {}
    local id = self:GetId()
    if ids[id] then return end

    ids[id] = true

    self.distanceToHive = distance

    for entId in self.children:IterateBackwards() do
        local cyst = Shared.GetEntity(entId)
        local isReachable, path = false, {}

        if cyst and cyst:isa("Cyst")then
            isReachable, path = CreateBetweenEntities(self, cyst)
            if isReachable then
                cyst:SetDistanceToHive(self.distanceToHive + GetPointDistance(path), ids)
            end
        end

        if not isReachable then
            self.children:Remove(entId)
        end
    end

    self:UpdateHealthScalar()
end

function Cyst:GetDistanceToHive()
    return self.distanceToHive
end

function Cyst:UpdateHealthScalar()
    self.healthScalar = 1 - Clamp(((self:GetDistanceToHive() - kMinCystScalingDistance) / kMaxCystScalingDistance), 0, 1)
end

function Cyst:TriggerDamage()

    if self:GetCystParent() == nil then

        local damage = kCystUnconnectedDamage * Cyst.kThinkTime
        self:DeductHealth(damage, self)

    end

end

function Cyst:ServerUpdate()

    if not self:GetIsAlive() then
        return
    end

    if self.bursted then
        self.bursted = self.timeBursted + Cyst.kBurstDuration > Shared.GetTime()
    end

    local now = Shared.GetTime()

    if now > self.nextUpdate then

        local connectedNow = self:GetIsActuallyConnected()

        -- the very first time we are placed, we try to connect
        if not self.madeInitialConnectAttempt then

            if not connectedNow then
                connectedNow = self:TryToFindABetterParent()
            end

            self.madeInitialConnectAttempt = true

        end

        -- try a single reconnect when we become disconnected
        if self.connected and not connectedNow then
            connectedNow = self:TryToFindABetterParent()
        end

        -- if we become connected, see if we have any unconnected cysts around that could use us as their parents
        if not self.connected and connectedNow then
            self:ReconnectOthers()
        end

        if connectedNow ~= self.connected then
            self.connected = connectedNow
            self:MarkBlipDirty()
        end

        -- avoid clumping; don't use now when calculating next think time (large kThinkTime)
        self.nextUpdate = self.nextUpdate + Cyst.kThinkTime

        -- Take damage if not connected
        if not self.connected and not self:GetIsCatalysted() and (now - self:GetCreationTime()) > 1 then
            self:TriggerDamage()
        end

    end

end

function Cyst:OnUpdate(deltaTime)

    ScriptActor.OnUpdate(self, deltaTime)

    if self:GetIsAlive() then

        self:ServerUpdate(deltaTime)
        self.hasChild = self.children:GetCount() > 0

    else

        local destructionAllowedTable = { allowed = true }
        if self.GetDestructionAllowed then
            self:GetDestructionAllowed(destructionAllowedTable)
        end

        if destructionAllowedTable.allowed then
            DestroyEntity(self)
        end

    end

end

function Cyst:UpdateInfestationCloaking()

    self.cloakInfestation = self.timeUncloaked < self.timeCloaked and self.timeCloaked > Shared.GetTime()

    return self:GetIsAlive()
end

function Cyst:ScanForNearbyEnemy()

    self.lastDetectedTime = self.lastDetectedTime or 0
    if self.lastDetectedTime + kDetectInterval < Shared.GetTime() then

        local done = false

        -- Check shades in range, and stop if a shade is in range and is cloaked.
        if not done then
            for _, shade in ipairs(GetEntitiesForTeamWithinRange("Shade", self:GetTeamNumber(), self:GetOrigin(), Shade.kCloakRadius)) do
                if shade:GetIsCloaked() then
                    done = true
                    break
                end
            end
        end

        -- Finally check if the cysts have players in range.
        if not done and #GetEntitiesForTeamWithinRange("Player", GetEnemyTeamNumber(self:GetTeamNumber()), self:GetOrigin(), kCystDetectRange) > 0 then
            self:TriggerUncloak()
            done = true
        end

        self.lastDetectedTime = Shared.GetTime()
    end

    return self:GetIsAlive()
end
