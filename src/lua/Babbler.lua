-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Babbler.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/ScriptActor.lua")
Script.Load("lua/Mixins/ClientModelMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/MobileTargetMixin.lua")
Script.Load("lua/DamageMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/OwnerMixin.lua")
Script.Load("lua/TargetCacheMixin.lua")
Script.Load("lua/PathingMixin.lua")
Script.Load("lua/PhysicsGroups.lua")
Script.Load("lua/CloakableMixin.lua")
Script.Load("lua/DetectableMixin.lua")
Script.Load("lua/FireMixin.lua")
Script.Load("lua/GameEffectsMixin.lua")

kBabblerMoveTypeStr = { 'None', 'Move', 'Cling', 'Attack', 'Wag' }
kBabblerMoveType = enum(kBabblerMoveTypeStr)

class 'Babbler' (ScriptActor)

Babbler.kMapName = "babbler"

Babbler.kModelName = PrecacheAsset("models/alien/babbler/babbler.model")
Babbler.kModelNameShadow = PrecacheAsset("models/alien/babbler/babbler_shadow.model")
local kBabblerModelVariants =
{
    [kBabblerVariants.normal] = Babbler.kModelName,
    [kBabblerVariants.Shadow] = Babbler.kModelNameShadow,
    [kBabblerVariants.Abyss] = Babbler.kModelName,
    [kBabblerVariants.Reaper] = Babbler.kModelName,
    [kBabblerVariants.Nocturne] = Babbler.kModelName,
    [kBabblerVariants.Kodiak] = Babbler.kModelName,
    [kBabblerVariants.Toxin] = Babbler.kModelName,
    [kBabblerVariants.Auric] = Babbler.kModelNameShadow,
}
local kBabblerWorldMaterialIndex = 0

local kAnimForagingDuration = 4
local kAnimationGraph = PrecacheAsset("models/alien/babbler/babbler.animation_graph")

Babbler.kMass = 15
Babbler.kRadius = 0.25
Babbler.kProcessHitRadius = 0.70

local kFinalDampingAfterDelay = 0.20 -- This seems to be the sweet spot delay
Babbler.kLinearDamping = 0
Babbler.kLinearDampingAtSpawn = 10 -- So they don't scatter at mac3 speed

Babbler.kRestitution = 0.30
Babbler.kFov = 360

Babbler.kWebWalkSpeed = 1.1
Babbler.kWebStanceRadius = 0.015

local kMaxWagDist = 8
local kTargetSearchRange = 12
local kTargetMaxFollowRange = 30
local kAttackRate = 0.42

local kBabblerOffMapInterval = 1
local kBabblerWagInterval = 0.4
local kUpdateMoveInterval = 0.3
local kUpdateAttackInterval = 0.4

local kMinJumpDistance = 5
local kBabblerRunSpeed = 8.2
local kBabblerJumpSpeed = 7.75
local kVerticalJumpForce = 6
local kMaxJumpForce = 15
local kMinJumpForce = 5
local kTurnSpeed = math.pi

-- Natural ground-movement wander: instead of beelining every path segment,
-- drift a heading offset via a clamped random walk and nudge each tick's
-- move sideways by it. Pathing re-aims from wherever we land next tick, so
-- this never fights its way back to the target - it just keeps the trip
-- there from looking like it's riding a rail.
local kWanderMaxAngle = math.rad(35)
local kWanderTurnAccel = 6 -- rad/s of random-walk drift on the wander angle

-- Subtle forward-speed pulse layered on top, so the run cadence doesn't
-- read as a constant conveyor-belt speed.
local kGaitPulseAmount = 0.12 -- +/- fraction of kBabblerRunSpeed

local Math_Wrap = Math.Wrap
local Math_Degrees = Math.Degrees

local math_atan2 = math.atan2

function GetEngagementOrOrigin(entity)
    if entity:isa("Player") then
        return entity:GetEyePos() -- Like bees, aim for the eyes
    end
    return HasMixin(entity, "Target") and entity:GetEngagementPoint() or entity:GetOrigin()
end

-- Small helpers to avoid allocating temp vectors
local function VecSub(out, a, b)
    out.x, out.y, out.z = a.x - b.x, a.y - b.y, a.z - b.z
    return out
end

local function VecAddScaled(out, a, b, scale)
    out.x, out.y, out.z = a.x + b.x * scale, a.y + b.y * scale, a.z + b.z * scale
    return out
end

local networkVars =
{
    attacking = "boolean",
    targetId = "entityid",
    ownerId = "entityid",
    clinged = "boolean",

    onWeb = "boolean",
    webWalking = "boolean",

    doesGroundMove = "boolean",
    jumping = "boolean",
    wagging = "boolean",
    foraging = "boolean",
    hungry = "boolean",
    creationTime = "time",
    silenced = "boolean",
    variant = "enum kBabblerVariants",
    -- Facing is derived client-side from moveDirection (see OnAdjustModelCoords),
    -- so this is never actually sent: bucket size 10 exceeds the 2*pi range.
    m_angles = "interpolated angles (by 10 [], by 10 [], by 10 [])",
    m_origin = "compensated interpolated position (by 0.015 [2 3 6], by 0.015 [2 3 7], by 0.015 [2 3 6])"
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ClientModelMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(CloakableMixin, networkVars)
AddMixinNetworkVars(DetectableMixin, networkVars)
AddMixinNetworkVars(FireMixin, networkVars)
AddMixinNetworkVars(GameEffectsMixin, networkVars)

-- The babbler ball / pheromone is the *only* thing that should decide these
-- three outcomes. Everything else a babbler does (idle wander, off-map
-- recovery, re-acquiring a morphed target, MoveRandom's own owner-seeking)
-- is idle behavior and talks to SetMoveType directly - see the Order*
-- wrappers below for the ball's entry points.
--
--   * hit a web, a player, or anything else that can host a cling -> Cling
--   * hit a damageable enemy                                      -> Attack
--   * hit nothing usable (or nothing at all)                      -> Move
function GetBabblerBallOrder(owner, target)

    if not target or not owner then
        return kBabblerMoveType.Move
    end

    local teamNumber = owner:GetTeamNumber()
    if HasMixin(target, "Team") and GetEnemyTeamNumber(teamNumber) == target:GetTeamNumber() then

        local canDamage = HasMixin(target, "Live") and target:GetIsAlive() and target:GetCanTakeDamage()

        return canDamage and kBabblerMoveType.Attack or kBabblerMoveType.Move
    end

    local isTargetAlive = HasMixin(target, "Live") and target:GetIsAlive()
    if isTargetAlive and target:isa("Player") and HasMixin(target, "BabblerCling") and target:GetCanAttachBabbler() then
        return kBabblerMoveType.Cling
    elseif target:isa("Web") and owner and HasMixin(owner, "BabblerOwner")
        and target:GetNumWebbedBabblers() < kWebMaxBabblers -- Check for web free slots
        and owner:GetBabblerCount() - owner:GetNumWebbedBabblers() > 0
        then
        return kBabblerMoveType.Cling
    end

    return kBabblerMoveType.Move
end

-- Cling-attach and babbler-cap counters (BabblerClingMixin, BabblerOwnerMixin) only update
-- once a babbler physically arrives and clings - they don't reflect babblers already
-- travelling toward a target with a Cling order. Anything computing how much room is left
-- on a target needs to subtract these in-flight babblers too, or it'll keep dispatching more
-- past the target's real remaining capacity while the first batch is still en route.
function GetNumBabblersEnRouteToCling(target)

    local count = 0
    if not target then return count end

    for _, babbler in ipairs(GetEntitiesForTeam("Babbler", target:GetTeamNumber())) do

        local isClinged = babbler:GetIsClinged()
        local hasClingOrder = (babbler.moveType == kBabblerMoveType.Cling)
        if not isClinged and hasClingOrder and babbler:GetTarget() == target then
            count = count + 1
        end

    end

    return count

end
function Babbler:CreateHitBox(coords)

    if self:GetIsAlive() and not self:GetIsDestroyed() and not self.clinged then

        if self.hitBox then
            if coords then
                self.hitBox:SetCoords(coords)
            end
            return
        end

        coords = coords or self:GetCoords()
        self.hitBox = Shared.CreatePhysicsSphereBody(false, Babbler.kRadius * 2, Babbler.kMass, coords)
        self.hitBox:SetGroup(PhysicsGroup.BabblerGroup)
        self.hitBox:SetCoords(coords)
        self.hitBox:SetEntity(self)
        self.hitBox:SetPhysicsType(CollisionObject.Kinematic)
        self.hitBox:SetTriggeringEnabled(true)

    end

end

function Babbler:SyncPhysicsCoords()
    if self.physicsBody then
        self.physicsBody:SetCoords(self:GetCoords())
    end
end

function Babbler:NotifyOwnerDestroyed(owner)
    if owner and HasMixin(owner, "BabblerOwner") then
        if self.babblerBombSpawned then
            owner:BombBabblerDestroyed()
        else
            owner:BabblerDestroyed()
        end
    end
end

function Babbler:NotifyOwnerCreated(owner)
    if owner and HasMixin(owner, "BabblerOwner") then
        if self.babblerBombSpawned then
            owner:BombBabblerCreated()
        else
            owner:BabblerCreated()
        end
    end
end

function Babbler:OnCreate()

    ScriptActor.OnCreate(self)

    InitMixin(self, BaseModelMixin)
    InitMixin(self, ClientModelMixin)

    InitMixin(self, LiveMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, DamageMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, CloakableMixin)
    InitMixin(self, DetectableMixin)
    InitMixin(self, FireMixin)
    InitMixin(self, GameEffectsMixin)

    self.variant = kDefaultBabblerVariant
    self.AttackDamageType = kDamageType.Normal
    self.lastSetRelevancyMask = nil

    if Server then

        self.targetId = Entity.invalidId
        self.timeLastJump = 0
        self.timeLastAttack = 0

        self.kNextUpdateAttack = 0
        self.jumpAttempts = 0

        self.kStopImpulseDone = 0
        self.timeLastStopImpulse = 0

        self.silenced = false
        -- Set true by Web:AttachInitialBabblers; everywhere else a babbler is
        -- created with a real owner.
        self.webSpawned = false

        InitMixin(self, PathingMixin)

        self.moveType = kBabblerMoveType.None
        self.clinged = false

        self.foraging = false
        self.hungry = false
        self.onWeb = false
        self.webWalking = false

        self.attacking = false

        self.creationTime = Shared.GetTime()

    elseif Client then

        self.clientJumping = self.jumping
        self.clientAttacking = self.attacking
        self.clientVelocity = nil

        self.dirtySkinState = false
        self.delayedSkinUpdate = false

    end

    self.lastOrigin = Vector(0,0,0)

    self:SetUpdateRate(kRealTimeUpdateRate)

end

function Babbler:OnInitialized()

    self:SetModel(Babbler.kModelName, kAnimationGraph)

    self.hatchAttack = true
    self.timeNextMoveJump = Shared.GetTime() + math.random() * 2
    self.attackRate = 0

    if Server then

        InitMixin(self, MobileTargetMixin)
        InitMixin(self, TargetCacheMixin)

        self:RefreshFreeRoam()
        self.targetSelector = TargetSelector():Init(
                                    self,
                                    kTargetSearchRange,
                                    true,
                                    { kAlienStaticTargets, kAlienMobileTargets })

        self:UpdateJumpPhysicsBody()

        self:Jump(Vector(
            math.random() * 2 - 1,
            4 - math.random() * 2,
            math.random() * 2 - 1)
        )

        -- Per-babbler personality: some scurry, some dawdle, some are restless
        self.webSpeedMult = 0.85 + math.random() * 0.35
        self.webIdleMult  = 0.75 + math.random() * 0.6

        -- Per-babbler ground-move personality, so a swarm doesn't weave or
        -- pulse in lockstep (see kWanderMaxAngle / kGaitPulseAmount usage in Move)
        self.wanderAngle = 0
        self.wanderTurnAccel = kWanderTurnAccel * (0.6 + math.random() * 0.8)
        self.gaitPhase = math.random() * math.pi * 2
        self.gaitFreq = 4 + math.random() * 4

    end

end

function Babbler:DestroyHitbox()
    if self.hitBox then

        Shared.DestroyCollisionObject(self.hitBox)
        self.hitBox = nil

    end
end

function Babbler:GetIsFlameAble()
    return true
end

function Babbler:GetIsAffectedByCrush()
    return true
end

function Babbler:OnDestroy()

    if Server then

        if not self.ownerCountNotified then
            self.ownerCountNotified = true
            self:NotifyOwnerDestroyed(self:GetOwner())
        end

        if self.onWeb then
            local web = self:GetWeb()
            if web then
                web:RemoveWebbedBabbler(self)
            end
        end

        self:Detach()
    end

    if self.physicsBody then
        Shared.DestroyCollisionObject(self.physicsBody)
        self.physicsBody = nil
    end

    self:DestroyHitbox()

    if Client then
        self.clientVelocity = nil

        local model = self:GetRenderModel()
        if model and self.addedToHiveVision then
            HiveVision_RemoveModel(model)
        end
    end

    ScriptActor.OnDestroy(self)

end

function Babbler:SetVariant(babblerVariant)
    self.variant = babblerVariant
    local model = kBabblerModelVariants[babblerVariant] or Babbler.kModelName
    assert(model)
    self:SetModel(model, kAnimationGraph)
end

function Babbler:OnModelChanged(hasModel)
    if hasModel then
        self.delayedSkinUpdate = true   --have to give time for the model to swap
        self.dirtySkinState = false
        self.addedToHiveVision = false
    end
end

function Babbler:GetIsClinged()
    return self.clinged
end

function Babbler:GetIsOnWeb()
    return self.onWeb == true
end

function Babbler:GetCanTakeDamage()
    return not self:GetIsClinged()
end

function Babbler:GetTarget()

    if self.targetId == nil or self.targetId == Entity.invalidId then
        return nil
    end

    return Shared.GetEntity(self.targetId)

end

function Babbler:GetIsOnGround(performGroundTrace)
    local vel = self:GetVelocity()
    local velLength = vel:GetLength()
    local absVelY = math.abs(vel.y)
    local absLastVelY = self.lastVelocity and math.abs(self.lastVelocity.y) or 0

    local minSpeed = 0.5
    local minGlidingSpeed = 3.5

    local isGlidingOnFloor = velLength < minGlidingSpeed and absVelY < 0.3
    local isOnGround = velLength < minSpeed or isGlidingOnFloor or self.babblerOffMap

    -- Extra condition to avoid snapping down when we are on physics body / gravity / jump
    -- Worst case figure, the babbler will look like it is falling in-place on the ground,
    -- but it won't produce a visual breaking teleport-down (because re-attaching to pathing mesh)
    if isOnGround and self.physicsBody and not self.babblerOffMap then

        local now = Shared.GetTime()
        local atApex = false
        if self.timeLastJump and self.lastVelocity then
            local tDiff = now - self.timeLastJump
            if 0.2 < tDiff and tDiff < 2.0 then  -- Within jump arc timeframe
                local nearApex = false
                local slowingDown = velLength < self.lastVelocity:GetLength() * 0.95
                local turningDown = vel.y < self.lastVelocity.y
                nearApex = absVelY < 0.3
                atApex = slowingDown and turningDown and nearApex
            end
        end

        -- Spawn protection
        if now - self:GetCreationTime() < 0.3 then
            isOnGround = false
        end

        -- Test if we are at the topmost jump position
        if atApex then
            isOnGround = false
        end

        -- Really make sure we stabilized (no longer going down)
        local minYSpeed = 0.1
        if not (absVelY < minYSpeed and absLastVelY < minYSpeed) then
            isOnGround = false
        end
    end

    return isOnGround
end

function Babbler:GetVelocity()

    if self.physicsBody then
        return self.physicsBody:GetLinearVelocity()
    end
    if self.lastOrigin and self.lastUpdate then
        local dt = Shared.GetTime() - self.lastUpdate
        if dt > kEpsilon then
            return (self:GetOrigin() - self.lastOrigin) / dt
        end
    end
    return Vector(0,0,0)

end

local kDefaultMask = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToReadyRoom)
local kDefaultMaskTeam1 = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToTeam1Commander, kRelevantToReadyRoom)
local kDefaultMaskTeam2 = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToTeam2Commander, kRelevantToReadyRoom)
local kDefaultMaskBoth = bit.bor(kDefaultMaskTeam1, kDefaultMaskTeam2)

-- Squared distance a babbler must stay within its owner to inherit the owner's "sighted"
-- reveal (e.g. from a marine scan).
local kSightedFollowRangeSq = 16
local kSightedLingerTime = 1

function Babbler:UpdateRelevancy()

    PROFILE("Babbler:UpdateRelevancy")

    local owner = self:GetOwner()
    local ownerSighted = owner ~= nil and (owner:GetOrigin() - self:GetOrigin()):GetLengthSquared() < kSightedFollowRangeSq
            and (HasMixin(owner, "LOS") and owner:GetIsSighted())

    local now = Shared.GetTime()
    if ownerSighted or (self:GetIsDetected() and self:GetIsOnWeb()) then
        self.timeLastSighted = now
    end

    local sighted = self.timeLastSighted ~= nil and now < self.timeLastSighted + kSightedLingerTime

    local mask = kDefaultMask

    local teamNumber = self:GetTeamNumber()
    if teamNumber == 1 then
        mask = kDefaultMaskTeam1
        if sighted then
            mask = kDefaultMaskBoth
        end
    end

    if teamNumber == 2 then
        mask = kDefaultMaskTeam2
        if sighted then
            mask = kDefaultMaskBoth
        end
    end

    if self.lastSetRelevancyMask ~= mask then
        self:SetExcludeRelevancyMask(mask)
        self.lastSetRelevancyMask = mask
    end

end


local function NoObstacleInWay(self, targetPos, ignoreEntity)
    local filter = ignoreEntity and EntityFilterTwoAndIsa(self, ignoreEntity, "Babbler") or EntityFilterOneAndIsa(self, "Babbler")
    local trace = Shared.TraceRay(self:GetEyePos(), targetPos,
            CollisionRep.LOS, PhysicsMask.All, filter)
    return trace.fraction >= 0.9
end

local kCanReachFallbackDist = 2 -- In case we are above target (cannot move to it with path)
local function CanReachTarget(self, target)

    local trace = Shared.TraceRay(self:GetEyePos(), GetEngagementOrOrigin(target),
            CollisionRep.LOS, PhysicsMask.All, EntityFilterAll())

    if trace.fraction >= 0.9 then
        return true
    end

    local toTarget = target:GetOrigin() - self:GetOrigin()
    return toTarget:GetLengthXZ() < kCanReachFallbackDist

end

function Babbler:UpdateClientSkinState()

    if Client and self.delayedSkinUpdate then
        self.dirtySkinState = true
        self.delayedSkinUpdate = false
    end

end

function Babbler:UpdateBabbler(deltaTime)

    self:UpdateClientSkinState()

    if self:GetIsClinged() or not self:GetIsAlive() then
        self.attacking = false
        self.doesGroundMove = false
        return
    end

    if Server then

        self.attacking = self.timeLastAttack + 0.2 > Shared.GetTime()

        if self.foraging or self.hungry then
            self:UpdateRelevancy()
            return
        end
        if self:GetIsOnWeb() then
            self:UpdateWebBehavior(deltaTime)
            self:UpdateRelevancy()
            return
        end

        local success = true
        local targetReached = false

        local target = self:UpdateTargetPos()
        local isEnemy = target and HasMixin(target, "Team")
                and target:GetTeamNumber() == GetEnemyTeamNumber(self:GetTeamNumber())

        if (self.moveType == kBabblerMoveType.Move or self.moveType == kBabblerMoveType.Cling) and self.timeLastJump + 0.5 < Shared.GetTime() and self:GetIsOnGround() then
            success, targetReached = self:UpdateMove(target, deltaTime) --> :Move()
        end

        -- If reached, try to cling to it
        if success and self.moveType == kBabblerMoveType.Cling then
            success = self:UpdateCling(target, deltaTime) --> :Cling()
        end

        if not success then
            self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
        end

        self.jumping = not self:GetIsOnGround()
        self:UpdateJumpPhysicsBody()
        self:UpdateJumpPhysics(deltaTime)

        self.wagging = self.moveType == kBabblerMoveType.Wag

        if isEnemy and self.moveType == kBabblerMoveType.Move and target and targetReached and CanReachTarget(self, target) then
            local targetPos = HasMixin(target, "Target") and target:GetEngagementPoint() or target:GetOrigin()
            self:SetMoveType(kBabblerMoveType.Attack, target, targetPos, true)
        end

        if target and self.moveType == kBabblerMoveType.Attack then
            self:UpdateAttack(target, false)
        end

        -- A finished Move with no enemy on it is a dead order. Drop back to
        -- None so MoveRandom can roll the next idle flavour (or wag/follow).
        if self.moveType == kBabblerMoveType.Move and targetReached and not isEnemy then
            self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
        end

        self:UpdateRelevancy()

        if self:GetOrigin() == self.lastOrigin and not self:GetIsOnGround() then
            self:SetGroundMoveType(false) -- Re-enables gravity (just in case)
        end

    elseif Client then

        self:UpdateMoveDirection(deltaTime)

        local model = self:GetRenderModel()
        if model ~= nil and not self.addedToHiveVision then
            HiveVision_AddModel(model, kHiveVisionOutlineColor.Green)
            self.addedToHiveVision = true
        end

    end

    self.lastVelocity = self:GetVelocity()
    self.lastUpdate = Shared.GetTime()

    VectorCopy(self:GetOrigin(), self.lastOrigin)

end

function Babbler:UpdatePhysics()
    self:CreateHitBox()
    if self.hitBox then
        local coords = self:GetCoords()
        self.hitBox:SetCoords(coords)
    end
end

function Babbler:GetCanBeUsed(entity, useSuccessTable)

    local success = true

    if not GetAreFriends(self, entity) or self:GetIsClinged() then
        success = false
    end

    if success and HasMixin(entity, "BabblerCling") then
        if not entity:GetCanAttachBabbler() then
            success = false
        end
        if entity:GetNumClingedBabblers() >= entity:GetMaxClingedBabblers() then
            success = false
        end
    end

    useSuccessTable.useSuccess = success

end

function Babbler:GetUseAllowedBeforeGameStart()
    return true
end

function Babbler:GetCanBeUsedDuringWarmup()
    return true
end

function Babbler:GetIsSecondaryUseUnit()
    return true
end

function Babbler:OnUse(player, elapsedTime, useSuccessTable)
    if Server and not self:GetIsClinged() then

        if self:GetIsOnWeb() then
            self:DetachFromWeb()
        end

        self:OrderCling(player, GetEngagementOrOrigin(player))
    end

    self:TriggerEffects("babbler_jump")

end

function Babbler:OnUpdatePhysics()
    self:UpdatePhysics()
end

function Babbler:OnFinishPhysics()
    self:UpdatePhysics()
end

function Babbler:OnUpdate(deltaTime)
    PROFILE("Babbler:OnUpdate")

    ScriptActor.OnUpdate(self, deltaTime)

    if self:GetIsClinged() then
        self:UpdateClientSkinState()
        return
    end

    self:UpdateBabbler(deltaTime)

    if Server and not self:GetIsOnWeb() then

        local now = Shared.GetTime()
        if not self.cb_routine_moveRandom or now > self.cb_routine_moveRandom then
            self:MoveRandom()
            self.cb_routine_moveRandom = now + kUpdateMoveInterval + math.random() / 8
        end
        if not self.cb_routine_updateWag or now > self.cb_routine_updateWag then
            self:UpdateWag()
            self.cb_routine_updateWag = now + kBabblerWagInterval
        end

        if not self.cb_routine_babblerOffMap or now > self.cb_routine_babblerOffMap then
            self:BabblerOffMap()
            self.cb_routine_babblerOffMap = now + kBabblerOffMapInterval
        end
        if self.babblerOffMap then
            -- Move toward destination to get back into the map we left like a coward
            local orig = self:GetOrigin()
            local dest = self.babblerOffMapRecoveryOrig
            local newPos = orig + (dest - orig):GetUnit() * deltaTime * kBabblerRunSpeed

            -- If close enough go straight for it
            -- Otherwise, we could have moved too far between now and next tick check
            if newPos:GetDistanceTo(dest) <= deltaTime * kBabblerRunSpeed then
                newPos = dest
            end
            if orig:GetDistanceTo(dest) >= kEpsilon then
                self:SetOrigin(newPos)
                self:SetGroundMoveType(true)
            end
        end
    end

end

function Babbler:OnProcessMove(input)
    local deltaTime = input.time
    self:UpdateBabbler(deltaTime)

    if Server then

        if self:GetIsClinged() then

            local parent = self:GetParent()
            if parent  then
                -- Somehow this position is used when I detach in specific cases on direct babbler balls hit
                -- So I have to set it correctly... even thought it should not be needed
                -- Only use GetAttachedOrigin for entities that need babbler to detach from their attach point
                -- Others are just using babblers as shield, getorigin is enough.
                local canEverDetach = HasMixin(parent, "BabblerOwner")
                local attachedOrigin = canEverDetach and parent:GetAttachedOrigin(self) or parent:GetOrigin()

                local current = self:GetOrigin()
                local dx, dy, dz = attachedOrigin.x - current.x, attachedOrigin.y - current.y, attachedOrigin.z - current.z
                if dx * dx + dy * dy + dz * dz > kEpsilon * kEpsilon then
                    self:SetOrigin(attachedOrigin) -- Only set if owner actually moved
                end
            end
        end

    end

end

function Babbler:GetPhysicsModelAllowedOverride()
    return false
end

if Server then

    function Babbler:RefreshFreeRoam()
        local babblerSearchTime = 6
        self.freeRoamUntil = Shared.GetTime() + babblerSearchTime
    end

    local kIdleConfig =
    {
        foragingChance = 0.4,                 -- Dig the ground for a bit
        pauseChance  = 0.28,                  -- sniff the air, do nothing
        pauseMin     = 1.4,  pauseRange = 2.6,
        chirpChance  = 0.3,                   -- chirp during pauses
        wanderMin    = 1.5,  wanderRange = 3.5,
        hopChance    = 0.45,                  -- mid-dart hop
        followChance = 0.3,                   -- visit a sibling babbler
        crowdRadius  = 1.4,                   -- don't stack on siblings
        crowdPush    = 1.5,
    }

    function Babbler:PickIdleDestination()

        local origin = self:GetOrigin()

        -- Mild flocking: sometimes just go see what a sibling is up to
        if math.random() < kIdleConfig.followChance then
            local siblings = GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), origin, 5)
            if #siblings > 1 then
                for _ = 1, 3 do
                    local s = siblings[math.random(1, #siblings)]
                    if s ~= self and s:GetIsAlive() and not s:GetIsClinged() then
                        return s:GetOrigin()
                    end
                end
            end
        end

        -- Crowd repulsion: stop babblers from funneling into the same spot
        local crowd = Vector(0, 0, 0)
        local crowded = false
        for _, s in ipairs(GetEntitiesWithinRange("Babbler", origin, kIdleConfig.crowdRadius)) do
            if s ~= self then
                crowd = crowd + (origin - s:GetOrigin())
                crowded = true
            end
        end
        if crowded then
            crowd:Normalize()
            crowd:Scale(kIdleConfig.crowdPush)
        end

        -- Occasionally investigate a nearby living teammate (hive, gorge...)
        local dest
        if math.random() < 0.3 then
            local interesting = GetEntitiesWithMixinForTeamWithinRange(
                    "Live", self:GetTeamNumber(), origin, 7)
            if #interesting > 0 then
                dest = interesting[math.random(1, #interesting)]:GetOrigin()
            end
        end

        if not dest then
            local dist = kIdleConfig.wanderMin + math.random() * kIdleConfig.wanderRange
            dest = origin + Vector((math.random() - 0.5) * 2 * dist + crowd.x,
                                   0,
                                   (math.random() - 0.5) * 2 * dist + crowd.z)
        end

        -- Snap onto real ground; a destination floating off the navmesh reads as glitchy
        local ground = GetGroundAt(self, dest, PhysicsMask.AIMovement)
        if ground ~= dest then
            dest = ground
        else
            return nil -- off-map or floating point, skip this round
        end

        return dest
    end

    -- Rolls the next idle flavour: pause, or a little dart.
    function Babbler:PickNextIdleAction()

        local now = Shared.GetTime()
        local roll = math.random()

        if roll < kIdleConfig.pauseChance then
            -- Sniff the air: stand still, maybe chirp, let the idle anim breathe
            self.idleNextDecisionTime = now + kIdleConfig.pauseMin + math.random() * kIdleConfig.pauseRange
            if math.random() < kIdleConfig.chirpChance then
                self:TriggerEffects("babbler_jump")
            elseif math.random() < kIdleConfig.foragingChance then
                if math.random() < 0.6 then
                    self.foraging = true
                else
                    self.hungry = true
                end
                self:AddTimedCallback(function(self) self.foraging = false ; self.hungry = false ; end, kAnimForagingDuration)
                self:SetMoveType(kBabblerMoveType.None, owner, ownerOrigin)
            end
        else
            local dest = self:PickIdleDestination()
            if dest then
                self:SetMoveType(kBabblerMoveType.Move, nil, dest, false, 0.2)
                if math.random() < kIdleConfig.hopChance then
                    self:JumpRandom()
                end
            end
        end
    end

    local kBabblerWebEndMargin = 0.15
    local kWebTravelSpeed = 3.5
    local kWebConfig =
    {
        strollTimeout = 8,
        idleMin       = 1,
        idleRange     = 1.8,          -- idle pause between strolls, calm: 1..2.5s
        panicMin      = 0.1,          -- panicked: chain strolls back-to-back
        panicRange    = 0.2,
        panicSpeedMult = 3.0,
        stackMax      = 2.0,          -- cap for stacking re-triggered panic

        chatterMin   = 6,
        chatterRange = 8,     -- ambient chirps, calm delay after attach
        chatterInitialMin = 2,
        chatterDelayRange = 4,
        foragingMin   = kAnimForagingDuration + 5,
        foragingRange = 18,
        foragingInitialMin = 10, -- let them spread a bit on the web first
        foragingDelayRange = 20,
        angerMin      = 0.4,
        angerRange = 0.5,    -- angry barks while panicked
    }

    local kWorldUp = Vector(0, 1, 0)
    local function GetWebUp(axis)

        local up = kWorldUp - axis * axis.y

        if up:GetLengthSquared() < 0.01 then -- nearly vertical strand
            up = Vector(1, 0, 0)
        else
            up:Normalize()
        end

        return up

    end

    local function BuildWebCoords(px, py, pz, axis, t, radius, forwardVec)

        local up = GetWebUp(axis)

        local forward = forwardVec - up * (forwardVec:DotProduct(up))
        if forward:GetLengthSquared() > kEpsilon * kEpsilon then
            forward:Normalize()
        end

        local right = up:CrossProduct(forward)

        return Coords(right, up, forward,
                Vector(px, py, pz) + axis * t + up * radius)

    end

    -- Babblers panic for a short while when the web loses a charge (enemy ran into it).
    function Babbler:PanicFromWeb(duration)

        local now = Shared.GetTime()

        local remaining = 0
        if self.panicExpire ~= nil and now < self.panicExpire then
            remaining = math.min(self.panicExpire - now, kWebConfig.stackMax)
        end
        self.panicExpire = now + remaining + duration

        self.webWalkTimer = 0
        self.timeNextWebAnger = now + 0.1

    end

    local function GetWebIdleTime(self)

        local panicking = self.panicExpire ~= nil and Shared.GetTime() < self.panicExpire

        if panicking then
            return (kWebConfig.panicMin + math.random() * kWebConfig.panicRange) * self.webIdleMult
        end

        return (kWebConfig.idleMin + math.random() * kWebConfig.idleRange) * self.webIdleMult
    end

    -- Restarts the idle/free behaviour after a babbler leaves a web or a player.
    local function ResumeFreeBehavior(self)

        self:RefreshFreeRoam()
        self:UpdateJumpPhysicsBody()
        self:OrderIdle()

    end

    function Babbler:GetWeb()
        return self.webId ~= nil and self.webId ~= Entity.invalidId and Shared.GetEntity(self.webId) or nil
    end

    local kEyeOffset = Vector(0, 0.2, 0)
    function Babbler:GetEyePos()
        return self:GetOrigin() + kEyeOffset
    end


    local kMoveVelocityScratch = Vector(0, 0, 0)
    function Babbler:GetMoveVelocity(targetPos)

        local moveVelocity = VecSub(kMoveVelocityScratch, targetPos, self:GetOrigin())
        local yDiff = moveVelocity.y
        local moveSpeedXZ = moveVelocity:GetLengthXZ()

        if moveSpeedXZ > kMaxJumpForce then
            moveVelocity:Scale(kMaxJumpForce / moveSpeedXZ)
        elseif moveSpeedXZ < kMinJumpForce then
            moveVelocity:Scale(kMinJumpForce / (moveSpeedXZ + 0.0001))
        end

        -- adjust jump height based on target's elevation
        if yDiff > 3 then
            moveVelocity.y = kVerticalJumpForce * 1.7
        elseif yDiff > 2.2 then
            moveVelocity.y = kVerticalJumpForce * 1.3
        elseif yDiff > 1.5 then
            moveVelocity.y = kVerticalJumpForce
        else
            moveVelocity.y = kVerticalJumpForce * 0.7
        end

        return moveVelocity

    end

    local kLeapVelocityScratch = Vector(0, 0, 0)
    function Babbler:GetLeapVelocity(targetPos)
        local babblerJumpGravity = 6.75

        local dirXZ = VecSub(kLeapVelocityScratch, targetPos, self:GetOrigin())
        local heightDiff = dirXZ.y
        dirXZ.y = 0

        local horizontalDist = dirXZ:GetLength()
        if horizontalDist > 0.0001 then
            dirXZ:Scale(1 / horizontalDist)
        end

        local arcHeight = math.max(heightDiff + 0.75, 1)
        local vY = math.sqrt(2 * babblerJumpGravity * arcHeight)
        local timeUp = vY / babblerJumpGravity
        local remainingHeight = arcHeight - heightDiff
        local timeDown = math.sqrt(2 * remainingHeight / babblerJumpGravity)
        local totalTime = timeUp + timeDown

        local speedXZ = Clamp(horizontalDist / math.max(totalTime, 0.0001), kMinJumpForce, kMaxJumpForce)
        dirXZ:Scale(speedXZ)
        dirXZ.y = vY
        return dirXZ, totalTime -- caller needs totalTime to know when this arc actually lands
    end

    local kJumpHangTimeEstimate = 0.8
    function Babbler:GetIsSafeJumpVelocity(velocity)

        local landingPos = self:GetOrigin() + Vector(velocity.x, 0, velocity.z) * kJumpHangTimeEstimate

        -- must have ground to land on...
        if GetGroundAt(self, landingPos, PhysicsMask.AIMovement) == landingPos then
            return false
        end

        local trace = Shared.TraceRay(self:GetEyePos(), landingPos + kEyeOffset,
                CollisionRep.Move, PhysicsMask.All, EntityFilterOneAndIsa(self, "Babbler"))

        return trace.fraction == 1

    end

    local function KillCallback(self)
        if self:GetIsAlive() and not self:GetOwner() then
            self:Kill()
        end
        return -- removes callback
    end

    function Babbler:OnOwnerChanged(oldOwner, newOwner)

        if oldOwner and not self.ownerCountNotified then
            self:NotifyOwnerDestroyed(oldOwner)
        end

        if newOwner and not self.ownerCountNotified then
            self:NotifyOwnerCreated(newOwner)
        elseif not newOwner and not self.webSpawned then
            -- Destroy Babblers without Owner
            -- Callback avoids server crashes from mixins touching a dying unit
            -- (web-spawned babblers are deliberately ownerless, see Web.lua)
            self:AddTimedCallback(KillCallback, 1)
        end

    end

    local function GetNewAlienCommanderPos(self, target)
        local pos = target:GetOrigin()
        local ents = GetEntitiesForTeam("Hive", self:GetTeamNumber())
        Shared.SortEntitiesByDistance(self:GetOrigin(), ents)

        if #ents > 0 then -- Take closest hive and cling to it until the com leaves
            pos = ents[1]:GetOrigin()
        end
        return pos
    end

    function Babbler:OnEntityChange(oldId, newId)

        if oldId == self.webId then
            local newWeb = newId and Shared.GetEntity(newId)
            if newWeb and newWeb:isa("Web") then
                self.webId = newId
            else
                self:DetachFromWeb()
                return
            end
        end

        -- Keep clinging if current host morphed into an embryo or went commander (drop otherwise)
        if oldId == self.targetId then
            local pos
            local target = newId and Shared.GetEntity(newId)
            local targetIsAlive = target and HasMixin(target, "Live") and target:GetIsAlive()
            local wasClinged = self:GetIsClinged()
            local wasClingOrder = self.moveType == kBabblerMoveType.Cling
            self.targetId = Entity.invalidId

            self:Detach()
            if wasClinged and targetIsAlive then
                if target:isa("AlienCommander") then
                    pos = GetNewAlienCommanderPos(self, target)
                elseif target:isa("Embryo") then
                    pos = target:GetOrigin()
                end
                if pos then
                    self:SetMoveType(kBabblerMoveType.Cling, nil, pos, true)
                    self.targetId = newId
                end
            elseif wasClingOrder and targetIsAlive then
                self:SetMoveType(kBabblerMoveType.Cling, nil, target:GetOrigin(), true)
                self.targetId = newId
            end
        end

    end

    function Babbler:GetTurnSpeedOverride()
        return kTurnSpeed
    end

    function Babbler:SetSilenced(silenced)
        self.silenced = silenced
    end

    local kResetJumpVelocity = Vector(0, 0, 0)
    function Babbler:Jump(velocity)
        self:SetGroundMoveType(false)

        local hasImpulse = velocity ~= nil and velocity:GetLengthSquared() > 0
        if hasImpulse then
            self.timeLastJump = Shared.GetTime()
        end

        if self.physicsBody and not (self:GetIsClinged() or self:GetIsOnWeb()) then
            if hasImpulse then
                self:SetVelocity(kResetJumpVelocity)
                local coords = self:GetCoords()
                self.physicsBody:SetCoords(coords)
                self.physicsBody:AddImpulse(coords.origin, velocity)
            end
        end
    end

    local kJumpRandomVect = Vector(0,0,0)
    function Babbler:JumpRandom()

        local velocity
        for _ = 1, 5 do
            kJumpRandomVect.x = (math.random() * 3) - 1.5
            kJumpRandomVect.y = 3 + (math.random() * 2)
            kJumpRandomVect.z = (math.random() * 3) - 1.5
            if self:GetIsSafeJumpVelocity(kJumpRandomVect) then
                velocity = kJumpRandomVect
                break
            end
        end

        -- No safe direction found nearby (likely on a ledge) -- hop straight
        -- up in place instead of risking a fall.
        if not velocity then
            kJumpRandomVect.x = 0
            kJumpRandomVect.y = 1 + math.random() * 4
            kJumpRandomVect.z = 0
            velocity = kJumpRandomVect
        end

        self:Jump(velocity)

    end

    function Babbler:UpdateMove_forwardJumps(distToTarget, targetPos)
        -- The closer we get, the higher the jump chances
        local success = false
        local jumpProbability = 0

        if distToTarget < kMinJumpDistance * 2 then
            jumpProbability = math.max(0, distToTarget - kMinJumpDistance) / 6
        end

        if jumpProbability >= math.random() then
            if NoObstacleInWay(self, targetPos) then
                self:Jump(self:GetMoveVelocity(targetPos))
                success = true
            end
        end
        return success
    end

    function Babbler:UpdateMove_randomJumps()
        -- Notes:
        --  To tune this, go gorge in a long hallway
        -- and throw babblers at the end.
        -- Tweak to your liking

        if not (self.cursor.index + 2 <= #self.cursor.points) then
            return
        end
        local now = Shared.GetTime()
        local deviation = 0.1 + math.random() * 0.2 -- How far they deviate from path when moving (no straight line, more variations)
        local highJumpProb = 0.05
        local targetOrigin = self.cursor.points[self.cursor.index + 2]
        local targetVelocity = Vector(math.random() - 0.5 < 0 and deviation or -deviation,
                0.2 + deviation * 1.5 + (math.random() < highJumpProb and 1.6 or 0),
                math.random() - 0.5 < 0 and deviation or -deviation)

        local moveVel = self:GetMoveVelocity(targetOrigin + targetVelocity)
        local jumpSpeed = moveVel:GetLength()

        if jumpSpeed > kBabblerJumpSpeed then
            moveVel:Scale(kBabblerJumpSpeed / jumpSpeed)
        end

        if self:GetIsSafeJumpVelocity(moveVel) then
            self:Jump(moveVel)
            self:TriggerUncloak()
        end

        -- The constant added delay has to be higher than the self.timeLastJump delay in the function
        -- so we are sure that we are not jumping as soon as we reached the floor
        local rand = 0.5 + math.random() * 0.7
        self.timeNextMoveJump = now + 0.4 + rand * rand * rand
    end

    function Babbler:Move(distToTarget, targetPos, deltaTime)

        local now = Shared.GetTime()
        local prevOrig = self:GetOrigin()
        local prevY = prevOrig.y

        -- Follow pathfinding, simply moving accross the map toward target
        local moveDone = true

        local dx0, dz0 = prevOrig.x - targetPos.x, prevOrig.z - targetPos.z
        if dx0 * dx0 + dz0 * dz0 > 0.0625 then -- same threshold as (prevOrig - targetPos):GetLengthXZ() > 0.25
            self:SetGroundMoveType(true)

            -- Gait pulse: subtle +/- speed wobble instead of a constant crawl
            -- speed, so the cadence (and the run-blend anim it drives, since
            -- that reads back actual velocity) doesn't look like a conveyor belt.
            local gaitSpeed = kBabblerRunSpeed * (1 + kGaitPulseAmount * math.sin(self.gaitPhase))
            self.gaitPhase = self.gaitPhase + deltaTime * self.gaitFreq

            moveDone = self:MoveToTarget(PhysicsMask.AIMovement, targetPos, gaitSpeed, deltaTime)

            local newOrigin = self:GetOrigin()
            -- Only lift while we really travelled; a stalled babbler must not
            -- keep ratcheting Y tick after tick
            local travelled = prevOrig:GetDistanceTo(newOrigin)
            if travelled > kEpsilon then

                local ground = GetGroundAt(self, newOrigin, PhysicsMask.AIMovement)
                local desiredY = ground.y + Babbler.kRadius
                -- a trace more than a step below means we found another level, not the
                -- surface we are walking on: keep last Y rather than diving through
                if prevY - desiredY < 1 then
                    newOrigin.y = Slerp(prevY, desiredY, deltaTime * Clamp(travelled / deltaTime / 2, 0, 3))
                end

                -- Weave: drift the wander angle with a clamped random walk, then
                -- rotate this tick's XZ displacement by it. Only the extra
                -- sideways component is applied (forward progress isn't shortened),
                -- and because pathing re-aims fresh from the new origin every
                -- tick, the drift never has to be corrected back out - it just
                -- makes the trip look less like it's on a rail.
                self.wanderAngle = Clamp(self.wanderAngle + (math.random() - 0.5) * deltaTime * self.wanderTurnAccel,
                        -kWanderMaxAngle, kWanderMaxAngle)

                local moveDirX, moveDirZ = newOrigin.x - prevOrig.x, newOrigin.z - prevOrig.z
                if moveDirX * moveDirX + moveDirZ * moveDirZ > kEpsilon * kEpsilon then
                    local sinA, cosA = math.sin(self.wanderAngle), math.cos(self.wanderAngle)
                    newOrigin.x = newOrigin.x + (moveDirX * cosA - moveDirZ * sinA - moveDirX)
                    newOrigin.z = newOrigin.z + (moveDirX * sinA + moveDirZ * cosA - moveDirZ)
                end

                self:SetOrigin(newOrigin)
            end

            self.targetSelector:AttackerMoved()
        end

        -- Errative jump behavior when going from one place to an other
        -- Applies if we are at least X path points away from target

        if not moveDone
            and self.cursor and self.cursor.index + 5 <= #self.cursor.points
            and self.timeNextMoveJump < now
            -- and (not self.lastMoveJumpPathPointLeft or self.cursor.index < self.lastMoveJumpPathPointLeft)
        then

            -- Could eventually do double jumps (forward and sideway)
            self:UpdateMove_randomJumps()
            self:UpdateMove_forwardJumps(distToTarget, targetPos)

            -- The constant added delay has to be higher than the self.timeLastJump delay in the function
            -- so we are sure that we are not jumping as soon as we reached the floor
            local rand = 0.5 + math.random() * 0.7
            self.timeNextMoveJump = now + 0.4 + rand * rand * rand
        end

        return moveDone

    end

    function Babbler:UpdateMove(target, deltaTime)

        PROFILE("Babbler:UpdateMove")

        local success = false
        local targetReached = false

        local orig = self:GetOrigin()
        local targetPos = self.targetPos or (target and target:GetOrigin())
        local distToTarget, distToTargetXZ
        if targetPos then
            local dx, dy, dz = orig.x - targetPos.x, orig.y - targetPos.y, orig.z - targetPos.z
            distToTargetXZ = math.sqrt(dx * dx + dz * dz)
            distToTarget = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        local isFriend = target and target.GetTeamNumber and target:GetTeamNumber() == self:GetTeamNumber()

        if distToTarget and distToTarget < kMinJumpDistance then
            self.targetReached = true
        end

        local followTarget = false
        if target then
            followTarget = (isFriend or (not self.targetReached or distToTarget <= kTargetMaxFollowRange))
        end

        local hasSomethingToMoveTo = targetPos and (target == nil or followTarget)
        if hasSomethingToMoveTo then

            local moveDone = self:Move(distToTarget, targetPos, deltaTime)
            if moveDone or distToTargetXZ < 0.5 then
                targetReached = true
            end
            success = true

        end
        return success, targetReached
    end

    -- Ground-hug toward a cling attach point at run speed.
    local kWalkOriginScratch = Vector(0, 0, 0)
    local function WalkTowardAttachPoint(self, delta, distance, deltaTime)
        local moveDir = GetNormalizedVector(delta)
        local travelDistance = math.min(deltaTime * kBabblerRunSpeed, distance)
        self:SetGroundMoveType(true)
        local newOrigin = VecAddScaled(kWalkOriginScratch, self:GetOrigin(), moveDir, travelDistance)
        self:SetOrigin(newOrigin)
    end

    function Babbler:Cling(target, deltaTime)


        local babblerMaxLeapDistance = 5
        if not target then return false end
        if not target:GetIsAlive() then return false end

        local attachPointOrigin, isWeb = self:GetClingAttachPoint(target)

        if not attachPointOrigin then
            return false
        end

        local now = Shared.GetTime()
        local orig = self:GetOrigin()
        local delta = attachPointOrigin - orig
        local distance = delta:GetLength()

        local d = 0.7
        local isAlienCom = target and target:isa("AlienCommander")
        local isOnos = target and target:isa("Onos")

        -- More tolerant if the babbler is overshooting its jump and goes above the web
        -- We want visually the babbler to "land" on the web on its own rather than direct assist it too much
        local yDiff = (attachPointOrigin.y - orig.y)
        local babblerDirectApproachRange = target:isa("Web") and 1.5 or (isAlienCom and 7 or (isOnos and 3.5 or 2.5))
        if distance <= d
            or (target:isa("Web") and target:GetClosestPointOnWeb(orig):GetDistanceTo(orig) < d)
            then
            local attachSuccess = self:FinalizeClingAttach(target, isWeb, attachPointOrigin)
            if not attachSuccess then
                self:Detach()
                return false
            end
            return true
        end

        -- direct approach: no real height to climb. Walk
        local obstacleInWay = not NoObstacleInWay(self, attachPointOrigin, target)
        if (distance < babblerDirectApproachRange and not obstacleInWay)
        then
            WalkTowardAttachPoint(self, delta, distance, deltaTime)
        else -- Multi-leap upward (or level, or downward) toward targets
            local leapTarget = attachPointOrigin

            if (self.nextLeapTime or 0) < now then
                if distance > babblerMaxLeapDistance then
                    leapTarget = orig + GetNormalizedVector(delta) * babblerMaxLeapDistance
                end

                local moveVelocity, flightTime = self:GetLeapVelocity(leapTarget)
                -- If target is above a 45/3 degree angle from us, need to jump
                -- If we havn't jumped for a while (stuck ?) jump anyway
                if not obstacleInWay and (yDiff > -0.5 or now - self.timeLastJump > 3) then
                    self:Jump(moveVelocity)
                end
                self.nextLeapTime = now + flightTime/2 + math.random() * 0.3
            end
        end
        return true

    end

    function Babbler:UpdateCling(target, deltaTime)
        if not self:Cling(target, deltaTime) then
            self:Detach()
            return false
        end
        return true
    end

    function Babbler:UpdateWag()

        if self.moveType == kBabblerMoveType.Wag and not self.babblerOffMap and self:GetIsOnGround() then

            local owner = self:GetOwner()
            if not owner or (owner:GetOrigin() - self:GetOrigin()):GetLength() > kMaxWagDist then
                self:SetMoveType(kBabblerMoveType.None)
            end

        end

    end

    function Babbler:GetBabblerBall()

        local orig = self:GetOrigin()
        local ballsInRange = GetEntitiesForTeamWithinRange("BabblerPheromone", self:GetTeamNumber(), orig, 20)

        local best, bestDist
        for _, ball in ipairs(ballsInRange) do

            -- Ignore balls that are already close to us, balls this order was
            -- already cancelled on (a newer throw superseded them - chasing a
            -- disabled ball made babblers walk toward stale throws), and balls
            -- that belong to a different owner.
            local dist = (ball:GetOrigin() - orig):GetLength()
            if dist > 4 and not ball.babblerOrderingDisabled and ball:GetOwnerId() == self:GetOwnerId() then
                if not bestDist or dist < bestDist then
                    best = ball
                    bestDist = dist
                end
            end

        end

        return best

    end

    local kOffMapOffset = Vector(0, 0.001, 0)
    function Babbler:GetIsBabblerOffMap()
        local orig = self:GetOrigin() + kOffMapOffset
        local ground = GetGroundAt(self, orig, PhysicsMask.AIMovement)
        local babblerOffMap = (ground == orig)

        return babblerOffMap, ground
    end

    function Babbler:BabblerOffMap()

        local babblerOffMap = self:GetIsBabblerOffMap()

        if self.babblerOffMap then
            if not babblerOffMap then
                self.babblerOffMap = nil
                self:UpdateJumpPhysicsBody()
                self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
                self:Jump(nil) -- Force update physics and reset ground move
            end
            return
        end

        if babblerOffMap then
            local inMapOrig
            local RTs = GetEntities("ResourcePoint")

            if #RTs > 0 then
                Shared.SortEntitiesByDistance(self:GetOrigin(), RTs)
                for _ = 1, 10 do
                    inMapOrig = GetRandomSpawnForCapsule(1, 1, RTs[1]:GetOrigin() + Vector(0, 1, 0),
                            1, 6, EntityFilterAll())
                    if inMapOrig then
                        break
                    end
                end
            end

            if inMapOrig then
                self.babblerOffMap = true
                self.babblerOffMapRecoveryOrig = inMapOrig + Vector(0, 0.5, 0)
            end
        end
    end

    -- Returns a sibling's live target if any idle-relevant babbler of the same
    -- owner is already fighting, nil when the whole pack is idle.
    function Babbler:AdoptSiblingTarget(ownerId)

        local siblings = GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), self:GetOrigin(), kTargetMaxFollowRange)
        for _, sibling in ipairs(siblings) do
            if sibling ~= self and sibling:GetOwnerId() == ownerId and not sibling:GetIsClinged() then
                local target = sibling:GetTarget()
                local isEnemy = target and HasMixin(target, "Team") and GetEnemyTeamNumber(self:GetTeamNumber()) == target:GetTeamNumber()
                if target and isEnemy then
                    local stillUsable = HasMixin(target, "Live") and target:GetIsAlive() and target:GetCanTakeDamage()
                    if stillUsable then
                        return target
                    end
                end
            end
        end

    end

    function Babbler:MoveRandom()
        PROFILE("Babbler:MoveRandom")

        if not self.babblerOffMap
            and (self.moveType == kBabblerMoveType.None)
            and self:GetIsOnGround() then

            local now = Shared.GetTime()
            local orig = self:GetOrigin()
            local target = self.targetSelector:AcquireTarget() or self:GetTarget()
            local owner = self:GetOwner()
            local ownerId = self:GetOwnerId()
            local alive = owner and HasMixin(owner, "Live") and owner:GetIsAlive()
            local ownerOrigin = owner and (not owner:isa("Commander") and GetEngagementOrOrigin(owner) or owner.lastGroundOrigin)

            if not target then
                target = self:AdoptSiblingTarget(ownerId)
            end

            if target then
                self:OrderAttack(target, target:GetOrigin())
            elseif not self.babblerBombSpawned and owner and alive and HasMixin(owner, "BabblerCling")
                    and now >= self.freeRoamUntil then
                if ownerOrigin then -- If nothing to do, go back to owner and wag a bit
                    if (ownerOrigin - orig):GetLength() < kMaxWagDist * 0.8 then
                        self:SetMoveType(kBabblerMoveType.Wag, owner, ownerOrigin)
                    else
                        self:SetMoveType(kBabblerMoveType.Move, nil, ownerOrigin)
                    end
                end
            else
                -- free roam active: idle flavours (pause or dart)
                if not self.idleNextDecisionTime or now >= self.idleNextDecisionTime then
                    self.idleNextDecisionTime = nil
                    self:PickNextIdleAction()
                end
            end
        end
    end

    function Babbler:SetIgnoreOrders(time)
        self.timeOrdersAllowed = Shared.GetTime() + time
    end

    local kAimLeadTime = kUpdateAttackInterval
    local function GetLeadPosition(target)

        local aimPos = GetEngagementOrOrigin(target)

        if target.GetVelocity then
            local velocity = target:GetVelocity()
            if velocity:GetLengthSquared() > kEpsilon then
                VecAddScaled(aimPos, aimPos, velocity, kAimLeadTime)
            end
        end

        return aimPos
    end

    -- Launch-time scatter on top of the lead point, so a swarm doesn't all
    -- jump at the exact same pixel.
    local kAimJitterXZ = 1 / 3
    local kAimJitterY = 1 / 1.8
    local function GetJumpAimPoint(target)
        local aimPos = GetLeadPosition(target)
        aimPos.x = aimPos.x + (math.random() - 0.5) * kAimJitterXZ
        aimPos.y = aimPos.y + math.random() * kAimJitterY
        aimPos.z = aimPos.z + (math.random() - 0.5) * kAimJitterXZ
        return aimPos
    end

    -- mid-air homing: babblers curve gently toward their target between
    -- attack jumps instead of overshooting in a straight line
    local kHomingNudgeSpeed = 3.5 -- How fast we converge
    local kHomingNudgeDelay = 0.5 -- How frequently we adjust
    local kHomingBurstSize  = 2   -- How many nudges per jump
    local kHomingLerpFactor = 0.1
    local function HomingFlightTrajectory(self, isOnGround, target)

        if isOnGround or self.kStopImpulseDone >= kHomingBurstSize then
            return
        end

        local now = Shared.GetTime()
        if now <= self.timeLastStopImpulse + kHomingNudgeDelay then
            return
        end

        local current = self:GetVelocity()
        local desiredDir = (GetLeadPosition(target) - self:GetOrigin()):GetUnit()
        local desiredVel = desiredDir * math.max(current:GetLength(), kHomingNudgeSpeed)

        self:SetVelocity(current + (desiredVel - current) * kHomingLerpFactor)

        self.kStopImpulseDone = self.kStopImpulseDone + 1
        self.timeLastStopImpulse = now
    end

    function Babbler:UpdateAttack(target, force)

        if self.babblerOffMap then
            return
        end

        local targetIsAlive = target and HasMixin(target, "Live") and target:GetIsAlive()
        if not target or not targetIsAlive then
            self:SetMoveType(kBabblerMoveType.None)
            return
        end

        local now = Shared.GetTime()
        local isOnGround = self:GetIsOnGround()

        if isOnGround then
            self.kStopImpulseDone = 0
        end

        HomingFlightTrajectory(self, isOnGround, target)

        if force or (isOnGround and now > self.kNextUpdateAttack + 0.1) then

            local canReach = CanReachTarget(self, target)
            local babblerBall = not canReach and self:GetBabblerBall()
            local babblerBallId = babblerBall and babblerBall:GetId()

            if canReach then

                local aimPos = GetJumpAimPoint(target)
                local moveVel = self:GetMoveVelocity(aimPos)

                local distXZ = (aimPos - self:GetOrigin()):GetLengthXZ()
                local desiredSpeedXZ = distXZ / kUpdateAttackInterval
                local speedXZ = moveVel:GetLengthXZ()
                if speedXZ > desiredSpeedXZ then
                    local scale = math.max(desiredSpeedXZ, kEpsilon) / speedXZ
                    moveVel.x = moveVel.x * scale
                    moveVel.z = moveVel.z * scale
                end

                local jumpSpeed = (self:GetVelocity() + moveVel):GetLength()
                if jumpSpeed > kBabblerJumpSpeed then
                    moveVel:Scale(kBabblerJumpSpeed / jumpSpeed)
                end

                self:Jump(moveVel)
                self:TriggerUncloak()
                self.kNextUpdateAttack = now + kUpdateAttackInterval

            elseif babblerBallId and babblerBallId ~= self.lastBabblerBallId then

                self.lastBabblerBallId = babblerBallId
                self:SetMoveType(kBabblerMoveType.Move, nil, babblerBall:GetOrigin(), false, 1)

            else

                self:SetMoveType(kBabblerMoveType.Move, target, target:GetOrigin(), true)

            end

        end

    end

    function Babbler:SetGroundMoveType(isGround)

        local t = isGround and CollisionObject.Kinematic or CollisionObject.Dynamic
        if self.physicsBody and (self.collisionObjectType == nil or self.collisionObjectType ~= t) then
            self.physicsBody:SetPhysicsType(t)
            self.collisionObjectType = t
            self:SyncPhysicsCoords()
        end

        if isGround ~= self.doesGroundMove then
            -- prevents us from getting teleported back when switching to ground move again
            self:ResetPathing()
            self.doesGroundMove = isGround

        end

    end

    function Babbler:GetClingAttachPoint(target)

        local isWeb = target:isa("Web")
        local isEmbryo = target:isa("Embryo")
        local isCommander = target:isa("AlienCommander")
        if isWeb or isEmbryo or isCommander or HasMixin(target, "BabblerCling") then
            local attachPointOrigin = self.targetPos
            if target.GetFreeBabblerAttachPointOrigin then
                attachPointOrigin = target:GetFreeBabblerAttachPointOrigin(self)
            end
            return attachPointOrigin, isWeb
        end

        return nil, false

    end

    function Babbler:FinalizeClingAttach(target, isWeb, attachPointOrigin)

        if isWeb then
            return self:AttachToWeb(target, attachPointOrigin)
        end

        if HasMixin(target, "BabblerCling") then

            local owner = self:GetOwner()
            local isPlayerOwner = HasMixin(owner, "BabblerOwner")
            local isTargetOwner = HasMixin(target, "BabblerOwner")

            local disablePointsAward = (not isPlayerOwner) or isTargetOwner
            if not target:AttachBabbler(self, disablePointsAward) then
                return false -- just for safety
            end

            self:SetOrigin(attachPointOrigin)
            return true

        end

        -- Embryo / AlienCommander: no real attach mechanism, just settle at
        -- the destination.
        return true

    end

    function Babbler:ReleaseFromParentCling(parent)
        if parent and HasMixin(parent, "BabblerCling") then
            self.clinged = false
            local p = parent
            self:SetParent(nil)
            p:DetachBabbler(self)
        end
    end

    function Babbler:Detach()
        if not self:GetIsClinged() then
            return
        end

        local parent = self:GetParent()

        if parent then
            local away = GetNormalizedVector(self:GetOrigin() - parent:GetOrigin())
            away.y = math.max(0, away.y) -- never push downward below the map
            if away:GetLengthSquared() < kEpsilon then
                away = Vector(math.random()-0.5, 0, math.random()-0.5)
            end

            local detachOrigin = self:GetOrigin() + away * Babbler.kRadius

            -- Safety net: if a low attach point still leaves us under the floor right below
            -- the detach point, snap back up onto it.
            local ground = GetGroundAt(self, detachOrigin, PhysicsMask.AIMovement)
            if ground and detachOrigin.y < ground.y + Babbler.kRadius and self:GetOrigin().y - ground.y < 1 then
                detachOrigin.y = ground.y + Babbler.kRadius
            end

            self:SetOrigin(detachOrigin)
        end

        self:ReleaseFromParentCling(parent)
        self.clinged = false

        self:CreateHitBox(Coords.GetTranslation(self:GetOrigin()))
        self:UpdateJumpPhysicsBody()
        self:SetGroundMoveType(false)
        ResumeFreeBehavior(self)
    end

    function Babbler:UpdateWebBehavior(deltaTime)

        local web = self:GetWeb()
        if not web or not web:GetIsAlive() then
            self:DetachFromWeb()
            return
        end

        local origin, axis, length = web:GetWebAxis()
        if not axis then return end

        -- angry chittering while panicked
        if self.panicExpire ~= nil then

            local now = Shared.GetTime()

            if now < self.panicExpire then
                if self.timeNextWebAnger == nil or now >= self.timeNextWebAnger then
                    self:TriggerEffects("babbler_engage")
                    self.timeNextWebAnger = now + kWebConfig.angerMin + math.random() * kWebConfig.angerRange
                end
            else
                -- panic over, clean up so the timer doesn't linger
                self.panicExpire = nil
                self.timeNextWebAnger = nil
            end

        end

        -- Don't go to the edge of the web (it might be inside walls)
        local margin = math.min(kBabblerWebEndMargin, length * 0.2)
        local myT = (self:GetOrigin() - origin):DotProduct(axis)
        self.webWalkTimer = (self.webWalkTimer or 1) - deltaTime

        if self.webTargetT == nil and self.webWalkTimer <= 0 then

            local minTravel = math.min(0.5, (length - margin * 2) * 0.3)
            local candidateT
            local accepted = false

            for _ = 1, 8 do
                candidateT = margin + math.random() * (length - margin * 2)
                if math.abs(candidateT - myT) >= minTravel then
                    accepted = true
                    break
                end
            end

            if not accepted then
                candidateT = (myT < (margin + length) * 0.5) and (length - margin) or margin
            end

            self.webTargetT = Clamp(candidateT, margin, length - margin)
            self.webWalkDir = (self.webTargetT >= myT) and 1 or -1
            self.webWalkSpeed = Babbler.kWebWalkSpeed * (0.5 + math.random() * 0.85)
            self.webWalking = true
            self.webWalkTimer = kWebConfig.strollTimeout

        end

        if self.webTargetT ~= nil then

            local panicking = self.panicExpire ~= nil and Shared.GetTime() < self.panicExpire
            local speed = (self.webFastTravel and kWebTravelSpeed or self.webWalkSpeed or Babbler.kWebWalkSpeed)
                    * self.webSpeedMult
                    * (panicking and kWebConfig.panicSpeedMult or 1)

            local arrived = math.abs(self.webTargetT - myT) <= deltaTime * speed
            local timedOut = self.webWalkTimer <= 0

            if arrived or not timedOut then

                local t = Clamp(arrived and self.webTargetT or myT + self.webWalkDir * deltaTime * speed,
                        margin, length - margin)

                local radius = Babbler.kWebStanceRadius
                if self.webFastTravel then
                    radius = radius * Clamp(math.abs(t - self.webTravelStartT) / math.max(self.webTravelTotal, kEpsilon), 0, 1)
                end

                local forward = self.webForwardScratch
                if not forward then
                    forward = Vector(0, 0, 0)
                    self.webForwardScratch = forward
                end
                forward.x = axis.x * self.webWalkDir
                forward.y = axis.y * self.webWalkDir
                forward.z = axis.z * self.webWalkDir

                self:SetCoords(BuildWebCoords(origin.x, origin.y, origin.z, axis, t, radius, forward))

            end

            if arrived or timedOut then
                self.webTargetT = nil
                self.webFastTravel = false
                self.webTravelStartT = nil
                self.webTravelTotal = nil
                self.webWalking = false
                self.webWalkTimer = GetWebIdleTime(self)
            end

            return
        end

        -- Make babbler do some happy noise once in a while
        if self.timeNextWebChatter == nil or Shared.GetTime() >= self.timeNextWebChatter then
            self:TriggerEffects(math.random() < 0.5 and "babbler_wag_begin" or "babbler_jump") 
            self.timeNextWebChatter = Shared.GetTime() + (kWebConfig.chatterMin + math.random() * kWebConfig.chatterRange) * self.webIdleMult
            self.wagging = math.random() < 0.4
        end
        -- Make babbler investigate the web once in a while
        if self.timeNextWebForage == nil or Shared.GetTime() >= self.timeNextWebForage then
            if math.random() < 0.65 then
                self.foraging = true
            else
                self.hungry = true
            end
            self:AddTimedCallback(function(self) self.foraging = false ; self.hungry = false ; end, kAnimForagingDuration)

            self.timeNextWebForage = Shared.GetTime() + (kWebConfig.foragingMin + math.random() * kWebConfig.foragingRange) * self.webIdleMult
        end

    end

    function Babbler:AttachToWeb(web, position)

        if not web or not self:GetIsAlive() then return false end

        if web:GetNumWebbedBabblers() >= kWebMaxBabblers then
            return false
        end

        if self.clinged then
            self:ReleaseFromParentCling(self:GetParent())
        end

        self:CreateHitBox()

        local origin, axis, length = web:GetWebAxis()
        if not axis then
            return false
        end

        self.onWeb = true
        self.webId = web:GetId()
        self.babblerOffMap = nil

        local margin = math.min(kBabblerWebEndMargin, length * 0.2)
        self.webTargetT = Clamp((position - origin):DotProduct(axis), margin, length - margin)
        local myT = (self:GetOrigin() - origin):DotProduct(axis)

        self.webWalkDir = (self.webTargetT >= myT) and 1 or -1
        self.webFastTravel = true
        self.webTravelStartT = myT
        self.webTravelTotal = math.abs(self.webTargetT - myT)
        self.webWalking = true
        self.webWalkTimer = kWebConfig.strollTimeout
        self.wagging = false

        self.timeNextWebChatter = Shared.GetTime() + kWebConfig.chatterInitialMin + math.random() * kWebConfig.chatterDelayRange
        self.timeNextWebForage = Shared.GetTime() + kWebConfig.chatterInitialMin + math.random() * kWebConfig.chatterDelayRange

        -- disable physic simulation
        self:SetGroundMoveType(true)
        self:UpdateJumpPhysicsBody()
        self:SetMoveType(kBabblerMoveType.None, nil, nil, true)

        web:AddWebbedBabbler(self)

        return true

    end

    function Babbler:DetachFromWeb()

        if not self.onWeb then return end

        local web = self:GetWeb()
        if web then
            web:RemoveWebbedBabbler(self)
        end

        self.foraging = false
        self.hungry = false
        self.onWeb = false
        self.webId = Entity.invalidId

        self.webWalking = false
        self.webFastTravel = false
        self.timeNextWebChatter = nil
        self.timeNextWebForage = nil

        self.panicExpire = nil
        self.timeNextWebAnger = nil

        -- Web-spawned babblers are deliberately ownerless (see Web:AttachInitialBabblers),
        -- so OnOwnerChanged's despawn-on-ownerless path never fires for them. Left to
        -- ResumeFreeBehavior they would idle-wander the map forever once their web dies.
        if self.webSpawned then
            self:AddTimedCallback(function(self)
                if self:GetIsAlive() then self:Kill() end
                return false
            end, 1)
            return
        end

        ResumeFreeBehavior(self)

    end

    function Babbler:UpdateTargetPos()

        local target = self:GetTarget()

        if target and not target:isa("AlienSpectator") and not target:isa("Web") then

            if target.GetFreeBabblerAttachPointOrigin then

                self.targetPos = target:GetFreeBabblerAttachPointOrigin()

                if not self.targetPos then
                    self:SetMoveType(kBabblerMoveType.None)
                end

            end

        end

        return target

    end

    function Babbler:GetDestroyOnKill()
        return true
    end

    function Babbler:OnKill()

        self:TriggerEffects("death", {effecthostcoords = Coords.GetTranslation(self:GetOrigin()) })

    end

    function Babbler:UpdateJumpPhysics(deltaTime)

        local velocity = self:GetVelocity()  -- Current velocity from physics body

        if self.physicsBody and not self.doesGroundMove then

            local coords = self.physicsBody:GetCoords()
            local origin = coords.origin  -- Current physics position

            local maxDistance = 1000

            if origin:GetLengthSquared() > maxDistance * maxDistance then
                Print("%s moved outside of the playable area, destroying", self:GetClassName())
                DestroyEntity(self)
            else
                self:SetCoords(coords)  -- Sync entity to physics
            end

            if self.lastVelocity ~= nil then

                local delta = velocity - self.lastVelocity
                if delta:GetLengthSquaredXZ() > 0.0001 then

                    local moveDirection = GetNormalizedVector(self.lastVelocity)
                    local startPoint = self.lastOrigin
                    local endPoint = startPoint + moveDirection * Babbler.kProcessHitRadius

                    local filter = EntityFilterOneAndIsa(self, "Babbler")
                    local _, trace, _ = GetBulletTargets(startPoint, endPoint, moveDirection, Babbler.kProcessHitRadius, filter, true)        

                    self:ProcessHit(trace.entity, trace.surface)
                    self:RefreshFreeRoam()

                end
            end

            if self.targetSelector then
                self.targetSelector:AttackerMoved()
            end

        end
    end

    function Babbler:GetSendDeathMessageOverride()
        return false
    end

    function Babbler:SetVelocity(velocity)

        self:SyncPhysicsCoords()

        velocity = Vector(velocity)

        self.desiredVelocity = velocity
        if self.physicsBody then
            self.physicsBody:SetLinearVelocity(velocity)
        end
        self.lastVelocity = velocity

    end

    local function BabblerSetLinearDampingCallback(self)

        if not self:GetIsAlive() then
            return false
        end

        if not self.physicsBody or self.clinged then
            return false
        end

        local lifeSpan = Shared.GetTime() - self:GetCreationTime()
        if self:GetIsOnGround() or lifeSpan >= kFinalDampingAfterDelay then
            self.physicsBody:SetLinearDamping(Babbler.kLinearDamping)
            --self:Jump(nil) -- Force update physics and reset ground move
            return false
        end

        return true
    end

    function Babbler:UpdateJumpPhysicsBody()
        local isOnWeb = self:GetIsOnWeb()
        local isClinged = self:GetIsClinged()
        if not self.physicsBody and not isClinged and not isOnWeb then
            self.physicsBody = Shared.CreatePhysicsSphereBody(true, Babbler.kRadius, Babbler.kMass, self:GetCoords() )
            self.physicsBody:SetGravityEnabled(true)
            self.physicsBody:SetGroup(PhysicsGroup.ProjectileGroup)
            self.physicsBody:SetGroupFilterMask(PhysicsMask.BabblerMovement)

            self.physicsBody:SetCCDEnabled(false)
            self.physicsBody:SetPhysicsType( CollisionObject.Dynamic )
            self.physicsBody:SetLinearDamping(Babbler.kLinearDampingAtSpawn)
            self.physicsBody:SetRestitution(Babbler.kRestitution)

            self:AddTimedCallback(BabblerSetLinearDampingCallback, kFinalDampingAfterDelay)


        elseif (isClinged or isOnWeb) and self.physicsBody then
            Shared.DestroyCollisionObject(self.physicsBody)
            self.physicsBody = nil
        end
    end

    function Babbler:SetGravityEnabled(state)
        if self.physicsBody then
            self.physicsBody:SetGravityEnabled(state)
        else
            Print("%s:SetGravityEnabled(%s) - Physics body is nil.", self:GetClassName(), tostring(state))
        end
    end

    local kMoveTypeEffectNames =
    {
        [kBabblerMoveType.Attack] = "babbler_engage",
        [kBabblerMoveType.Wag] = "babbler_wag_begin",

    }

    local function OnMoveTypeChanged(self)

        local effectName = kMoveTypeEffectNames[self.moveType]

        if effectName then
            self:TriggerEffects(effectName)
        end

    end

    local function GetIgnoreOrders(self)
        return self:GetIsClinged() or (self.timeOrdersAllowed and self.timeOrdersAllowed > Shared.GetTime())
    end

    function Babbler:SetMoveType(moveType, target, position, force, ignoreOrderDelay)

        if moveType == kBabblerMoveType.Attack and not target then
            Log("Error: trying to assign an attack order to %s with no target", self)
            return
        end

        local targetId = Entity.invalidId

        if target then
            targetId = target:GetId()
            position = position or (target and GetEngagementOrOrigin(target))
        end

        -- Clear move type if no pos nor targets
        if moveType == kBabblerMoveType.Move and not target and not position then
            Log("Error: %s has move type with no target nor position", self)
            moveType = kBabblerMoveType.None
        end

        local diffOfPosition = (self.targetPos and position) and position:GetDistanceTo(self.targetPos) or 0
        if force or ((moveType ~= self.moveType or targetId ~= self.targetId or diffOfPosition > 0) and not GetIgnoreOrders(self)) then

            if self:GetIsClinged() then
                self:Detach()
            end

            self.moveType = moveType
            self.targetId = targetId
            self.targetPos = position
            self.hungry = false
            self.foraging = false
            if not (moveType == kBabblerMoveType.Move or moveType == kBabblerMoveType.Attack) then
                self.targetReached = false -- preserve that state when moving from move <-> attack
            end

            OnMoveTypeChanged(self)

            if force or ignoreOrderDelay then
                self:SetIgnoreOrders(ignoreOrderDelay or 0.25)
            end

        end

    end

    function Babbler:OrderCling(target, position)
        self:SetMoveType(kBabblerMoveType.Cling, target, position or GetEngagementOrOrigin(target), true, 0.6)
    end

    function Babbler:OrderAttack(target, position)
        self:SetMoveType(kBabblerMoveType.Attack, target, position or GetEngagementOrOrigin(target), true, 0.6)
    end

    function Babbler:OrderMove(position)
        self:SetMoveType(kBabblerMoveType.Move, nil, position, true, 0.6)
    end

    function Babbler:OrderIdle()
        self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
    end

    function Babbler:ProcessHit(entityHit, surface)

        if entityHit then

            local orig = self:GetOrigin()

            if self.moveType == kBabblerMoveType.Cling and entityHit:isa("Web") then
                if self:AttachToWeb(entityHit, orig) then
                    return
                end
                -- couldn't attach (full/dead) -> fall through to normal handling
            end

            if HasMixin(entityHit, "Live") and HasMixin(entityHit, "Team") and entityHit:GetTeamNumber() ~= self:GetTeamNumber() then

                if self.timeLastAttack + self.attackRate < Shared.GetTime() then

                    self.timeLastAttack = Shared.GetTime()
                    self.attackRate = math.max(0.1, kAttackRate + (math.random()-0.5)/2)

                    self:DoDamage(kBabblerDamage, entityHit, orig, nil, surface)
                    self:TriggerUncloak()

                    if entityHit:isa("Player") then
                        self:Jump((entityHit:GetOrigin() - orig):GetUnit() * 2)
                    end

                end

            end

        end

    end

    function Babbler:GetShowHitIndicator()
        return true
    end

elseif Client then

    function Babbler:OnUpdateRender()
        PROFILE("Babbler:OnUpdateRender")

        if self.dirtySkinState and not self.delayedSkinUpdate then

            local model = self:GetRenderModel()
            if model then
                if self.variant ~= kBabblerVariants.normal and self.variant ~= kBabblerVariants.Shadow then
                    local material = GetPrecachedCosmeticMaterial(self:GetClassName(), self.variant)
                    if material then
                        model:SetOverrideMaterial(kBabblerWorldMaterialIndex, material)
                    end
                else
                    model:ClearOverrideMaterials()
                end

                self:SetHighlightNeedsUpdate()
            else
                return false --skip to next frame
            end

            self.dirtySkinState = false
        end

    end

    local function Smoothstep(e)
        e = Clamp(e, 0, 1)
        return e * e * (3 - 2 * e)
    end

    local function Hash01(a, b)
        local v = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
        return v - math.floor(v)
    end

    local function GetSpinDelta(id, seg)
        local sign = Hash01(id, seg) < 0.5 and -1 or 1
        local mag = math.rad(30 + Hash01(id, seg + 101) * 30)
        if Hash01(id, seg + 202) < 0.25 then
            mag = mag + math.rad(60 + Hash01(id, seg + 303) * 30)
        end
        return sign * mag
    end
    local kSpinPeriod   = 4.0
    local kIdleEnd      = 0.42  -- idle fraction of each segment
    local kGlanceEnd    = 0.55  -- glance-to-spin-direction window
    local kGlanceAmount = math.rad(30)
    local kHoldEnd      = 0.60  -- glance holds until the spin unwind begins
    local kSpinEnd      = 0.95  -- spin completes by here, then holds

    local kClientWorldUp = Vector(0, 1, 0)
    local kFacingTurnRate = math.pi * 3   -- rad/s: a 180-degree pirouette in ~0.33s
    local kSpinWobble = math.rad(13)      -- how much the spin cones off-axis instead of rolling flat

    local function GetWebPoseCoords(origin, axis, facingAngle, rollAngle, prevUp0)

        local reference = prevUp0 or kClientWorldUp
        local up0 = reference - axis * reference:DotProduct(axis)

        if up0:GetLengthSquared() < 0.01 then
            reference = kClientWorldUp
            up0 = reference - axis * reference:DotProduct(axis)
            if up0:GetLengthSquared() < 0.01 then
                up0 = axis:CrossProduct(Vector(1, 0, 0))
                if up0:GetLengthSquared() < 0.01 then
                    up0 = axis:CrossProduct(Vector(0, 0, 1))
                end
            end
        end
        up0:Normalize()

        local w = axis:CrossProduct(up0)   -- tangent around the strand

        local cu, su = math.cos(rollAngle), math.sin(rollAngle)
        local up = up0 * cu + w * su
        local t  = w * cu - up0 * su

        -- tilt "up" slightly toward the strand as it spins so the roll traces a
        -- shallow cone instead of a flat, mechanical rotation around the axis
        local wobble = (math.sin(rollAngle * 2) + 0.3 * math.sin(rollAngle * 5)) * kSpinWobble
        up = up + axis * wobble
        up:Normalize()
        local cf, sf = math.cos(facingAngle), math.sin(facingAngle)
        local forward = axis * cf + t * sf
        forward = forward - up * up:DotProduct(forward) -- re-orthogonalize against tilted up
        forward:Normalize()

        local co = Coords.GetIdentity()
        co.origin = origin
        co.xAxis = up:CrossProduct(forward)
        co.yAxis = up
        co.zAxis = forward

        return co, up0

    end

    function Babbler:GetSpinRenderAngle()

        if not self.spinPhase then
            self.spinPhase = 0
            self.spinSeg = 0
            self.spinAngle = 0
        end

        if not self.spinSeg then
            self.spinSeg = math.floor(self.spinPhase or 0)
            self.spinAngle = 0
        end

        local id = self:GetId()
        local seg = math.floor(self.spinPhase)
        local u = self.spinPhase - seg

        while self.spinSeg < seg do
            self.spinAngle = self.spinAngle + GetSpinDelta(id, self.spinSeg) -- fold previous segment's delta
            self.spinSeg = self.spinSeg + 1
        end

        local delta = GetSpinDelta(id, seg)
        local glance = (delta >= 0 and 1 or -1) * kGlanceAmount

        if u < kIdleEnd then
            return self.spinAngle
        elseif u < kGlanceEnd then
            return self.spinAngle + glance * Smoothstep((u - kIdleEnd) / (kGlanceEnd - kIdleEnd))
        elseif u < kHoldEnd then
            return self.spinAngle + glance
        else
            return self.spinAngle + glance + (delta - glance) * Smoothstep((u - kHoldEnd) / (kSpinEnd - kHoldEnd))
        end

    end

    function Babbler:OnAdjustModelCoords(modelCoords)

        if self:GetIsOnWeb() then

            if self.clientSpinAxis then
                local co, up0 = GetWebPoseCoords(modelCoords.origin, self.clientSpinAxis,
                        self.webFacingAngle or 0, self:GetSpinRenderAngle(), self.clientWebUp0)
                self.clientWebUp0 = up0
                return co
            end
            return modelCoords

        end

        if not self:GetIsClinged() and self.moveDirection
                and self.moveDirection:GetLengthSquaredXZ() >= kEpsilon then
            modelCoords = Coords.GetLookIn(modelCoords.origin, self.moveDirection)
            modelCoords.origin.y = modelCoords.origin.y - Babbler.kRadius
        end

        return modelCoords

    end

    local kSpinAxisMinSpeed = 0.05
    function Babbler:UpdateSpinAxis(deltaTime)

        if not self:GetIsOnWeb() then
            self.clientSpinAxis = nil
            self.spinAngle = nil
            self.spinSeg = nil
            self.spinPhase = nil
            self.webFacingAngle = nil
            self.clientWebUp0 = nil
            self.webWalkSign = nil
            return
        end

        local dt = Clamp(deltaTime, 0, 0.1)

        local moving = false
        if self.clientVelocity then

            local speed = self.clientVelocity:GetLength()

            if speed > kSpinAxisMinSpeed then

                local axis = Vector(self.clientVelocity)
                axis:Normalize()

                if self.clientSpinAxis and self.clientSpinAxis:DotProduct(axis) < 0 then
                    axis:Scale(-1)
                end

                if self.clientSpinAxis then
                    self.clientSpinAxis = self.clientSpinAxis + axis * dt * 5
                else
                    self.clientSpinAxis = axis
                end
                self.clientSpinAxis:Normalize()

                local along = self.clientVelocity:DotProduct(self.clientSpinAxis)
                if not self.webWalkSign then
                    self.webWalkSign = along >= 0 and 1 or -1
                elseif along < -0.15 and self.webWalkSign > 0 then
                    self.webWalkSign = -1
                elseif along > 0.15 and self.webWalkSign < 0 then
                    self.webWalkSign = 1
                end

                local target = self.clientVelocity:DotProduct(self.clientSpinAxis) >= 0
                        and 0 or math.pi
                local a = self.webFacingAngle or 0
                local d = Math.Wrap(target - a, -math.pi, math.pi)
                a = math.abs(d) < 0.01 and target or a + Clamp(d, -kFacingTurnRate * dt, kFacingTurnRate * dt)
                self.webFacingAngle = a

                moving = true

            end

        end

        local phase = self.spinPhase or 0
        if moving then
            phase = phase + dt / kSpinPeriod
        else
            local boundary = math.floor(phase) + 1
            local u = phase - boundary + 1
            if u > kIdleEnd and u < kSpinEnd then
                phase = math.min(phase + dt / kSpinPeriod, boundary)
            end
        end
        self.spinPhase = phase

    end

    function Babbler:UpdateMoveDirection(deltaTime)

        if not self:GetIsClinged() then -- No sound when attached
            if self.clientJumping ~= self.jumping and self.jumping then
                local vel = self:GetVelocity()
                if vel:GetLengthSquared() > 4 then
                    self:TriggerEffects("babbler_jump")
                end
            end

            if self.clientAttacking ~= self.attacking and self.attacking then
                self:TriggerEffects("babbler_attack")
            end

            if self.clientGroundMove ~= self.doesGroundMove and self.doesGroundMove then
                self:TriggerEffects("babbler_move")
            end

            self:UpdateSpinAxis(deltaTime)
        end

        self.clientGroundMove = self.doesGroundMove

        if self.lastOrigin then
            local orig = self:GetOrigin()
            if not self.moveDirection then
                self.moveDirection = Vector(0, 0, 0)
            end

            -- PRIORITY 1: Actual movement direction (last origin → current origin)
            -- This reflects where we actually moved, including wander/weave offsets
            local moveDirFromPath = orig - self.lastOrigin
            local hasMovement = moveDirFromPath:GetLengthSquaredXZ() >= kEpsilon

            -- PRIORITY 2: Only use target direction if not moving or in attack mode
            local target = self:GetTarget()
            local targetDirection = nil
            if target and not hasMovement then
                -- Stationary but has target - face the target
                targetDirection = GetNormalizedVectorXZ(target:GetOrigin() - orig)
            elseif self.moveType == kBabblerMoveType.Attack and hasMovement then
                -- Attacking AND moving - face target for better hit registration
                targetDirection = GetNormalizedVectorXZ(target:GetOrigin() - orig)
            end

            local rawDir = targetDirection or moveDirFromPath

            if rawDir:GetLengthSquaredXZ() >= kEpsilon then
                local moveDirection = GetNormalizedVectorXZ(rawDir)

                -- Smooth out turning of babblers... (rest unchanged)
                local smoothed = self.moveDirection
                local dx = moveDirection.x - smoothed.x
                local dy = moveDirection.y - smoothed.y
                local dz = moveDirection.z - smoothed.z
                local turnScale = deltaTime * math.sqrt(dx * dx + dy * dy + dz * dz) * 5

                smoothed.x = smoothed.x + moveDirection.x * turnScale
                smoothed.y = smoothed.y + moveDirection.y * turnScale
                smoothed.z = smoothed.z + moveDirection.z * turnScale
                smoothed:Normalize()
            end

            if deltaTime > 0 then
                self.clientVelocity = (orig - self.lastOrigin) / deltaTime
            end
        end

        self.clientJumping = self.jumping
        self.clientAttacking = self.attacking

    end

    function Babbler:OnUpdateAnimationInput(modelMixin)

        PROFILE("Babbler:OnUpdateAnimationInput")

        local move = "idle"
        if self.clinged or self.foraging or self.hungry then
            move = "idle"
        elseif self.onWeb then
            if self.wagging then
                move = "wag"
            end
            if self.webWalking then
                move = "run"
            end
        elseif self.jumping then
            move = "jump"
        elseif self.doesGroundMove then
            move = "run"
        elseif self.wagging then
            move = "wag"
        end

        modelMixin:SetAnimationInput("forage", self.foraging)
        modelMixin:SetAnimationInput("hungry", self.hungry)
        modelMixin:SetAnimationInput("move", move)
        modelMixin:SetAnimationInput("attacking", not (self.clinged or self.foraging or self.hungry) and self.attacking)

    end

    function Babbler:OnUpdatePoseParameters()

        PROFILE("Babbler:OnUpdatePoseParameters")

        local moveYaw = 0
        local targetSpeed = 0

        if self.onWeb then
            targetSpeed = self.webWalking and 1 or 0
        elseif self.clientVelocity then
            local moveDirection = ConditionalValue(self.clientVelocity:GetLengthXZ() > 0,
                    GetNormalizedVectorXZ(self.clientVelocity), self.moveDirection)
            local coords = Coords.GetLookIn(self:GetOrigin(), Vector(moveDirection.x, 0, moveDirection.z))

            local x = coords.xAxis:DotProduct(moveDirection)
            local z = coords.zAxis:DotProduct(moveDirection)

            moveYaw = Math_Wrap(Math_Degrees(math_atan2(z, x)), -180, 180) + 180
            targetSpeed = Clamp(self.clientVelocity:GetLength() / kBabblerRunSpeed, 0, 1)
        end

        local now = Shared.GetTime()
        local dt = self.lastPoseParamTime and (now - self.lastPoseParamTime) or 0.016
        self.lastPoseParamTime = now
        dt = Clamp(dt, 0.001, 0.1)

        self.smoothedMoveSpeed = Slerp(self.smoothedMoveSpeed or 0, targetSpeed, dt * 10)

        local poseParamArgs = self.poseParamArgsCache
        if not poseParamArgs then
            poseParamArgs = { {"move_speed", 0}, {"move_yaw", 0} }
            self.poseParamArgsCache = poseParamArgs
        end
        poseParamArgs[1][2] = self.smoothedMoveSpeed
        poseParamArgs[2][2] = moveYaw

        self:SetPoseParams(poseParamArgs)

    end

    function Babbler:OnGetIsVisible(visibleTable)

        local parent = self:GetParent()
        if parent and (parent == Client.GetLocalPlayer() and not parent:GetIsThirdPerson()) then
            visibleTable.Visible = false
        end

    end

end

function Babbler:GetEffectParams(tableParams)
    tableParams[kEffectFilterSilenceUpgrade] = self.silenced
end

function Babbler:GetDeathIconIndex()
    return kDeathMessageIcon.Babbler
end

function Babbler:GetFov()
    return Babbler.kFov
end

function Babbler:GetSpeedScalar()
    if self.clinged then
        local parent = self:GetParent()
        if parent and parent.GetSpeedScalar then
            return parent:GetSpeedScalar()
        end
    end

    if Client and self.clientVelocity then
        return self.clientVelocity:GetLength() / self:GetMaxSpeed()
    end

    return self:GetVelocity():GetLength() / self:GetMaxSpeed()
end

function Babbler:GetMaxSpeed()
    return kBabblerRunSpeed
end

--prevent babblers from being show as sensor blips when attached. Saves UI spam for Marine players
function Babbler:GetShowSensorBlip()
    return not self.clinged
end

function Babbler:GetIsDetectedOverride()
    if self.clinged then
        local parent = self:GetParent()
        if parent and HasMixin(parent, "Detectable") then
            return parent:GetIsDetected()
        end
    end

    return not self.clinged and self.detected
end

function Babbler:GetIsCamouflaged()
    if self.clinged then
        local parent = self:GetParent()
        if parent and HasMixin(parent, "Cloakable") then
            return parent:GetIsCamouflaged()
        end
    end

    return false
end

function Babbler:OnDamageDone(doer, target)
    self.timeLastDamageDealt = Shared.GetTime()
end

function Babbler:GetCanGiveDamageOverride()
    return true
end

function Babbler:SetDamageType(DamageType)
    self.AttackDamageType = DamageType
end

function Babbler:GetDamageType()
    return self.AttackDamageType
end

Shared.LinkClassToMap("Babbler", Babbler.kMapName, networkVars, true)
