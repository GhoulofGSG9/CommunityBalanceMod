-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\ControllerMixin.lua
--
--    Created by:   Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Vector.lua")

ControllerMixin = CreateMixin( ControllerMixin )
ControllerMixin.type = "Controller"

-- The controller uses a 0.1m thick "skin" around it to handle collisions properly
local kSkinOffset = 0.1
        
ControllerMixin.expectedCallbacks =
{
    GetControllerSize = "Should return a height and radius",
    GetMovePhysicsMask = "Should return a mask for the physics groups to collide with",
    GetControllerPhysicsGroup = "Should return physics grouop for controller.",
}

ControllerMixin.optionalCallbacks =
{
    GetHasController = "Creates/destroys controller when returned true/false.",
    GetHasOutterController = "Creates/destroys outter controller when returned true/false."
}

ControllerMixin.networkVars =
{
}

function ControllerMixin:__initmixin()
    
    PROFILE("ControllerMixin:__initmixin")
    
    self.controller = nil
    
    self.moveOrigOffset = Vector()
    self.moveVelocity = Vector()
    self.moveAverageSurfaceNormal = Vector()
end

function ControllerMixin:OnDestroy()
    self:DestroyController()
    self:DestroyOutterController()
end

function ControllerMixin:CreateController()

    local physicsGroup = self:GetControllerPhysicsGroup()    
    
    self.controller = Shared.CreateCollisionObject(self)
    self.controller:SetGroup(physicsGroup)
    self.controller:SetTriggeringEnabled( true )

    -- Make the controller kinematic so physically simulated objects will
    -- interact/collide with it.
    self.controller:SetPhysicsType(CollisionObject.Kinematic)


end

function ControllerMixin:CreateOutterController()

    local physicsGroup = self:GetControllerPhysicsGroup()  
    
    self.controllerOutter = Shared.CreateCollisionObject(self)
    self.controllerOutter:SetGroup(physicsGroup)
    self.controllerOutter:SetTriggeringEnabled( false )
    self.controllerOutter:SetPhysicsType(CollisionObject.Kinematic) 
    
end

local function SetNearbyPlayerControllers(self, enabled)

    for _, player in ipairs(GetEntitiesWithinRange("Player", self:GetOrigin(), 4)) do
    
        if player ~= self then

            if player.controllerOutter then

                player.controllerOutter:SetCollisionEnabled(enabled)
            end
            
            if player.controller then
                player.controller:SetCollisionEnabled(enabled)
            end
        
        end
    
    end

end

function ControllerMixin:DestroyController()

    if self.controller ~= nil then
    
        Shared.DestroyCollisionObject(self.controller)
        self.controller = nil
        
    end
    
end

function ControllerMixin:DestroyOutterController()

    if self.controllerOutter then 

        Shared.DestroyCollisionObject(self.controllerOutter)
        self.controllerOutter = nil
        
    end
    
end

function ControllerMixin:SetPositions(origin, allowTrigger)

    if (self.controller:GetPosition() ~= origin) then
        self.controller:SetPosition(origin, allowTrigger)
    end
    
    if self.controllerOutter then
        if self.controllerOutter:GetPosition() ~= origin then
            self.controllerOutter:SetPosition(origin, allowTrigger)
        end
    end
end

--
-- Synchronizes the origin and shape of the physics controller with the current
-- state of the entity.
--
local origin = Vector()
function ControllerMixin:UpdateControllerFromEntity(allowTrigger)

    PROFILE("ControllerMixin:UpdateControllerFromEntity")

    if allowTrigger == nil then
        allowTrigger = true
    end

    if self.controller ~= nil then
    
        local controllerHeight, controllerRadius = self:GetControllerSize()
        
        if controllerHeight ~= self.controllerHeight or controllerRadius ~= self.controllerRadius then
        
            self.controllerHeight = controllerHeight
            self.controllerRadius = controllerRadius
        
            local capsuleHeight = controllerHeight - 2*controllerRadius
        
            -- Skulks/Gorges/Lerks
            if capsuleHeight < 0.001 then
                -- Use a sphere controller
                --Log("A - %s", self)
                self.controller:SetupSphere( controllerRadius, self.controller:GetCoords(), allowTrigger )
            else -- Marines/Exos/Fades/Onos
                -- A flat bottomed cylinder works well for movement since we don't
                -- slide down as we walk up stairs or over other lips. The curved
                -- edges of the cylinder allows players to slide off when we hit them,
                --Log("%s - %s / %s", self, controllerRadius, capsuleHeight)
                self.controller:SetupCapsule( controllerRadius, capsuleHeight, self.controller:GetCoords(), allowTrigger )
                --self.controller:SetupCylinder( controllerRadius, controllerHeight, self.controller:GetCoords(), allowTrigger )
            end

            if self.controllerOutter then                
            --if self.controllerOutter and self:isa("Fade") then                
                --self.controllerOutter:SetupBox(Vector(self.controllerRadius * 1.3, self.controllerHeight * 0.5, self.controllerRadius * 1.3), self.controller:GetCoords(), allowTrigger)
                local outerOffset = 0.22
                self.controllerOutter:SetupCylinder( controllerRadius + outerOffset, controllerHeight, self.controller:GetCoords(), allowTrigger )
                --DebugCapsule(self:GetOrigin() + Vector(0, 0.5, 0), self:GetOrigin() + Vector(0, 0.5, 0), controllerRadius * 1.55, controllerHeight, 5)
            end                
            
            -- Remove all collision reps except movement from the controller.
            for i = 0, #CollisionRep - 1 do
                if i ~= CollisionRep.Move then
                
                    self.controller:RemoveCollisionRep(i)
                    
                    if self.controllerOutter then
                        self.controllerOutter:RemoveCollisionRep(i)
                    end
                    
                end
            end
            
            self.controller:SetTriggeringCollisionRep(CollisionRep.Move)
            self.controller:SetPhysicsCollisionRep(CollisionRep.Move)
 
        end
        
        -- The origin of the controller is at its center and the origin of the
        -- player is at their feet, so offset it.
        VectorCopy(self:GetOrigin(), origin)
        origin.y = origin.y + self.controllerHeight * 0.5 + kSkinOffset

        self:SetPositions(origin, allowTrigger)
 
    end
    
end

--
-- Synchronizes the origin of the entity with the current state of the physics
-- controller.
--
function ControllerMixin:UpdateOriginFromController()

    -- The origin of the controller is at its center and the origin of the
    -- player is at their feet, so offset it.
    local origin = Vector(self.controller:GetPosition())
    origin.y = origin.y - self.controllerHeight * 0.5 - kSkinOffset
    
    self:SetOrigin(origin)
    
end

local function UpdateControllerAfterPhysics(self)
    local hasController = not self.GetHasController or self:GetHasController()
    local hasOutterController = not self.GetHasOutterController or self:GetHasOutterController()

    if not self.controller and hasController then
        self:CreateController()
    elseif self.controller and not hasController then
        self:DestroyController()
    end    
    
    if not self.controllerOutter and hasOutterController then
        self:CreateOutterController()
    elseif self.controllerOutter and not hasOutterController then
        self:DestroyOutterController()
    end

    self:UpdateControllerFromEntity()
end


function ControllerMixin:OnUpdatePhysics()
    UpdateControllerAfterPhysics(self)
end

-- call from multithreaded-physics
function ControllerMixin:OnFinishPhysics()
    UpdateControllerAfterPhysics(self)
end

--
-- Returns true if the entity is colliding with anything that passes its movement
-- mask at its current position.
--
function ControllerMixin:GetIsColliding()

    PROFILE("ControllerMixin:GetIsColliding")

    if self.controller then
    
        if self.controllerOutter then
            self.controllerOutter:SetCollisionEnabled(false)
        end
        
        self:UpdateControllerFromEntity()
        
        local result = self.controller:Test(CollisionRep.Move, CollisionRep.Move, self:GetMovePhysicsMask())
        
        if self.controllerOutter then
            self.controllerOutter:SetCollisionEnabled(true)
        end
        
        return result
        
    end
    
    return false

end

--
-- Moves by the player by the specified offset, colliding and sliding with the world.
--
function ControllerMixin:PerformMovement(o, maxTraces, velocity, isMove, slowDownFraction, deflectMove, slowDownFilterFunc, deltaTime)

    PROFILE("ControllerMixin:PerformMovement")

    local offset = Vector(o) -- Do not modify parameter which is passed by ref (so caller can use constant)
    local controller = self.controller
    local controllerOutter = self.controllerOutter

    if isMove == nil then
        isMove = true
    end
    
    if deflectMove == nil then
        deflectMove = false
    end
    
    if slowDownFraction == nil then
        slowDownFraction = 1
    end

    if (deltaTime) then
        -- Vanilla move-rate per second is 26 (to make it time based, rather than tick)
        slowDownFraction = math.min(1, slowDownFraction * 26 * deltaTime)
    end
    local origSlowDownFraction = slowDownFraction
    
    VectorCopy(offset, self.moveOrigOffset)
    local origOffset = self.moveOrigOffset
    local oldVelocity = nil
    local prevXZSpeed = nil

    if (velocity) then
        VectorCopy(velocity, self.moveVelocity)
        oldVelocity = self.moveVelocity
        prevXZSpeed = self.moveVelocity:GetLengthXZ()
    end
    
    local hitEntities
    local completedMove = true
    local averageSurfaceNormal
    local surfaceMaterial

    if controller then
        
        if controllerOutter then
            controllerOutter:SetCollisionEnabled(false)        
        end
        
        self:UpdateControllerFromEntity()

        local tracesPerformed = 0
        local physicsMask = self:GetMovePhysicsMask()

        while offset:GetLengthSquared() > 0.0 and tracesPerformed < maxTraces do
        
            local trace = controller:Move(offset, CollisionRep.Move, CollisionRep.Move, physicsMask)

            completedMove = (trace.fraction >= 1)
            if completedMove then
                break
            else
                -- Remove the amount of the offset we've already moved.
                offset = offset * (1 - trace.fraction)
                
                -- Make the motion perpendicular to the surface we collided with so we slide.
                offset = offset - offset:GetProjection(trace.normal) -- + trace.normal*0.001

                -- Redirect velocity if specified
                if velocity ~= nil and slowDownFraction ~= nil then
                
                    assert(deltaTime ~= nil) -- We are now timed based (not tick based), make sure we have the deltaTime !
                    -- Scale it according to how much velocity we lost
                    local newVelocity = velocity - velocity:GetProjection(trace.normal) * slowDownFraction -- + trace.normal*0.001
                    
                    -- Copy it so it's changed for caller
                    VectorCopy(newVelocity, velocity)
                    --Log("Applying slow down of %s * %s", deltaTime, slowDownFraction)
                    
                end
                
                if not averageSurfaceNormal then
                    VectorCopy(trace.normal, self.moveAverageSurfaceNormal)
                    averageSurfaceNormal = self.moveAverageSurfaceNormal
                else
                    averageSurfaceNormal = averageSurfaceNormal + trace.normal
                end
                
                -- Defer the processing of the callbacks until after we've finished moving,
                -- since the callbacks may modify our self an interfere with our loop
                if trace.entity ~= nil and trace.entity.OnCapsuleTraceHit ~= nil then
                
                    if not hitEntities then
                        hitEntities = {}
                    end
                    hitEntities[#hitEntities + 1] = trace.entity  -- Faster than table.insert

                end
                surfaceMaterial = trace.surface
            end
            
            tracesPerformed = tracesPerformed + 1
            
        end
        
        if isMove then
            self:UpdateOriginFromController()
        end
        
        if controllerOutter then
            controllerOutter:SetCollisionEnabled(true)
        end
        
    end

    -- Do the hit callbacks. (but not if we do the blank one to nornalize, isMove would be set to "1")
    if hitEntities and isMove then
        
        for _, entity in ipairs(hitEntities) do
        
            entity:OnCapsuleTraceHit(self)
            self:OnCapsuleTraceHit(entity)
            
        end
        
    end

    if velocity and oldVelocity and not deflectMove then
        
        -- edge case when jumping down slopes. we never want that the controller can add speed
        local newXZSpeed = velocity:GetLengthXZ()
        if newXZSpeed > prevXZSpeed then
        
            local ySpeed = velocity.y
            velocity.y = 0
            velocity:Scale(prevXZSpeed / newXZSpeed)
            velocity.y = ySpeed
            
        end
        
    end

    if averageSurfaceNormal and averageSurfaceNormal:GetLength() > 0 then
        averageSurfaceNormal:Normalize()
    end

    -- TODO: dont compare velocities, use some boolean
    -- averageSurfaceNormal should not normally be nil at this point but there is an edge
    -- case where it is.
    if oldVelocity ~= velocity and isMove and averageSurfaceNormal and self.OnWorldCollision then
    
        local impactForce = math.max(0, (-averageSurfaceNormal):DotProduct(oldVelocity))    
        self:OnWorldCollision(averageSurfaceNormal, impactForce, velocity)
        
    end
    
    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial
end
