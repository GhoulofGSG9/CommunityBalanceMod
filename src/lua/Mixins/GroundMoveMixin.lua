-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GroundMoveMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
--    UpdateOnGround checks only when we leave ground state.
--    ONWorldCollision considers actual impact with a surface and handles entering ground state.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Mixins/BaseMoveMixin.lua")

GroundMoveMixin = CreateMixin(GroundMoveMixin)
GroundMoveMixin.type = "GroundMove"

local kDownSlopeFactor = math.tan(math.rad(60))

local kStepHeight = 0.5
local kAirGroundTransistionTime = 0.2

local kFallAccel = 0.34
local kMaxAirAccel = 0.54

local kStopFriction = 6
local kStopSpeed = 4

local kMaxAirVeer = 1.3

local kTracesAmount = 7
local kPvPTracesAmount = 10

-- min ~13 FPS assumed, otherwise players will move slower
local kMaxDeltaTime = 0.07

GroundMoveMixin.networkVars =
{
    onGround = "compensated boolean",
    onGroundSurface = "enum kSurfaces", 
    isOnEntity = "private compensated boolean",
    timeGroundAllowed = "private compensated time",
    timeGroundTouched = "private compensated time"
}

GroundMoveMixin.expectedMixins =
{
    BaseMove = "Give basic method to handle player or entity movement"
}

GroundMoveMixin.expectedCallbacks =
{
    GetPerformsVerticalMove = "Return true if vertical movement should get performed."
}

GroundMoveMixin.optionalCallbacks =
{
    PreUpdateMove = "Allows children to update state before the update happens.",
    PostUpdateMove = "Allows children to update state after the update happens.",
    ModifyVelocity = "Should modify the passed in velocity based on the input and whatever other conditions are needed.",
    OverrideGetIsOnGround = "Manipulate on ground.",
    GetClampedMaxSpeed = "Absolute maximum which never can be exceeded."
}

function GroundMoveMixin:__initmixin()
    
    PROFILE("GroundMoveMixin:__initmixin")
    
    self.onGround = true
    -- onGroundSurface is only valid when onGround is true
    self.onGroundSurface = kSurfaces.metal
    self.isOnEntity = false
    self.onGroundClient = true
    self.timeGroundAllowed = 0
    self.timeGroundTouched = 0
    self.lastGroundCheck = {
        distance = 0, -- How far from the ground we checked we were
        origin = false, -- Position of the test
        normal = false, -- Normal from position to ground
        surfaceMaterial = "" -- material hit
    }
    
end

local function _SetGroundCheckCache(self, distance, hitEntities, normal, surfaceMaterial)

    -- Only cache a successfull ground check if no entity hit (because they can move/die/etc)
    -- The ground is our friend, it's always there for us
    if (hitEntities == nil) then
        self.lastGroundCheck.distance = distance
        self.lastGroundCheck.origin = Vector(self:GetOrigin())
        self.lastGroundCheck.normal = normal
        self.lastGroundCheck.surfaceMaterial = surfaceMaterial
    else
        --if Server then Log("Set error: %s/%s/%s", hitEntities, distance, origDistance) end
        self.lastGroundCheck.distance = -1
        self.lastGroundCheck.origin = Vector(-1,-1,-1)
    end
end

local function _GetGroundCheckCache(self)
    local completedMove = true
    local hitEntities = nil
    return completedMove, hitEntities, self.lastGroundCheck.normal, self.lastGroundCheck.surfaceMaterial, self.lastGroundCheck.distance
end
local function _GetIsStillOnSameGroundPosition(self, distance)
    -- Any test with a higher or equal threshold distance and same position is on ground too
    local distValid = self.lastGroundCheck.distance <= distance
    local sameOrigin = self:GetOrigin() == self.lastGroundCheck.origin
    local isCacheHit = (distValid and sameOrigin)
    --[[ if not isCacheHit then
        Log("Miss: distValid: %s(%s,%s), sameOrigin: %s(%s,%s)",
            distValid, self.lastGroundCheck.distance, distance,
            sameOrigin, self:GetOrigin(), self.lastGroundCheck.origin
            )
    end --]]
    return isCacheHit
end

local function CosFalloff(distanceFraction)
    local piFraction = Clamp(distanceFraction, 0, 1) * math.pi / 2
    return math.cos(piFraction + math.pi) + 1 
end

local function GetOnGroundFraction(self)

    PROFILE("GroundMoveMixin:GetOnGroundFraction")

    local transistionTime = not self.GetGroundTransistionTime and kAirGroundTransistionTime or self:GetGroundTransistionTime()
    local groundFraction = self.onGround and Clamp( (Shared.GetTime() - self.timeGroundTouched) / transistionTime, 0, 1) or 0
    groundFraction = CosFalloff(groundFraction)
    if self.ModifyGroundFraction then
        groundFraction = self:ModifyGroundFraction(groundFraction)
    end
    return groundFraction

end

function GroundMoveMixin:GetGroundFraction()
    return GetOnGroundFraction(self)
end

local function DoesStopMove(self, move, velocity)

    PROFILE("GroundMoveMixin:DoesStopMove")

    local wishDir = GetNormalizedVectorXZ(self:GetViewCoords().zAxis) * move.z    
    return wishDir:DotProduct(GetNormalizedVectorXZ(velocity)) < -0.8

end


--[[
local _slowDown = 0
local _toggle = false
local function OnConsoleSetBounce5() _slowDown = 0.05 end
local function OnConsoleSetBounce10() _slowDown = 0.10 end
local function OnConsoleSetBounce15() _slowDown = 0.15 end
local function OnConsoleSetBounce20() _slowDown = 0.20 end
local function OnConsoleSetBounce25() _slowDown = 0.25 end
local function OnConsoleSetBounce50() _slowDown = 0.50 end
local function OnConsoleSetBounce75() _slowDown = 0.75 end
local function OnConsoleSetBounce100() _slowDown = 1 end
local function OnConsoleToggle()
    _toggle = not _toggle
    Log("%s", _toggle)
end

Event.Hook("Console_s5", OnConsoleSetBounce5)
Event.Hook("Console_s10", OnConsoleSetBounce10)
Event.Hook("Console_s15", OnConsoleSetBounce15)
Event.Hook("Console_s20", OnConsoleSetBounce20)
Event.Hook("Console_s25", OnConsoleSetBounce25)
Event.Hook("Console_s50", OnConsoleSetBounce50)
Event.Hook("Console_s75", OnConsoleSetBounce75)
Event.Hook("Console_s100", OnConsoleSetBounce100)
Event.Hook("Console_t", OnConsoleToggle)
--]]

local function _PerformMovement(self, offset, maxTraces, velocity, isMove, slowDownFraction, deflectMove, slowDownFilterFunc, deltaTime)

    local hitPlayer = nil

    if slowDownFraction and _toggle then
        slowDownFraction = _slowDown
    end
    local completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial = self:PerformMovement(offset, maxTraces, velocity, isMove, slowDownFraction, deflectMove, slowDownFilterFunc, deltaTime)

    for i = 1, (hitEntities and #hitEntities or 0) do
        if hitEntities[i]:isa("Player") then
            hitPlayer = hitEntities[i]
            --if Server then Log("%s colliding with %s", self, hitPlayer) end
            break
            
        end
    end

    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial, hitPlayer

end


local function GetIsCloseToGround(self, distance)

    PROFILE("GroundMoveMixin:GetIsCloseToGround")

    local onGround = false
    local normal = nil
    local completedMove, hitEntities, surfaceMaterial

    if self.controller == nil then
      
        onGround = true
    
    elseif self.timeGroundAllowed <= Shared.GetTime() then
    
        -- Try to move the controller downward a small amount to determine if
        -- we're on the ground.
        
        -- need to do multiple slides here to not get traped in V shaped spaces

        -- Reuse the ground check done last moverate (we performed a down move to the max)
        -- - Same position as before ? then no reasons we would not still be on ground
        -- Regaring hitEntities, if we are as close to ground as possible
        -- then no entities that could disrupt our movement could sneak below us.
        if _GetIsStillOnSameGroundPosition(self, distance) then
            _, _, normal, surfaceMaterial = _GetGroundCheckCache(self)
            onGround = true
        else
            local offset = Vector(0, -distance, 0)
            completedMove, hitEntities, normal, surfaceMaterial = _PerformMovement(self, offset, kTracesAmount, nil, false)
            if normal and normal.y >= 0.5 then
                _SetGroundCheckCache(self, distance, hitEntities, normal, surfaceMaterial)
                onGround = true
            end
        end
    
    end
    
    -- Nil surface material implies it wasn't set, so we default to "metal".
    -- It doesn't matter if we're on the ground or not -- checking the surface material should NOT
    -- double as checking if we're on the ground or not -- that's what "onGround" is for.
    surfaceMaterial = surfaceMaterial or "metal"
    normal = normal or Vector()
    
    return onGround, normal, hitEntities, surfaceMaterial
    
end

local function GetWishDir_moveAdjust(self, viewCoords, move, simpleAcceleration, velocity, maxSpeed)
    PROFILE("GroundMoveMixin:GetWishDir_moveAdjust")

    if simpleAcceleration == nil then
        simpleAcceleration = true
    end

    -- don't punish people for using the forward key, help them
    if not simpleAcceleration and not self.onGround and move.z ~= 0 and not DoesStopMove(self, move, velocity) then
        
        if move.x ~= 0 then
            move.z = 0
        elseif velocity then
            
            local translateDirection = (-viewCoords.xAxis):DotProduct(GetNormalizedVectorXZ(velocity))
            local absTranslateDirection = math.abs(translateDirection)
            local xMove = translateDirection == 0 and 1 or translateDirection / absTranslateDirection
            local speedFraction = velocity:GetLengthXZ() / maxSpeed
            move.z = 0
            
            -- normalize translate direction
            -- translate z move to x
            if absTranslateDirection * speedFraction > 0.2 then            
                move.x = xMove
            end

        end
    end
    return GetNormalizedVector(move)
end

local function GetWishDir(self, move, simpleAcceleration, velocity, maxSpeed)

    PROFILE("GroundMoveMixin:GetWishDir")

    local wishDir = nil
    local viewCoords = self:GetViewCoords()
    local normedMove = GetWishDir_moveAdjust(self, viewCoords, move, simpleAcceleration, velocity, maxSpeed)

    if self:GetPerformsVerticalMove() then
        wishDir = viewCoords:TransformVector(normedMove)
    else
    
        local local2World = viewCoords
        local2World.xAxis.y = 0
        local2World.xAxis:Normalize()
        local2World.zAxis.y = 0
        local2World.zAxis:Normalize()
        local2World.yAxis = local2World.zAxis:CrossProduct(local2World.xAxis)
        local2World.zAxis = local2World.xAxis:CrossProduct(local2World.yAxis)
        wishDir = local2World:TransformVector(normedMove)
        wishDir.y = 0
        wishDir:Normalize()
        
    end

    
    return wishDir

end

function GroundMoveMixin:DisableGroundMove(time)

    self.timeGroundAllowed = Shared.GetTime() + time
    self.onGround = false  
    
end

function GroundMoveMixin:EnableGroundMove()
    self.timeGroundAllowed = 0
end

function GroundMoveMixin:ModifyMaxSpeed(maxSpeedTable, input)

    PROFILE("GroundMoveMixin:ModifyMaxSpeed")

    local backwardsSpeedScalar = 1

    if input and input.move.z < 0 then
    
        if input.move.x ~= 0 then
            backwardsSpeedScalar = self:GetMaxBackwardSpeedScalar() * 1.4
        else
            backwardsSpeedScalar = self:GetMaxBackwardSpeedScalar()
        end 
        
        backwardsSpeedScalar = Clamp(backwardsSpeedScalar, 0, 1)
    
    end

    maxSpeedTable.maxSpeed = maxSpeedTable.maxSpeed * backwardsSpeedScalar

end

local function AccelerateSimpleXZ(self, input, velocity, maxSpeedXZ, acceleration, deltaTime)

    PROFILE("GroundMoveMixin:AccelerateSimpleXZ")

    if acceleration > 0 then -- For instance, lerk have 0 fall accel
        maxSpeedXZ = math.max(velocity:GetLengthXZ(), maxSpeedXZ)
        -- do XZ acceleration
        
        local wishDir = self:GetViewCoords():TransformVector(input.move)
        wishDir.y = 0
        wishDir:Normalize()
        
        velocity:Add(wishDir * acceleration * deltaTime)
        
        if velocity:GetLengthXZ() > maxSpeedXZ then
        
            local yVel = velocity.y        
            velocity.y = 0
            velocity:Normalize()
            velocity:Scale(maxSpeedXZ)
            velocity.y = yVel
            
        end
    end
end

local function ForwardControl(self, deltaTime, velocity)

    PROFILE("GroundMoveMixin:ForwardControl")

    local airControl = self:GetAirControl() * 2

    if airControl > 0 then

        local wishDir = self:GetViewCoords().zAxis
        wishDir.y = 0
        wishDir:Normalize()
        
        --local dot = math.max(0, GetNormalizedVectorXZ(velocity):DotProduct(wishDir))
        local prevXZSpeed = velocity:GetLengthXZ()
        local prevY = velocity.y

        velocity:Add(wishDir * deltaTime * airControl)
        velocity.y = 0
        velocity:Normalize()
        velocity:Scale(prevXZSpeed)
        velocity.y = prevY
    
    end

end

local function Accelerate_onGround(self, input, velocity, maxSpeed, deltaTime)
    PROFILE("GroundMoveMixin:Accelerate_onGround")

    local wishDir = GetWishDir(self, input.move, false, velocity, maxSpeed)
    local prevXZSpeed = velocity:GetLengthXZ()
    
    local wishSpeed = maxSpeed
    local currentSpeed = math.min(velocity:GetLength(), velocity:DotProduct(wishDir))
    local addSpeed = wishSpeed - currentSpeed
    
    if addSpeed > 0 then
         
        local groundFraction = GetOnGroundFraction(self)
        local accel = groundFraction * self:GetAcceleration()
        local accelSpeed = accel * deltaTime * wishSpeed
        
        accelSpeed = math.min(addSpeed, accelSpeed)    
        velocity:Add(wishDir * accelSpeed)
    
    end
end

local function Accelerate_inTheAir(self, input, useFallAccel, velocity, maxSpeed, deltaTime)
    
    PROFILE("GroundMoveMixin:Accelerate_inTheAir")

    local groundFraction = 0
    
    local wishSpeed = kMaxAirVeer
    local wishDir = GetWishDir(self, input.move, false, velocity, maxSpeed)
    local currentSpeed = math.min(velocity:GetLength(), velocity:DotProduct(wishDir))
    local addSpeed = wishSpeed - currentSpeed
    
    local prevXZSpeed = velocity:GetLengthXZ()
    local clampedAirSpeed = prevXZSpeed + deltaTime * kMaxAirAccel
    local clampSpeedXZ = math.max(clampedAirSpeed, prevXZSpeed)
    
    if input.move.z == 1 then
        ForwardControl(self, deltaTime, velocity)
    end
    
    if addSpeed > 0 then
         
        local accel = self:GetAirControl()
        local accelSpeed = accel * deltaTime * wishSpeed
        
        accelSpeed = math.min(addSpeed, accelSpeed)    
        velocity:Add(wishDir * accelSpeed)
    
    end

    if useFallAccel then
    
        wishDir.y = 0
        local fallAccel = math.max(-velocity.y, 0) * deltaTime * kFallAccel
        velocity:Add(GetNormalizedVectorXZ(velocity) * fallAccel)
        
    end

    if velocity:GetLengthXZ() > clampSpeedXZ then
    
        local prevY = velocity.y
        velocity.y = 0
        velocity:Normalize()            
        velocity:Scale(clampSpeedXZ)
        velocity.y = prevY
    
    end

    local speedScalar = 1 - Clamp(velocity:GetLengthXZ() / maxSpeed, 0, 1) ^ 2
    local acceleration = self:GetAirAcceleration() * speedScalar
    
    if acceleration > 0 then
        AccelerateSimpleXZ(self, input, velocity, maxSpeed, acceleration, deltaTime)
    end

end

local function Accelerate(self, input, velocity, deltaTime)

    PROFILE("GroundMoveMixin:Accelerate")

    local maxSpeedTable = { maxSpeed = self:GetMaxSpeed() }
    self:ModifyMaxSpeed(maxSpeedTable, input) -- modifies the maxSpeed if crouching for instance
    local maxSpeed = maxSpeedTable.maxSpeed

    if self.onGround then
        Accelerate_onGround(self, input, velocity, maxSpeed, deltaTime)
    else
        local useFallAccel = not self.GetHasFallAccel or self:GetHasFallAccel()
        Accelerate_inTheAir(self, input, useFallAccel, velocity, maxSpeed, deltaTime)
    end
end

local function ApplyGravity(self, input, velocity, deltaTime)

    PROFILE("GroundMoveMixin:ApplyGravity")

    local gravityTable = { gravity = self:GetGravityForce(input) }
    if self.ModifyGravityForce then
        self:ModifyGravityForce(gravityTable)
    end

    velocity.y = velocity.y + gravityTable.gravity * deltaTime

end

function GroundMoveMixin:GetFriction(input, velocity)

    PROFILE("GroundMoveMixin:GetFriction")

    local friction = GetNormalizedVector(-velocity)
    local velocityLength = 0
    local frictionScalar = 1
    
    local isOnGround = self:GetIsOnGround()
    
    if isOnGround then
        velocityLength = velocity:GetLength()
    else
        if self:GetPerformsVerticalMove() then
            velocityLength = velocity:GetLength()
        else
            velocityLength = velocity:GetLengthXZ()
            friction.y = 0
        end
    end

    local groundFriction = self:GetGroundFriction()
    local airFriction = self:GetAirFriction()
    
    local onGroundFraction = GetOnGroundFraction(self)
    frictionScalar = velocityLength * (onGroundFraction * groundFriction + (1 - onGroundFraction) * airFriction)
    
    -- use minimum friction when on ground
    if isOnGround and input.move:GetLength() == 0 and velocity:GetLength() < kStopSpeed then
        frictionScalar = math.max(kStopFriction, frictionScalar)
    end
    
    return friction * frictionScalar
    
end

local function ApplyFriction(self, input, velocity, deltaTime)

    PROFILE("GroundMoveMixin:ApplyFriction")

    -- Add in the friction force.
    -- GetFrictionForce is an expected callback.
    local friction = self:GetFriction(input, velocity) * deltaTime

    -- If the friction force will cancel out the velocity completely, then just
    -- zero it out so that the velocity doesn't go "negative".
    if math.abs(friction.x) >= math.abs(velocity.x) then
        velocity.x = 0
    else
        velocity.x = friction.x + velocity.x
    end    
    if math.abs(friction.y) >= math.abs(velocity.y) then
        velocity.y = 0
    else
        velocity.y = friction.y + velocity.y
    end    
    if math.abs(friction.z) >= math.abs(velocity.z) then
        velocity.z = 0
    else
        velocity.z = friction.z + velocity.z
    end  

end

function GroundMoveMixin:PreUpdateMove()

    self.prevOrigin = Vector(self:GetOrigin())
    
end

local kUpVector = Vector(0, kStepHeight, 0)
local function DoStepMove(self, _, velocity, deltaTime)

    PROFILE("GroundMoveMixin:DoStepMove")
    
    local oldOrigin = Vector(self:GetOrigin())
    local oldVelocity = Vector(velocity)
    local success = false
    local stepAmount = 0
    local slowDownFraction = self.GetCollisionSlowdownFraction and self:GetCollisionSlowdownFraction() or 1
    local deflectMove = self.GetDeflectMove and self:GetDeflectMove() or false

    local onGround, normal
    
    -- step up at first
    --_PerformMovement(self, kUpVector, 1)
    --stepAmount = self:GetOrigin().y - oldOrigin.y

    -- Shortcut the up PerformMovement(), because any issues will be catched up
    -- by the next forward PerformMovement anyway. (and kUpVector is small enough)
    self:SetOrigin(oldOrigin + kUpVector)
    stepAmount = kUpVector.y
    
    -- do the normal move
    local startOrigin = Vector(self:GetOrigin())
    local completedMove = _PerformMovement(self, velocity * deltaTime, kTracesAmount, velocity, true, slowDownFraction, deflectMove, nil, deltaTime)
    local horizMoveAmount = (startOrigin - self:GetOrigin()):GetLengthXZ()

    if completedMove then
        -- step down again (slightly more than we went up to account for slopes)
        local downDistance = -stepAmount - horizMoveAmount * kDownSlopeFactor
        local downVect = Vector(0, downDistance, 0)
        local _, hitEntities, averageSurfaceNormal, surfaceMaterial = _PerformMovement(self, downVect, 1)

        if not (averageSurfaceNormal and averageSurfaceNormal.y >= 0.5) then
            downDistance = 0.15
            onGround, averageSurfaceNormal, hitEntities, surfaceMaterial = GetIsCloseToGround(self, downDistance) 
        else
            downDistance = 0 -- We reached the ground
        end

        if (averageSurfaceNormal and averageSurfaceNormal.y >= 0.5) then
            _SetGroundCheckCache(self, downDistance, hitEntities, averageSurfaceNormal, surfaceMaterial)
            success = true
        end
        
    end
    
    -- not succesful. fall back to normal move
    if not success then
    
        self:SetOrigin(oldOrigin)
        VectorCopy(oldVelocity, velocity)
        _PerformMovement(self, velocity * deltaTime, kTracesAmount, velocity, true, slowDownFraction, deflectMove, nil, deltaTime)
        
    end

    return success

end


function GroundMoveMixin:GetCanStep()
    return true
end    

local function FlushCollisionCallbacks(self, velocity)

    PROFILE("GroundMoveMixin:FlushCollisionCallbacks")

    if not self.onGround and self.storedNormal then

        local onGround, normal, _, surfaceMaterial = GetIsCloseToGround(self, 0.15)
        
        if surfaceMaterial then
            self.onGroundSurface = StringToEnum(kSurfaces, surfaceMaterial) or kSurfaces.metal
        end
    
        if self.OverrideUpdateOnGround then
            onGround = self:OverrideUpdateOnGround(onGround)
        end

        if onGround then
        
            self.onGround = true
            
            -- dont transistion for only short in air durations
            if self.timeGroundTouched + kAirGroundTransistionTime <= Shared.GetTime() then
                self.timeGroundTouched = Shared.GetTime()
            end

            if self.OnGroundChanged then
                self:OnGroundChanged(self.onGround, self.storedImpactForce, normal, velocity)
            end
            
        end
    
    end
    
    self.storedNormal = nil
    self.storedImpactForce = nil

end

function GroundMoveMixin:UpdatePosition(input, velocity, deltaTime)

    PROFILE("GroundMoveMixin:UpdatePosition")
    
    if self.controller then
        
        local onGround = self.onGround
        local normal
        local hitEntities
        local surfaceMaterial

        local stepAllowed = onGround and self:GetCanStep()
        local didStep = false
        local stepAmount = 0
        local playerHit = nil

        -- check if we are allowed to step
        local completedMove = false

        ---------
        local friendlyPlayerInRange = false
        local enemyPlayerInRange = false
        local enemyPlayerHit = false
        local vanillaMoveRate = 26
        -- Checks if players are within X mr-tick from us at current speed
        -- This allows us to skip the expensive PerformMovement() if none is found
        local distCheckEnemy = 3--math.max(1.5,(velocity * 0.20):GetLength())
        local distCheckFriendly = 2.5 --math.max(1.5,(velocity * 0.15):GetLength())

        local teamNumber = self:GetTeamNumber()
        local enemyTeamNumber = GetEnemyTeamNumber(self:GetTeamNumber())
        local playersAround = GetEntitiesWithinRange("Player", self:GetOrigin(), 4)
        for _, player in ipairs(playersAround) do
            if player:GetTeamNumber() == enemyTeamNumber then
                enemyPlayerInRange = true
            end
            if self ~= player and player:GetTeamNumber() == teamNumber then
                local dist = self:GetOrigin():GetDistanceTo(player:GetOrigin())
                if dist <= distCheckFriendly then
                    friendlyPlayerInRange = true
                end
            end
        end
        --

        if enemyPlayerInRange or friendlyPlayerInRange then
            local lookAheadDist = enemyPlayerInRange and distCheckEnemy or distCheckFriendly

            -- This call is very important for Predict side collision (and client to a lesser extent)
            -- It has to be done in all case for Client/Predict.
            -- * Server inits capsule once on EntityCreate()
            -- * Client inits capsule upon entering relevancy range
            -- * Predict inits capsule upon impact (and is responsible for a smooth collision feeling)
            -- It makes the client predict if it will bump into other players and create the collision controller accordingly.
            -- If not called, then the client will rubberband in place back&forth upon colliding with a player

            completedMove, hitEntities = _PerformMovement(self, velocity * (1.0/vanillaMoveRate * lookAheadDist), 1, nil, false)
            if stepAllowed and hitEntities then
            
                for i = 1, #hitEntities do
                    if hitEntities[i]:isa("Player") then
                        playerHit = hitEntities[i]
                        stepAllowed = false
                        if playerHit:GetTeamNumber() == GetEnemyTeamNumber(self:GetTeamNumber()) then
                            enemyPlayerHit = true
                        end
                        --Log("%s colliding with %s", self, hitEntities[i])
                        --break
                        
                    end
                end
            
            end
        end
        
        if not stepAllowed then -- Handles PvP collisions or jumps (no move-over movement checks)
            
            local slowDownFraction = self.GetCollisionSlowdownFraction and self:GetCollisionSlowdownFraction() or 1
            
            local deflectMove = self.GetDeflectMove and self:GetDeflectMove() or false
            
            -- Increases deflect traces in combat
            local numTraces = enemyPlayerHit and kPvPTracesAmount or kTracesAmount
            _PerformMovement(self, velocity * deltaTime, numTraces, velocity, true, slowDownFraction * 0.5, deflectMove, nil, deltaTime)
            
        else     
            DoStepMove(self, input, velocity, deltaTime)            
        end
        
        FlushCollisionCallbacks(self, velocity)
        
        if self.OnPositionUpdated then
            self:OnPositionUpdated(self:GetOrigin() - self.prevOrigin, stepAllowed, input, velocity)
        end
        
    end
    
    SetSpeedDebugText("onGround %s", ToString(self.onGround))

end

-- stub
function GroundMoveMixin:ModifyVelocity(input, velocity, deltaTime)
end

function GroundMoveMixin:GetIsOnGround()
    return self.onGround
end

function GroundMoveMixin:GetOnGroundSurface()
    return self.onGroundSurface
end

function GroundMoveMixin:GetIsOnEntity()
    return self.isOnEntity == true
end

-- for compatibility
function GroundMoveMixin:GetIsOnSurface()
    return self.onGround
end

local function Surfaces_StringToEnum(surfaceMaterial)
    --PROFILE("GroundMoveMixin:Surfaces_StringToEnum")
    if (surfaceMaterial == "metal") then
        return kSurfaces.metal -- 99% of the cases, no need to do an enum lookup for it
    end
    if (surfaceMaterial == "thin_metal") then
        return kSurfaces.thin_metal
    end

    --Log("-- %s", surfaceMaterial)
    return StringToEnum(kSurfaces, surfaceMaterial)
end

local function UpdateOnGround(self)

    PROFILE("GroundMoveMixin:UpdateOnGround")

    local onGround, _, hitEntities, surfaceMaterial = GetIsCloseToGround(self, 0.15)
    
    if surfaceMaterial then
        self.onGroundSurface = Surfaces_StringToEnum(surfaceMaterial) or kSurfaces.metal
    end
    
    if self.OverrideUpdateOnGround then
        onGround = self:OverrideUpdateOnGround(onGround)
    end
      
    if not onGround and onGround ~= self.onGround then
    
        self.onGround = false
        self.isOnEntity = false
        self.timeGroundTouched = Shared.GetTime()
        
        if self.OnGroundChanged then
            self:OnGroundChanged(onGround, 0)
        end
    
    end
    
    self.isOnEntity = self.onGround and hitEntities ~= nil and #hitEntities > 0

end

function GroundMoveMixin:GetTimeGroundTouched()
    return self.timeGroundTouched
end

-- Update origin and velocity from input.
function GroundMoveMixin:UpdateMove(input)
    PROFILE("GroundMoveMixin:UpdateMove")

    self.lastUpdateMoveTime = now

    local deltaTime = input.time -- math.min(kMaxDeltaTime, input.time)
    local velocity = self:GetVelocity()
    
    --Log("Velocity-in %s",velocity)

    UpdateOnGround(self)
    self:ModifyVelocity(input, velocity, deltaTime)
    if (velocity:GetLength() > 0) then
        ApplyFriction(self, input, velocity, deltaTime)
    end
    ApplyGravity(self, input, velocity, deltaTime)
    Accelerate(self, input, velocity, deltaTime)

    if (velocity:GetLength() > 0) then -- No update if not moving
        self:UpdatePosition(input, velocity, deltaTime)    
    --else
    --    Log("Not moving, skipping")
    end
    self:SetVelocity(velocity)
    --Log("Velocity-out %s",velocity)
end

function GroundMoveMixin:OnWorldCollision(normal, impactForce)

    PROFILE("GroundMoveMixin:OnWorldCollision")

    if normal then

        if not self.storedNormal then
            self.storedNormal = normal
        else
            self.storedNormal:Add(normal)
            self.storedNormal:Normalize()
        end
    
    end
    
    if impactForce then
    
        if not self.storedImpactForce then
            self.storedImpactForce = impactForce
        else
            self.storedImpactForce = (self.storedImpactForce + impactForce) * 0.5
        end
        
    end
    
end
