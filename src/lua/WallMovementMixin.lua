-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\WallMovementMixin.lua
--
--    Created by:   Mats Olsson (mats.olsson@matsotech.se)
--
-- Contains shared code used by Skulk to walk on walls and Lerks to grip walls.
--
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

--
-- WallMovementMixin handles processing attack orders.
--
WallMovementMixin = CreateMixin(WallMovementMixin)
WallMovementMixin.type = "WallMovement"

WallMovementMixin.expectedMixins =
{
}

if Server then

    WallMovementMixin.expectedCallbacks =
    {
    }

end

WallMovementMixin.expectedConstants =
{
}

WallMovementMixin.networkVars =
{
}

local Shared_TraceRay = Shared.TraceRay
local Shared_TraceCapsule = Shared.TraceCapsule

local math_pi = math.pi

local kNumTraces = 8

local kTraceCache_flatdisc = {}
local kTraceCache_diagcone = {}

local function _initTracesTables()
    for i = 0, kNumTraces - 1 do
        local angle = ((i * 360/kNumTraces) / 360) * math_pi * 2
        local directionVector = Vector(math.cos(angle), 0, math.sin(angle))
        table.insert(kTraceCache_flatdisc, directionVector)
    end

   for i=0, kNumTraces - 1 do
        local theta = (i/kNumTraces) * math_pi * 2
        directionVector = Vector(math.cos(theta), 1, math.sin(theta))
        table.insert(kTraceCache_diagcone, directionVector)
    end
end
_initTracesTables()

function WallMovementMixin:__initmixin()
    
    PROFILE("WallMovementMixin:__initmixin")
    
    self.smoothedYaw = self.viewYaw
end

--
-- Smooth the currentNormal towards the goalNormal with the given fraction.
-- Returns goalNormal if fraction >= 1
--
function WallMovementMixin:SmoothWallNormal(currentNormal, goalNormal, fraction)
    local result = goalNormal
    
    if fraction < 1 then
        local diff = goalNormal:DotProduct(currentNormal)
        
        -- if we are "close enough", we make them equal - stop float rounding from eating bandwidth
        if diff < 0.98 then
 
            -- Smooth out the normal.
            local normalDiff = goalNormal - currentNormal
            
            -- Check if the vectors are polar opposites.
            if diff == -1 then
            
                -- Prefer spinning around the x axis.
                if self:GetCoords().xAxis:DotProduct(goalNormal) ~= -1 then
                    normalDiff = goalNormal - self:GetCoords().xAxis
                else
                    normalDiff = goalNormal - currentNormal:GetPerpendicular()
                end
                
            end

            result = currentNormal + normalDiff * fraction
        end
    end

    if result:Normalize() < 0.01 then
        result = Vector(0, 1, 0)  
    end
    
    return result
end

function WallMovementMixin:GetAnglesFromWallNormal(normal)

    PROFILE("WallMovementMixin:GetAnglesFromWallNormal")

    -- Use the wall normal as Y, and try to point Z according to the view
    local c = Coords()
    c.yAxis = normal
    c.zAxis = self:GetViewAngles():GetCoords().zAxis
    c.xAxis = c.yAxis:CrossProduct(c.zAxis)

    if c.xAxis:Normalize() < 0.001 then
        
        -- Can't really find a good coords, so just keep the previous one
        return nil

    else

        c.zAxis = c.xAxis:CrossProduct( c.yAxis )

        --DebugDrawAxes( c, self:GetOrigin(), 5.0, 0.5, 0.0 )

        local angles = Angles()
        angles:BuildFromCoords(c)
        return angles

    end

end

function WallMovementMixin:ValidWallTrace(trace)

    if trace.fraction > 0 and trace.fraction < 1 and trace.surface ~= "nocling" then
        local entity = trace.entity
        local entityClingable = entity and (entity.GetIsWallWalkingAllowed and entity:GetIsWallWalkingAllowed(self))
        return not entity or entityClingable
    end
    return false
    
end

function WallMovementMixin:TraceWallNormal(startPoint, endPoint, result, feelerSize, physicsMask)
    
    local theTrace = Shared_TraceCapsule(startPoint, endPoint, feelerSize, 0, CollisionRep.Move, physicsMask, EntityFilterOneAndIsa(self, "Babbler"))
    
    --Debug_VisualizeCapsuleTrace(startPoint, endPoint, feelerSize, 0, theTrace.fraction)
    
    --[[ double-comment to see wall-walk traces
    if Client then
        DebugLine(startPoint, theTrace.endPoint, 5, 0, 1, 0, 1)
    end --]]
    
    if self:ValidWallTrace(theTrace) then
   
        table.insert(result, theTrace.normal)
        return true
        
    end
    
    return false
    
end

--
-- Returns the average normal within wall-walking range. Perform 8 trace lines in circle around us and 1 above us, but not below.
-- Returns nil if we aren't in range of a valid wall-walking surface.  For any surfaces hit, remember surface normal and average
-- with others hit so we know if we're wall-walking and the normal to orient our model and the direction to jump away from
-- when jumping off a wall.
--
--local numHit = 0
--local numCalls = 0
--local numHitDisc = 0
--local numHitAbove = 0
--local numHit45 = 0
function WallMovementMixin:GetAverageWallWalkingNormal(extraRange, feelerSize, physicsMaskOverride)

    PROFILE("WallMovementMixin:GetAverageWallWalkingNormal")

    --local client = self.GetClient and self:GetClient()
    --if client and client:GetIsVirtual() then
    --    return nil
    --end
    
    --Debug_ClearTraceVis()

    local physicsMask = ConditionalValue(physicsMaskOverride ~= nil, physicsMaskOverride, PhysicsMask.AllButPCs)
    
    local startPoint = Vector(self:GetOrigin())
    local extents = self:GetExtents()
    startPoint.y = startPoint.y + extents.y
    local wallNormals = {}

    -- Trace in a circle around self, looking for walls we hit
    local wallWalkingRange = math.max(extents.x, extents.y) + extraRange
    local directionVector
    local angle
    local normalFound = false

    --numCalls = numCalls + 1
    if (self.lastSuccessfullWallTraceDir) then
        directionVector = self.lastSuccessfullWallTraceDir
        if self:TraceWallNormal(startPoint, startPoint + self.lastSuccessfullWallTraceDir * wallWalkingRange, wallNormals, feelerSize, physicsMask) then
            normalFound = true
            --numHit = numHit + 1
        else
            self.lastSuccessfullWallTraceDir = nil
        end
    end

    -- Trace around (flat disc)
    if not normalFound then
        for i = 1, kNumTraces do
        
            directionVector = kTraceCache_flatdisc[i]
            
            -- Avoid excess vector creation
            local endPoint = Vector()
            endPoint.x = startPoint.x + directionVector.x * wallWalkingRange
            endPoint.y = startPoint.y
            endPoint.z = startPoint.z + directionVector.z * wallWalkingRange
            
            if self:TraceWallNormal(startPoint, endPoint, wallNormals, feelerSize, physicsMask) then

                normalFound = true
                --numHitDisc = numHitDisc + 1
                break
                
            end   
            
        end
    
    end

    -- Trace above too.
    if not normalFound then
        directionVector = Vector(0, wallWalkingRange, 0)
        normalFound = self:TraceWallNormal(startPoint, startPoint + directionVector, wallNormals, feelerSize, physicsMask)
        --if (normalFound) then
        --    numHitAbove = numHitAbove + 1
        --end
    end
    
    -- Trace in a 45 degree cone around skulk.  Like halfway between vertical and the flat disc we did above.
    if not normalFound then
        for i=1, kNumTraces do
            directionVector = kTraceCache_diagcone[i]
            normalFound = self:TraceWallNormal(startPoint, startPoint + directionVector * wallWalkingRange * 0.707, wallNormals, feelerSize, physicsMask)
            if normalFound then
                --numHit45 = numHit45 + 1
                break
            end
        end
    end

    if normalFound then

        --if Server then Log("%s/%s -- %s/%s/%s", numHit, numCalls, numHitDisc, numHitAbove, numHit45) end
    
        -- Check if we are right above a surface we can stand on.
        -- Even if we are in "wall walking mode", we want it to look
        -- like it is standing on a surface if it is right above it.
        self.lastSuccessfullWallTraceDir = directionVector
        local groundTrace = Shared_TraceRay(startPoint, startPoint + Vector(0, -wallWalkingRange, 0), CollisionRep.Move, physicsMask, EntityFilterOne(self))
        if (groundTrace.fraction > 0 and groundTrace.fraction < 1 and groundTrace.entity == nil) then
            return groundTrace.normal
        end
        
        local rval = wallNormals[1]
        wallNormals = nil
        return rval
        
    end

    return nil
    
end

function WallMovementMixin:OnAdjustModelCoords(modelCoords)

    local offset = self:GetExtents().y

    -- Make the model rotate around the center point rather than the feet
    -- when we're walking on walls.

    modelCoords.origin = modelCoords.origin - modelCoords.yAxis * offset
    modelCoords.origin.y = modelCoords.origin.y + offset
            
    return modelCoords
    
end


