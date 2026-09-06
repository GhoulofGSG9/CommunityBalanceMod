-- ======= Copyright (c) 2003-2022, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua/bots/LocationGraph.lua
--
-- Created by: Darrell Gentry (darrell@unkownworlds.com)
--
-- Has all direct paths from any location (grouped by name)
-- Should be loaded on OnMapPostLoad
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

assert(Server, "LocationGraph.lua should be loaded on Server only!")

Script.Load("lua/IterableDict.lua")
Script.Load("lua/UnorderedSet.lua")

---@type LocationGraph
local kLocationGraphInstance
function GetLocationGraph()
    if not kLocationGraphInstance then
        kLocationGraphInstance = LocationGraph()
        kLocationGraphInstance:Initialize()
    end
    return kLocationGraphInstance
end

---@class LocationGraph
LocationGraph = nil

class "LocationGraph"

local function TryNudgeFindPoint(point, dist, scans, step)
    assert(point)

    --type check and range clamp
    dist = ( not dist ) and 2 or math.abs(dist)
    scans = ( not scans ) and 1 or math.abs(scans)
    step = ( not step ) and 0 or math.abs(step)

    if not dist then
        dist = 2
    else
        dist = math.abs(dist)
    end

    local samples = {}
    for i = 1, scans do
        local stepDist = dist + step * i

        local nudges =  --CUUUUuuuuubbbbess!
        {
            --NSEW,Up,Down
            Vector(0,0,stepDist),
            Vector(0,0,-stepDist),
            Vector(-stepDist,0,0),
            Vector(stepDist,0,0),
            Vector(0,stepDist,0),
            Vector(0,-stepDist,0),

            Vector(-stepDist,stepDist,stepDist),   --Fwd-up-left
            Vector(stepDist,stepDist,stepDist),   --Fwd-up-right
            Vector(-stepDist,stepDist,-stepDist),   --back-up-left
            Vector(stepDist,stepDist,-stepDist),   --back-up-right

            Vector(-stepDist,-stepDist,stepDist),   --Fwd-down-left
            Vector(stepDist,-stepDist,stepDist),   --Fwd-down-right
            Vector(-stepDist,-stepDist,-stepDist),   --back-down-left
            Vector(stepDist,-stepDist,-stepDist),   --back-down-right
        }

        for n = 1, #nudges do
            local samp = Vector(point + nudges[n])
            local v = Pathing.GetClosestPoint(samp)
            if v ~= samp then
                table.insert(samples, v)
            end
        end
    end

    if #samples > 0 then
        --sort by shortest distance to original Point
        table.sort(samples, function(a, b)
            if a and b then
                local aV = Vector(a - point)
                local bV = Vector(b - point)
                return bV:GetLength() > aV:GetLength()
            else
                return a
            end
        end)

        --Print("\n Nudge Samples for [%s]\n%s\n", ToString(point), ToString(samples))
        --[[
        Print("Distance Table:\n")
        for v = 1, #samples do
            Print("\t\t\t [%s]\n", Vector(samples[v] - point):GetLength() )
        end
        --]]

        return samples[1]   --nearest
    end

    return point    --fail-over
end

function LocationGraph:Initialize()
    PROFILE("LocationGraph:Initialize")

    -- Location Name (From) -> UnorderedSet of directly connected location names (Destinations)
    self.locationDirectPaths = IterableDict()

    -- Location Name (Source) -> IterableDict (Directly Connected Location -> Gateway point)
    self.locationGateways = IterableDict()

    -- Location Name -> Position of center of location group (location entities of same name)
    self.locationCentroids = IterableDict()

    -- <Start Location>_<Dest Location> -> Distance between gateways
    -- A->B == B->A
    self.locationGatewayDistances = IterableDict()

    -- Location Name -> Position to go to for exploring
    self.locationExplorePositions = IterableDict()

    -- Location Names
    self.techPointLocations = UnorderedSet()

    -- Can also be tech point locations
    self.resourcePointLocations = UnorderedSet()

    -- TechPoint Location Name -> UnorderedSet<Natural RT Locations>
    self.techPointLocationsNaturals = IterableDict()

    -- Location Name -> Table of data for determining "safer" building placements
    self.techPointsSafePlacementData = IterableDict()

    -- Location Name (As Starting Point) -> IterableDict (Location Name -> Depth from starting point)
    self.exploreDepths = IterableDict()

    -- Location Name (From) -> UnorderedSet of increasing paths.
    -- Set key (path): <source>_<dest>
    -- Increasing path is where the dest location has a connection that is also deeper than the dest.
    self.increasingPaths = IterableDict()

    if #GetLocations() > 0 then

        -- In some cases maps may not have a valid map entity to use as an explore pos. (tutorials, challenges, custom modes, etc)
        -- If so, then we use the centroid of location entities as a fallback.
        self:InitializeLocationCentroids() -- 0

        self:InitializeExplorePositions()  -- 1
        self:InitializeDirectPaths()       -- 2
        self:InitializeGatewayDistances()  -- 3
        self:InitializeExploreDepths()     -- 4
        self:InitializeIncreasingPaths()   -- 5
        self:InitializeTechpointNaturalRTLocations()

    else

        Print("Warning: No location entities on map! LocationGraph will be empty, and bots won't work!")

    end

end

-- Tries to find a general area in which commander bots can
-- place important structures that need hiding, or some protection via geo
-- Example: Placing Spur upgrades behind hive, away from prying eyes, etc
function LocationGraph:InitializeTechPointSpawnData()
    PROFILE("LocationGraph:InitializeTechPointSpawnData")

    Log("$ InitializeTechPointSpawnData")

    local allTechPoints = GetEntities("TechPoint")
    for _, techpointEnt in ipairs(allTechPoints) do

        local techPointLocationName = techpointEnt:GetLocationName()
        if techPointLocationName and techPointLocationName ~= "" then

            Log("\tLocation: %s", techPointLocationName)

            local searchStartPoint = techpointEnt:GetOrigin() + Vector(0,1,0)

            -- Get directional vectors to every gateway between our starting techpoint and neighboring rooms
            local neighborLocations = self:GetDirectPathsForLocationName(techPointLocationName)
            local gatewayDirections = {}
            for i = 1, #neighborLocations do
                local gatewayPos = Vector(self.locationGateways[techPointLocationName][neighborLocations[i]])
                assert(gatewayPos, "Missing Gateway in InitializeTechPointSpawnData")

                --DebugLine(searchStartPoint, gatewayPos, 500, 1,0,1,1)

                gatewayPos.y = searchStartPoint.y

                local gatewayAwayDir = (searchStartPoint - gatewayPos):GetUnit()
                --DebugLine(searchStartPoint, searchStartPoint + (gatewayAwayDir * 10), 500, 1,1,0,1)
                table.insert(gatewayDirections, gatewayAwayDir)
            end

            -- Find the "bias direction", which is the average direction AWAY from location gateways to
            -- neighboring locations
            local biasDirection
            local numGateways = #gatewayDirections

            if numGateways <= 0 then -- None! No data will be filled out.

            elseif numGateways == 1 then -- Dead-end, should be very rare
                biasDirection = gatewayDirections[1]
            elseif numGateways >= 2 then

                local gatewayDirSum = Vector(0,0,0)
                for i, gatewayDir in ipairs(gatewayDirections) do
                    gatewayDirSum = gatewayDirSum + gatewayDir
                end

                biasDirection = (gatewayDirSum / numGateways):GetUnit()

            end

            Log("\t\tBias Direction: %s", biasDirection)

            -- We only fill data if the location is not just a singular room floating in space with no other connections (test map?)
            if biasDirection then

                DebugLine(searchStartPoint, searchStartPoint + (biasDirection * 10), 500, 1,1,1,1)

                local placementData =
                {
                    isEnclosed = false,
                    enclosureAngles = { startAngle = nil, endAngle = nil },
                    enclosureDist = 0,
                    biasDirection = biasDirection, -- Fallback, if we don't have an enclosure
                }

                self.techPointsSafePlacementData[techPointLocationName] = placementData

                -- Now trace a certain distance out from our searchStartPoint, every X degrees
                -- to try and find out if we are in an enclosure
                local kMaxEnclosureTraceDist = math.min(18, kHiveInfestationRadius)
                local kXZPlaneTrace_DTheta = math.rad(5)
                local kEnclosureTolerance = 15 -- meters to tolerate trace distances for "enclosed"
                local kMinThetaForEnclosure = math.pi/2

                local enclosedPartitions = {}

                local isCurrentPartitionEnclosed = false

                -- Keep track of for "tolerance"
                local lastPartitionTraceDist

                -- Partition Results
                local partitionStartAngle
                local partitionStartAngleTraceDist
                local minEnclosureDist = math.huge

                -- Find enclosed paritions around the tech point
                for theta = 0, 2*math.pi, kXZPlaneTrace_DTheta do

                    -- Geo-trace the current angle
                    local traceStart = searchStartPoint
                    local traceDir = Vector(math.cos(theta), 0, math.sin(theta))
                    local traceEnd = traceStart + (traceDir * kMaxEnclosureTraceDist)
                    local trace = Shared.TraceRay(traceStart, traceEnd, CollisionRep.Damage, PhysicsMask.AIEnclosure)

                    local traceDist = trace.fraction * kMaxEnclosureTraceDist
                    local isTraceIntolerable = isCurrentPartitionEnclosed and traceDist > lastPartitionTraceDist + kEnclosureTolerance
                    if trace.fraction >= 1 or isTraceIntolerable then -- We hit nothing, this trace is not enclosed!

                        local traceDebugEnd = (traceEnd - traceStart) * trace.fraction
                        DebugLine(traceStart, traceStart + traceDebugEnd, 500, 0.25, 0, 0, 1)

                        if isCurrentPartitionEnclosed then -- End "enclosed" partition

                            if theta - partitionStartAngle > kMinThetaForEnclosure then

                                table.insert(enclosedPartitions,
                                {
                                    startAngle = partitionStartAngle,
                                    startAngleDist = partitionStartAngleTraceDist,
                                    endAngle = theta,
                                    endAngleDist = traceDist,
                                    minRadius = minEnclosureDist
                                })

                            end

                            isCurrentPartitionEnclosed = false

                        end

                    else -- We hit something!

                        local traceDebugEnd = (traceEnd - traceStart) * trace.fraction
                        DebugLine(traceStart, traceStart + traceDebugEnd, 500, 0, 0.25, 0, 1)

                        if not isCurrentPartitionEnclosed then -- New enclosed parition!
                            partitionStartAngle = theta
                            partitionStartAngleTraceDist = traceDist
                            isCurrentPartitionEnclosed = true
                        end

                        minEnclosureDist = math.min(minEnclosureDist, traceDist)
                        lastPartitionTraceDist = traceDist
                    end

                end

                Log("\t\t#Enclosed Partitions: %s", #enclosedPartitions)

                -- Try to find the best enclosed parition
                -- i.e, one that FACES the gateways (wall between hive enclosure and gateway average)
                if #enclosedPartitions > 0 then

                    local desiredEnclosureDirection = biasDirection
                    local preferredEnclosedPartition
                    for i, partition in ipairs(enclosedPartitions) do

                        Log("\t\tPartition (%s)", i)
                        Log("\t\t%s", partition)

                        local startEncDir = Vector(math.cos(partition.startAngle), 0, math.sin(partition.startAngle))
                        DebugLine(searchStartPoint, searchStartPoint + (startEncDir * partition.startAngleDist), 500, 0, 1, 0, 1)

                        local endEncDir = Vector(math.cos(partition.endAngle), 0, math.sin(partition.endAngle))
                        DebugLine(searchStartPoint, searchStartPoint + (endEncDir * partition.endAngleDist), 500, 1, 0, 0, 1)

                        local desiredAngle = GetAngleBetweenVectors(Vector.xAxis, desiredEnclosureDirection)
                        if not preferredEnclosedPartition and desiredAngle >= partition.startAngle and desiredAngle <= partition.endAngle then
                            preferredEnclosedPartition = partition
                        end

                    end

                    if preferredEnclosedPartition then
                        placementData.isEnclosed = true
                        placementData.enclosureAngles = preferredEnclosedPartition
                        placementData.enclosureDist = minEnclosureDist
                        DebugCircle(searchStartPoint, preferredEnclosedPartition.minRadius, Vector(0,1,0), 500, 1,0,1,1)
                    end
                end
            end
        end
    end
end

function LocationGraph:InitializeLocationCentroids()

    local locations = GetLocations()
    assert(#locations > 0, "|ERROR|: No Location entities in map")

    local namedLocs = {}

    --Build unique name list, for sorting/lookup later
    for i = 1, #locations do
        if not table.icontains( namedLocs, locations[i]:GetName() ) then
            table.insert( namedLocs, locations[i]:GetName() )
        end
    end

    --We build a list that denotes the Center of all collective
    --Named location entity volumes. The ensures points for sampling
    --Location to Location are always within each _gameplay_ Location
    for i = 1, #namedLocs do
        local name = namedLocs[i]

        local locs = {}
        for t = 1, #locations do
            if locations[t]:GetName() == name then
                table.insert(locs, locations[t])
            end
        end

        local tmpCent = Vector(0,0,0)
        for c = 1, #locs do
            local org = locs[c]:GetOrigin()
            tmpCent.x = tmpCent.x + org.x
            tmpCent.y = 0.0    --tmpCent.y + org.y  --Note: some Location volumes have ABSURD heights, normalize them
            tmpCent.z = tmpCent.z + org.z
        end

        --Note: this is mean'd, so it will skew towards density
        local namedCenter = Vector(0,0,0)
        namedCenter.x = tmpCent.x / #locs
        namedCenter.y = tmpCent.y / #locs
        namedCenter.z = tmpCent.z / #locs

        --Note: this can potentially throw gameCenter into another Location
        local gameCenter = TryNudgeFindPoint(namedCenter, 0.1, 250, 0.15)  --transform to playable space, ideally. But this is not a gaurantee...
        if gameCenter == namedCenter then
            --Print("\t\t |INFO|: Location[%s] centroid not clost to nav-mesh", name)
        end

        gameCenter.y = gameCenter.y + 0.25  --tiny offset to nudge above floors (usually)

        --Print("\t [%s] centered at: (%s, %s, %s)", name, gameCenter.x, gameCenter.y, gameCenter.z)

        if not self.locationCentroids[name] then
            self.locationCentroids[name] = Vector(gameCenter) --copy to new memory
        end
    end

end

function LocationGraph:GetGatewayDistance(fromLocationName, toLocationName)
    local aKey = string.format("%s_%s", fromLocationName, toLocationName)
    local bKey = string.format("%s_%s", toLocationName, fromLocationName)
    return self.locationGatewayDistances[aKey] or self.locationGatewayDistances[bKey]
end

-- Location Gateways are the points between two named location entity volumes.
-- Used for bot related stuff, i.e. distance calculations
function LocationGraph:InitializeGatewayDistances()
    PROFILE("LocationGraph:InitializeGatewayDistances")

    local processed = UnorderedSet()

    for locationName, locationGatewaysDict in pairs(self.locationGateways) do

        -- Find shortest path to other locations, even ones that are not directly connected
        for destLocationName, destLocationGatewaysDict in pairs(self.locationGateways) do

            local gatewayDistKey = string.format("%s_%s", locationName, destLocationName)
            local otherGatewayDistKey = string.format("%s_%s", destLocationName, locationName)
            if locationName ~= destLocationName and
                not processed:Contains(gatewayDistKey) and
                not processed:Contains(otherGatewayDistKey) then

                -- Now we have two different locations, test all possible gateway combinations (1 per location)
                -- and find the shortest path.

                local shortestGatewayDistance
                local shortestEnterPos
                local shortestExitPos
                local shortestPath

                for _, startGatewayPos in pairs(locationGatewaysDict) do
                    for _, destGatewayPos in pairs(destLocationGatewaysDict) do

                        local pathPoints = PointArray()
                        local reachable = Pathing.GetPathPoints(startGatewayPos, destGatewayPos, pathPoints)
                        assert(reachable, "Path was not reachable!")

                        local pathDist = GetPointDistance(pathPoints)
                        if not shortestGatewayDistance or pathDist < shortestGatewayDistance then
                            shortestGatewayDistance = pathDist
                            shortestEnterPos = startGatewayPos
                            shortestExitPos = destGatewayPos
                            shortestPath = pathPoints
                        end

                    end
                end

                if shortestGatewayDistance then
                    local resultTable = { distance = shortestGatewayDistance, enterGatePos = shortestEnterPos, exitGatePos = shortestExitPos, path = shortestPath }
                    local otherResultTable = { distance = shortestGatewayDistance, enterGatePos = shortestExitPos, exitGatePos = shortestEnterPos, path = shortestPath }
                    self.locationGatewayDistances[gatewayDistKey] = resultTable
                    self.locationGatewayDistances[otherGatewayDistKey] = otherResultTable
                    processed:Add(gatewayDistKey)
                    processed:Add(otherGatewayDistKey)
                end

            end
        end

    end

end

function LocationGraph:GetTechpointLocations()
    return self.techPointLocations
end

function LocationGraph:GetIsLocationAStartPoint(locationName)
    return self.techPointLocations:Contains(locationName)
end

function LocationGraph:GetIsPathIncreasing(rootLocation, startLocation, destLocation)
    if not self.techPointLocations:Contains(rootLocation) then Log("WARNING: Rootlocation Invalid! %s", rootLocation) return end
    local pathName = string.format("%s:%s", startLocation, destLocation)
    return self.increasingPaths[rootLocation]:Contains(pathName)
end

function LocationGraph:InitializeIncreasingPaths()
    PROFILE("LocationGraph:InitializeIncreasingPaths")

    for i = 1, #self.techPointLocations do

        local techPointLocation = self.techPointLocations[i]
        if not self.increasingPaths[techPointLocation] then
            self.increasingPaths[techPointLocation] = UnorderedSet()
        end

        local checkedPaths = UnorderedSet()
        for sourceLocName, directPaths in pairs(self.locationDirectPaths) do

            local sourceDepth = self:GetDepthForExploreLocation(techPointLocation, sourceLocName)
            for j = 1, #directPaths do

                local destLocName = directPaths[j]
                local pathName = string.format("%s:%s", sourceLocName, destLocName)

                if not checkedPaths:Contains(pathName) then

                    checkedPaths:Add(pathName)
                    local destDepth = self:GetDepthForExploreLocation(techPointLocation, destLocName)

                    -- Make sure that the very next destination is in fact increasing depth
                    if destDepth > sourceDepth then
                        local destDirectPaths = self.locationDirectPaths[destLocName]
                        -- Finally, check if ANY path from that destination is still increasing... (save if yes)
                        for k = 1, #destDirectPaths do
                            local testLoc = destDirectPaths[k]
                            local testDepth = self:GetDepthForExploreLocation(techPointLocation, testLoc)
                            if testDepth >= destDepth then
                                self.increasingPaths[techPointLocation]:Add(pathName)
                                break
                            end
                        end

                    end
                end
            end
        end
    end
end

--- Gets all possible explore positions from given location name.
--- Creates a table so editing the returned table is safe.
function LocationGraph:GetAllExplorePointsFromLocationName(locationName)

    local result = {}
    local directLocations = self.locationDirectPaths[locationName]
    for i = 1, #directLocations do
        local explorePos = self:GetExplorePointForLocationName(directLocations[i])
        if explorePos then
            table.insert(result, Vector(explorePos))
        end
    end

    return result

end

function LocationGraph:GetDirectPathsForLocationName(locationName)
    return self.locationDirectPaths[locationName]
end

function LocationGraph:GetExplorePointForLocationName(locationName)
    return self.locationExplorePositions[locationName]
end

-- SourceLocationName is a techpoint location
function LocationGraph:GetDepthForExploreLocation(sourceLocationName, toLocationName)
    local depthsTable = self.exploreDepths[sourceLocationName]
    if not depthsTable then return nil end

    local depth = depthsTable[toLocationName] or 0

    return depth
end

function LocationGraph:GetNaturalRtsForTechpoint(techpointLocationName)
    return self.techPointLocationsNaturals[techpointLocationName]
end

-- Currently just the closest ResourcePoint having location (that is not a techpoint location)
function LocationGraph:InitializeTechpointNaturalRTLocations()
    PROFILE("LocationGraph:InitializeTechpointNaturalRTLocations")

    for i = 1, #self.techPointLocations do

        local techPointLocation = self.techPointLocations[i]

        local naturalLocationsSet = UnorderedSet()

        local locations = {}

        for i = 1, #self.resourcePointLocations do

            local rtLocation = self.resourcePointLocations[i]

            if rtLocation ~= techPointLocation --[[ not self.techPointLocations:Contains(rtLocation) ]] then

                local gatewayInfo = self:GetGatewayDistance(techPointLocation, rtLocation)

                if not gatewayInfo then
                    Log("LocationGraph: no traversal information between TechPoint %s and RT location %s. Bots will have reduced functionality.",
                        techPointLocation, rtLocation)
                else

                    -- Simple euclidean distance to handle locations that are adjacent to the techpoint
                    local dist = gatewayInfo.distance
                        + self:GetExplorePointForLocationName(techPointLocation):GetDistance(gatewayInfo.enterGatePos)
                        + self:GetExplorePointForLocationName(rtLocation):GetDistance(gatewayInfo.exitGatePos)

                    table.insert(locations, { rtLocation, dist })

                end

            end

        end

        table.sort(locations, function(a, b) return a[2] < b[2] end)

        -- if we don't have two natural RT locations we're running a dev map or a challenge map
        if #locations >= 2 then

            -- Closest two resource locations are considered naturals
            naturalLocationsSet:Add(locations[1][1])
            naturalLocationsSet:Add(locations[2][1])

        end

        self.techPointLocationsNaturals[techPointLocation] = naturalLocationsSet

    end

end

function LocationGraph:InitializeExplorePositions()
    PROFILE("LocationGraph:InitializeExplorePositions")

    -- Which entity class we should use over others.
    -- (Highest = use over others)
    local entityPriorityMap =
    {
        ["TechPoint"] = 3,
        ["ResourcePoint"] = 2,
        ["PowerPoint"] = 1,
    }

    local filterFunc = function(ent) return ent:isa("TechPoint") or ent:isa("ResourcePoint") or ent:isa("PowerPoint") end
    local relevantEnts = GetEntitiesWithFilter(Shared.GetEntitiesWithClassname("ScriptActor"), filterFunc)
    local locations = GetEntities("Location")
    local locationNamesPriorities = IterableDict()

    for i = 1, #locations do
        local location = locations[i]
        local locationName = location:GetName()
        locationNamesPriorities[locationName] = 0
    end

    for i = 1, #relevantEnts do

        local ent = relevantEnts[i]
        local entClassName = ent:GetClassName()
        local entPriority = entityPriorityMap[entClassName] or 0
        local entLocationName = ent:GetLocationName()
        local prevPriority = locationNamesPriorities[entLocationName] or 0

        -- Remember locations with tech points, they will be used as "start positions"
        -- for route blocking...
        if entClassName == "TechPoint" then
            self.techPointLocations:Add(entLocationName)
        elseif entClassName == "ResourcePoint" then
            self.resourcePointLocations:Add(entLocationName)
        end

        if entPriority > prevPriority then
            local resultPos = Pathing.GetClosestPoint(ent:GetOrigin())
            self.locationExplorePositions[entLocationName] = resultPos
            locationNamesPriorities[entLocationName] = entPriority
        end

    end

    -- In some cases, locations may not have any map entities... (tutorials, unfinished maps, etc)
    -- If so, we should
    for i = 1, #locations do
        local location = locations[i]
        local locationName = location:GetName()

        if not self.locationExplorePositions[locationName] then
            self.locationExplorePositions[locationName] = self.locationCentroids[locationName]
        end
    end

end

local function GetMidpointBetweenVectors(a, b)
    local midDiffVec = b - a
    midDiffVec.x = midDiffVec.x / 2
    midDiffVec.y = midDiffVec.y / 2
    midDiffVec.z = midDiffVec.z / 2

    return a + midDiffVec
end

local function EnsureGatewayDict(locGraph, sourceLocName, destLocName)
    if not locGraph.locationGateways[sourceLocName] then
        locGraph.locationGateways[sourceLocName] = IterableDict()
    end

    -- If A->B is traversable, then B->A is. Just use the first result for each case
    if not locGraph.locationGateways[destLocName] then
        locGraph.locationGateways[destLocName] = IterableDict()
    end
end

function LocationGraph:InitializeDirectPaths()
    PROFILE("LocationGraph:InitializeDirectPaths")

    for sourceLocationName, sourceExplorePos in pairs(self.locationExplorePositions) do

        if not self.locationDirectPaths[sourceLocationName] then
            self.locationDirectPaths[sourceLocationName] = UnorderedSet()
        end

        local directlyConnectedLocations = self.locationDirectPaths[sourceLocationName]

        -- Check every possible location group and it's explore position for direct paths. (test like complete k graph)
        for destLocationName, destExplorePos in pairs(self.locationExplorePositions) do

            if sourceLocationName ~= destLocationName then

                local pathPoints = PointArray()
                local reachable = Pathing.GetPathPoints(sourceExplorePos, destExplorePos, pathPoints)
                if reachable then

                    local isDirectPath = true
                    local firstPointLocName
                    local lastPointLocName

                    local locGateSource
                    local locGateDest

                    -- Check every point in the array. If any point is in a location that is not the source pos and is not the dest pos,
                    -- then it is not a direct path.
                    for i = 1, #pathPoints do

                        local pathPoint = pathPoints[i]
                        local pointLocation = GetLocationForPoint(pathPoint)
                        if pointLocation then

                            local pointLocationName = pointLocation:GetName()

                            if i == 1 then
                                firstPointLocName = pointLocationName
                            elseif i == #pathPoints then
                                lastPointLocName = pointLocationName
                            end

                            -- Find closest unmodified path points between the border of two locations
                            -- Source is last, so keep updating it.
                            -- Dest should be first, so only update once
                            if pointLocationName == sourceLocationName then
                                locGateSource = Vector(pathPoint)
                            elseif not locGateDest and pointLocationName == destLocationName then
                                locGateDest = Vector(pathPoint)
                            end

                            if (sourceLocationName ~= pointLocationName) and (destLocationName ~= pointLocationName) then
                                isDirectPath = false
                                break
                            end
                        end

                    end

                    local pathActuallyMakesSense = firstPointLocName == sourceLocationName and lastPointLocName == destLocationName
                    if isDirectPath and pathActuallyMakesSense then

                        directlyConnectedLocations:Add(destLocationName)

                        -- Try and get the most accurate point that is between the two locations
                        if locGateSource and locGateDest then

                            EnsureGatewayDict(self, sourceLocationName, destLocationName)

                            local kLocGatewayMaxDistance = 0.5
                            local initialDistanceVec = locGateDest - locGateSource
                            local initialDistance = initialDistanceVec:GetLength()

                            if self.locationGateways[destLocationName][sourceLocationName] then
                                -- If A->B is traversable, then B->A is. Just use the first result for each case
                                self.locationGateways[sourceLocationName][destLocationName] = self.locationGateways[destLocationName][sourceLocationName]
                            elseif initialDistance <= kLocGatewayMaxDistance then
                                -- The points are already valid, just get midpoint
                                self.locationGateways[sourceLocationName][destLocationName] = GetMidpointBetweenVectors(locGateSource, locGateDest)
                            else
                                local locGatewayDist = initialDistance
                                local locGateStart = locGateSource
                                local locGateEnd = locGateDest
                                local locGateResult = GetMidpointBetweenVectors(locGateStart, locGateEnd)
                                local maxSteps = 15 -- ...Should cover it, prolly too much
                                local curStep = 1
                                while locGatewayDist > kLocGatewayMaxDistance and curStep < maxSteps do

                                    curStep = curStep + 1
                                    local midPoint = GetMidpointBetweenVectors(locGateStart, locGateEnd)
                                    local midPointLocation = GetLocationForPoint(midPoint)

                                    -- If this point does not have a location, then screw it and get that midpoint, it's close enough
                                    if not midPointLocation then
                                        break
                                    else -- Try to close in on that perfect point
                                        local midPointLocationName = midPointLocation:GetName()
                                        if midPointLocationName == sourceLocationName then
                                            locGateStart = midPoint
                                        elseif midPointLocationName == destLocationName then
                                            locGateEnd = midPoint
                                        else
                                            Log("Warning: Midpoint location differs! < %s : %s > - %s", sourceLocationName, destLocationName, midPointLocationName)
                                            break
                                        end
                                    end

                                end -- End while

                                locGatewayDist = (locGateEnd - locGateStart):GetLength()
                                locGateResult = GetMidpointBetweenVectors(locGateStart, locGateEnd)

                                self.locationGateways[sourceLocationName][destLocationName] = locGateResult
                                self.locationGateways[destLocationName][sourceLocationName] = locGateResult

                            end

                        end
                    end
                end

            end

        end

    end

end

local function RecursiveBFS(self, rootLocationName, locationsByDepth, currentDepth)
    PROFILE("LocationGraph:RecursiveBFS")

    if not self.exploreDepths[rootLocationName] then
        self.exploreDepths[rootLocationName] = IterableDict()
    end

    local depthsTable = self.exploreDepths[rootLocationName]

    currentDepth = currentDepth + 1
    locationsByDepth[currentDepth] = locationsByDepth[currentDepth] or {}

    local parentLocations = locationsByDepth[currentDepth - 1]
    local thisDepthLocations = locationsByDepth[currentDepth]
    for i = 1, #parentLocations do
        local parentConnectedLocations = self.locationDirectPaths[parentLocations[i]]
        for j = 1, #parentConnectedLocations do
            local parentConnectedLocationName = parentConnectedLocations[j]
            if not depthsTable[parentConnectedLocationName] then
                depthsTable[parentConnectedLocationName] = currentDepth
                table.insert(thisDepthLocations, parentConnectedLocationName)
            end

        end

    end

    for i = 1, #thisDepthLocations do
        local connectedLocationName = thisDepthLocations[i]
        RecursiveBFS(self, rootLocationName, locationsByDepth, currentDepth)
    end

end

function LocationGraph:InitializeExploreDepths()
    PROFILE("LocationGraph:InitializeExploreDepths")

    -- Create a depth-graph for every possible starting point. (All locations with tech points)
    for i = 1, #self.techPointLocations do
        local rootLocation = self.techPointLocations[i]
        local locationsByDepth = {}
        local currentDepth = 0

        if not self.exploreDepths[rootLocation] then
            self.exploreDepths[rootLocation] = IterableDict()
        end

        self.exploreDepths[rootLocation][rootLocation] = currentDepth
        locationsByDepth[currentDepth] = locationsByDepth[currentDepth] or {}
        table.insert(locationsByDepth[currentDepth], rootLocation)

        RecursiveBFS(self, rootLocation, locationsByDepth, currentDepth)
    end

end

Event.Hook("Console_locgraph_place", function(client, ...)

    if not Shared.GetTestsEnabled() then
        Log("Tests are required for this command!")
    end

    GetLocationGraph():InitializeTechPointSpawnData()

end)

local function DrawPath(path)
    Log("Drawing %s points", #path)
    for i = 1, #path do
        DebugCapsule(path[i], path[i], 0.2, 0.2, 500, false)
    end
end

Event.Hook("Console_locgraph_naturals", function(client)

    if not Shared.GetTestsEnabled() then
        Log("Tests are required for this command!")
        return
    end

    -- LocationGraph:GetNaturalRtsForTechpoint(techpointLocationName)
    -- LocationGraph:GetTechpointLocations()

    local locGraph = GetLocationGraph()
    if not locGraph then
        Log("Could not get LocationGraph instance!")
        return
    end

    local techPointLocations = locGraph:GetTechpointLocations()
    for i = 1, #techPointLocations do
        local techPointLocation = techPointLocations[i]
        Log("\tTechpoint Location: %s", techPointLocation)
        local tpPos = locGraph:GetExplorePointForLocationName(techPointLocation)
        local naturalLocations = locGraph:GetNaturalRtsForTechpoint(techPointLocation)
        if naturalLocations then

            -- random color for each techpoint
            local r = math.random()
            local g = math.random()
            local b = math.random()

            -- Debug lines pointing from the techpoint (explore pos) to the natural rt explore pos
            for i = 1, #naturalLocations do
                Log("\t\tNatural Location: %s", naturalLocations[i])
                local naturalLoc = naturalLocations[i]
                local rtPos = locGraph:GetExplorePointForLocationName(naturalLoc)
                DebugLine(tpPos, rtPos, 500, r, g, b,1)
            end

        end
    end

end)

Event.Hook("Console_debug_locgraph", function(client, ...)

    if not Shared.GetTestsEnabled() then
        Log("Tests are required for this command!")
        return
    end

    local startLocationName = StringConcatArgs(...)

    Log("Putting boxes on AI explore positions... (cleardebuglines to remove)")
    Log("\tPassed Location Name: %s", startLocationName)

    local locGraph = GetLocationGraph()
    local startLoc = startLocationName and locGraph.techPointLocations:Contains(startLocationName) and locGraph.techPointLocations[locGraph.techPointLocations:GetIndex(startLocationName)]
    if not startLoc then
        startLoc = locGraph.techPointLocations[1]
    end

    Log("\tStart Location: %s", startLoc)
    local debugDrawLifetime = 600

    for locName, pos in pairs(locGraph.locationExplorePositions) do
        DebugBox(pos, pos + Vector(0, 6, 0), Vector(0.1, 0, 0.1), debugDrawLifetime, 1, 1, 1, 1)

        local lineOffset = Vector(0, 6, 0)
        local directPathsSet = locGraph.locationDirectPaths[locName]
        for i = 1, #directPathsSet do
            local destLocName = directPathsSet[i]
            local destExplorePoint = locGraph.locationExplorePositions[destLocName]
            DebugLine(pos + lineOffset, destExplorePoint + lineOffset, debugDrawLifetime, 1, 1, 1, 1)
        end

        if startLoc and locName ~= startLoc then
            local depth = locGraph:GetDepthForExploreLocation(startLoc, locName)
            for i = 1, depth do
                local radius = 0.25
                local sideOffset = (radius * 2 * i) + (radius / 4)
                local depthOffset = lineOffset + Vector(sideOffset, 1, 0)
                DebugCircle(pos + depthOffset, radius, Vector(0, 1, 0), debugDrawLifetime, 1, 1, 0, 1)
            end
        end

    end

    -- Visualize location gateways
    Log("\tLocation Gateways (%s)", locGraph.locationGateways:GetSize())
    for sourceLoc, destLocDict in pairs(locGraph.locationGateways) do
        for destLoc, gatewayPoint in pairs(destLocDict) do
            Log("\t\t'%s' -> '%s'", sourceLoc, destLoc)
            local gCoords = Coords()
            gCoords.origin = gatewayPoint
            gCoords.xAxis = Vector(1,0,0)
            gCoords.yAxis = Vector(0,1,0)
            gCoords.zAxis = Vector(0,0,1)
            DebugDrawAxes(gCoords, gCoords.origin, 0.5, debugDrawLifetime)
        end
    end

    -- Print out distances between gateways
    --Log("$ Gateway Distances (%s)", locGraph.locationGatewayDistances:GetSize())
    --for key, pathTable in pairs(locGraph.locationGatewayDistances) do
    --    Log("\t%s: %s (%s : %s)", key, pathTable.distance, pathTable.enterGatePos, pathTable.exitGatePos)
    --end

end)

Event.Hook("Console_debuggatewaypath", function(client, ...)

    if not Shared.GetCheatsEnabled() and not Shared.GetTestsEnabled() then
        Log("Requires Tests/Cheats")
        return
    end

    local path = StringConcatArgs(...)

    local locGraph = GetLocationGraph()
    if not path or not locGraph.locationGatewayDistances[path] then
        Log("%s does not exist", path)
        return
    end

    Log("Path Entered: %s", path)

    local pathTable = locGraph.locationGatewayDistances[path]
    DrawPath(pathTable.path)

end)

Event.Hook("Console_lg_paths", function(client)

    if not Shared.GetTestsEnabled() then
        Log("Tests are required for this command!")
        return
    end

    Log("Printing all paths...")

    local oneWayPaths = {}

    local locGraph = GetLocationGraph()
    for sourceLocName, directPathsSet in pairs(locGraph.locationDirectPaths) do
        Log("\t%s", sourceLocName)
        local isTwoWay = true
        for i = 1, #directPathsSet do
            local directLocationName = directPathsSet[i]
            Log("\t\t%s", directLocationName)
            local connectionPaths = locGraph:GetDirectPathsForLocationName(directLocationName)
            if not connectionPaths:Contains(sourceLocName) then
                isTwoWay = false
                table.insert(oneWayPaths, {sourceLocName, directLocationName})
                break
            end
        end
    end

    Log("One Way Paths (%s)", #oneWayPaths)
    for i = 1, #oneWayPaths do
        local oneWayPath = oneWayPaths[i]
        Log("\t%s -> %s is one way!", oneWayPath[1], oneWayPath[2])
    end

    Log("\tDone!")
end)
