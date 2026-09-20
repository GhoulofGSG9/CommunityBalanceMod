--======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\NS2Utility_Server.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- Server-side NS2-specific utility functions.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================
Script.Load("lua/Table.lua")
Script.Load("lua/Utility.lua")

function UpdateHallucinationLifeTime(self)
    
    if self.isHallucination or self:isa("Hallucination") then
    
        if self.creationTime + kHallucinationLifeTime < Shared.GetTime() then
            
            self:TriggerEffects("death_hallucination")
            -- don't do any ragdolls or death messages in this case, timing out of a hallucination is nothing the enemy team has to know
            DestroyEntity(self)
            
        end
    
    end
    
end

function DestroyEntitiesWithinRange(className, origin, range, filterFunc)

    for index, entity in ipairs(GetEntitiesWithinRange(className, origin, range)) do
        if not filterFunc or not filterFunc(entity) then
            DestroyEntity(entity)
        end
    end

end

function SetAlwaysRelevantToCommander(unit, relevant)
    
    local includeMask = 0
    
    if relevant then
    
        if not HasMixin(unit, "Team") then
            includeMask = bit.bor(kRelevantToTeam1Commander, kRelevantToTeam2Commander)
        elseif unit:GetTeamNumber() == 1 then
            includeMask = kRelevantToTeam1Commander
        elseif unit:GetTeamNumber() == 2 then
            includeMask = kRelevantToTeam2Commander
        end
    end
    
    unit:SetIncludeRelevancyMask( includeMask )
    
end    

function PushPlayersInRange(origin, range, impulseStrength, team)

    local players = GetEntitiesForTeamWithinRange("Player", team, origin, range)
    
    for _, player in ipairs(players) do
    
        player:AddPushImpulse(GetNormalizedVector( player:GetOrigin() - origin)  * impulseStrength)
    
    end

end

local gLastHitEffectCounterReset = 0
local gCurrentNumHitEffects = 0

function GetShouldSendHitEffect()

    local time = Shared.GetTime()
    if gLastHitEffectCounterReset + 1 < time then
        gLastHitEffectCounterReset = time
        gCurrentNumHitEffects = 0
    end
    
    gCurrentNumHitEffects = gCurrentNumHitEffects + 1

    return gCurrentNumHitEffects < kMaxHitEffectsPerSecond

end

local kUp = Vector(0, 1, 0)

function CreateEntityForTeam(techId, position, teamNumber, player)

    local newEnt
    
    local mapName = LookupTechData(techId, kTechDataMapName)
    if mapName ~= nil then
    
        -- Allow entities to be positioned off ground (eg, hive hovers over tech point)
        local spawnHeight = LookupTechData(techId, kTechDataSpawnHeightOffset, 0)
        local spawnHeightPosition = Vector(position.x,
                                           position.y + spawnHeight,
                                           position.z)
        
        newEnt = CreateEntity( mapName, spawnHeightPosition, teamNumber )
        
        -- Hook it up to attach entity
        local attachEntity = GetAttachEntity(techId, position)    
        if attachEntity then    
            newEnt:SetAttached(attachEntity)        
        end
        
    else
        Print("CreateEntityForTeam(%s): Couldn't kTechDataMapName for entity.", EnumToString(kTechId, techId))
        assert(false)    
    end
    
    return newEnt
    
end

-- 6 players means 0 reduction in time, under 6 players respawn scalar is below 1
local kPlayerNumBase = 6
local kPlayerNumMax = 16
local kOverSizeExponent = 1.1
local kMinTimeFraction = 0.1
local kTimeReductionMultiplier = 2
function GetPlayerSizeBasedRespawnTime(team, defaultTime)

    local numPlayer = team:GetNumPlayers()
    local overSize = math.max(0, numPlayer - kPlayerNumBase)
    
    if overSize == 0 then
        return defaultTime
    end    
    
    local overSizeFraction = (overSize / kPlayerNumMax) 
    local timeReduction = (overSizeFraction ^ kOverSizeExponent) * defaultTime * kTimeReductionMultiplier
    
    local spawnTime = math.max(kMinTimeFraction * defaultTime, defaultTime - timeReduction)
    
    --Print("timeReduction : %s", ToString(timeReduction))
    --Print("spawnTime: %s", ToString(spawnTime))
    
    return spawnTime

end

function CreateEntityForCommander(techId, position, commander)

    local newEnt = CreateEntityForTeam(techId, position, commander:GetTeamNumber(), commander)
    ASSERT(newEnt ~= nil, "Didn't create entity for techId: " .. EnumToString(kTechId, techId))
    
    -- It is possible the new entity was created in a spot where it was instantly destroyed.
    if newEnt:GetIsDestroyed() then
        newEnt = nil
    end
    
    if newEnt then
    
        newEnt:SetOwner(commander)
        UpdateInfestationMask(newEnt)
        
    end
    
    return newEnt
    
end

-- returns a time fraction of the passed base time
function GetAlienCatalystTimeAmount(baseTime, entity)

    if HasMixin(entity, "Catalyst") then
        
        local catalystTime = entity:GetCatalystScalar() * baseTime * (1 + kNutrientMistPercentageIncrease/100)
        return catalystTime
        
    end    
    
    return 0
    
end

local kEggExtents = nil
local kEggOffsetY = 0
local gEggCenterScratch = Vector(0, 0, 0)

local function InitializeEggTechData()
    kEggExtents = LookupTechData(kTechId.Egg, kTechDataMaxExtents)
    ASSERT(kEggExtents and math.max(kEggExtents.x, kEggExtents.y) > 0, "invalid x extents for Egg")
    kEggOffsetY = kEggExtents.y + 0.05
end

-- Assumes position is at the bottom center of the egg
function GetCanEggFit(position)

    if not kEggExtents then
        InitializeEggTechData()
    end

    if not GetIsPointOnInfestation(position) then
        return false
    end

    gEggCenterScratch.x = position.x
    gEggCenterScratch.y = position.y + kEggOffsetY
    gEggCenterScratch.z = position.z

    return not Shared.CollideBox(kEggExtents, gEggCenterScratch, CollisionRep.Default, PhysicsMask.AllButPCs, nil)

end

-- Don't spawn eggs on railings or edges of steps, etc. Check each corner of the egg to make
-- sure the heights are all about the same
function GetFullyOnGround(position, maxExtentsDimension, numSlices, variationAllowed)

    ASSERT(type(maxExtentsDimension) == "number")
    ASSERT(maxExtentsDimension > 0)
    ASSERT(type(numSlices) == "number")
    ASSERT(numSlices > 1)
    ASSERT(type(variationAllowed) == "number")
    ASSERT(variationAllowed > 0)

    local function GetGroundHeight(position)

        local trace = Shared.TraceRay(position, position - kUp, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterOne(nil))
        return position.y - trace.fraction
        
    end
    
    
    -- Get height of surface underneath center of egg
    local centerHeight = GetGroundHeight(position)
    
    -- Make sure center isn't overhanging
    if math.abs(centerHeight - position.y) > variationAllowed then    
    
        return false        
        
    end

    -- Four slices, in radius around edge of egg
    for index = 1, numSlices do
        
        local angle = (index / numSlices) * math.pi * 2        
        local xOffset = math.cos(angle) * maxExtentsDimension
        local zOffset = math.sin(angle) * maxExtentsDimension
        
        local edgeHeight = GetGroundHeight(position + Vector(xOffset, 0, zOffset))
        
        if math.abs(edgeHeight - centerHeight) > variationAllowed then
        
            return false
            
        end
        
    end
    
    return true
    
end

-- Assumes position is at the bottom center of the egg
function GetIsPlacementForTechId(position, checkInfestation, techId)

    local extents = Vector(LookupTechData(techId, kTechDataMaxExtents, Vector(0.4, 0.4, 0.4)))
    local center = position + Vector(0, extents.y, 0)
    
    if not Shared.CollideBox(extents, center, CollisionRep.Move, PhysicsMask.All, nil) then
    
        local maxExtentsDimension = math.max(extents.x, extents.z)
        ASSERT(maxExtentsDimension > 0, "invalid x extents for")
        
        if GetFullyOnGround(position, maxExtentsDimension, 4, 0.5) then
        
            if not checkInfestation or GetIsPointOnInfestation(position) then
                return true
            end
            
        end
        
    end
    
    return false
    
end

local kBigUpVector = Vector(0, 1000, 0)
local function CastToGround(pointToCheck, height, radius, filterEntity)

    local filter = EntityFilterOne(filterEntity)
    
    local extents = Vector(radius, height * 0.5, radius)
    local trace = Shared.TraceBox( extents, pointToCheck, pointToCheck - kBigUpVector, CollisionRep.Move, PhysicsMask.All, filter)
    
    if trace.fraction ~= 1 then
    
        -- Check the start point is not colliding.
        if not Shared.CollideBox(extents, trace.endPoint, CollisionRep.Move, PhysicsMask.All, filter) then
            return trace.endPoint - Vector(0, height * 0.5, 0)
        end
        
    end
    
    return nil
    
end

-- Find random spot near hive that we could put an egg. Allow spawn points that are on the other side of walls
-- but pathable. Returns point on ground.
local function FindPlaceForTechId(filterEntity, origin, techId, minRange, maxRange, checkPath, maxVerticalDistance)

    PROFILE("NS2Utility:FindPlaceForTechId")
    
    local extents = LookupTechData(techId, kTechDataMaxExtents, Vector(0.4, 0.4, 0.4))
    local capsuleHeight, capsuleRadius = GetTraceCapsuleFromExtents(extents)
    
    -- Find random spot within range, using random orientation (0 to -45 degrees)
    local randomRange = minRange + math.random() * (maxRange - minRange)
    
    local randomRadians = math.random() * math.pi * 2
    local randomHeight = -math.random() * 3
    local randomPoint = Vector(origin.x + randomRange * math.cos(randomRadians),
                               origin.y + randomHeight,
                               origin.z + randomRange * math.sin(randomRadians))
    
    local pointToUse = CastToGround(randomPoint, capsuleHeight, capsuleRadius, filterEntity)
    if pointToUse then
    
        if checkPath then
        
            local pathPoints = PointArray()
            local hasPathToPoint = Pathing.GetPathPoints(origin, pointToUse, pathPoints)
            
            -- This path is invalid if no path was found or the last path point was not the
            -- exact point we were looking for.
            if not hasPathToPoint or #pathPoints == 0 or pathPoints[#pathPoints] ~= pointToUse then
                return nil
            end
            
        end
        
        if maxVerticalDistance then
        
            if math.abs(origin.y - pointToUse.y) > maxVerticalDistance then
                return nil
            end
            
        end
        
        return pointToUse
        
    end
    
    return nil
    
end

function CalculateRandomSpawn(filterEntity, origin, techId, checkPath, minDistance, maxDistance, maxVerticalDistance)

    PROFILE("NS2Utility:CalculateRandomSpawn")
    
    local possibleSpawn = FindPlaceForTechId(filterEntity, origin, techId, minDistance, maxDistance, checkPath, maxVerticalDistance)
    if possibleSpawn then
    
        if GetIsPlacementForTechId(possibleSpawn, false, techId) then
            return possibleSpawn
        end
        
    end
    
    return nil
    
end

-- Translate from SteamId to player (returns nil if not found)
function GetPlayerFromUserId(userId)

    for index, currentPlayer in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        local owner = Server.GetOwner(currentPlayer)
        if owner and owner:GetUserId() == userId then
            return currentPlayer
        end
    end
    
    return nil
    
end

function DestroyPowerForLocation(locationName, instantAuxilaryLights)
    local powerPoint = GetPowerPointForLocation(locationName)
    if not powerPoint then return end

    if not powerPoint:GetIsBuilt() then
        powerPoint:SetConstructionComplete()
    end

    powerPoint:Kill()

    if instantAuxilaryLights then
        -- Hack to skip directly to axillary lights
        powerPoint.timeOfLightModeChange = 0
    end
end

function SocketPowerForLocation(locationName)

    local powerPoint = GetPowerPointForLocation(locationName)
    if not powerPoint then return end

    if powerPoint:GetPowerState() == PowerPoint.kPowerState.unsocketed then
        powerPoint:SocketPowerNode()
    end
end

local gTechIdToMapNameCache = {}
local function UnlockAbility(forAlien, techId)

    if not forAlien:GetIsAlive() then
        return
    end

    local mapName = gTechIdToMapNameCache[techId]
    if mapName == nil then
        mapName = LookupTechData(techId, kTechDataMapName) or false
        gTechIdToMapNameCache[techId] = mapName
    end

    if not mapName then
        return
    end

    if not forAlien:GetWeapon(mapName) then
        local activeWeapon = forAlien:GetActiveWeapon()

        forAlien:GiveItem(mapName)

        if activeWeapon then
            forAlien:SetActiveWeapon(activeWeapon:GetMapName())
        end
    end

end

local function LockAbility(forAlien, techId)

    local mapName = LookupTechData(techId, kTechDataMapName)    
    if mapName and forAlien:GetIsAlive() then
    
        local tierWeapon = forAlien:GetWeapon(mapName)
        local activeWeapon = forAlien:GetActiveWeapon()
        local activeWeaponMapName
        
        if activeWeapon ~= nil then
            activeWeaponMapName = activeWeapon:GetMapName()
        end
        
        if tierWeapon then
            forAlien:RemoveWeapon(tierWeapon)
        end
        
        if activeWeaponMapName == mapName then
            forAlien:SwitchWeapon(1)
        end
        
    end    
    
end

local function CheckHasPrereq(teamNumber, techId)

    local hasPrereq = false

    local techTree = GetTechTree(teamNumber)
    if techTree then
        
        local techNode = techTree:GetTechNode(techId)
        if techNode then
            hasPrereq = techTree:GetHasTech(techNode:GetPrereq1())
        end
    
    end

    return hasPrereq

end

function UpdateAbilityAvailability(forAlien, tierOneTechId, tierTwoTechId, tierThreeTechId)

    local time = Shared.GetTime()
    local lastUpdate = forAlien.timeOfLastNumHivesUpdate

    if lastUpdate and time <= lastUpdate + 0.5 then
        return
    end
    forAlien.timeOfLastNumHivesUpdate = time

    local team = forAlien:GetTeam()
    if not (team and team.GetTechTree) then
        return
    end

    local gamerules = GetGamerules()
    local allTech = gamerules and gamerules:GetAllTech()

    -- Don't lose abilities unless you die.
    if tierOneTechId and tierOneTechId ~= kTechId.None then
        if not forAlien.oneHive then
            forAlien.oneHive = allTech or GetIsTechUnlocked(forAlien, tierOneTechId)
        end

        if forAlien.oneHive then
            UnlockAbility(forAlien, tierOneTechId)
        else
            LockAbility(forAlien, tierOneTechId)
        end
    else
        forAlien.oneHive = forAlien.oneHive or allTech
    end

    if tierTwoTechId and tierTwoTechId ~= kTechId.None then
        if not forAlien.twoHives then
            forAlien.twoHives = allTech or GetIsTechUnlocked(forAlien, tierTwoTechId)
        end

        if forAlien.twoHives then
            UnlockAbility(forAlien, tierTwoTechId)
        else
            LockAbility(forAlien, tierTwoTechId)
        end
    else
        forAlien.twoHives = forAlien.twoHives or allTech
    end

    if tierThreeTechId and tierThreeTechId ~= kTechId.None then
        if not forAlien.threeHives then
            forAlien.threeHives = allTech or GetIsTechUnlocked(forAlien, tierThreeTechId)
        end

        if forAlien.threeHives then
            UnlockAbility(forAlien, tierThreeTechId)
        else
            LockAbility(forAlien, tierThreeTechId)
        end
    else
        forAlien.threeHives = forAlien.threeHives or allTech
    end

    if forAlien.GetTierFourTechId then

        local tierFourTechId = forAlien:GetTierFourTechId()
        if tierFourTechId and tierFourTechId ~= kTechId.None then
            if not forAlien.fourHives then
                forAlien.fourHives = allTech or GetIsTechUnlocked(forAlien, tierFourTechId)
            end

            if forAlien.fourHives then
                UnlockAbility(forAlien, tierFourTechId)
            else
                LockAbility(forAlien, tierFourTechId)
            end
        else
            forAlien.fourHives = forAlien.fourHives or allTech
        end
    end

end

function ScaleWithPlayerCount(value, numPlayers, scaleUp)

    -- 6 is supposed to be ideal, in this case the value wont be modified
    local factor = 1
    
    if scaleUp then
        factor = math.max(6, numPlayers) / 6
    else
        factor = 6 / math.max(6, numPlayers)
    end

    return value * factor

end

function TriggerCameraShake(triggerinEnt, minIntensity, maxIntensity, range)

    local players = GetEntitiesWithinRange("Player", triggerinEnt:GetOrigin(), range)
    local owner = HasMixin(triggerinEnt, "Owner") and triggerinEnt:GetOwner()

    if owner and not owner:isa("Commander") then
        
        table.removevalue(players, owner)
        local shakeIntensity = (owner:GetOrigin() - triggerinEnt:GetOrigin()):GetLength() / (range*2)
        shakeIntensity = 1 - Clamp(shakeIntensity, 0, 1)
        shakeIntensity = minIntensity + shakeIntensity * (maxIntensity - minIntensity)
        
        owner:SetCameraShake(shakeIntensity)   
        
    end
    
    for _, player in ipairs(players) do
    
        if not  player:isa("Commander") then
            local shakeIntensity = (player:GetOrigin() - triggerinEnt:GetOrigin()):GetLength() / range
            shakeIntensity = 1 - Clamp(shakeIntensity, 0, 1)
            shakeIntensity = minIntensity + shakeIntensity * (maxIntensity - minIntensity)
            
            player:SetCameraShake(shakeIntensity)
        end
        
    end

end

local kGivenAchievement = {}
function Server.SetAchievement(client, name, force)

    local clientId = client and client:GetUserId()
    if clientId == 0 or (not force and (not Server.IsDedicated() or Shared.GetCheatsEnabled())) then return end

    if not kGivenAchievement[clientId] then
        kGivenAchievement[clientId] = {}
    end

    if client and not kGivenAchievement[clientId][name] then
        Server.SendNetworkMessage(client, "SetAchievement", {name = name}, true)
        kGivenAchievement[clientId][name] = true
    end

end

