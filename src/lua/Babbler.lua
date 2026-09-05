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

local kTargetSearchRange = 12
local kTargetMaxFollowRange = 30
local kAttackRate = 0.40

local kBabblerSearchTime = 8
local kBabblerOffMapInterval = 1

local kUpdateMoveInterval = 0.3
local kUpdateAttackInterval = 0.4

local kMinJumpDistance = 5
local kBabblerRunSpeed = 8.2
local kBabblerJumpSpeed = 7.75
local kVerticalJumpForce = 6
local kMaxJumpForce = 15
local kMinJumpForce = 5
local kTurnSpeed = math.pi

local Math_DotProduct = Math.DotProduct
local Math_Wrap = Math.Wrap
local Math_Degrees = Math.Degrees

local math_atan2 = math.atan2

local function GetEngagementOrOrigin(entity)
    return HasMixin(entity, "Target") and entity:GetEngagementPoint() or entity:GetOrigin()
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
    creationTime = "time",
    silenced = "boolean",
    variant = "enum kBabblerVariants",
    -- updates every 10 and [] means no compression used (not updates are send in this case)
    m_angles = "interpolated angles (by 0.05 [2 3 5], by 0.1 [2 3 5], by 0.05 [2 3 5])",
    m_origin = "compensated interpolated position (by 0.05 [2 3 5], by 0.05 [2 3 5], by 0.05 [2 3 5])",
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ClientModelMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(CloakableMixin, networkVars)
AddMixinNetworkVars(DetectableMixin, networkVars)
AddMixinNetworkVars(FireMixin, networkVars)
AddMixinNetworkVars(GameEffectsMixin, networkVars)

function Babbler:CreateHitBox()

    if self:GetIsAlive() and not self:GetIsDestroyed() and not self.clinged and not self.hitBox then
    
        -- Log("Creating hitbox for %s", self)
        self.hitBox = Shared.CreatePhysicsSphereBody(false, Babbler.kRadius * 2, Babbler.kMass, self:GetCoords() )
        self.hitBox:SetGroup(PhysicsGroup.BabblerGroup)
        self.hitBox:SetCoords(self:GetCoords())
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
        self.silenced = false
        
        InitMixin(self, PathingMixin)
        
        self.moveType = kBabblerMoveType.None
        self.clinged = false

        self.onWeb = false

        self.attacking = false

        self.creationTime = Shared.GetTime()

    elseif Client then
    
        self.oldModelIndex = 0
        self.clientJumping = self.jumping
        self.clientTimeLastAttack = 0
        self.clientClinged = self.clinged
        self.clientAttacking = self.attacking
        self.clientVelocity = nil

        --skins stuff
        self.dirtySkinState = false
        self.delayedSkinUpdate = false
        self.clientVariant = false
        
    end

    self:SetUpdateRate(kRealTimeUpdateRate)
    
end

function Babbler:OnInitialized()

    self:SetModel(Babbler.kModelName, kAnimationGraph)
    
    self.hatchAttack = true
    self.kGetIsOnGround = false
    self.timeNextMoveJump = Shared.GetTime() + math.random() * 2
    self.kGetIsOnGroundLastCheck = 0

    if Server then

        InitMixin(self, MobileTargetMixin)
        InitMixin(self, TargetCacheMixin)
        
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

        self:NotifyOwnerDestroyed(self:GetOwner())

        if self.onWeb and self:GetWeb() then
            self:GetWeb():RemoveWebbedBabbler(self)
        end

    end

    ScriptActor.OnDestroy(self)

    if Server then
        self:Detach(true)
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
    return self.clinged --not self.babblerBombSpawned and self.clinged
end

function Babbler:GetIsOnWeb()
    return self.onWeb == true
end

function Babbler:GetCanTakeDamage()
    return not self:GetIsClinged()
end

function Babbler:GetTarget()

    local target = self.targetId ~= nil and Shared.GetEntity(self.targetId)
    return target

end

function Babbler:GetIsOnGround()
    local vel = self:GetVelocity()
    local velLength = vel:GetLength()
    local isGlidingOnFloor = velLength < 3.5 and math.abs(vel.y) < 0.30

    return velLength < 0.5 or isGlidingOnFloor or self.babblerOffMap
end

function Babbler:GetVelocity()

    if self.physicsBody then
        return self.physicsBody:GetLinearVelocity()
    end
    if self.lastOrigin then
        local now = Shared.GetTime()
        return (self:GetOrigin() - self.lastOrigin) / (now - self.lastUpdate)
    end
    return Vector(0,0,0)
    
end

local kDefaultMask = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToReadyRoom)
local kDefaultMaskTeam1 = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToTeam1Commander, kRelevantToReadyRoom)
local kDefaultMaskTeam2 = bit.bor(kRelevantToTeam1Unit, kRelevantToTeam2Unit, kRelevantToTeam2Commander, kRelevantToReadyRoom)
local kDefaultMaskBoth = bit.bor(kDefaultMaskTeam1, kDefaultMaskTeam2)
function Babbler:UpdateRelevancy()

    PROFILE("Babbler:UpdateRelevancy")

    local owner = self:GetOwner()
    local sighted = owner ~= nil and (owner:GetOrigin() - self:GetOrigin()):GetLengthSquared() < 16 and (HasMixin(owner, "LOS") and owner:GetIsSighted())

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
        self:SetExcludeRelevancyMask( mask )
        self.lastSetRelevancyMask = mask
    end

end

function Babbler:UpdateBabbler(deltaTime)

    if Client then  -- deal with skins
        if self.delayedSkinUpdate then
            self.dirtySkinState = true
            self.delayedSkinUpdate = false
        end
    end

    if not self:GetIsAlive() or self:GetIsClinged() then
        return
    end

    if Server then

        -- web behavior is driven from OnUpdate; nothing else to do here
        if self:GetIsOnWeb() then
            return
        end

        self:UpdateMove(deltaTime)
        self:UpdateJumpPhysicsBody()
        self:UpdateJumpPhysics(deltaTime)
        self.attacking = self.timeLastAttack + 0.2 > Shared.GetTime()
        self.wagging = self.moveType == kBabblerMoveType.Wag

        self:UpdateAttack()
        self:UpdateRelevancy()

    elseif Client then

        self:UpdateMoveDirection(deltaTime)

        local model = self:GetRenderModel()
        if model ~= nil and not self.addedToHiveVision then
            HiveVision_AddModel(model, kHiveVisionOutlineColor.Green)
            self.addedToHiveVision = true
        end

    end

    self.lastVelocity = self:GetVelocity()
    self.lastOrigin = self:GetOrigin()
    self.lastUpdate = Shared.GetTime()

end

function Babbler:UpdatePhysics()
    self:CreateHitBox()
    if self.hitBox then
        self.hitBox:SetCoords(self:GetCoords())
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

        -- Whoever uses it pulls it off the web immediately; the Cling move order
        -- below then handles flying to the user and re-attaching/re-owning it.
        if self:GetIsOnWeb() then
            self:DetachFromWeb()
        end

        local moveType = kBabblerMoveType.Cling
        local position = GetEngagementOrOrigin(player)
        self:SetMoveType(moveType, player, position, true)
    end

    self:TriggerEffects("babbler_jump") 

end

function Babbler:OnUpdatePhysics()
    self:UpdatePhysics()
end

function Babbler:OnFinishPhysics()
    self:UpdatePhysics()
end

function Babbler:ForceAttack(deltaTime)

    if not Server then
        return false
    end

    local lifetime = Shared.GetTime() - self:GetCreationTime()
    local target = self:GetTarget()
    local isTargetEnemy = target and HasMixin(target, "Team") and target:GetTeamNumber() == GetEnemyTeamNumber(self:GetTeamNumber())

    if 0.25 < lifetime then -- Time to spread babblers on hatch a bit
        if self.hatchAttack and target and isTargetEnemy and target:isa("Player") and lifetime < 1 then
            local targetPosition = GetEngagementOrOrigin(target)
            local direction = (targetPosition - self:GetOrigin()):GetUnit()
            local distToTarget = self:GetOrigin():GetDistanceTo(targetPosition)

            self:SetOrigin(self:GetOrigin() + direction * deltaTime * kBabblerRunSpeed * 1.50)
            self:SyncPhysicsCoords()

            if distToTarget < 1.5 then
                self:SetMoveType(kBabblerMoveType.Attack, target, targetPosition)
                self:UpdateAttack(true)
                self.hatchAttack = false
            else
                self:SetGroundMoveType(true)
                return true
            end
            return false
        else
            if self.hatchAttack then
                self.hatchAttack = false
                self:SetGroundMoveType(false)
            end
        end
    end

    return false
end

function Babbler:OnUpdate(deltaTime)
    PROFILE("Babbler:OnUpdate")

    ScriptActor.OnUpdate(self, deltaTime)

    self:UpdateBabbler(deltaTime)

    if Server then
        if self.onWeb then
            self:UpdateWebBehavior(deltaTime)
        elseif self.babblerOffMap then
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
        
        local parent = self:GetParent()
        if parent then
            self:SetOrigin(parent:GetOrigin())
        end
        
    end
    
end

function Babbler:GetPhysicsModelAllowedOverride()
    return false
end

if Server then

    local kBabblerWebEndMargin = 0.2
    local kWebTravelSpeed = 3.5

    -- all web-behaviour tuning in one place
    local kWebConfig =
    {
        strollChance   = 0.65,
        strollTimeout = 8,
        idleMin       = 1,
        idleRange     = 1.5,          -- idle action delay, calm: 1..2.5s
        panicMin      = 0.1,          -- panicked: chain strolls back-to-back
        panicRange    = 0.2,
        panicSpeedMult = 4.0,
        stackMax      = 2.0,          -- cap for stacking re-triggered panic

        chatterMin   = 6,
        chatterRange = 8,     -- ambient chirps, calm delay after attach
        chatterInitialMin = 2,
        chatterDelayRange = 4,
        angerMin      = 0.4,
        angerRange = 0.5,    -- angry barks while panicked

        spinSpeedRad  = 3,
        spinMinimum   = math.pi / 6,
        spinRange     = math.pi / 4,
    }

    local kTwoPi = math.pi * 2
    local kWebOrbitRadius = 0.1 -- How far from the web we orbit the web

    local kWebScratchPerp1 = Vector(0, 0, 0)
    local kWebScratchPerp2 = Vector(0, 0, 0)

    local function BuildWebBasis(axis, outPerp1, outPerp2)

        -- project world-up onto the plane perpendicular to the strand,
        -- so stance angle 0 means "perched on top"
        local dx = -axis.x * axis.y
        local dy = 1 - axis.y * axis.y
        local dz = -axis.y * axis.z

        if dx*dx + dy*dy + dz*dz < 0.01 then -- nearly vertical strand
            dx, dy, dz = 1, 0, 0
        end

        local invLen = 1 / math.sqrt(dx*dx + dy*dy + dz*dz)
        outPerp1.x, outPerp1.y, outPerp1.z = dx * invLen, dy * invLen, dz * invLen

        outPerp2.x = axis.y * outPerp1.z - axis.z * outPerp1.y
        outPerp2.y = axis.z * outPerp1.x - axis.x * outPerp1.z
        outPerp2.z = axis.x * outPerp1.y - axis.y * outPerp1.x

    end

    local function BuildWebCoords(px, py, pz, axis, t, stanceAngle, radius, yaw, pitch)

        BuildWebBasis(axis, kWebScratchPerp1, kWebScratchPerp2)

        local cosA, sinA = math.cos(stanceAngle), math.sin(stanceAngle)

        local ux = kWebScratchPerp1.x * cosA + kWebScratchPerp2.x * sinA
        local uy = kWebScratchPerp1.y * cosA + kWebScratchPerp2.y * sinA
        local uz = kWebScratchPerp1.z * cosA + kWebScratchPerp2.z * sinA

        -- facing from yaw + pitch (full 3D movement direction)
        local cp = math.cos(pitch)
        local fx = -math.sin(yaw) * cp
        local fy = math.sin(pitch)
        local fz = math.cos(yaw) * cp

        -- re-project forward onto the plane perpendicular to up, so the frame
        -- stays orthonormal even mid-turn
        local dotUF = ux * fx + uy * fy + uz * fz
        fx, fy, fz = fx - ux * dotUF, fy - uy * dotUF, fz - uz * dotUF
        local flen = math.sqrt(fx*fx + fy*fy + fz*fz)
        if flen > kEpsilon then
            fx, fy, fz = fx / flen, fy / flen, fz / flen
        end

        local cx = uy * fz - uz * fx
        local cy = uz * fx - ux * fz
        local cz = ux * fy - uy * fx

        return Coords(Vector(cx, cy, cz), Vector(ux, uy, uz), Vector(fx, fy, fz),
                Vector(px + axis.x * t + ux * radius, py + axis.y * t + uy * radius, pz + axis.z * t + uz * radius))
    end

    local function DirectionYawPitch(dirX, dirY, dirZ)

        local horiz = math.sqrt(dirX * dirX + dirZ * dirZ)
        return math.atan2(-dirX, dirZ), math.atan2(dirY, horiz)

    end

    local function StepWebYaw(self, targetYaw, deltaTime)

        local diff = Math.Wrap(targetYaw - self.webYaw + math.pi, 0, kTwoPi) - math.pi
        local maxStep = kTurnSpeed * deltaTime

        if math.abs(diff) <= maxStep then
            self.webYaw = targetYaw % kTwoPi
        else
            self.webYaw = (self.webYaw + (diff < 0 and -maxStep or maxStep)) % kTwoPi
        end

    end

    local function StepWebPitch(self, targetPitch, deltaTime)

        local diff = targetPitch - self.webPitch
        local maxStep = kTurnSpeed * deltaTime

        if math.abs(diff) <= maxStep then
            self.webPitch = targetPitch
        else
            self.webPitch = self.webPitch + (diff < 0 and -maxStep or maxStep)
        end

    end

    local function EndSpin(self)
        self.webSpinActive = false
        self.webSpinT = nil
        self.wagging = false
    end

    -- Babblers panic for a short while when the web loses a charge (enemy ran into it).
    function Babbler:PanicFromWeb(duration)

        local now = Shared.GetTime()

        -- re-triggering stacks remaining time, capped to avoid infinite panic loops
        local remaining = 0
        if self.panicExpire ~= nil and now < self.panicExpire then
            remaining = math.min(self.panicExpire - now, kWebConfig.stackMax)
        end
        self.panicExpire = now + remaining + duration

        -- stop whatever we're doing and scramble immediately
        EndSpin(self)
        self.webWalkTimer = 0

        -- start the angry chittering almost immediately
        self.timeNextWebAnger = now + 0.1

    end

    local function GetWebIdleTime(self)

        local panicking = self.panicExpire ~= nil and Shared.GetTime() < self.panicExpire

        if panicking then
            return kWebConfig.panicMin + math.random() * kWebConfig.panicRange
        end

        return kWebConfig.idleMin + math.random() * kWebConfig.idleRange

    end

    -- Restarts the idle/free behaviour after a babbler leaves a web or a player.
    local function ResumeFreeBehavior(self)

        self.lastDetachTime = Shared.GetTime()
        self:UpdateJumpPhysicsBody()
        self:SetMoveType(kBabblerMoveType.None, nil, nil, true)

        self:AddTimedCallback(Babbler.BabblerOffMap, kBabblerOffMapInterval)
        self:AddTimedCallback(Babbler.MoveRandom, kUpdateMoveInterval + math.random() / 5)
        self:AddTimedCallback(Babbler.UpdateWag, 0.4)

    end

    function Babbler:GetWeb()
        return self.webId ~= nil and self.webId ~= Entity.invalidId and Shared.GetEntity(self.webId) or nil
    end

    local kEyeOffset = Vector(0, 0.2, 0)
    function Babbler:GetEyePos()
        return self:GetOrigin() + kEyeOffset
    end

    function Babbler:GetMoveVelocity(targetPos)

        local moveVelocity = targetPos - self:GetOrigin()
        local yDiff = moveVelocity.y
        local moveSpeedXZ = moveVelocity:GetLengthXZ()

        if moveSpeedXZ > kMaxJumpForce then
            moveVelocity:Scale(kMaxJumpForce / moveSpeedXZ)
        elseif moveSpeedXZ < kMinJumpForce then
            moveVelocity:Scale(kMinJumpForce / (moveSpeedXZ + 0.0001) )
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

    local function KillCallback(this)
        this:Kill()
        return -- remove callback
    end

    function Babbler:OnOwnerChanged(oldOwner, newOwner)

        self:NotifyOwnerDestroyed(oldOwner)

        if newOwner then
            self:NotifyOwnerCreated(newOwner)
        else -- Destroy Babblers without Owner
            -- Use callback to avoid server crashs due to calls to destroyed unit by mixins
            self:AddTimedCallback(KillCallback, 1)
        end

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

        if oldId == self.targetId then
            local target = newId and Shared.GetEntity(newId)

            if target and HasMixin(target, "Live") and target:GetIsAlive() then
                if self:GetIsClinged() then
                    self:Detach()

                    if target:isa("Embryo") or target:isa("AlienCommander") then
                        local pos = target:GetOrigin()

                        if target:isa("AlienCommander") then
                            local ents = GetEntitiesForTeam("Hive", self:GetTeamNumber())
                            Shared.SortEntitiesByDistance(self:GetOrigin(), ents)

                            if #ents > 0 then
                                pos = ents[1]:GetOrigin()
                            end
                        end

                        self:SetMoveType(kBabblerMoveType.Cling, nil, pos, true)
                        self.targetId = newId
                    end
                elseif self.moveType == kBabblerMoveType.Cling then
                    self:SetMoveType(kBabblerMoveType.Cling, nil, target:GetOrigin(), true)
                    self.targetId = newId
                else
                    self.targetId = Entity.invalidId
                end
            else
                if self:GetIsClinged() then
                    self:Detach()
                end

                self.targetId = Entity.invalidId
            end
        end

    end

    function Babbler:GetTurnSpeedOverride()
        return kTurnSpeed
    end

    function Babbler:SetSilenced(silenced)
        self.silenced = silenced
    end

    function Babbler:Jump(velocity)

        self:SetGroundMoveType(false)
        if self.physicsBody then
            self.physicsBody:SetCoords(self:GetCoords())
            self.physicsBody:AddImpulse(self:GetOrigin(), velocity)
        end
        self.timeLastJump = Shared.GetTime()

    end

    function Babbler:Move(targetPos, deltaTime)

        self:SetGroundMoveType(true)

        local prevOrig = self:GetOrigin()
        local prevY = prevOrig.y

        local done = self:MoveToTarget(PhysicsMask.AIMovement, targetPos, kBabblerRunSpeed, deltaTime)

        local newOrigin = self:GetOrigin()
        local desiredY = newOrigin.y + Babbler.kRadius
        local speed = prevOrig:GetDistanceTo(newOrigin) / deltaTime
        local now = Shared.GetTime()

        newOrigin.y = Slerp(prevY, desiredY, deltaTime * Clamp(speed / 2, 0, 3))

        self:SetOrigin(newOrigin)
        self.targetSelector:AttackerMoved()

        if self.cursor and self.cursor.index + 5 <= #self.cursor.points and self.timeNextMoveJump < now
        then

            local deviation = 0.15 + math.random() / 6
            local targetOrigin = self.cursor.points[self.cursor.index + 2]
            local targetVelocity = Vector(math.random() - 0.5 < 0 and deviation or -deviation,
                    math.random() / 1.2,
                    math.random() - 0.5 < 0 and deviation or -deviation)

            local moveVel = self:GetMoveVelocity(targetOrigin + targetVelocity)
            local jumpSpeed = moveVel:GetLength()

            if jumpSpeed > kBabblerJumpSpeed then
                moveVel:Scale(kBabblerJumpSpeed / jumpSpeed)
            end

            self:Jump(moveVel)
            self:TriggerUncloak()

            -- The constant added delay has to be higher than the self.timeLastJump delay in the function
            -- so we are sure that we are not jumping as soon as we reached so floor
            self.timeNextMoveJump = now + 0.60 + math.random() * 3.15
        end

        return done

    end

    function Babbler:GetBabblerBall()

        local orig = self:GetOrigin()
        for _, ball in ipairs(GetEntitiesForTeamWithinRange("BabblerPheromone", self:GetTeamNumber(), orig, 20)) do

            if (ball:GetOrigin() - orig):GetLength() > 4 and ball:GetOwnerId() == self:GetOwnerId() then
                return ball
            end

        end

    end

    local randomTargetPosition = Vector(0,0,0)
    function Babbler:FindSomethingInteresting()

        PROFILE("Babbler:FindSomethingInteresting")

        local origin = self:GetOrigin()
        local searchRange = 7
        local targetPos

        VectorCopy(origin, randomTargetPosition)
        randomTargetPosition.x = math.random() * 4 - 2
        randomTargetPosition.z = math.random() * 4 - 2
        if math.random() < 0.2 then
            targetPos = randomTargetPosition
        else

            local babblerBall = self:GetBabblerBall()

            if babblerBall then
                targetPos = babblerBall:GetOrigin()
            else

                local interestingTargets = GetEntitiesWithMixinForTeamWithinRange("Live", self:GetTeamNumber(), origin, searchRange)
                local numTargets = #interestingTargets
                if numTargets > 1 then
                    targetPos = interestingTargets[math.random (1, numTargets)]:GetOrigin()
                elseif numTargets == 1 then
                    targetPos = interestingTargets[1]:GetOrigin()
                else
                    targetPos = randomTargetPosition
                end

            end

        end

        return targetPos

    end

    function Babbler:UpdateWag()

        if self.moveType == kBabblerMoveType.Wag and self:GetIsOnGround() and not self.babblerOffMap then

            local owner = self:GetOwner()
            if not owner or (owner:GetOrigin() - self:GetOrigin()):GetLength() > 6 then
                self:SetMoveType(kBabblerMoveType.None)
            end

        end

        return not self.clinged and self:GetIsAlive() and not self:GetIsOnWeb()

    end

    function Babbler:JumpRandom()
        self:Jump(Vector( (math.random() * 3) - 1.5, 3 + math.random() * 2, (math.random() * 3) - 1.5 ))
    end

    local kOffMapOffset = Vector(0, 0.001, 0)
    function Babbler:GetIsBabblerOffMap()
        local orig = self:GetOrigin() + kOffMapOffset
        local ground = GetGroundAt(self, orig, PhysicsMask.AIMovement)
        local babblerOffMap = (ground == orig)

        return babblerOffMap, ground
    end

    function Babbler:BabblerOffMap()

        if self.clinged or self:GetIsOnWeb() then
            return self:GetIsAlive()
        end

        local babblerOffMap = self:GetIsBabblerOffMap()

        if self.babblerOffMap then
            if not babblerOffMap then
                self.babblerOffMap = nil
                self:UpdateJumpPhysicsBody()
                self:SetMoveType(kBabblerMoveType.None, nil, nil, true)
                self:Jump(Vector(0,0,0)) -- Force update physics and reset ground move
            end
            return self:GetIsAlive()
        end

        self.babblerOffMap = nil
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

        return not self.clinged and self:GetIsAlive()
    end

    function Babbler:MoveRandom()
        PROFILE("Babbler:MoveRandom")

        if self.moveType == kBabblerMoveType.None and self:GetIsOnGround() and not self.babblerOffMap then
            -- check for targets to attack
            local target = self.targetSelector:AcquireTarget() or self:GetTarget()
            local owner = self:GetOwner()
            local ownerId = self:GetOwnerId()
            local alive = owner and HasMixin(owner, "Live") and owner:GetIsAlive()
            local ownerOrigin = owner and (not owner:isa("Commander") and owner:GetOrigin() or owner.lastGroundOrigin)

            if target then
                -- All babblers get that attack order too (all the group focus on the same target)
                for _, babbler in ipairs(GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), self:GetOrigin(), 30)) do
                    if babbler:GetOwnerId() == ownerId and babbler:GetTarget() ~= target then
                        babbler:SetMoveType(kBabblerMoveType.Attack, target, target:GetOrigin())
                    end
                end
            elseif not self.babblerBombSpawned and owner and alive and HasMixin(owner, "BabblerCling") and self.lastDetachTime < (Shared.GetTime() - kBabblerSearchTime) then
                if owner:GetCanAttachBabbler() then
                    self:SetMoveType(kBabblerMoveType.Cling, owner, ownerOrigin)
                elseif ownerOrigin then
                    if (ownerOrigin - self:GetOrigin()):GetLength() <= 6 then
                        self:SetMoveType(kBabblerMoveType.Wag, owner, ownerOrigin)
                    else
                        self:SetMoveType(kBabblerMoveType.Move, nil, ownerOrigin)
                    end
                end
            else
                -- nothing to do, find something "interesting" (maybe glowing)
                local targetPos = self:FindSomethingInteresting()

                if targetPos then
                    self:SetMoveType(kBabblerMoveType.Move, nil, targetPos)
                end
            end

            -- jump randomly
            if math.random() < 0.6 then
                self:JumpRandom()
            end
        end

        return not self.clinged and self:GetIsAlive() and not self:GetIsOnWeb()
    end

    function Babbler:SetIgnoreOrders(time)
        self.timeOrdersAllowed = Shared.GetTime() + time
    end

    local function GetCanReachTarget(self, target)

        local obstacleNormal = Vector(0, 1, 0)

        local targetOrig = target:GetOrigin()
        local targetTraceOrigin = GetEngagementOrOrigin(target)
        local trace = Shared.TraceRay(self:GetOrigin() + kEyeOffset, targetTraceOrigin, CollisionRep.LOS, PhysicsMask.All, EntityFilterAll())

        local canReach = trace.fraction >= 0.9 or self:IsTargetReached(targetOrig, 1)
        if canReach then
            return true, nil
        else
            obstacleNormal = trace.normal
        end

        return false, obstacleNormal

    end

    -- try to jump into the enemy
    function Babbler:UpdateAttack(force)

        local now = Shared.GetTime()
        local target = self:GetTarget()
        local targetOrig = target and target:GetOrigin()
        local targetIsAlive = target and HasMixin(target, "Live") and target:GetIsAlive()

        --Special-case handler for PowerPoints because they have unique states (e.g. unbuilt but damagable)
        if target and target:isa("PowerPoint") then
            targetIsAlive = target:GetBuiltFraction() >= 0.009  --built frac comes back in microscopic levels
        end

        local targetVelocity = Vector(0,0,0)

        if target and target.GetVelocity then
            targetVelocity = target:GetVelocity()
            targetVelocity:Scale(1.15 + ((math.random() - 0.5) / 3))
        end

        local timeSinceLastAttack = self.kNextUpdateAttack and now - self.kNextUpdateAttack or 0

        -- Adjust the jump
        if target and self.kNextUpdateAttack and self.kStopImpulseDone < 3 and 0.2 < timeSinceLastAttack
        then
            local targetEngagementPoint = GetEngagementOrOrigin(target)

            self:SyncPhysicsCoords()

            self:SetVelocity((targetEngagementPoint - self:GetOrigin()):GetUnit() * 1.5)
            self.kStopImpulseDone = self.kStopImpulseDone + 1
        end

        if force or
                (
                        self.moveType == kBabblerMoveType.Attack and self:GetIsOnGround() and now > self.kNextUpdateAttack
                                and not self.babblerOffMap
                )
        then

            if not target or not targetIsAlive then

                self:SetMoveType(kBabblerMoveType.None)
                return self:GetIsAlive()

            end

            local moveVel
            local canReach = GetCanReachTarget(self, target)
            local babblerBall = not canReach and self:GetBabblerBall()

            if canReach then

                local destinationOrigin = target:GetOrigin()
                local destination = GetEngagementOrOrigin(target)
                if HasMixin(target, "Target") then
                    if destination.y > destinationOrigin.y then -- Aim a bit lower not to jump above the target
                        local yDiff = destination.y - destinationOrigin.y
                        destination.y = destination.y - (yDiff * (0.15 + (math.random() / 4)))
                    end
                end

                -- Only adjust if we are on the ground (otherwise the babbler most of time go at the other end of the room)
                if self:GetIsOnGround() then
                    moveVel = self:GetMoveVelocity(destination + targetVelocity)
                    if self.kStopImpulseDone >= 3 then
                        self.kStopImpulseDone = self.kStopImpulseDone + 1
                        if self.kStopImpulseDone >= 5 then
                            self.kStopImpulseDone = math.random(0, 1)
                        end
                    end
                else
                    moveVel = self:GetMoveVelocity(destination)
                end

                local jumpSpeed = (self:GetVelocity() + moveVel):GetLength()
                if jumpSpeed > kBabblerJumpSpeed then
                    moveVel:Scale(kBabblerJumpSpeed / jumpSpeed)
                end

                self:Jump(moveVel)
                self:TriggerUncloak()
                self.kNextUpdateAttack = now + kUpdateAttackInterval

            elseif babblerBall and babblerBall:GetId() ~= self.lastBabblerBallId then

                self.lastBabblerBallId = babblerBall:GetId()
                self:SetMoveType(kBabblerMoveType.Move, nil, babblerBall:GetOrigin(), false, 1)

            else

                self:SetMoveType(kBabblerMoveType.Move, target, target:GetOrigin())

            end

        end

        return self:GetIsAlive()

    end

    function Babbler:SetGroundMoveType(isGround)

        if isGround ~= self.doesGroundMove then

            self.doesGroundMove = isGround
            self:ResetPathing()

            if self.doesGroundMove then
                if self.physicsBody then
                    self.physicsBody:SetPhysicsType(CollisionObject.Kinematic)
                end
            else
                -- prevents us from getting teleported back when switching to ground move again
                self:ResetPathing()
                if self.physicsBody then
                    self.physicsBody:SetPhysicsType(CollisionObject.Dynamic)
                end
            end

        end

    end

    function Babbler:UpdateCling(deltaTime)
        if not self:Attach(deltaTime) then
            self:Detach()
            return false
        end

        return true
    end

    function Babbler:Attach(deltaTime)
        local target = self:GetTarget()
        if not target then return false end

        if not target:GetIsAlive() then return false end

        if HasMixin(target, "BabblerCling") or target:isa("Embryo") or target:isa("AlienCommander") then

            local attachPointOrigin
            if HasMixin(target, "BabblerCling") then
                attachPointOrigin = target:GetFreeBabblerAttachPointOrigin()
            else
                attachPointOrigin = self.targetPosition
            end

            if attachPointOrigin then
                local moveDir = GetNormalizedVector(attachPointOrigin - self:GetOrigin())

                local distance = (self:GetOrigin() - attachPointOrigin):GetLength()
                local travelDistance = deltaTime * 15

                if distance < travelDistance then

                    if HasMixin(target, "BabblerCling") then

                        if target:AttachBabbler(self) then
                            self.clinged = true

                            self:DestroyHitbox()
                            travelDistance = distance
                        else -- Just for safety
                            return false
                        end
                    else
                        if target:isa("Embryo") and not target:GetIsAlive() then
                            self.babblerOffMap = true -- Force unstuck (since we are inside the egg/ground)
                            self.babblerOffMapRecoveryOrig = self:GetOrigin() + Vector(0, 0.7, 0)
                            return false
                        end
                        if distance < 0.1 then
                            return true
                        end
                    end

                end

                -- disable physic simulation
                self:SetGroundMoveType(true)
                self:SetOrigin(self:GetOrigin() + moveDir * travelDistance)

                return true

            end

        end

        return false
    end

    local function RandomNegate(value)
        return math.random() > 0.5 and -value or value
    end

    -- Shared by Detach and AttachToWeb: tell a BabblerCling parent to let go
    -- before this babbler stops considering itself clinged.
    function Babbler:ReleaseFromParentCling(parent)
        if parent and HasMixin(parent, "BabblerCling") then
            parent:DetachBabbler(self)
        end
        self.clinged = false
    end

    function Babbler:Detach(force)
        if not self.clinged then
            return
        end

        local parent = self:GetParent()

        if parent and not force then
            -- Do not detach from the alien if he is out of the map (inside a tunnel)
            local maxDistance = 1000
            local origin = parent:GetOrigin()
            if origin:GetLengthSquared() > maxDistance * maxDistance then
                return
            end
        end

        self:ReleaseFromParentCling(parent)

        self:CreateHitBox()

        local detachOffset = Vector(RandomNegate(math.random(15, 70) / 100), 0.25, RandomNegate(math.random(15, 70) / 100))
        -- Check so babbler scatter is not thru walls etc.
        if GetWallBetween(self:GetOrigin(), self:GetOrigin() + detachOffset, parent) then
            detachOffset = Vector(0, 0.25, 0)
        end
        self:SetOrigin(self:GetOrigin() + detachOffset)
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

        local margin = math.min(kBabblerWebEndMargin, length * 0.2)

        self.webStanceAngle = self.webStanceAngle or 0
        self.webWalkTimer = (self.webWalkTimer or 1) - deltaTime

        if self.webTargetT == nil and not self.webSpinActive and self.webWalkTimer <= 0 then

            local panicking = self.panicExpire ~= nil and Shared.GetTime() < self.panicExpire

            if panicking or math.random() < kWebConfig.strollChance then

                local myT = (self:GetOrigin() - origin):DotProduct(axis)

                -- Long strides only: retry the random pick a few times, and if it
                -- keeps landing too close, commit to the far half of the strand
                -- so the run animation actually gets going.
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
                    -- push to the farther end of the usable span
                    candidateT = (myT < (margin + length) * 0.5) and (length - margin) or margin
                end

                self.webTargetT = Clamp(candidateT, margin, length - margin)
                self.webWalkDir = (self.webTargetT >= myT) and 1 or -1
                self.webSpinActive = false
                self.webSpinT = nil
                self.webWalking = true
                self.wagging = false
                self.webWalkTimer = kWebConfig.strollTimeout

            else
                self.webSpinActive = true
                self.webTargetT = nil
                self.wagging = true
                self.webWalkTimer = GetWebIdleTime(self)
            end

        end

        if self.webTargetT ~= nil then

            local panicking = self.panicExpire ~= nil and Shared.GetTime() < self.panicExpire
            local speed = (self.webFastTravel and kWebTravelSpeed or Babbler.kWebWalkSpeed) * (panicking and kWebConfig.panicSpeedMult or 1)

            local myT = (self:GetOrigin() - origin):DotProduct(axis)
            local destinationT = Clamp(self.webTargetT, margin, length - margin)

            -- facing toward the walk direction (identical for both modes)
            local moveYaw, movePitch = DirectionYawPitch(
                    axis.x * self.webWalkDir, axis.y * self.webWalkDir, axis.z * self.webWalkDir)
            StepWebYaw(self, moveYaw, deltaTime)
            StepWebPitch(self, movePitch, deltaTime)

            local arrived = math.abs(self.webTargetT - myT) <= deltaTime * speed

            if arrived or self.webWalkTimer <= 0 then

                -- Reached the target (or gave up after walking too long) — never
                -- snap over the remaining distance, just stop where we stand.
                if arrived then
                    self:SetCoords(BuildWebCoords(origin.x, origin.y, origin.z, axis, destinationT,
                            self.webStanceAngle, 0, self.webYaw, self.webPitch))
                end

                self.webTargetT = nil
                self.webFastTravel = false
                self.webWalking = false
                self.webWalkTimer = GetWebIdleTime(self)

            else

                local nextT = Clamp(myT + self.webWalkDir * deltaTime * speed, margin, length - margin)
                self:SetCoords(BuildWebCoords(origin.x, origin.y, origin.z, axis, nextT,
                        self.webStanceAngle, 0, self.webYaw, self.webPitch))

            end

            return
        end

        if self.webSpinActive then

            if self.webSpinT == nil then
                self.webSpinT = Clamp((self:GetOrigin() - origin):DotProduct(axis), margin, length - margin)
                self.webSpinDir = (math.random() < 0.5) and -1 or 1
                self.webSpinRemaining = kWebConfig.spinMinimum + math.random() * kWebConfig.spinRange
            end

            local spinStep = math.min(deltaTime * kWebConfig.spinSpeedRad, self.webSpinRemaining)
            self.webSpinRemaining = self.webSpinRemaining - spinStep
            self.webYaw = (self.webYaw + self.webSpinDir * spinStep) % kTwoPi
            self.webStanceAngle = (self.webStanceAngle + self.webSpinDir * spinStep) % kTwoPi

            self:SetCoords(BuildWebCoords(origin.x, origin.y, origin.z, axis, self.webSpinT,
                    self.webStanceAngle, kWebOrbitRadius, self.webYaw, self.webPitch))

            if self.webSpinRemaining <= kEpsilon then
                EndSpin(self)
                self.webWalkTimer = GetWebIdleTime(self)
            end

            return
        end

        -- Make babbler do some happy noise once in a while
        if self.timeNextWebChatter == nil or Shared.GetTime() >= self.timeNextWebChatter then
            self:TriggerEffects("babbler_jump") 
            self.timeNextWebChatter = Shared.GetTime() + kWebConfig.chatterMin + math.random() * kWebConfig.chatterRange
        end

    end

    function Babbler:AttachToWeb(web, position)

        if not web or not self:GetIsAlive() then return false end

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

        local margin = math.min(kBabblerWebEndMargin, length * 0.2)

        -- Walk to wherever the gorge placed us, projected onto the strand
        self.webTargetT = Clamp((position - origin):DotProduct(axis), margin, length - margin)
        local myT = (self:GetOrigin() - origin):DotProduct(axis)
        self.webWalkDir = (self.webTargetT >= myT) and 1 or -1
        self.webFastTravel = true
        self.webWalking = true
        self.webSpinActive = false
        self.webSpinT = nil
        self.webStanceAngle = (math.random() - 0.5) * math.pi * 0.35
        self.webWalkTimer = kWebConfig.strollTimeout

        local moveYaw, movePitch = DirectionYawPitch(axis.x * self.webWalkDir,
                axis.y * self.webWalkDir, axis.z * self.webWalkDir)
        self.webYaw = moveYaw
        self.webPitch = movePitch

        self.timeNextWebChatter = Shared.GetTime() + kWebConfig.chatterInitialMin + math.random() * kWebConfig.chatterDelayRange

        -- disable physic simulation
        self:SetGroundMoveType(true)
        self:UpdateJumpPhysicsBody()
        self:SetMoveType(kBabblerMoveType.None, nil, nil, true)

        web:AddWebbedBabbler(self)

        return true

    end

    -- Releases the babbler from a web: picked back up (OnUse), the web was
    -- triggered by an enemy, or the web died/was destroyed. It resumes exactly
    -- like a freshly-detached free babbler.
    function Babbler:DetachFromWeb()

        if not self.onWeb then return end

        local web = self:GetWeb()
        if web then
            web:RemoveWebbedBabbler(self)
        end

        self.onWeb = false
        self.webId = Entity.invalidId

        self.wagging = false
        self.webSpinT = nil
        self.webWalking = false
        self.webSpinActive = false
        self.webFastTravel = false
        self.timeNextWebChatter = nil

        self.panicExpire = nil
        self.timeNextWebAnger = nil

        ResumeFreeBehavior(self)

    end

    function Babbler:UpdateTargetPosition()

        if self.moveType ~= kBabblerMoveType.Cling then
            return
        end

        local target = self:GetTarget()

        if target and not target:isa("AlienSpectator") then

            if target.GetFreeBabblerAttachPointOrigin then

                self.targetPosition = target:GetFreeBabblerAttachPointOrigin()
                -- If there are no free attach points, stop trying to cling.
                if not self.targetPosition then
                    self:SetMoveType(kBabblerMoveType.None)
                end

            end

        end

    end

    local function NoObstacleInWay(self, targetPosition)

        local trace = Shared.TraceRay(self:GetOrigin() + kEyeOffset, targetPosition, CollisionRep.LOS, PhysicsMask.All, EntityFilterAll())
        return trace.fraction == 1

    end

    function Babbler:UpdateMove(deltaTime)

        PROFILE("Babbler:UpdateMove")

        self:UpdateTargetPosition()

        local success

        if self.moveType == kBabblerMoveType.Move or self.moveType == kBabblerMoveType.Cling then

            if self.moveType == kBabblerMoveType.Cling and self.targetPosition and (self:GetOrigin() - self.targetPosition):GetLength() < 7 then

                success = self:UpdateCling(deltaTime)

            elseif self:GetIsOnGround() then

                if self.timeLastJump + 0.5 < Shared.GetTime() then

                    local target = self:GetTarget()
                    local targetPosition = self.targetPosition or (target and target:GetOrigin())
                    local distToTarget = targetPosition and targetPosition:GetDistanceTo(self:GetOrigin())
                    local isFriend = target and target.GetTeamNumber and target:GetTeamNumber() == self:GetTeamNumber()

                    if distToTarget < kMinJumpDistance then
                        self.targetReached = true
                    end

                    local followTarget = target and (isFriend or not self.targetReached or distToTarget <= kTargetMaxFollowRange)

                    if targetPosition and (not target or followTarget) then

                        local distance = math.max(0, ((self:GetOrigin() - targetPosition):GetLength() - kMinJumpDistance))
                        local shouldJump = math.random()
                        local jumpProbablity = 0

                        if 0 < distance and distance < kMinJumpDistance then
                            jumpProbablity = distance / 5
                        end

                        local done = false
                        if self.jumpAttempts < 3 and jumpProbablity >= shouldJump and NoObstacleInWay(self, targetPosition) then
                            done = self:Jump(self:GetMoveVelocity(targetPosition))
                            self.jumpAttempts = self.jumpAttempts + 1
                        else
                            done = self:Move(targetPosition, deltaTime)
                        end

                        if done or (self:GetOrigin() - targetPosition):GetLengthXZ() < 0.5 then
                            self:SyncPhysicsCoords()
                            self:SetMoveType(target and kBabblerMoveType.Attack or kBabblerMoveType.None,
                                    target, targetPosition)
                            if self:GetTarget() then
                                -- Call it here once to prevent babblers to stare at the marine
                                -- for a few seconds before attacking after reaching it
                                self:UpdateAttack(true)
                            end
                        end

                        success = true

                    end

                    if not success then
                        self:SetMoveType(kBabblerMoveType.None)
                    end
                end


            end

        end

        self.jumping = not self:GetIsOnGround()

    end

    function Babbler:GetDestroyOnKill()
        return true
    end

    function Babbler:OnKill()

        self:TriggerEffects("death", {effecthostcoords = Coords.GetTranslation(self:GetOrigin()) })

        if self.onWeb then
            local web = self:GetWeb()
            if web then
                web:RemoveWebbedBabbler(self)
            end
        end

    end

    function Babbler:UpdateJumpPhysics(deltaTime)
    
        local velocity = self:GetVelocity()
        
        -- simulation is updated only during jumping
        if self.physicsBody and not self.doesGroundMove then

            -- If the Babbler has moved outside of the world, destroy it
            local coords = self.physicsBody:GetCoords()
            local origin = coords.origin
            
            local maxDistance = 1000
            
            if origin:GetLengthSquared() > maxDistance * maxDistance then
                Print( "%s moved outside of the playable area, destroying", self:GetClassName() )
                DestroyEntity(self)
            else
                -- Update the position/orientation of the entity based on the current
                -- position/orientation of the physics object.
                self:SetCoords( coords )
            end
            
            if self.lastVelocity ~= nil then
            
                local delta = velocity - self.lastVelocity
                if delta:GetLengthSquaredXZ() > 0.0001 then
              
                    local endPoint = self.lastOrigin + self.lastVelocity * (deltaTime + Babbler.kRadius * 3)
                    
                    local trace = Shared.TraceCapsule(self.lastOrigin, endPoint, Babbler.kProcessHitRadius, 0, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOneAndIsa(self, "Babbler"))
                    self:ProcessHit(trace.entity, trace.surface)

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

        self.desiredVelocity = velocity
        if self.physicsBody then
            self.physicsBody:SetLinearVelocity(velocity)
        end
        self.lastVelocity = velocity

    end

    local function BabblerSetLinearDampingCallback(self)
        local lifeSpan = Shared.GetTime() - self:GetCreationTime()
        if self.physicsBody and not self.clinged and (self:GetIsOnGround() or lifeSpan >= kFinalDampingAfterDelay)
        then
            self.physicsBody:SetLinearDamping(Babbler.kLinearDamping)
            self:Jump(Vector(0,0,0)) -- Force update physics and reset ground move
            return false
        end
        return self:GetIsAlive()
    end

    -- creates physic object used for jump simulation
    function Babbler:UpdateJumpPhysicsBody()

        if not self.physicsBody and not self.clinged and not self.onWeb then

            self.physicsBody = Shared.CreatePhysicsSphereBody(true, Babbler.kRadius, Babbler.kMass, self:GetCoords() )
            self.physicsBody:SetGravityEnabled(true)
            self.physicsBody:SetGroup(PhysicsGroup.ProjectileGroup)
            self.physicsBody:SetGroupFilterMask(PhysicsMask.BabblerMovement)

            self.physicsBody:SetCCDEnabled(false)
            self.physicsBody:SetPhysicsType( CollisionObject.Dynamic )
            self.physicsBody:SetLinearDamping(Babbler.kLinearDampingAtSpawn)
            self.physicsBody:SetRestitution(Babbler.kRestitution)

            self:AddTimedCallback(BabblerSetLinearDampingCallback, kFinalDampingAfterDelay)

        elseif (self.clinged or self.onWeb) and self.physicsBody then
        
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

        -- Do not apply the attack sound here to prevent gorges to instantly know if there
        -- are marines around the corner by simply throwing in a the bait. The sound is instead
        -- played before the babbler is attacking.
        if effectName and (self.moveType ~= kBabblerMoveType.Attack)
        then
            self:TriggerEffects(effectName)
        end
        
    end
    
    local function GetIgnoreOrders(self)
        return self.clinged or (self.timeOrdersAllowed and self.timeOrdersAllowed > Shared.GetTime())
    end

    function Babbler:SetMoveType(moveType, target, position, force, ignoreOrderDelay)

        local targetId = Entity.invalidId

        if target then
            targetId = target:GetId()
            position = position or (target and target:GetOrigin())
        end
        
        local diffOfPosition = (self.targetPosition and position) and position:GetDistanceTo(self.targetPosition) or 0
        if force or ( (moveType ~= self.moveType or targetId ~= self.targetId or diffOfPosition > 0) and not GetIgnoreOrders(self) ) then

            self.moveType = moveType
            self.targetId = targetId
            self.targetPosition = position
            if not (moveType == kBabblerMoveType.Move or moveType == kBabblerMoveType.Attack) then
                self.targetReached = false -- preserve that state when moving from move <-> attack
            end
            
            if moveType == kBabblerMoveType.None or moveType == kBabblerMoveType.Move then
                -- makes sure that babbler will fall down when move ends
                self:Jump(Vector(0,0,0)) -- Force update physics and reset ground move
            end    

            self.jumpAttempts = 0
            OnMoveTypeChanged(self)
            
            if force or ignoreOrderDelay then
                self:SetIgnoreOrders(ignoreOrderDelay or 0.5)
            end

        end

    end
        
    function Babbler:ProcessHit(entityHit, surface)

        if entityHit then

            if HasMixin(entityHit, "Live") and HasMixin(entityHit, "Team") and entityHit:GetTeamNumber() ~= self:GetTeamNumber() then
            
                if self.timeLastAttack + kAttackRate < Shared.GetTime() then
                    
                    -- Adds a bit of randomness for the first attack
                    self.timeLastAttack = Shared.GetTime() + math.random() * kAttackRate
                    
                    local targetOrigin = GetEngagementOrOrigin(entityHit)

                    self:DoDamage( kBabblerDamage, entityHit, self:GetOrigin(), nil, surface )
                    self:TriggerUncloak()

                    if entityHit:isa("Player") then
                        self:Jump((entityHit:GetOrigin() - self:GetOrigin()):GetUnit() * 2)
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
                    local material = GetPrecachedCosmeticMaterial( self:GetClassName(), self.variant )
                    if material then
                        model:SetOverrideMaterial( kBabblerWorldMaterialIndex, material )
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

    function Babbler:OnAdjustModelCoords(modelCoords)

        if not self:GetIsClinged() and self.moveDirection and not self:GetIsOnWeb() then
            modelCoords = Coords.GetLookIn(modelCoords.origin, self.moveDirection)
            modelCoords.origin.y = modelCoords.origin.y - Babbler.kRadius
        end

        return modelCoords

    end

    function Babbler:UpdateMoveDirection(deltaTime)

        if self.clientClinged ~= self.clinged then
        
            --self:TriggerEffects("babbler_cling")
            self.clientClinged = self.clinged
        
        end

        if not self.clinged then -- No sound when attached
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
        end

        
        self.clientGroundMove = self.doesGroundMove
        
        if self.lastOrigin then
        
            local orig = self:GetOrigin()
            if not self.moveDirection then
                self.moveDirection = Vector(0, 0, 0)
            end
            
            local moveDirection = nil
            local target = self:GetTarget()
            if target then
                local targetPosition = target:GetOrigin()
                moveDirection = GetNormalizedVectorXZ(targetPosition - orig)
            else
                moveDirection = GetNormalizedVectorXZ(orig - self.lastOrigin)
            end
            
            -- smooth out turning of babblers
            self.moveDirection = self.moveDirection + moveDirection * deltaTime * (moveDirection - self.moveDirection):GetLength() * 5
            self.moveDirection:Normalize()
            
            if deltaTime > 0 then
                self.clientVelocity = (orig - self.lastOrigin) / deltaTime
            end
            
        end
        
        self.clientJumping = self.jumping
        self.clientAttacking = self.attacking
        self.clientTimeLastAttack = self.timeLastAttack 

        
    end
    
    function Babbler:OnUpdateAnimationInput(modelMixin)
    
        PROFILE("Babbler:OnUpdateAnimationInput")
    
        local move = "idle"
        if self.clinged then
            move = "idle"
        elseif self.onWeb then
            if self.webWalking then
                move = "run"
            elseif self.wagging then
                move = "wag"
            end
        elseif self.jumping then
            move = "jump"
        elseif self.doesGroundMove then
            move = "run"
        elseif self.wagging then
            move = "wag"
        end
        
        modelMixin:SetAnimationInput("move", move)
        modelMixin:SetAnimationInput("attacking", self.attacking)

    end
    
    function Babbler:OnUpdatePoseParameters()

        PROFILE("Babbler:OnUpdatePoseParameters")

        local moveYaw = 0
        local targetSpeed = 0

        if self.clientVelocity then

            local coords = self:GetCoords()
            local moveDirection = ConditionalValue(self.clientVelocity:GetLengthXZ() > 0, GetNormalizedVectorXZ(self.clientVelocity), self.moveDirection)
            local x = Math_DotProduct(coords.xAxis, moveDirection)
            local z = Math_DotProduct(coords.zAxis, moveDirection)

            moveYaw = Math_Wrap(Math_Degrees( math_atan2(z,x) ), -180, 180) + 180

            local maxSpeed = self.onWeb and Babbler.kWebWalkSpeed or kBabblerRunSpeed
            targetSpeed = Clamp(self.clientVelocity:GetLength() / maxSpeed, 0, 1)

        end

        -- smooth out quantization jitter in the networked origin before it
        -- reaches the animation graph
        local deltaTime = self.lastUpdatePosParam and Shared.GetTime() - self.lastUpdatePosParam or 0
        self.smoothedMoveSpeed = Slerp(self.smoothedMoveSpeed or 0, targetSpeed, deltaTime * 8)
        self:SetPoseParams({
            {"move_speed", self.smoothedMoveSpeed},
            {"move_yaw", moveYaw}
        })
        self.lastUpdatePosParam = Shared.GetTime()

    end
    
    -- hide babblers which are clinged on the local player to not obscure their view
    function Babbler:OnGetIsVisible(visibleTable)
        
        local parent = self:GetParent()
        if parent and (parent == Client.GetLocalPlayer() and not parent:GetIsThirdPerson() ) then
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

-- %%% New CBM Functions %%% --
function Babbler:OnDamageDone(doer, target)
    self.timeLastDamageDealt = Shared.GetTime()
end

function Babbler:GetCanGiveDamageOverride()
    -- Babbler can hurt you
    return true
end

function Babbler:SetDamageType(DamageType)
    self.AttackDamageType = DamageType
end

function Babbler:GetDamageType()
    return self.AttackDamageType
end

Shared.LinkClassToMap("Babbler", Babbler.kMapName, networkVars, true)
