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
local AddScaled3 = VectorMath.AddScaled3

local kNumTraces = 8

local kWallTraceCacheDuration = 0.25

-- The scan order. Index 1..8 is a flat disc around the body, 9 is straight up and 10..17 is a
-- 45 degree cone between the disc and "up". Never straight down. The first direction that hits
-- a valid surface wins, so the order matters (walls before ceilings).
--
-- Directions are kept as plain numbers (dirX, dirY, dirZ) with a range scale, and the end
-- point of a trace is built with Vector(AddScaled3(...)): one Vector per trace instead of
-- two temporaries.
local kUpIndex = kNumTraces + 1
local kNumScanTraces = kNumTraces * 2 + 1

local kScanDirX, kScanDirY, kScanDirZ, kScanRangeScale = {}, {}, {}, {}

local function _initTracesTables()

    for i = 0, kNumTraces - 1 do
        local angle = ((i * 360/kNumTraces) / 360) * math_pi * 2
        kScanDirX[i + 1] = math.cos(angle)
        kScanDirY[i + 1] = 0
        kScanDirZ[i + 1] = math.sin(angle)
        kScanRangeScale[i + 1] = 1
    end

    kScanDirX[kUpIndex], kScanDirY[kUpIndex], kScanDirZ[kUpIndex] = 0, 1, 0
    kScanRangeScale[kUpIndex] = 1

    for i = 0, kNumTraces - 1 do
        local theta = (i/kNumTraces) * math_pi * 2
        local index = kUpIndex + 1 + i
        kScanDirX[index] = math.cos(theta)
        kScanDirY[index] = 1
        kScanDirZ[index] = math.sin(theta)
        kScanRangeScale[index] = 0.707
    end

end
_initTracesTables()

-- End point of scan trace 'index' starting at (sx, sy, sz)
local function GetScanEndPoint(index, sx, sy, sz, range)
    return Vector(AddScaled3(sx, sy, sz, kScanDirX[index], kScanDirY[index], kScanDirZ[index], range * kScanRangeScale[index]))
end

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
            if diff <= -0.999 then
            
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

function WallMovementMixin:TraceWallNormal(startPoint, endPoint, feelerSize, physicsMask, filter)

    local theTrace = Shared_TraceCapsule(startPoint, endPoint, feelerSize, 0, CollisionRep.Move, physicsMask, filter or EntityFilterOneAndIsa(self, "Babbler"))

    if self:ValidWallTrace(theTrace) then
        return theTrace.normal
    end

    return nil
end

--
-- Returns the normal of the surface we can wall walk on, or nil if we aren't in range of a valid
-- wall-walking surface. 8 traces in a circle around us, 1 above us and 8 in a 45 degree cone
-- (see the scan order above), but none below. The first one that hits wins. The normal is used
-- to orient our model and as the direction to jump away from when jumping off a wall.
--
-- We are very likely still on the same surface as at the previous call, so the index of the
-- trace that hit is remembered and retraced first. When that still hits the other 16 traces
-- are skipped. A full scan is forced after kWallTraceCacheDuration, and whenever the cached
-- trace misses (the one that missed is not traced a second time).
--
-- The remembered index is kept per physics mask: Skulk calls this with different masks for
-- wall walking and for the wall jump check, and they must not overwrite each other's entry.
--

function WallMovementMixin:GetAverageWallWalkingNormal(extraRange, feelerSize, physicsMaskOverride)

    PROFILE("WallMovementMixin:GetAverageWallWalkingNormal")

    --local client = self.GetClient and self:GetClient()
    --if client and client:GetIsVirtual() then
    --    return nil
    --end
    
    --Debug_ClearTraceVis()

    local physicsMask = ConditionalValue(physicsMaskOverride ~= nil, physicsMaskOverride, PhysicsMask.AllButPCs)
    
    local origin = self:GetOrigin()
    local extents = self:GetExtents()
    local extentX, extentY = extents.x, extents.y
    local sx, sy, sz = origin.x, origin.y + extentY, origin.z
    local startPoint = Vector(sx, sy, sz)

    -- Trace range: largest horizontal/vertical extent plus caller-provided extra.
    local wallWalkingRange = (extentX > extentY and extentX or extentY) + extraRange

    local filter = self.wallTraceFilter
    if not filter then
        filter = EntityFilterOneAndIsa(self, "Babbler")
        self.wallTraceFilter = filter
    end

    local wallNormal = nil
    local hitIndex = nil
    local missedIndex = nil
    local now = Shared.GetTime()

    -- Cached: retrace the direction that hit last time while the cache is still fresh.
    local caches = self.wallTraceCaches
    if not caches then
        caches = {}
        self.wallTraceCaches = caches
    end

    local cache = caches[physicsMask]
    if not cache then
        cache = { index = nil, time = 0 }
        caches[physicsMask] = cache
    end

    local cachedIndex = cache.index
    if cachedIndex then

        local age = now - cache.time
        if age >= 0 and age < kWallTraceCacheDuration then

            wallNormal = self:TraceWallNormal(startPoint, GetScanEndPoint(cachedIndex, sx, sy, sz, wallWalkingRange), feelerSize, physicsMask, filter)
            if wallNormal then
                hitIndex = cachedIndex
            else
                missedIndex = cachedIndex
            end

        end

    end

    -- Full scan, in the original order. Skips what was just traced above and missed.
    local fullScan = not wallNormal
    if fullScan then

        for i = 1, kNumScanTraces do

            if i ~= missedIndex then
                wallNormal = self:TraceWallNormal(startPoint, GetScanEndPoint(i, sx, sy, sz, wallWalkingRange), feelerSize, physicsMask, filter)
                if wallNormal then
                    hitIndex = i
                    break
                end
            end

        end

    end

    if wallNormal then

        -- Remember the direction that hit. Only a full scan refreshes the timestamp, so the
        -- cache is always re-validated by a full scan within kWallTraceCacheDuration.
        if fullScan then
            cache.index = hitIndex
            cache.time = now
        end

        -- Check if we are right above a surface we can stand on.
        -- Even if we are in "wall walking mode", we want it to look
        -- like it is standing on a surface if it is right above it.
        local groundFilter = self.wallTraceGroundFilter
        if not groundFilter then
            groundFilter = EntityFilterOne(self)
            self.wallTraceGroundFilter = groundFilter
        end

        local groundTrace = Shared_TraceRay(startPoint, Vector(sx, sy - wallWalkingRange, sz), CollisionRep.Move, physicsMask, groundFilter)
        if groundTrace.fraction > 0 and groundTrace.fraction < 1 and groundTrace.entity == nil then
            return groundTrace.normal
        end

        return wallNormal

    end

    -- Nothing in range: nothing to retrace next time
    cache.index = nil
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
