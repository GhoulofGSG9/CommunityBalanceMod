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
    self.moveOffset = Vector()
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

    self.controllerHeight = nil
    self.controllerRadius = nil

end

function ControllerMixin:CreateOutterController()

    local physicsGroup = self:GetControllerPhysicsGroup()  
    
    self.controllerOutter = Shared.CreateCollisionObject(self)
    self.controllerOutter:SetGroup(physicsGroup)
    self.controllerOutter:SetTriggeringEnabled( false )
    self.controllerOutter:SetPhysicsType(CollisionObject.Kinematic) 

    self.controllerHeight = nil
    self.controllerRadius = nil
    
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
                self.controller:SetupSphere( controllerRadius, self.controller:GetCoords(), allowTrigger )
            else -- Marines/Exos/Fades/Onos
                -- A flat bottomed cylinder works well for movement since we don't
                -- slide down as we walk up stairs or over other lips. The curved
                -- edges of the cylinder allows players to slide off when we hit them,
                self.controller:SetupCapsule( controllerRadius, capsuleHeight, self.controller:GetCoords(), allowTrigger )
            end

            if self.controllerOutter then                
                local outerOffset = 0.22
                self.controllerOutter:SetupCylinder( controllerRadius + outerOffset, controllerHeight, self.controller:GetCoords(), allowTrigger )
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


-- Normals of the distinct planes hit so far by the move in progress (scratch, reset at the
-- start of every sweep; a sweep is never re-entered since hit callbacks are deferred).
local kPlaneX, kPlaneY, kPlaneZ = {}, {}, {}
local gPlaneCount = 0

local function IsMovingIntoPlane(offset, planeIndex)
    return offset.x * kPlaneX[planeIndex] + offset.y * kPlaneY[planeIndex] + offset.z * kPlaneZ[planeIndex] < -kEpsilon
end

local function IsMovingIntoAnyPlaneExcept(offset, skipIndex)

    for k = 1, gPlaneCount do
        if k ~= skipIndex and IsMovingIntoPlane(offset, k) then
            return true
        end
    end

    return false

end

--
-- Crease sliding.
--
-- Sliding into a concave corner (e.g. a wall meeting a ramp): clipping the offset against
-- one plane at a time ping-pongs between the two planes. Each clip leaves a small component
-- into the other plane, so every sweep is blocked at fraction 0 and the trace budget runs out
-- without the controller ever moving. With a flat floor and a wall the clips are exact and it
-- converges at once, which is why only sloped planes show it. When a real move (one that is
-- passed a velocity) still moves into a plane it hit earlier, slide along the crease of the
-- two planes instead (the direction perpendicular to both normals).
--

-- Keeps only the part of the offset that runs along the crease between the earlier plane
-- (planeIndex) and the plane with the normal (nx, ny, nz).
local function ClipOffsetToCrease(offset, planeIndex, nx, ny, nz)

    local px, py, pz = kPlaneX[planeIndex], kPlaneY[planeIndex], kPlaneZ[planeIndex]
    local cx = py * nz - pz * ny
    local cy = pz * nx - px * nz
    local cz = px * ny - py * nx
    local creaseLengthSq = cx * cx + cy * cy + cz * cz

    if creaseLengthSq > (kEpsilon * kEpsilon) then

        local invLength = 1 / math.sqrt(creaseLengthSq)
        cx, cy, cz = cx * invLength, cy * invLength, cz * invLength

        local along = offset.x * cx + offset.y * cy + offset.z * cz
        offset.x, offset.y, offset.z = cx * along, cy * along, cz * along

        -- A third plane that the crease runs into is a corner, stop there.
        if IsMovingIntoAnyPlaneExcept(offset, planeIndex) then
            offset.x, offset.y, offset.z = 0, 0, 0
        end

    else
        -- opposing parallel planes, squeezed between two surfaces
        offset.x, offset.y, offset.z = 0, 0, 0
    end

end

-- Call for every hit of a real move, after the offset was clipped against the hit plane.
-- If the offset still moves into a plane that was hit earlier in this move, it is redirected
-- along the crease of the two planes. Returns true when that happened.
local function SlideAlongCrease(offset, normal)

    local nx, ny, nz = normal.x, normal.y, normal.z
    local isNewPlane = true
    local creased = false
    local kSamePlaneDot = 0.999
    local kMaxCreasePlanes = 8

    for i = 1, gPlaneCount do

        if kPlaneX[i] * nx + kPlaneY[i] * ny + kPlaneZ[i] * nz > kSamePlaneDot then
            -- same plane as before, nothing new to learn from it
            isNewPlane = false
        elseif IsMovingIntoPlane(offset, i) then
            ClipOffsetToCrease(offset, i, nx, ny, nz)
            creased = true
            break
        end

    end

    if isNewPlane and gPlaneCount < kMaxCreasePlanes then
        gPlaneCount = gPlaneCount + 1
        kPlaneX[gPlaneCount], kPlaneY[gPlaneCount], kPlaneZ[gPlaneCount] = nx, ny, nz
    end

    return creased

end

--
-- Sweeping the controller.
--

-- Removes the part of the offset that is already moved and the part pointing into the
-- surface we hit, so the rest of the offset slides along that surface.
local function ClipOffsetToHit(offset, trace)

    -- Remove the amount of the offset we've already moved.
    local keep = 1 - trace.fraction
    offset.x = offset.x * keep
    offset.y = offset.y * keep
    offset.z = offset.z * keep

    -- Make the motion perpendicular to the surface we collided with so we slide
    -- (offset -= normal * (offset . normal)). Written out, since Vector:GetProjection
    -- allocates a vector for every hit.
    local normal = trace.normal
    local nx, ny, nz = normal.x, normal.y, normal.z
    local dot = offset.x * nx + offset.y * ny + offset.z * nz
    offset.x = offset.x - nx * dot
    offset.y = offset.y - ny * dot
    offset.z = offset.z - nz * dot

end

-- Redirect velocity (changed in place, so it's changed for the caller).
-- Scales it according to how much velocity we lost.
-- Same projection as above (velocity -= normal * (velocity . normal) * slowDownFraction).
local function RedirectVelocity(velocity, normal, slowDownFraction)

    local nx, ny, nz = normal.x, normal.y, normal.z
    local dot = velocity.x * nx + velocity.y * ny + velocity.z * nz
    velocity.x = velocity.x - nx * dot * slowDownFraction
    velocity.y = velocity.y - ny * dot * slowDownFraction
    velocity.z = velocity.z - nz * dot * slowDownFraction

end

-- Always accumulate in the shared vector, so the returned normal is consistently the
-- same object whether we hit once or many times.
local function AccumulateSurfaceNormal(self, averageSurfaceNormal, normal)

    if not averageSurfaceNormal then
        VectorCopy(normal, self.moveAverageSurfaceNormal)
        return self.moveAverageSurfaceNormal
    end

    averageSurfaceNormal:Add(normal)
    return averageSurfaceNormal

end

-- Entities that want to know about being hit are collected here, their callbacks are
-- deferred until we've finished moving, since the callbacks may modify our self and
-- interfere with our loop.
local function AddHitEntity(hitEntities, entity)

    if entity ~= nil and entity.OnCapsuleTraceHit ~= nil then

        if not hitEntities then
            hitEntities = {}
        end
        hitEntities[#hitEntities + 1] = entity  -- Faster than table.insert

    end

    return hitEntities

end

-- Sweeps the controller along the offset, sliding along every surface it hits, for at most
-- maxTraces traces. The velocity (if any) is redirected along the way.
local function SweepController(self, o, maxTraces, velocity, slowDownFraction)

    -- Work on a copy, the offset of the caller is not to be modified (so the caller can use
    -- a constant). A scratch vector of the entity, instead of a new vector for every call.
    local offset = self.moveOffset
    VectorCopy(o, offset)

    local controller = self.controller
    local physicsMask = self:GetMovePhysicsMask()
    local useCreaseSlide = velocity ~= nil

    local completedMove = true
    local tracesPerformed = 0
    local hitEntities, averageSurfaceNormal, surfaceMaterial

    gPlaneCount = 0

    while offset:GetLengthSquared() > 0.0 and tracesPerformed < maxTraces do

        local trace = controller:Move(offset, CollisionRep.Move, CollisionRep.Move, physicsMask)

        if trace.fraction >= 1 then
            break
        end

        ClipOffsetToHit(offset, trace)

        if velocity ~= nil then
            RedirectVelocity(velocity, trace.normal, slowDownFraction)
        end

        averageSurfaceNormal = AccumulateSurfaceNormal(self, averageSurfaceNormal, trace.normal)
        hitEntities = AddHitEntity(hitEntities, trace.entity)
        surfaceMaterial = trace.surface
        completedMove = false

        tracesPerformed = tracesPerformed + 1

    end

    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial

end

-- Syncs the controller with the entity, sweeps it and (if isMove) applies the result to the
-- entity origin. The outer controller must not take part in the sweep.
local function MoveController(self, o, maxTraces, velocity, slowDownFraction, isMove)

    local controllerOutter = self.controllerOutter

    if controllerOutter then
        controllerOutter:SetCollisionEnabled(false)
    end

    self:UpdateControllerFromEntity()

    local completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial =
        SweepController(self, o, maxTraces, velocity, slowDownFraction)

    if isMove then
        self:UpdateOriginFromController()
    end

    if controllerOutter then
        controllerOutter:SetCollisionEnabled(true)
    end

    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial

end

--
-- Helpers for the parts around the sweep.
--

local function GetSlowDownFraction(slowDownFraction, deltaTime)

    if slowDownFraction == nil then
        slowDownFraction = 1
    end

    if deltaTime then
        -- Vanilla move-rate per second is 26 (to make it time based, rather than tick)
        slowDownFraction = math.min(1, slowDownFraction * 26 * deltaTime)
    end

    return slowDownFraction

end

local function NotifyTraceHits(self, hitEntities)

    for i = 1, #hitEntities do

        local entity = hitEntities[i]
        entity:OnCapsuleTraceHit(self)
        if self.OnCapsuleTraceHit then
            self:OnCapsuleTraceHit(entity)
        end

    end

end

-- edge case when jumping down slopes. we never want that the controller can add speed
local function ClampXZSpeedGain(velocity, prevXZSpeed)

    local newXZSpeed = velocity:GetLengthXZ()
    if newXZSpeed > prevXZSpeed then

        local ySpeed = velocity.y
        velocity.y = 0
        velocity:Scale(prevXZSpeed / newXZSpeed)
        velocity.y = ySpeed

    end

end

local function NotifyWorldCollision(self, averageSurfaceNormal, oldVelocity, velocity)

    -- (-normal . velocity) without creating the negated vector
    local impactForce = math.max(0, -averageSurfaceNormal:DotProduct(oldVelocity))
    self:OnWorldCollision(averageSurfaceNormal, impactForce, velocity)

end

--
-- Moves by the player by the specified offset, colliding and sliding with the world.
--
function ControllerMixin:PerformMovement(o, maxTraces, velocity, isMove, slowDownFraction, deflectMove, slowDownFilterFunc, deltaTime)

    PROFILE("ControllerMixin:PerformMovement")

    if isMove == nil then
        isMove = true
    end

    if deflectMove == nil then
        deflectMove = false
    end

    slowDownFraction = GetSlowDownFraction(slowDownFraction, deltaTime)

    local oldVelocity = nil

    if velocity then
        VectorCopy(velocity, self.moveVelocity)
        oldVelocity = self.moveVelocity
    end

    local hitEntities
    local completedMove = true
    local averageSurfaceNormal
    local surfaceMaterial
    local prevXZSpeed = nil

    if self.controller then
        completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial =
            MoveController(self, o, maxTraces, velocity, slowDownFraction, isMove)

        -- The velocity is only changed by a hit, so the speed before the move is only needed
        -- then (taken before the hit callbacks below can run).
        if not completedMove and oldVelocity and not deflectMove then
            prevXZSpeed = oldVelocity:GetLengthXZ()
        end
    end

    -- Do the hit callbacks. (but not if we do the blank one to nornalize, isMove would be set to "1")
    if hitEntities and isMove then
        NotifyTraceHits(self, hitEntities)
    end

    if prevXZSpeed then
        ClampXZSpeedGain(velocity, prevXZSpeed)
    end

    if averageSurfaceNormal and averageSurfaceNormal:GetLength() > 0 then
        averageSurfaceNormal:Normalize()
    end

    -- TODO: dont compare velocities, use some boolean
    -- averageSurfaceNormal should not normally be nil at this point but there is an edge
    -- case where it is.
    if oldVelocity ~= velocity and isMove and averageSurfaceNormal and self.OnWorldCollision then
        NotifyWorldCollision(self, averageSurfaceNormal, oldVelocity, velocity)
    end

    return completedMove, hitEntities, averageSurfaceNormal, surfaceMaterial
end
