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
    self.kTimeLastControllerMove = 0
    
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
        
            --Log("Collisions for %s: %s (%s/%s)", player, enabled, player.controller, player.controllerOutter)

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
                self.controllerOutter:SetupCylinder( controllerRadius * 1.55, controllerHeight, self.controller:GetCoords(), allowTrigger )
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

-- TODO: nornalize, make the fastest one move first, then do our move, but don't touch them, just make us move as if they moved first
-- (no commit move, just recall the move and get a coord of where we ended up ? maybe just a set coords could work of its controller for collisions ?)

--
-- Moves by the player by the specified offset, colliding and sliding with the world.
-- slowDownFraction: 0.5s -> Takes 2s to lose all momentum, 1 -> takes 1s, 2 -> takes 0.5s, 
--
--local minOverlapping = 5
local kFirstCall = nil
local kSimulatedMove = 0
local kAdjustedMove = 1
function ControllerMixin:PerformMovement(offset, maxTraces, velocity, isMove, slowDownFraction, deflectMove, slowDownFilterFunc, deltaTime, correctionDone)

    PROFILE("ControllerMixin:PerformMovement")
    
    local commitChanges = (correctionDone == kFirstCall or correctionDone == kAdjustedMove)

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
    local origOffset = Vector(offset)
    
    local hitEntities
    local completedMove = true
    local averageSurfaceNormal
    local oldVelocity = velocity ~= nil and Vector(velocity) or nil
    local prevXZSpeed = velocity ~= nil and velocity:GetLengthXZ()
    local hitVelocity
    local surfaceMaterial

    if self.controller then
        
        if self.controllerOutter then
            self.controllerOutter:SetCollisionEnabled(false)        
        end
        
        self:UpdateControllerFromEntity()
        
        local tracesPerformed = 0
        
        
        while offset:GetLengthSquared() > 0.0 and tracesPerformed < maxTraces do
        
            local trace = self.controller:Move(offset, CollisionRep.Move, CollisionRep.Move, self:GetMovePhysicsMask())
            
            if trace.fraction < 1 then

                -- Remove the amount of the offset we've already moved.
                offset = offset * (1 - trace.fraction)
                
                -- Make the motion perpendicular to the surface we collided with so we slide.
                offset = offset - offset:GetProjection(trace.normal) -- + trace.normal*0.001

                -- Normalized and make the slowest one move
                -- (because it is the smallest possible adjustment out of the two)
                if deltaTime and trace.entity and correctionDone == kFirstCall
                    -- Only simulate the collidee if he hasn't moved yet this mr-tick (we are first to move)
                    and self.kTimeLastControllerMove and trace.entity.kTimeLastControllerMove
                    and not (self.kTimeLastControllerMove < trace.entity.kTimeLastControllerMove)
                    and trace.entity.GetVelocity and trace.entity:GetVelocity():GetLength() > 0
                    and self.GetVelocity and self:GetVelocity():GetLength() > 0
                    and self:GetVelocity():GetLength() < trace.entity:GetVelocity():GetLength()

                    then


                    local e = trace.entity
                    local eo = Vector(e:GetOrigin())
                    local ev = Vector(e:GetVelocity())
                    local es = e.GetCollisionSlowdownFraction and e:GetCollisionSlowdownFraction() or 1
                    local ed = e.GetDeflectMove and e:GetDeflectMove() or false
                    
                    local sos = Vector(self:GetOrigin())
                    local sov = oldVelocity

                    -- Reset our current controller collisions
                    preventRedirect = true
                    if self.controllerOutter then
                        self.controllerOutter:SetCollisionEnabled(true)        
                    end
                    self:UpdateControllerFromEntity()
                    -- Make the other move (Only its controller, never touch origin or it could get stuck when we revert)
                    --Log("1. %s", e.controller:GetPosition())
                    completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial = e:PerformMovement(ev * deltaTime, maxTraces, ev, true, es, ed, slowDownFilterFunc, deltaTime, kSimulatedMove)
                    --Log("2. %s", e.controller:GetPosition())
                    if self.controllerOutter then
                        self.controllerOutter:SetCollisionEnabled(false)        
                    end


                    -- Move ourselves now that the other has moved his way
                    completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial = self:PerformMovement(origOffset, maxTraces, oldVelocity, isMove, origSlowDownFraction, deflectMove, slowDownFilterFunc, deltaTime, kAdjustedMove)
                    
    
                    -- Print the position diff before and after that move (to see by how much this has changed the outcome)
                    --[[
                    Log("Collision - diff of position: %s=%s(v:%s/%s), %s=%s(v:%s/%s)",
                        self, (self:GetOrigin() - sos):GetLength(), sov:GetLength(), velocity:GetLength(),
                        e, (eo - e:GetOrigin()):GetLength(), ev:GetLength(), e:GetVelocity():GetLength()
                    )
                    --]]

                    -- From benchmark, client rarely goes below 0.003, but server does reach 0.0000 0000 1, so restrict to a bit below client value
                    -- (even with very low values, there were no stuck within each others, this more about excluding the case where it's so close it gets stuck)
                    -- (and it is mostly marines vs marines case)
                    -- If we are overlapping with even just a slight diff, engine will handle well and smooth it out
                    local isOverlapping = (self:GetOrigin() - sos):GetLength() < 0.0001
                    -- Since we are reverting the colidee to its old position, make sure we are not too much "inside" him.
                    -- Otherwise this could lead to the RR or IP bug, where two entities are stuck within each others.
                    --if (minOverlapping > (self:GetOrigin() - sos):GetLength()) then
                    --    Log("New overlapping min found: %s (%s vs %s)", minOverlapping, self, e)
                    --    minOverlapping = (self:GetOrigin() - sos):GetLength()
                    --end

                    -- Reset the colidee move
                    --e:SetOrigin(eo)
                    --VectorCopy(ev, e:GetVelocity())
                    e:UpdateControllerFromEntity()
                    --Log("3. %s", e.controller:GetPosition())

                    if not isOverlapping then
                        -- Return data with the colidee simulated move first
                        return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial
                    else
                        -- Redo the classic one
                        return self:PerformMovement(origOffset, maxTraces, oldVelocity, isMove, origSlowDownFraction, deflectMove, slowDownFilterFunc, deltaTime, kAdjustedMove)
                    end
                end

                --if trace.entity and trace.entity:isa("Player") then
                --    Log("%s colliding with %s (first ? %s (%s/%s))", self, trace.entity, Shared.GetTime() > (trace.entity.kTimeLastControllerMove and trace.entity.kTimeLastControllerMove or 0), self.kTimeLastControllerMove, trace.entity.kTimeLastControllerMove)
                --end

                -- Redirect velocity if specified
                if velocity ~= nil and slowDownFraction ~= nil and commitChanges then
                
                    assert(deltaTime ~= nil) -- We are now timed based (not tick based), make sure we have the deltaTime !
                    -- Scale it according to how much velocity we lost
                    local newVelocity = velocity - velocity:GetProjection(trace.normal) * slowDownFraction -- + trace.normal*0.001
                    
                    -- Copy it so it's changed for caller
                    VectorCopy(newVelocity, velocity)
                    --Log("Applying slow down of %s * %s", deltaTime, slowDownFraction)
                    
                end
                
                if not averageSurfaceNormal then
                    averageSurfaceNormal = Vector(trace.normal)
                else
                
                    averageSurfaceNormal = averageSurfaceNormal + trace.normal
                    if averageSurfaceNormal:GetLength() > 0 then
                        averageSurfaceNormal:Normalize()
                    end
                
                end
                
                -- Defer the processing of the callbacks until after we've finished moving,
                -- since the callbacks may modify our self an interfere with our loop
                if trace.entity ~= nil and trace.entity.OnCapsuleTraceHit ~= nil then
                
                    if hitEntities == nil then
                        hitEntities = { trace.entity }
                    else
                        table.insert(hitEntities, trace.entity)
                    end

                end
                
                if trace.entity and trace.entity.GetVelocity and trace.entity:GetVelocity() then
                    hitVelocity = trace.entity:GetVelocity()
                end
                
                surfaceMaterial = trace.surface
                
                completedMove = false
                
            else
                offset = Vector(0, 0, 0)
            end
            
            tracesPerformed = tracesPerformed + 1
            
        end
        
        if isMove and commitChanges then
            self:UpdateOriginFromController()
        end
        
        if self.controllerOutter then
            self.controllerOutter:SetCollisionEnabled(true)
        end
        
    end
    
    if isMove and commitChanges then
        self.kTimeLastControllerMove = Shared.GetTime()
    end

    -- Do the hit callbacks. (but not if we do the blank one to nornalize, isMove would be set to "1")
    if hitEntities and isMove and commitChanges then
        
        --[[
        if hitVelocity and oldVelocity then
        
            hitVelocity.y = 0
            local addSpeed = Clamp(oldVelocity:DotProduct(hitVelocity), 0, prevXZSpeed)
            if addSpeed > 0 then            
                velocity:Add(addSpeed * GetNormalizedVector(oldVelocity))
            end
        
        end
        --]]
        for _, entity in ipairs(hitEntities) do
        
            entity:OnCapsuleTraceHit(self)
            self:OnCapsuleTraceHit(entity)
            
        end
        
    end

    if velocity and oldVelocity and not deflectMove and commitChanges then
        
        -- edge case when jumping down slopes. we never want that the controller can add speed
        local newXZSpeed = velocity:GetLengthXZ()
        if newXZSpeed > prevXZSpeed then
        
            local ySpeed = velocity.y
            velocity.y = 0
            velocity:Scale(prevXZSpeed / newXZSpeed)
            velocity.y = ySpeed
            
        end
        
    end

    -- TODO: dont compare velocities, use some boolean
    -- averageSurfaceNormal should not normally be nil at this point but there is an edge
    -- case where it is.
    if oldVelocity ~= velocity and isMove and commitChanges and averageSurfaceNormal and self.OnWorldCollision then
    
        local impactForce = math.max(0, (-averageSurfaceNormal):DotProduct(oldVelocity))    
        self:OnWorldCollision(averageSurfaceNormal, impactForce, velocity)
        
    end
    
    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial
end
