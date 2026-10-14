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
local kTurnSpeed = math.pi



local kMinJumpForce = 5           -- slowest horizontal speed a hop/leap will use
local kMaxJumpForce = 15          -- fastest horizontal speed a hop/leap will use
local kMaxVerticalJumpForce = 12  -- vertical speed cap, kept independent of horizontal speed

local kBabblerGravity = 9.7 -- real gravity value measured (to compute flight time)
local kLegacyGravityAssumption = 6.7 -- what the babbler code was tuned with (higher for stronger jumps)
local kHeightTuningScale = kLegacyGravityAssumption / kBabblerGravity -- Adjust the forces

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

local math_atan2 = math.atan2
local math_sqrt = math.sqrt
local math_sin = math.sin
local math_cos = math.cos
local math_deg = math.deg

local VectorMath = VectorMath
local VecAddScaled = VecAddScaled

local LengthSqXZ = VectorMath.LengthSqXZ
local LengthXZ = VectorMath.LengthXZ
local LengthSq3 = VectorMath.LengthSq3
local Length3 = VectorMath.Length3

local Dot3 = VectorMath.Dot3
local Cross3 = VectorMath.Cross3
local AddScaled3 = VectorMath.AddScaled3
local Combine3 = VectorMath.Combine3

local Normalize3 = VectorMath.Normalize3
local NormalizeXZ = VectorMath.NormalizeXZ
local RotateXZ = VectorMath.RotateXZ
local WrapAngle = VectorMath.WrapAngle

function GetEngagementOrOrigin(entity)
    if entity:isa("Player") then
        return entity:GetEyePos() -- Like bees, aim for the eyes
    end
    -- GetEngagementPoint returns TargetMixin's cached vector; writing into it moves the target's aim point for everyone
    return HasMixin(entity, "Target") and Vector(entity:GetEngagementPoint()) or entity:GetOrigin()
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
        self.moveDirX = 0
        self.moveDirZ = 0

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

function Babbler:DestroyPhysicsBody()
    if self.physicsBody then
        Shared.DestroyCollisionObject(self.physicsBody)
        self.physicsBody = nil
        self.collisionObjectType = nil
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

    self:DestroyPhysicsBody()
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

function Babbler:GetIsOnGround(now)
    local vel = self:GetVelocity(now)
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

        now = now or Shared.GetTime()
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

function Babbler:GetVelocity(now, orig)

    if self.physicsBody then
        return self.physicsBody:GetLinearVelocity()
    end
    local lastOrigin = self.lastOrigin
    if lastOrigin and self.lastUpdate then
        local dt = (now or Shared.GetTime()) - self.lastUpdate
        if dt > kEpsilon then
            orig = orig or self:GetOrigin()
            return Vector((orig.x - lastOrigin.x) / dt, (orig.y - lastOrigin.y) / dt, (orig.z - lastOrigin.z) / dt)
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

function Babbler:UpdateRelevancy(now, orig)

    PROFILE("Babbler:UpdateRelevancy")

    local owner = self:GetOwner()
    local ownerSighted = owner ~= nil and (owner:GetOrigin() - (orig or self:GetOrigin())):GetLengthSquared() < kSightedFollowRangeSq
            and (HasMixin(owner, "LOS") and owner:GetIsSighted())

    now = now or Shared.GetTime()
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

function Babbler:UpdateBabbler(deltaTime, now)

    self:UpdateClientSkinState()

    if self:GetIsClinged() or not self:GetIsAlive() then
        self.attacking = false
        self.doesGroundMove = false
        return
    end

    local orig = nil

    if Server then

        self.attacking = self.timeLastAttack + 0.2 > now

        if self.foraging or self.hungry then
            self:UpdateRelevancy(now)
            return
        end
        if self:GetIsOnWeb() then
            self:UpdateWebBehavior(deltaTime, now)
            self:UpdateRelevancy(now)
            return
        end

        local success = true
        local targetReached = false

        local target = self:UpdateTargetPos()

        if self.moveType == kBabblerMoveType.Attack and not target then
            self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
        end

        local isEnemy = target and HasMixin(target, "Team")
                and target:GetTeamNumber() == GetEnemyTeamNumber(self:GetTeamNumber())

        -- Host went commander: there is nothing to attach to, so gather at the
        -- commander's hive and stand still there (see UpdateHoldAtHive)
        local holdAtHive = self.moveType == kBabblerMoveType.Cling and target and target:isa("AlienCommander")

        if holdAtHive then
            success = self:UpdateHoldAtHive(target, deltaTime, now)
        else
            if (self.moveType == kBabblerMoveType.Move or self.moveType == kBabblerMoveType.Cling) and self.timeLastJump + 0.5 < now and self:GetIsOnGround(now) then
                success, targetReached = self:UpdateMove(target, deltaTime, now) --> :Move()
            end

            -- If reached, try to cling to it
            if success and self.moveType == kBabblerMoveType.Cling then
                success = self:UpdateCling(target, deltaTime, now) --> :Cling()
            end
        end

        if not success then
            self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
        end

        self.jumping = not self:GetIsOnGround(now)
        self:UpdateJumpPhysicsBody()
        self:UpdateJumpPhysics(deltaTime, now)

        self.wagging = self.moveType == kBabblerMoveType.Wag

        if isEnemy and self.moveType == kBabblerMoveType.Move and target and targetReached and CanReachTarget(self, target) then
            local targetPos = HasMixin(target, "Target") and target:GetEngagementPoint() or target:GetOrigin()
            self:SetMoveType(kBabblerMoveType.Attack, target, targetPos, true)
        end

        if target and self.moveType == kBabblerMoveType.Attack then
            self:UpdateAttack(target, false, now)
        end

        -- A finished Move with no enemy on it is a dead order. Drop back to
        -- None so MoveRandom can roll the next idle flavour (or wag/follow).
        if self.moveType == kBabblerMoveType.Move and targetReached and not isEnemy then
            self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
        end

        orig = self:GetOrigin()
        self:UpdateRelevancy(now, orig)

        if orig == self.lastOrigin and not self:GetIsOnGround(now) then
            self:SetGroundMoveType(false) -- Re-enables gravity (just in case)
            orig = nil -- state may have changed, re-read below
        end

    elseif Client then

        orig = self:GetOrigin()
        self:UpdateMoveDirection(deltaTime, now, orig)

        local model = self:GetRenderModel()
        if model ~= nil and not self.addedToHiveVision then
            HiveVision_AddModel(model, kHiveVisionOutlineColor.Green)
            self.addedToHiveVision = true
        end

    end

    orig = orig or self:GetOrigin()
    self.lastVelocity = self:GetVelocity(now, orig)
    self.lastUpdate = now

    VectorCopy(orig, self.lastOrigin)

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

    if success and not HasMixin(entity, "BabblerCling") then
        success = false
    end

    if success and not HasMixin(entity, "BabblerOwner") and entity:GetNumFreeDonationSpots() <= 0 then
        success = false
    end

    useSuccessTable.useSuccess = success

end



function Babbler:GetUseAllowedBeforeGameStart()
    return true
end

function Babbler:GetCanBeUsedDuringWarmup()
    return true
end

function Babbler:GetIsSecondaryUseUnit(other)
    if other == nil or other:isa("Web") then
        return false
    end
    return true
end

function Babbler:OnUse(player, elapsedTime, useSuccessTable)

    if Server and not self:GetIsClinged() then

        local isOwner = self:GetOwnerId() == player:GetId()
        if HasMixin(player, "BabblerCling") and (isOwner or player:GetNumFreeDonationSpots() > 0) then

            local wasOnWeb = self:GetIsOnWeb()
            if wasOnWeb then
                self:DetachFromWeb()
            end

            local attachPos = GetEngagementOrOrigin(player)
            self:OrderCling(player, attachPos)

            if wasOnWeb and not self.webSpawned then
                local target = player.GetFreeBabblerAttachPointOrigin and player:GetFreeBabblerAttachPointOrigin() or attachPos
                local velocity, flightTime = self:GetArcVelocity(target)
                self:Jump(velocity) -- sets timeLastJump, zeroes velocity, adds the impulse
                self.nextLeapTime = Shared.GetTime() + flightTime / 2
            end
        end
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

    local now = Shared.GetTime()
    self:UpdateBabbler(deltaTime, now)

    if Server and not self:GetIsOnWeb() then

        if not self.cb_routine_moveRandom or now > self.cb_routine_moveRandom then
            self:MoveRandom(now)
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
                if LengthSq3(dx, dy, dz) > kEpsilon * kEpsilon then
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

    -- Timed callbacks are hoisted to file scope: creating a closure inside a
    -- hot path is an NYI bytecode for LuaJIT (FNEW) and allocates every time.
    local function ClearForagingCallback(self)
        self.foraging = false
        self.hungry = false
        return false -- removes callback
    end

    local function KillIfAliveCallback(self)
        if self:GetIsAlive() then
            self:Kill()
        end
        return false -- removes callback
    end

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
                self:AddTimedCallback(ClearForagingCallback, kAnimForagingDuration)
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

    local function GetWebIdleTime(self, now)

        local panicking = self.panicExpire ~= nil and (now or Shared.GetTime()) < self.panicExpire

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


    -- Returns velocity, flightTime (flightTime is when this arc lands, useful
    -- for landing-safety checks and for pacing the next jump decision).
    local kJumpPowerVariance = 0.2   -- +/- fraction of horizontal jump speed, rolled per jump
    local kJumpHeightVariance = 0.15 -- +/- fraction of jump height, rolled per jump
    local kArcClearance = 0.75 * kHeightTuningScale       -- padding added above the target's real height
    local kDefaultMinArcHeight = 1.0 * kHeightTuningScale -- how high a level/downward hop still arcs

    -- Pure ballistic solve: plain numbers in, plain numbers out, so LuaJIT can
    -- compile it as a single trace. Returns vx, vy, vz, flightTime.
    local function SolveArc(dx, dy, dz, minArcHeight)

        local horizontalDist = LengthXZ(dx, dz)
        local dirX, dirZ = dx, dz
        if horizontalDist > 0.0001 then
            local inv = 1 / horizontalDist
            dirX, dirZ = dx * inv, dz * inv
        end

        -- Arc apex must clear the target's real height (heightDiff, never
        -- scaled - it's level geometry) plus a little tuned padding, with
        -- per-jump variance so hops at the same range bracket don't all arc
        -- identically.
        local arcHeight = math.max(dy + kArcClearance, minArcHeight or kDefaultMinArcHeight)
        arcHeight = arcHeight * (1 + (math.random() - 0.35) * kJumpHeightVariance)

        local vY = math_sqrt(2 * kBabblerGravity * arcHeight)
        local timeUp = vY / kBabblerGravity
        local remainingHeight = math.max(arcHeight - dy, 0)
        local timeDown = math_sqrt(2 * remainingHeight / kBabblerGravity)
        local totalTime = timeUp + timeDown

        -- Horizontal speed is solved independently from vertical speed and
        -- clamped on its own axis - it must never scale vY down too, or a
        -- jump that needs to go both far AND up loses the very velocity that
        -- gets it up in order to satisfy a horizontal-distance budget.
        local speedXZ = Clamp(horizontalDist / math.max(totalTime, 0.0001), kMinJumpForce, kMaxJumpForce)
        speedXZ = Clamp(speedXZ * (1 + (math.random() - 0.5) * kJumpPowerVariance), kMinJumpForce, kMaxJumpForce)

        return dirX * speedXZ, math.min(vY, kMaxVerticalJumpForce), dirZ * speedXZ, totalTime

    end

    -- minArcHeight is a number (or nil). orig is optional: callers that already
    -- read the origin this tick can pass it in. The returned vector is a shared scratch.
    local kArcVelocityScratch = Vector(0, 0, 0)
    function Babbler:GetArcVelocity(targetPos, minArcHeight, orig)

        orig = orig or self:GetOrigin()
        local vx, vy, vz, flightTime = SolveArc(targetPos.x - orig.x, targetPos.y - orig.y, targetPos.z - orig.z, minArcHeight)

        local velocity = kArcVelocityScratch
        velocity.x, velocity.y, velocity.z = vx, vy, vz

        return velocity, flightTime

    end

    function Babbler:GetMoveVelocity(targetPos)
        return self:GetArcVelocity(targetPos)
    end

    function Babbler:GetLeapVelocity(targetPos)
        return self:GetArcVelocity(targetPos)
    end

    local kJumpHangTimeEstimate = 0.8 -- fallback only, used when the caller has no computed flight time
    function Babbler:GetIsSafeJumpVelocity(velocity, flightTime)

        local landingPos = self:GetOrigin() + Vector(velocity.x, 0, velocity.z) * (flightTime or kJumpHangTimeEstimate)

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

        if #ents > 0 then -- Take closest hive and stand still in it until the com leaves
            pos = ents[1]:GetOrigin()
        end
        return pos
    end

    -- Babblers whose host went commander keep the Cling order on the commander (so they
    -- re-cling to whoever comes out when the com logs out, see OnEntityChange), but they
    -- can't attach to anything: walk to the hive (self.targetPos), then stand still.
    -- The hive origin sits inside the hive's collision, so it can't be reached exactly:
    -- arriving within this XZ radius (or the path ending) counts as being in the hive.
    local kHiveHoldRadius = 3.5
    local kHiveHoldRadiusSq = kHiveHoldRadius * kHiveHoldRadius

    function Babbler:UpdateHoldAtHive(target, deltaTime, now)

        local hivePos = self.targetPos
        if not hivePos then
            return false -- nothing to hold at, drop the order
        end

        if not self.holdingAtHive then

            local orig = self:GetOrigin()
            local dx, dz = orig.x - hivePos.x, orig.z - hivePos.z

            if LengthSqXZ(dx, dz) <= kHiveHoldRadiusSq then
                self.holdingAtHive = true
            elseif self.timeLastJump + 0.5 < (now or Shared.GetTime()) and self:GetIsOnGround(now) then
                local _, targetReached = self:UpdateMove(target, deltaTime, now) --> :Move()
                if targetReached then
                    self.holdingAtHive = true
                end
            end

        end

        -- Holding: no movement at all, gravity / jump physics still run in UpdateBabbler
        return true

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

        -- Keep clinging if current host morphed into an embryo (drop otherwise).
        -- If it went commander, gather at the commander's hive and stand still until the com leaves
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
                local orderPos = target:isa("AlienCommander") and GetNewAlienCommanderPos(self, target) or target:GetOrigin()
                self:SetMoveType(kBabblerMoveType.Cling, nil, orderPos, true)
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
    function Babbler:Jump(velocity, now)
        self:SetGroundMoveType(false)

        local hasImpulse = velocity ~= nil and velocity:GetLengthSquared() > 0
        if hasImpulse then
            self.timeLastJump = now or Shared.GetTime()
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

    function Babbler:UpdateMove_forwardJumps(distToTarget, targetPos, now, orig)
        -- The closer we get, the higher the jump chances
        local success = false
        local jumpProbability = 0

        if distToTarget < kMinJumpDistance * 2 then
            jumpProbability = math.max(0, distToTarget - kMinJumpDistance) / 6
        end

        if jumpProbability >= math.random() then
            if NoObstacleInWay(self, targetPos) then
                local velocity, flightTime = self:GetArcVelocity(targetPos, nil, orig)
                if self:GetIsSafeJumpVelocity(velocity, flightTime) then
                    self:Jump(velocity, now)
                    success = true
                end
            end
        end
        return success
    end

    function Babbler:UpdateMove_randomJumps(targetPos, now, orig)
        -- Notes:
        --  To tune this, go gorge in a long hallway
        -- and throw babblers at the end.
        -- Tweak to your liking

        local cursorNextPos = nil
        -- Sideway jumps only if we still have some ground to cover, otherwise counterproductive
        if (self.cursor and self.cursor.index + 5 <= #self.cursor.points) then
            cursorNextPos = self.cursor.points[self.cursor.index + 2]
        end

        now = now or Shared.GetTime()
        local deviation = 0.1 + math.random() * 0.2 -- How far they deviate from path when moving (no straight line, more variations)
        local highJumpProb = 0.05
        local targetOrigin = cursorNextPos or targetPos
        local sideOffset = Vector(math.random() - 0.5 < 0 and deviation or -deviation,
                0,
                math.random() - 0.5 < 0 and deviation or -deviation)

        -- Occasionally arc noticeably higher, for visual variety
        local minArcHeight = (math.random() < highJumpProb) and (2.6 * kHeightTuningScale) or nil

        local velocity, flightTime = self:GetArcVelocity(targetOrigin + sideOffset, minArcHeight, orig)

        if self:GetIsSafeJumpVelocity(velocity, flightTime) then
            self:Jump(velocity, now)
            self:TriggerUncloak()
        end

        -- The constant added delay has to be higher than the self.timeLastJump delay in the function
        -- so we are sure that we are not jumping as soon as we reached the floor
        local rand = 0.5 + math.random() * 0.7
        self.timeNextMoveJump = now + 0.4 + rand * rand * rand
    end

    local function GetGaitSpeed(gaitPhase)
        return kBabblerRunSpeed * (1 + kGaitPulseAmount * math_sin(gaitPhase))
    end

    -- Weave: drift the wander angle with a clamped random walk, then rotate this
    -- tick's XZ displacement by it. Only the extra sideways component is applied
    -- (forward progress isn't shortened). Returns the new wanderAngle and the
    -- (possibly shifted) new X / Z.
    local function ApplyWander(wanderAngle, turnAccel, deltaTime, prevX, prevZ, newX, newZ)

        wanderAngle = Clamp(wanderAngle + (math.random() - 0.5) * deltaTime * turnAccel,
                -kWanderMaxAngle, kWanderMaxAngle)

        local moveDirX, moveDirZ = newX - prevX, newZ - prevZ
        if LengthSqXZ(moveDirX, moveDirZ) > kEpsilon * kEpsilon then
            local rotX, rotZ = RotateXZ(moveDirX, moveDirZ, wanderAngle)
            newX = newX + (rotX - moveDirX)
            newZ = newZ + (rotZ - moveDirZ)
        end

        return wanderAngle, newX, newZ

    end

    function Babbler:Move(distToTarget, targetPos, deltaTime, now, orig)

        now = now or Shared.GetTime()
        local prevOrig = orig or self:GetOrigin()
        local prevX, prevY, prevZ = prevOrig.x, prevOrig.y, prevOrig.z

        -- Follow pathfinding, simply moving accross the map toward target
        local moveDone = true

        local dx0, dz0 = prevX - targetPos.x, prevZ - targetPos.z
        if LengthSqXZ(dx0, dz0) > 0.0625 then -- same threshold as (prevOrig - targetPos):GetLengthXZ() > 0.25
            self:SetGroundMoveType(true)

            -- Gait pulse: subtle +/- speed wobble instead of a constant crawl
            -- speed, so the cadence (and the run-blend anim it drives, since
            -- that reads back actual velocity) doesn't look like a conveyor belt.
            local gaitSpeed = GetGaitSpeed(self.gaitPhase)
            self.gaitPhase = self.gaitPhase + deltaTime * self.gaitFreq

            moveDone = self:MoveToTarget(PhysicsMask.AIMovement, targetPos, gaitSpeed, deltaTime)

            local newOrigin = self:GetOrigin()
            local newX, newY, newZ = newOrigin.x, newOrigin.y, newOrigin.z

            -- Only lift while we really travelled; a stalled babbler must not
            -- keep ratcheting Y tick after tick
            local tdx, tdy, tdz = newX - prevX, newY - prevY, newZ - prevZ
            local travelled = Length3(tdx, tdy, tdz)
            if travelled > kEpsilon then

                local ground = GetGroundAt(self, newOrigin, PhysicsMask.AIMovement)
                local desiredY = ground.y + Babbler.kRadius
                -- a trace more than a step below means we found another level, not the
                -- surface we are walking on: keep last Y rather than diving through
                if prevY - desiredY < 1 then
                    newY = Slerp(prevY, desiredY, deltaTime * Clamp(travelled / deltaTime / 2, 0, 3))
                end

                -- Pathing re-aims fresh from the new origin every tick, so the
                -- drift never has to be corrected back out - it just makes the
                -- trip look less like it's on a rail.
                self.wanderAngle, newX, newZ = ApplyWander(self.wanderAngle, self.wanderTurnAccel, deltaTime,
                        prevX, prevZ, newX, newZ)

                newOrigin.x, newOrigin.y, newOrigin.z = newX, newY, newZ
                self:SetOrigin(newOrigin)
            end

            self.targetSelector:AttackerMoved()
        else -- Safety net
             if self.doesGroundMove then
                 local ground = GetGroundAt(self, prevOrig, PhysicsMask.AIMovement, nil, true)

                if prevY - ground.y > Babbler.kRadius or targetPos.y - prevY > Babbler.kRadius then
                     self:SetGroundMoveType(false) -- Trigger falling
                end
            end
        end

        -- Errative jump behavior when going from one place to an other
        if not moveDone and self.timeNextMoveJump < now
        then

            -- Could eventually do double jumps (forward and sideway)
            -- (origin may have changed above, so let these re-read it)
            self:UpdateMove_randomJumps(targetPos, now)
            self:UpdateMove_forwardJumps(distToTarget, targetPos, now)

            -- The constant added delay has to be higher than the self.timeLastJump delay in the function
            -- so we are sure that we are not jumping as soon as we reached the floor
            local rand = 0.5 + math.random() * 0.7
            self.timeNextMoveJump = now + 0.4 + rand * rand * rand
        end

        return moveDone

    end

    function Babbler:UpdateMove(target, deltaTime, now)

        PROFILE("Babbler:UpdateMove")

        local success = false
        local targetReached = false

        local orig = self:GetOrigin()
        local targetPos = self.targetPos or (target and target:GetOrigin())
        local distToTarget, distToTargetXZ
        if targetPos then
            local dx, dy, dz = orig.x - targetPos.x, orig.y - targetPos.y, orig.z - targetPos.z
            distToTargetXZ = LengthXZ(dx, dz)
            distToTarget = Length3(dx, dy, dz)
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

            local moveDone = self:Move(distToTarget, targetPos, deltaTime, now, orig)
            if moveDone or distToTargetXZ < 0.5 then
                targetReached = true
            end
            success = true

        end
        return success, targetReached
    end

    -- Ground-hug toward a cling attach point at run speed.
    local kWalkOriginScratch = Vector(0, 0, 0)
    local function WalkTowardAttachPoint(self, delta, distance, deltaTime, orig)
        local moveDir = GetNormalizedVector(delta)
        local travelDistance = math.min(deltaTime * kBabblerRunSpeed, distance)
        self:SetGroundMoveType(true)
        local newOrigin = VecAddScaled(kWalkOriginScratch, orig, moveDir, travelDistance)
        self:SetOrigin(newOrigin)
    end

    function Babbler:Cling(target, deltaTime, now)


        local babblerMaxLeapDistance = 5
        if not target then return false end
        if not target:GetIsAlive() then return false end

        local attachPointOrigin, isWeb = self:GetClingAttachPoint(target)

        if not attachPointOrigin then
            return false
        end

        now = now or Shared.GetTime()
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
            WalkTowardAttachPoint(self, delta, distance, deltaTime, orig)
        else -- Multi-leap upward (or level, or downward) toward targets

            -- Last safeguard to prevent in-the-air stuck babblers (kept just in case)
            if self.doesGroundMove and self.lastOrigin:GetDistanceTo(orig) < kEpsilon then
                self:SetGroundMoveType(false)
            end

            local leapTarget = attachPointOrigin
            if (self.nextLeapTime or 0) < now then
                if distance > babblerMaxLeapDistance then
                    leapTarget = orig + GetNormalizedVector(delta) * babblerMaxLeapDistance
                end

                local moveVelocity, flightTime = self:GetArcVelocity(leapTarget, nil, orig)
                -- If target is above a 45/3 degree angle from us, need to jump
                -- If we havn't jumped for a while (stuck ?) jump anyway
                -- if (not obstacleInWay and yDiff > -0.5) or now - self.timeLastJump > 3 then
                if (not obstacleInWay and yDiff > -0.5) then
                    self:Jump(moveVelocity, now)
                end
                self.nextLeapTime = now + flightTime/2 + math.random() * 0.3
            end
        end
        return true

    end

    function Babbler:UpdateCling(target, deltaTime, now)
        if not self:Cling(target, deltaTime, now) then
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

    function Babbler:MoveRandom(now)
        PROFILE("Babbler:MoveRandom")

        now = now or Shared.GetTime()
        if not self.babblerOffMap
            and (self.moveType == kBabblerMoveType.None)
            and self:GetIsOnGround(now) then

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
    local kPlayerAimLeadTime = 0.9  -- players get a longer lead - 0.4s isn't enough to cut off circle-strafing
    local function GetLeadPosition(target)

        local aimPos = GetEngagementOrOrigin(target)
        local isMoving = false

        if target.GetVelocity then
            local velocity = target:GetVelocity()
            if velocity:GetLengthSquared() > kEpsilon then
                local leadTime = target:isa("Player") and kPlayerAimLeadTime or kAimLeadTime
                VecAddScaled(aimPos, aimPos, velocity, leadTime)
                isMoving = true
            end
        end

        return aimPos, isMoving
    end

    -- Launch-time scatter on top of the lead point, so a swarm doesn't all
    -- jump at the exact same pixel - and so no two jumps in the same chase
    -- look alike, since this is freshly rolled every single jump.
    local kAimJitterXZ = 1.1
    local kAimJitterY = 1.0

    local kStaticNudgeMinDist = 0.3
    local kStaticNudgeMaxDist = 0.6
    local function GetJumpAimPoint(self, target)
        local aimPos, isMoving = GetLeadPosition(target)

        if isMoving then
            aimPos.x = aimPos.x + (math.random() - 0.5) * kAimJitterXZ
            aimPos.z = aimPos.z + (math.random() - 0.5) * kAimJitterXZ
        else
            -- Only apply horizontal scatter for distant/static ground targets
            local targetHeightDiff = aimPos.y - self:GetOrigin().y
            
            if targetHeightDiff <= 0.5 then
                -- Minimal scatter for ground-level targets (still useful for hitbox coverage)
                local angle = math.random() * math.pi * 2
                local dist = 0.2 + math.random() * 0.2
                aimPos.x = aimPos.x + math.cos(angle) * dist
                aimPos.z = aimPos.z + math.sin(angle) * dist
                
                -- Tight vertical nudge for ground targets
                aimPos.y = aimPos.y + (math.random() - 0.5) * 0.15
            else
                -- No horizontal scatter for elevated targets - preserve vertical momentum
                -- Vertical scatter remains but centered closer to target height
                aimPos.y = aimPos.y + (math.random() - 0.5) * 0.4
            end
        end

        return aimPos
    end

    -- mid-air homing: babblers curve gently toward their target between
    -- attack jumps instead of overshooting in a straight line
    local kHomingNudgeSpeed = 3.5 -- How fast we converge
    local kHomingNudgeDelay = 0.5 -- How frequently we adjust
    local kHomingBurstSize  = 2   -- How many nudges per jump
    local kHomingLerpFactor = 0.1

    local function ComputeHomingNudge(cx, cz, toX, toZ)

        if LengthSqXZ(toX, toZ) <= kEpsilon then
            return nil
        end

        local dirX, dirZ = NormalizeXZ(toX, toZ)
        local currentSpeedXZ = math.max(LengthXZ(cx, cz), kHomingNudgeSpeed)

        return cx + (dirX * currentSpeedXZ - cx) * kHomingLerpFactor,
               cz + (dirZ * currentSpeedXZ - cz) * kHomingLerpFactor

    end

    local function HomingFlightTrajectory(self, isOnGround, target, now)

        if isOnGround or self.kStopImpulseDone >= kHomingBurstSize then
            return
        end

        now = now or Shared.GetTime()
        if now <= self.timeLastStopImpulse + kHomingNudgeDelay then
            return
        end

        local current = self:GetVelocity(now)
        local leadPos = GetLeadPosition(target)
        local origin = self:GetOrigin()

        local newX, newZ = ComputeHomingNudge(current.x, current.z, leadPos.x - origin.x, leadPos.z - origin.z)
        if newX then
            current.x = newX
            current.z = newZ
            self:SetVelocity(current)
        end

        self.kStopImpulseDone = self.kStopImpulseDone + 1
        self.timeLastStopImpulse = now
    end

    function Babbler:UpdateAttack(target, force, now)

        if self.babblerOffMap then
            return
        end

        local targetIsAlive = target and HasMixin(target, "Live") and target:GetIsAlive()
        if not target or not targetIsAlive then
            self:SetMoveType(kBabblerMoveType.None)
            return
        end

        now = now or Shared.GetTime()
        local isOnGround = self:GetIsOnGround(now)

        if isOnGround then
            self.kStopImpulseDone = 0
        end

        HomingFlightTrajectory(self, isOnGround, target, now)

        if force or (isOnGround and now > self.kNextUpdateAttack + 0.1) then

            local canReach = CanReachTarget(self, target)
            local babblerBall = not canReach and self:GetBabblerBall()
            local babblerBallId = babblerBall and babblerBall:GetId()

            if canReach then

                local aimPos = GetJumpAimPoint(self, target)
                local orig = self:GetOrigin()

                local moveVel = self:GetArcVelocity(aimPos, nil, orig)
                local aimDX, aimDZ = aimPos.x - orig.x, aimPos.z - orig.z
                local distXZ = LengthXZ(aimDX, aimDZ)
                local desiredSpeedXZ = distXZ / kUpdateAttackInterval
                local speedXZ = LengthXZ(moveVel.x, moveVel.z)
                if speedXZ > desiredSpeedXZ then
                    local scale = math.max(desiredSpeedXZ, kEpsilon) / speedXZ
                    moveVel.x = moveVel.x * scale
                    moveVel.z = moveVel.z * scale
                end

                self:Jump(moveVel, now)
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
            away.y = math.max(0.05, away.y) -- never push downward below the map
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


    -- Picks the next stroll target along the strand. Returns targetT, walkDir (+1 / -1).
    local function PickWebStrollTarget(myT, length, margin)

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

        local targetT = Clamp(candidateT, margin, length - margin)
        return targetT, (targetT >= myT) and 1 or -1

    end

    -- Advances one tick along the strand. Returns arrived, newT.
    local function StepWebPosition(myT, targetT, walkDir, deltaTime, speed, margin, length)

        local arrived = math.abs(targetT - myT) <= deltaTime * speed
        local t = Clamp(arrived and targetT or myT + walkDir * deltaTime * speed, margin, length - margin)
        return arrived, t

    end

    function Babbler:UpdateWebBehavior(deltaTime, now)

        local web = self:GetWeb()
        if not web or not web:GetIsAlive() then
            self:DetachFromWeb()
            return
        end

        local origin, axis, length = web:GetWebAxis()
        if not axis then return end

        now = now or Shared.GetTime()

        -- angry chittering while panicked
        if self.panicExpire ~= nil then

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
        local selfOrigin = self:GetOrigin()
        local myT = (selfOrigin.x - origin.x) * axis.x
                + (selfOrigin.y - origin.y) * axis.y
                + (selfOrigin.z - origin.z) * axis.z
        self.webWalkTimer = (self.webWalkTimer or 1) - deltaTime

        if self.webTargetT == nil and self.webWalkTimer <= 0 then

            self.webTargetT, self.webWalkDir = PickWebStrollTarget(myT, length, margin)
            self.webWalkSpeed = Babbler.kWebWalkSpeed * (0.5 + math.random() * 0.85)
            self.webWalking = true
            self.webWalkTimer = kWebConfig.strollTimeout

        end

        if self.webTargetT ~= nil then

            local panicking = self.panicExpire ~= nil and now < self.panicExpire
            local speed = (self.webFastTravel and kWebTravelSpeed or self.webWalkSpeed or Babbler.kWebWalkSpeed)
                    * self.webSpeedMult
                    * (panicking and kWebConfig.panicSpeedMult or 1)

            local arrived, t = StepWebPosition(myT, self.webTargetT, self.webWalkDir, deltaTime, speed, margin, length)
            local timedOut = self.webWalkTimer <= 0

            if arrived or not timedOut then

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
                self.webWalkTimer = GetWebIdleTime(self, now)
            end

            return
        end

        -- Make babbler do some happy noise once in a while
        if self.timeNextWebChatter == nil or now >= self.timeNextWebChatter then
            self:TriggerEffects(math.random() < 0.5 and "babbler_wag_begin" or "babbler_jump") 
            self.timeNextWebChatter = now + (kWebConfig.chatterMin + math.random() * kWebConfig.chatterRange) * self.webIdleMult
            self.wagging = math.random() < 0.4
        end
        -- Make babbler investigate the web once in a while
        if self.timeNextWebForage == nil or now >= self.timeNextWebForage then
            if math.random() < 0.65 then
                self.foraging = true
            else
                self.hungry = true
            end
            self:AddTimedCallback(ClearForagingCallback, kAnimForagingDuration)

            self.timeNextWebForage = now + (kWebConfig.foragingMin + math.random() * kWebConfig.foragingRange) * self.webIdleMult
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
            self:AddTimedCallback(KillIfAliveCallback, 1)
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

    local kMeasureGravity = false
    local function MeasureGravity(self, velocity, deltaTime)

        local isOnGround = self:GetIsOnGround()

        -- Landed (or never left): flush and print whatever this flight collected.
        if isOnGround then
            if self.gravityMeasureCount and self.gravityMeasureCount > 0 then
                Print("[gravity measure] %d samples, avg = %.3f, min = %.3f, max = %.3f",
                        self.gravityMeasureCount,
                        self.gravityMeasureSum / self.gravityMeasureCount,
                        self.gravityMeasureMin, self.gravityMeasureMax)
            end
            self.gravityMeasureSum, self.gravityMeasureCount = nil, nil
            self.gravityMeasureMin, self.gravityMeasureMax = nil, nil
            return
        end

        -- Skip the tick a jump impulse lands on - that's a discrete velocity
        -- change from AddImpulse, not gravity integrating over the timestep.
        local now = Shared.GetTime()
        local justJumped = self.timeLastJump and (now - self.timeLastJump) <= deltaTime

        if not justJumped and self.lastVelocity and deltaTime > 0 then

            local accelY = (self.lastVelocity.y - velocity.y) / deltaTime -- positive = being pulled down

            -- Sanity bounds reject the occasional bounce/collision tick (which
            -- shows up as a negative or wildly large "gravity") without us
            -- having to specifically detect collisions.
            if accelY > 1 and accelY < 100 then
                self.gravityMeasureSum = (self.gravityMeasureSum or 0) + accelY
                self.gravityMeasureCount = (self.gravityMeasureCount or 0) + 1
                self.gravityMeasureMin = math.min(self.gravityMeasureMin or accelY, accelY)
                self.gravityMeasureMax = math.max(self.gravityMeasureMax or accelY, accelY)
            end

        end

    end

    function Babbler:UpdateJumpPhysics(deltaTime, now)

        local velocity = self:GetVelocity(now)  -- Current velocity from physics body

        if self.physicsBody and not self.doesGroundMove then

            if kMeasureGravity then
                MeasureGravity(self, velocity, deltaTime)
            end

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

            self.physicsBody:SetEntity(self)

            self:AddTimedCallback(BabblerSetLinearDampingCallback, kFinalDampingAfterDelay)


        elseif (isClinged or isOnWeb) then
            self:DestroyPhysicsBody()
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
            Log("Error: trying to assign an attack order to %s with no target\n%s", self,
                    Script.CallStack and Script.CallStack() or "")
            moveType = position and kBabblerMoveType.Move or kBabblerMoveType.None
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
            self.holdingAtHive = nil
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

        local targetUsable = target ~= nil and not (HasMixin(target, "Live") and not target:GetIsAlive())
        if not targetUsable then
            if position then
                self:OrderMove(position)
            else
                self:OrderIdle()
            end
            return
        end

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

    local kFacingTurnRate = math.pi * 3   -- rad/s: a 180-degree pirouette in ~0.33s
    local kSpinWobble = math.rad(13)      -- how much the spin cones off-axis instead of rolling flat

    local function ComputeWebPose(ax, ay, az, facingAngle, rollAngle, p0x, p0y, p0z)

        -- up0: reference direction made perpendicular to the axis
        local rx, ry, rz = 0, 1, 0
        if p0x then
            rx, ry, rz = p0x, p0y, p0z
        end

        local ux, uy, uz = AddScaled3(rx, ry, rz, ax, ay, az, -Dot3(rx, ry, rz, ax, ay, az))

        if LengthSq3(ux, uy, uz) < 0.01 then
            ux, uy, uz = AddScaled3(0, 1, 0, ax, ay, az, -ay) -- world up, perpendicular to the axis
            if LengthSq3(ux, uy, uz) < 0.01 then
                ux, uy, uz = Cross3(ax, ay, az, 1, 0, 0)
                if LengthSq3(ux, uy, uz) < 0.01 then
                    ux, uy, uz = Cross3(ax, ay, az, 0, 0, 1)
                end
            end
        end
        ux, uy, uz = Normalize3(ux, uy, uz)

        -- w: tangent around the strand
        local wx, wy, wz = Cross3(ax, ay, az, ux, uy, uz)

        local cu, su = math_cos(rollAngle), math_sin(rollAngle)
        local upx, upy, upz = Combine3(ux, uy, uz, cu, wx, wy, wz, su)
        local tx, ty, tz = Combine3(wx, wy, wz, cu, ux, uy, uz, -su)

        -- tilt "up" slightly toward the strand as it spins so the roll traces a
        -- shallow cone instead of a flat, mechanical rotation around the axis
        local wobble = (math_sin(rollAngle * 2) + 0.3 * math_sin(rollAngle * 5)) * kSpinWobble
        upx, upy, upz = AddScaled3(upx, upy, upz, ax, ay, az, wobble)
        upx, upy, upz = Normalize3(upx, upy, upz)

        local cf, sf = math_cos(facingAngle), math_sin(facingAngle)
        local fx, fy, fz = Combine3(ax, ay, az, cf, tx, ty, tz, sf)

        -- re-orthogonalize against tilted up
        fx, fy, fz = AddScaled3(fx, fy, fz, upx, upy, upz, -Dot3(upx, upy, upz, fx, fy, fz))
        fx, fy, fz = Normalize3(fx, fy, fz)

        -- xAxis = up x forward
        local xx, xy, xz = Cross3(upx, upy, upz, fx, fy, fz)

        return ux, uy, uz, xx, xy, xz, upx, upy, upz, fx, fy, fz

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

        local id = self.spinId
        if not id then
            id = self:GetId()
            self.spinId = id
        end
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

    local kModelLookDir = Vector(0, 0, 0) -- reused; y stays 0
    function Babbler:OnAdjustModelCoords(modelCoords)

        if self:GetIsOnWeb() then

            if self.spinAxX then
                local u0x, u0y, u0z, xx, xy, xz, yx, yy, yz, zx, zy, zz = ComputeWebPose(
                        self.spinAxX, self.spinAxY, self.spinAxZ,
                        self.webFacingAngle or 0, self:GetSpinRenderAngle(),
                        self.webUp0X, self.webUp0Y, self.webUp0Z)
                self.webUp0X, self.webUp0Y, self.webUp0Z = u0x, u0y, u0z

                local co = Coords.GetIdentity()
                co.origin = modelCoords.origin
                co.xAxis = Vector(xx, xy, xz)
                co.yAxis = Vector(yx, yy, yz)
                co.zAxis = Vector(zx, zy, zz)
                return co
            end
            return modelCoords

        end

        local mdX, mdZ = self.moveDirX, self.moveDirZ
        if not self:GetIsClinged() and mdX and LengthSqXZ(mdX, mdZ) >= kEpsilon then
            kModelLookDir.x = mdX
            kModelLookDir.z = mdZ
            modelCoords = Coords.GetLookIn(modelCoords.origin, kModelLookDir)
            modelCoords.origin.y = modelCoords.origin.y - Babbler.kRadius
        end

        return modelCoords

    end

    local kSpinAxisMinSpeed = 0.05

    -- Blends the smoothed spin axis toward the (normalised) velocity direction.
    -- ax may be nil (no axis yet). Returns the new unit axis and velocity . axis.
    local function ComputeSpinAxis(ax, ay, az, vx, vy, vz, speed, dt)

        local nx, ny, nz = vx / speed, vy / speed, vz / speed

        if ax then
            if Dot3(ax, ay, az, nx, ny, nz) < 0 then
                nx, ny, nz = -nx, -ny, -nz
            end
            ax, ay, az = AddScaled3(ax, ay, az, nx, ny, nz, dt * 5)
        else
            ax, ay, az = nx, ny, nz
        end

        ax, ay, az = Normalize3(ax, ay, az)

        return ax, ay, az, Dot3(vx, vy, vz, ax, ay, az)

    end

    -- Turns the facing angle toward target, limited by kFacingTurnRate.
    local function StepFacingAngle(a, target, dt)

        local d = WrapAngle(target - a)
        if math.abs(d) < 0.01 then
            return target
        end
        return a + Clamp(d, -kFacingTurnRate * dt, kFacingTurnRate * dt)

    end

    local function AdvanceSpinPhase(phase, dt, moving)

        if moving then
            return phase + dt / kSpinPeriod
        end

        local boundary = math.floor(phase) + 1
        local u = phase - boundary + 1
        if u > kIdleEnd and u < kSpinEnd then
            phase = math.min(phase + dt / kSpinPeriod, boundary)
        end
        return phase

    end

    function Babbler:UpdateSpinAxis(deltaTime)

        if not self:GetIsOnWeb() then
            self.spinAxX, self.spinAxY, self.spinAxZ = nil, nil, nil
            self.spinAngle = nil
            self.spinSeg = nil
            self.spinPhase = nil
            self.webFacingAngle = nil
            self.webUp0X, self.webUp0Y, self.webUp0Z = nil, nil, nil
            self.webWalkSign = nil
            return
        end

        local dt = Clamp(deltaTime, 0, 0.1)

        local moving = false
        local cv = self.clientVelocity
        if cv then

            local vx, vy, vz = cv.x, cv.y, cv.z
            local speed = Length3(vx, vy, vz)

            if speed > kSpinAxisMinSpeed then

                local ax, ay, az, along = ComputeSpinAxis(self.spinAxX, self.spinAxY, self.spinAxZ, vx, vy, vz, speed, dt)
                self.spinAxX, self.spinAxY, self.spinAxZ = ax, ay, az

                if not self.webWalkSign then
                    self.webWalkSign = along >= 0 and 1 or -1
                elseif along < -0.15 and self.webWalkSign > 0 then
                    self.webWalkSign = -1
                elseif along > 0.15 and self.webWalkSign < 0 then
                    self.webWalkSign = 1
                end

                self.webFacingAngle = StepFacingAngle(self.webFacingAngle or 0, along >= 0 and 0 or math.pi, dt)

                moving = true

            end

        end

        self.spinPhase = AdvanceSpinPhase(self.spinPhase or 0, dt, moving)

    end

    -- Smooths the facing direction (XZ) toward the wanted direction.
    local function SmoothMoveDirection(sx, sz, mx, mz, deltaTime)

        local dx, dz = mx - sx, mz - sz
        local turnScale = deltaTime * LengthXZ(dx, dz) * 5

        sx = sx + mx * turnScale
        sz = sz + mz * turnScale

        return NormalizeXZ(sx, sz)

    end

    function Babbler:UpdateMoveDirection(deltaTime, now, orig)

        if not self:GetIsClinged() then -- No sound when attached
            if self.clientJumping ~= self.jumping and self.jumping then
                local vel = self:GetVelocity(now, orig)
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

        local lastOrigin = self.lastOrigin
        if lastOrigin then
            orig = orig or self:GetOrigin()

            -- Read the engine vectors once, everything below is plain numbers
            local ox, oy, oz = orig.x, orig.y, orig.z
            local mvX, mvY, mvZ = ox - lastOrigin.x, oy - lastOrigin.y, oz - lastOrigin.z

            -- PRIORITY 1: Actual movement direction (last origin -> current origin)
            -- This reflects where we actually moved, including wander/weave offsets
            local hasMovement = LengthSqXZ(mvX, mvZ) >= kEpsilon

            -- PRIORITY 2: Only use target direction if not moving or in attack mode
            local target = self:GetTarget()
            local useTargetDirection = false
            if target and not hasMovement and not target:isa("Commander") then
                -- Stationary but has target - face the target (a commander's origin is just its camera)
                useTargetDirection = true
            elseif target and self.moveType == kBabblerMoveType.Attack and hasMovement then
                -- Attacking AND moving - face target for better hit registration
                useTargetDirection = true
            end

            local rawX, rawZ = mvX, mvZ
            if useTargetDirection then
                local targetOrigin = target:GetOrigin()
                rawX, rawZ = NormalizeXZ(targetOrigin.x - ox, targetOrigin.z - oz)
            end

            if LengthSqXZ(rawX, rawZ) >= kEpsilon then
                local wantX, wantZ = NormalizeXZ(rawX, rawZ)
                self.moveDirX, self.moveDirZ = SmoothMoveDirection(self.moveDirX or 0, self.moveDirZ or 0,
                        wantX, wantZ, deltaTime)
            end

            if deltaTime > 0 then
                local cv = self.clientVelocity
                if not cv then
                    cv = Vector(0, 0, 0)
                    self.clientVelocity = cv
                end
                cv.x, cv.y, cv.z = mvX / deltaTime, mvY / deltaTime, mvZ / deltaTime
            end
        end

        self.clientJumping = self.jumping
        self.clientAttacking = self.attacking

    end

    -- Fraction of kBabblerRunSpeed. doesGroundMove stays set after a ground move
    -- ends (the body is kept kinematic at rest), so it alone can't pick "run".
    local kRunAnimMinSpeed = 0.05

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
        elseif self.doesGroundMove and (self.smoothedMoveSpeed or 0) > kRunAnimMinSpeed then
            move = "run"
        elseif self.wagging then
            move = "wag"
        end

        modelMixin:SetAnimationInput("forage", self.foraging)
        modelMixin:SetAnimationInput("hungry", self.hungry)
        modelMixin:SetAnimationInput("move", move)
        modelMixin:SetAnimationInput("attacking", not (self.clinged or self.foraging or self.hungry) and self.attacking)

    end

    local function ComputeMoveYaw(forwardX, forwardZ, dirX, dirZ)

        -- xAxis = up x forward = (forwardZ, 0, -forwardX), zAxis = forward
        local x = forwardZ * dirX - forwardX * dirZ
        local z = forwardX * dirX + forwardZ * dirZ

        return (math_deg(math_atan2(z, x)) + 180) % 360

    end

    function Babbler:OnUpdatePoseParameters()

        PROFILE("Babbler:OnUpdatePoseParameters")

        local moveYaw = 0
        local targetSpeed = 0

        if self.onWeb then
            targetSpeed = self.webWalking and 1 or 0
        elseif self.clientVelocity then
            local cv = self.clientVelocity
            local vx, vy, vz = cv.x, cv.y, cv.z

            -- Same forward the model is rendered with (see OnAdjustModelCoords)
            local fwdX, fwdZ = self.moveDirX or 0, self.moveDirZ or 0
            if LengthSqXZ(fwdX, fwdZ) < kEpsilon then
                local zAxis = self:GetCoords().zAxis
                fwdX, fwdZ = NormalizeXZ(zAxis.x, zAxis.z)
            end

            local dirX, dirZ
            if LengthSqXZ(vx, vz) > 0 then
                dirX, dirZ = NormalizeXZ(vx, vz)
            else
                dirX, dirZ = fwdX, fwdZ
            end

            moveYaw = ComputeMoveYaw(fwdX, fwdZ, dirX, dirZ)
            targetSpeed = Clamp(Length3(vx, vy, vz) / kBabblerRunSpeed, 0, 1)
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
