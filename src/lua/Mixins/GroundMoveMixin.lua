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

local function GetIsCloseToGround(self, distance)

    PROFILE("GroundMoveMixin:GetIsCloseToGround")

    local onGround = false
    local normal = Vector()
    local completedMove, hitEntities, surfaceMaterial

    if self.controller == nil then
      
        onGround = true
    
    elseif self.timeGroundAllowed <= Shared.GetTime() then
    
        local velocity = self:GetVelocity()

        -- Try to move the controller downward a small amount to determine if
        -- we're on the ground.
        local offset = Vector(0, -distance, 0)
        -- need to do multiple slides here to not get traped in V shaped spaces
        completedMove, hitEntities, normal, surfaceMaterial = self:PerformMovement(offset, 3, nil, false)
        
        if normal and normal.y >= 0.5 then
            onGround = true
        end
    
    end
    
    -- Nil surface material implies it wasn't set, so we default to "metal".
    -- It doesn't matter if we're on the ground or not -- checking the surface material should NOT
    -- double as checking if we're on the ground or not -- that's what "onGround" is for.
    surfaceMaterial = surfaceMaterial or "metal"
    
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
    
    local clampedAirSpeed = prevXZSpeed + deltaTime * kMaxAirAccel
    local clampSpeedXZ = math.max(maxSpeed, prevXZSpeed)
    
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

local function DoStepMove(self, _, velocity, deltaTime)

    PROFILE("GroundMoveMixin:DoStepMove")
    
    local oldOrigin = Vector(self:GetOrigin())
    local oldVelocity = Vector(velocity)
    local success = false
    local stepAmount = 0
    local slowDownFraction = self.GetCollisionSlowdownFraction and self:GetCollisionSlowdownFraction() or 1
    local deflectMove = self.GetDeflectMove and self:GetDeflectMove() or false

    -- Do normal one
    local completedMove, _, averageSurfaceNormal = self:PerformMovement(velocity * deltaTime, 3, velocity, true, slowDownFraction, deflectMove)
    local distMoved = self:GetOrigin():GetDistanceTo(oldOrigin)
    local expectedDestPos = oldOrigin + velocity * deltaTime
    local diffPos = expectedDestPos:GetDistanceTo(self:GetOrigin())
    success = (diffPos == 0) -- If we are exactly where we should, keep it

    local c1 = false
    local c2 = false

--[[
    if (not completedMove
        or (hitEntities and #hitEntities > 0)
        or (averageSurfaceNormal and averageSurfaceNormal.y < 1)
        or diffPos > 0.001 or math.abs(self:GetOrigin().y - oldOrigin.y) > 0.001
        ) then
        c1 = true
    end
    --]]

    if ((averageSurfaceNormal and averageSurfaceNormal.y < 1) or diffPos > 0.001 or self:GetOrigin().y - oldOrigin.y > 0.001 or not completedMove) then
        --c2 = true
--[[
    if (not completedMove
        or (hitEntities and #hitEntities > 0)
        or (averageSurfaceNormal and averageSurfaceNormal.y < 1)
        or diffPos > 0.001 or math.abs(self:GetOrigin().y - oldOrigin.y) > 0.001
        ) then
--]]

        --if (Server) then
        --    Log("Elevation or geo-block detected, fallbacking to move-over: (diff-pos: %s)/(diff-y %sm)/completed: %s/normal: %s",
        --        diffPos, newOriginWithDefaultMove.y - oldOrigin.y, completedMove, (averageSurfaceNormal and averageSurfaceNormal.y < 1 or -999))
        --end
        success = false
    else
        success = true
    end

--[[
    if c1 ~= c2 then
        if (Server) then
            Log("%s, %s/%s",
                (hitEntities and #hitEntities > 0),
                math.abs(self:GetOrigin().y - oldOrigin.y) > 0.001,
                self:GetOrigin().y - oldOrigin.y > 0.001
                )
        end
    end
    --]]

    -- return true for the move-over checks to always happen
    -- return false for it to never happen (lerks for instance)
    -- undefined to only happen in regular cases to walk over geo
    if (self.DoExtraGroundStepsChecks) then
        if (not self:DoExtraGroundStepsChecks()) then
            return success
        else
            success = false -- Else force the regular check to happen
        end
    end

    if not success then
        -- step up at first
        self:SetOrigin(oldOrigin)
        VectorCopy(oldVelocity, velocity)
        self:PerformMovement(Vector(0, kStepHeight, 0), 1)
        stepAmount = self:GetOrigin().y - oldOrigin.y
        
        -- do the normal move
        local startOrigin = Vector(self:GetOrigin())
        local completedMove = self:PerformMovement(velocity * deltaTime, 3, velocity, true, slowDownFraction, deflectMove)
        local horizMoveAmount = (startOrigin - self:GetOrigin()):GetLengthXZ()
        
        if completedMove then
            -- step down again
            local _, _, averageSurfaceNormal = self:PerformMovement(Vector(0, -stepAmount - horizMoveAmount * kDownSlopeFactor, 0), 1)
            
            --Log("averageSurfaceNormal.y:%s", averageSurfaceNormal.y)
            if averageSurfaceNormal and averageSurfaceNormal.y >= 0.5 then
                success = true
            else    
            
                local onGround = GetIsCloseToGround(self, 0.15)
                if onGround then
                    success = true
                end
                
            end
        end
    end

    -- If still not succesful. Have to redo first normal move (rare case of geo feature/stuck)
    if not success then
    
        self:SetOrigin(oldOrigin)
        VectorCopy(oldVelocity, velocity)
        self:PerformMovement(velocity * deltaTime, 3, velocity, true, slowDownFraction, deflectMove)
        
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
        
        local stepAllowed = self.onGround and self:GetCanStep()
        local didStep = false
        local stepAmount = 0
        local hitObstacle = false
    
        -- check if we are allowed to step
        local completedMove = false
        local hitEntities = nil

        -- - Checks for player collision while on ground, if none then we can step-over floor features
        -- We usually move at, at most, 1.2m/update for very high speed stuff, so 5m player check is generous
        -- We if are in the air/jumping or if nobody is in range, don't even bother checking ground move-over
        if stepAllowed and #GetEntitiesWithinRange("Player", self:GetOrigin(), 5) > 1 then -- exclude self
            completedMove, hitEntities = self:PerformMovement(velocity * deltaTime * 2.5, 1, nil, false)
            if stepAllowed and hitEntities then
            
                for i = 1, #hitEntities do
                    if hitEntities[i]:isa("Player") then
                        hitObstacle = true
                        stepAllowed = false
                        --Log("%s colliding with %s", self, hitEntities[i])
                        break
                        
                    end
                end
            
            end
        end
        
        if not stepAllowed then
            
            local slowDownFraction = self.GetCollisionSlowdownFraction and self:GetCollisionSlowdownFraction() or 1 
            
            local deflectMove = self.GetDeflectMove and self:GetDeflectMove() or false
            
            self:PerformMovement(velocity * deltaTime, 3, velocity, true, slowDownFraction * 0.5, deflectMove)
            
        else     
            didStep, stepAmount = DoStepMove(self, input, velocity, deltaTime)            
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

