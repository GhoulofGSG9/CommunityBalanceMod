-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\Hydra_Server.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- Creepy plant turret the Gorge can create.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Hydra.kUpdateInterval = .5

function Hydra:OnKill(attacker, doer, point, direction)

    ScriptActor.OnKill(self, attacker, doer, point, direction)
    
    local team = self:GetTeam()
    if team then
        team:UpdateClientOwnedStructures(self:GetId())
    end

end

function Hydra:GetSendDeathMessageOverride()
    return not self.consumed
end

function Hydra:GetDistanceToTarget(target)
    return (target:GetEngagementPoint() - self:GetModelOrigin()):GetLength()           
end

-- Spread changes based on target distance.
function Hydra:CreateSpikeProjectile(startPoint)

    -- TODO: make hitscan at account for target velocity (more inaccurate at higher speed)

    startPoint = startPoint or self:GetBarrelPoint()

    local target = self.target
    local targetPoint = target:GetEngagementPoint()
    local directionToTarget = targetPoint - startPoint
    local targetDistance = directionToTarget:GetLength()
    local theTimeToReachEnemy = targetDistance / Hydra.kSpikeSpeed
    local engagementPoint = targetPoint
    if target.GetVelocity then

        local targetVelocity = target:GetVelocity()
        engagementPoint = targetPoint - targetVelocity * (Hydra.kTargetVelocityFactor * theTimeToReachEnemy)

    end

    local fireDirection = GetNormalizedVector(engagementPoint - startPoint)
    local fireCoords = Coords.GetLookIn(startPoint, fireDirection)

    local spreadFraction = Clamp((targetDistance - Hydra.kNearDistance) / (Hydra.kFarDistance - Hydra.kNearDistance), 0, 1)
    local spread = Hydra.kNearSpread * (1.0 - spreadFraction) + Hydra.kFarSpread * spreadFraction

    local spreadDirection = CalculateSpread(fireCoords, spread, math.random)

    local endPoint = startPoint + spreadDirection * Hydra.kRange

    local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOneAndIsa(self, "Hydra"))

    if trace.fraction < 1 then

        local surface

        -- Disable friendly fire.
        trace.entity = (not trace.entity or GetAreEnemies(trace.entity, self)) and trace.entity or nil

        if not trace.entity then
            surface = trace.surface
        end

        -- local direction = (trace.endPoint - startPoint):GetUnit()
        self:DoDamage(Hydra.kDamage, trace.entity, trace.endPoint, fireDirection, surface, false, true)

    end

end

function Hydra:GetRateOfFire()
    return Hydra.kRateOfFire
end

-- No changes (incorporating a change to a local function).
function Hydra:AttackTarget(barrelPoint)

    self:TriggerUncloak()

    self:CreateSpikeProjectile(barrelPoint)
    self:TriggerEffects("hydra_attack")


    self.timeOfNextFire = Shared.GetTime() + self:GetRateOfFire()

end

function Hydra:OnOwnerChanged(_, newOwner)

    self.hydraParentId = Entity.invalidId
    if newOwner ~= nil then
        self.hydraParentId = newOwner:GetId()
    end
    
end

function Hydra:OnUpdate(deltaTime)

    PROFILE("Hydra:OnUpdate")
    
    ScriptActor.OnUpdate(self, deltaTime)
    
    local now = Shared.GetTime()

    self.electrified = self.timeElectrifyEnds > now
    
    if not self.timeLastUpdate then
        self.timeLastUpdate = now
    end
    
    if self.timeLastUpdate + Hydra.kUpdateInterval < now then
    
        if GetIsUnitActive(self) and not (self:GetIsOnFire() or self.electrified) then
            self.target = self.targetSelector:AcquireTarget()

            -- Check for obstacles between the origin and barrel point of the hydra so it doesn't shoot while sticking through walls
            local barrelPoint
            if self.target then
                barrelPoint = self:GetBarrelPoint()
                self.attacking = not GetWallBetween(barrelPoint, self:GetOrigin(), self) and not GetIsPointInsideClogs(barrelPoint)
            else
                self.attacking = false
            end

            if self.attacking and (not self.timeOfNextFire or now > self.timeOfNextFire) then
                self:AttackTarget(barrelPoint)
            elseif not self.target then
                -- Play alert animation if marines nearby and we're not targeting (ARCs?)
                if not self.timeLastAlertCheck or now > self.timeLastAlertCheck + Hydra.kAlertCheckInterval then
                
                    self.alerting = false
                    
                    if self:GetIsEnemyNearby() then
                    
                        self.alerting = true
                        self.timeLastAlertCheck = now
                        
                    end
                    
                end
            end

        else
            self.attacking = false
        end
        
        self.timeLastUpdate = now
        
    end
    
end

function Hydra:GetIsEnemyNearby()

    local range = Hydra.kRange
    local rangeSq = range * range
    local origin = self:GetModelOrigin()
    local kEngagementMargin = 2

    -- Native range query instead of building a list of every enemy player on the map
    local enemyPlayers = GetEntitiesForTeamWithinRange("Player", GetEnemyTeamNumber(self:GetTeamNumber()), origin, range + kEngagementMargin)
    
    for i = 1, #enemyPlayers do
    
        local player = enemyPlayers[i]

        if player:GetIsVisible() and not player:isa("Commander")
           and (player:GetEngagementPoint() - origin):GetLengthSquared() < rangeSq then
            return true
        end
            
    end
    
    return false
    
end
