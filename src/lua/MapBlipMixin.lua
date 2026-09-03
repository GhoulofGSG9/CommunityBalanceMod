-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\MapBlipMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--    Modified by: Mats Olsson (mats.olsson@matsotech.se)
--
-- Creates a mapblip for an entity that may have one.
--
-- Also marks a mapblip as dirty for later updates if it changes, by
-- listening on SetLocation, SetAngles and SetSighted calls.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/FogOfWarEntity.lua")

MapBlipMixin = CreateMixin( MapBlipMixin )
MapBlipMixin.type = "MapBlip"

--
-- Listen on the state that the mapblip depends on
--
MapBlipMixin.expectedCallbacks =
{
    SetOrigin = "Sets the location of an entity",
    SetAngles = "Sets the angles of an entity",
    SetCoords = "Sets both both location and angles"
}

MapBlipMixin.optionalCallbacks =
{
    GetDestroyMapBlipOnKill = "Return true to destroy map blip when units is killed.",
    OnGetMapBlipInfo = "Override for getting the Map Blip Info",
}

-- What entities have become dirty.
-- Flushed in the UpdateServer hook by MapBlipMixin.OnUpdateServer
local mapBlipMixinDirtyTable = unique_set()

local kFogOfWarEnts_hostToFog = {}
local kFogOfWarEnts_fogToHost = {}
local kFogOfWarEntsPool = {}

--
-- Update all dirty mapblips
--
local function MapBlipMixinOnUpdateServer()
    PROFILE("MapBlipMixin:OnUpdateServer")

    for entityId in mapBlipMixinDirtyTable:Iterate() do
        local entity = Shared.GetEntity(entityId)
        if entity then
            entity:UpdateBlip()
        end
    end

    mapBlipMixinDirtyTable:Clear()

end


local function CreateMapBlip(self, blipType, blipTeam, _)

    local mapName = MapBlip.kMapName
    --special mapblips
    if self:isa("Player") then
        mapName = PlayerMapBlip.kMapName
    elseif self:isa("Scan") then
        mapName = ScanMapBlip.kMapName
    end

    local mapBlip = Server.CreateEntity(mapName)
    -- This may fail if there are too many entities.
    if mapBlip then

        mapBlip.isFogOfWarMapBlip = self:isa("FogOfWarEntity")
        mapBlip:SetOwner(self:GetId(), blipType, blipTeam)
        self.mapBlipId = mapBlip:GetId()

    end

end

function MapBlipMixin:__initmixin()
    
    PROFILE("MapBlipMixin:__initmixin")
    
    assert(Server)

    self.lastBlipOrigin = nil
    self.lastBlipAngleYaw = 0
    self.blipIsPlayer = nil
    self.blipClassName = nil
    self.previousSighted = false

    -- Check if the new entity should have a map blip to represent it.
    local success, blipType, blipTeam, isInCombat = self:GetMapBlipInfo()
    if success then
        CreateMapBlip(self, blipType, blipTeam, isInCombat)
    end

    self.mapBlipSyncTick = Shared.GetTime()

end

function MapBlipMixin:OnInitialized()
    UpdateEntityForTeamBrains(self)
end

function MapBlipMixin:UpdateBlip()
    local mapBlip = self and self.mapBlipId and Shared.GetEntity(self.mapBlipId)
    if mapBlip then
        mapBlip:Update(self) -- Pass the owner, so we do not refetch it
    end
end

--
-- Intercept the functions that changes the state the mapblip depends on
--
function MapBlipMixin:SetOrigin(orig)
    if self.lastBlipOrigin ~= orig then
        self.lastBlipOrigin = orig

        local isInitTick = not self.mapBlipSyncTick or Shared.GetTime() == self.mapBlipSyncTick
        if isInitTick then
            self:UpdateBlip()
        else
            self:MarkBlipDirty()
        end
    end
end

 -- How much degree we must be off to update map blip (in case we stand still, otherwise SetOrigin will catch up)
local kMinYawDelta = Math.Radians(6)
function MapBlipMixin:SetAngles(angles)
    if self.lastBlipAngleYaw ~= nil then
        local currentYaw = angles.yaw
        local lastYaw = self.lastBlipAngleYaw

        -- Minimap blips, only look for left/right
        local diff = currentYaw - lastYaw
        local absDiff = diff < 0 and -diff or diff
        local isInitTick = not self.mapBlipSyncTick or Shared.GetTime() == self.mapBlipSyncTick
        if isInitTick or (currentYaw ~= lastYaw and absDiff >= kMinYawDelta) then --currentYaw ~= lastYaw then
            if isInitTick then
                self:UpdateBlip()
            else
                self:MarkBlipDirty()
            end

            self.lastBlipAngleYaw = currentYaw
        end
    end
end

function MapBlipMixin:SetCoords(coords)
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnEnterCombat()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnLeaveCombat()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:MarkBlipDirty()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnConstructionComplete()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnPowerOn()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnPowerOff()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnPhaseGateEntry()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnCargoGateEntry()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnUseGorgeTunnel()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:OnPreBeacon()
    mapBlipMixinDirtyTable:Insert(self:GetId())
end

function MapBlipMixin:UpdateFogEntity(sighted)

    if not HasMixin(self, "Team") or self.reentranceOff then
        return nil
    end

    local id = self:GetId()
    local isNewEntity = false
    local f = kFogOfWarEnts_hostToFog[id]

    assert(not self:isa("FogOfWarEntity"))

    local teamNumber = self:GetTeamNumber()
    local alive = HasMixin(self, "Live") and self:GetIsAlive()
    if sighted or not alive or not ((teamNumber == kTeam1Index or teamNumber == kTeam2Index)) then

        if f and f:IsMapBlipVisible() then
            local _, blipType = self:GetMapBlipInfo()
            f:SetFogEntMapBlipInfo(false)
        end

        return nil
    end

    if not f then
        if #kFogOfWarEntsPool > 0 then
            f = kFogOfWarEntsPool[#kFogOfWarEntsPool]
            table.remove(kFogOfWarEntsPool, #kFogOfWarEntsPool)
        else
            isNewEntity = true
            f = CreateEntity(FogOfWarEntity.kMapName)
        end

    end

    if not f then
        return nil
    end

    local _, blipType = self:GetMapBlipInfo()
    f:SetFogEntMapBlipInfo(true, blipType, teamNumber, GetIsUnitActive(self))

    if not kFogOfWarEnts_hostToFog[id] then -- We fetched a new entity that needs to be init

        kFogOfWarEnts_hostToFog[id] = f
        kFogOfWarEnts_fogToHost[f:GetId()] = id
    end

    f.reentranceOff = true
    if isNewEntity then
        f:OnInitializedMapBlipMixin() -- Need to happen AFTER we set the custom host blips
    else
        -- Update mapBlip with new type, team, and active state
        -- Since mapBlip will recheck relevancy too, and that is how
        -- we decide if we should create ghosts or not, we need to
        -- prevent re-entrancies here

        local mapBlip = f.mapBlipId and Shared.GetEntity(f.mapBlipId)
        if mapBlip then
            mapBlip.isFogOfWarMapBlip = true
            mapBlip:SetOwner(f:GetId(), blipType, teamNumber) -- Update blip (if we went active/inactive for instance)
        end
    end
    f.reentranceOff = nil

    local orig = self:GetOrigin()
    if self:isa("Player") then
        orig.y = self:GetModelOrigin().y -- Model middle, better for LOS check
    elseif not self:isa("PowerPoint") then -- Elevate a bit off the ground anything but powernode (their orig is good)
        orig = self:GetOrigin() + Vector(0, 0.25, 0)
    end

    f:SetOrigin(orig)
    f:SetAngles(self:GetAngles())  
    return f
end

function MapBlipMixin:IsFogEntityDetached()
    assert(self:isa("FogOfWarEntity"))
    return kFogOfWarEnts_fogToHost[self:GetId()] == nil
end

function MapBlipMixin:StashFogEntity()
    local kMaxQueueSize = 25

    -- Make sure the link to us as been cleared
    assert(self:isa("FogOfWarEntity") and self:IsFogEntityDetached())

    self.visible = false
    self.blipType = kMinimapBlipType.CommandStation
    self.blipTeam = -1
    self.isActive = false
    self:SetTeamNumber(self.blipTeam)

    if #kFogOfWarEntsPool > kMaxQueueSize then
        self:AddTimedCallback(DestroyEntity, 0)
    else
        table.insert(kFogOfWarEntsPool, self)
    end
    return
end

function MapBlipMixin:OnSighted(sighted)

    -- because sighted is always set during each LOS calc, we need to keep track of
    -- what the previous value was so we don't mark it dirty unnecessarily
    if self.previousSighted ~= sighted then

        self.previousSighted = sighted
        mapBlipMixinDirtyTable:Insert(self:GetId())

    end

end

-- Todo: Add per frame time cache
function MapBlipMixin:GetMapBlipInfo()
    PROFILE("MapBlipMixin:GetMapBlipInfo")

    if self.OnGetMapBlipInfo then
        return self:OnGetMapBlipInfo()
    end

    if self.blipIsPlayer == nil then
         self.blipIsPlayer = self:isa("Player")
         self.blipClassName = self:GetClassName()
    end

    local success = false
    local blipType = kMinimapBlipType.Undefined
    local blipTeam = -1
    local isAttacked = HasMixin(self, "Combat") and self:GetIsInCombat()
    local isParasited = HasMixin(self, "ParasiteAble") and self:GetIsParasited()
    local isPlayer = self.blipIsPlayer

    -- World entities
    if not isPlayer and self:isa("Cyst") then

        blipType = kMinimapBlipType.Infestation

        if not self:GetIsConnected() then
            blipType = kMinimapBlipType.InfestationDying
        end

        blipTeam = self:GetTeamNumber()
        isAttacked = false

    elseif not isPlayer and self:isa("Door") then
        blipType = kMinimapBlipType.Door
    elseif not isPlayer and self:isa("ResourcePoint") then
        blipType = kMinimapBlipType.ResourcePoint
    elseif not isPlayer and self:isa("TechPoint") then
        blipType = kMinimapBlipType.TechPoint
        -- Don't display PowerPoints unless they are in an unpowered state.
    elseif not isPlayer and self:isa("PowerPoint") then

        if self:GetIsDisabled() then
            blipType = kMinimapBlipType.DestroyedPowerPoint
        elseif self:GetIsBuilt() then
            blipType = kMinimapBlipType.PowerPoint
        elseif self:GetIsSocketed() then
            blipType = kMinimapBlipType.BlueprintPowerPoint
        else
            blipType = kMinimapBlipType.UnsocketedPowerPoint
        end

        blipTeam = self:GetTeamNumber()

    elseif not isPlayer and self:isa("Hallucination") then

        local hallucinatedTechId = self:GetAssignedTechId()

        if hallucinatedTechId == kTechId.Drifter then
            blipType = kMinimapBlipType.Drifter
        elseif hallucinatedTechId == kTechId.Hive then
            blipType = kMinimapBlipType.Hive
        elseif hallucinatedTechId == kTechId.Harvester then
            blipType = kMinimapBlipType.Harvester
        end

        blipTeam = self:GetTeamNumber()

    elseif self.GetMapBlipType then
        blipType = self:GetMapBlipType()
        blipTeam = self:GetTeamNumber()

        -- Everything else that is supported by kMinimapBlipType.
    elseif self:GetIsVisible() then

        local className = self.blipClassName or self:GetClassName()

        if rawget( kMinimapBlipType, className ) ~= nil then
            blipType = kMinimapBlipType[className]
        else
            Shared.Message( "Element '"..tostring(className).."' doesn't exist in the kMinimapBlipType enum" )
        end

        blipTeam = HasMixin(self, "Team") and self:GetTeamNumber() or kTeamReadyRoom

    end

    if blipType ~= 0 then
        success = true
    end

    -- %%% CBM Blips %%% --
    local techId = self:GetTechId()
    if isPlayer then
        return success, blipType, blipTeam, isAttacked, isParasited
    elseif techId == kTechId.FortressCrag then 
        blipType = kMinimapBlipType.FortressCrag
        blipTeam = self:GetTeamNumber()
        return success, blipType, blipTeam, isAttacked, isParasited

    elseif techId == kTechId.FortressShade then 
        blipType = kMinimapBlipType.FortressShade
        blipTeam = self:GetTeamNumber()
        return success, blipType, blipTeam, isAttacked, isParasited

    elseif techId == kTechId.FortressShift then 
        blipType = kMinimapBlipType.FortressShift
        blipTeam = self:GetTeamNumber()
        return success, blipType, blipTeam, isAttacked, isParasited
      
    elseif techId == kTechId.FortressWhip then 
        local mature = self:GetIsMature()
        blipTeam = self:GetTeamNumber()
        if mature then 
            blipType = kMinimapBlipType.FortressWhipMature
        else 
            blipType = kMinimapBlipType.FortressWhip
        end
        return success, blipType, blipTeam, isAttacked, isParasited

    elseif self:isa("CommandStation") then 
        local occupied = not ( self:GetCommander() == nil )
        blipTeam = self:GetTeamNumber()  

        if occupied then 
            blipType = kMinimapBlipType.CommandStationOccupied
        else 
            blipType = kMinimapBlipType.CommandStation
        end

        return success, blipType, blipTeam, isAttacked, isParasited
         
    elseif self:isa("Whip") then 
        local mature = self:GetIsMature()
        blipTeam = self:GetTeamNumber()  

        if mature then 
            blipType = kMinimapBlipType.WhipMature
        else 
            blipType = kMinimapBlipType.Whip
        end

        return success, blipType, blipTeam, isAttacked, isParasited

    elseif self:isa("Hive") then
        local maturityLevel =  self:GetMaturityFraction()
        local occupied = not ( self:GetCommander() == nil )
        blipTeam = self:GetTeamNumber()  

        if self.bioMassLevel == 5 then
            if maturityLevel < 0.34 then 
                if occupied then 
                    blipType = kMinimapBlipType.HiveFreshOccupiedFifthBio
                else 
                    blipType = kMinimapBlipType.HiveFreshFifthBio
                end

            elseif maturityLevel > 0.65 then 
                if occupied then 
                    blipType = kMinimapBlipType.HiveMatureOccupiedFifthBio
                else 
                    blipType = kMinimapBlipType.HiveMatureFifthBio
                end

            else 
                if occupied then 
                    blipType = kMinimapBlipType.HiveOccupiedFifthBio
                else 
                    blipType = kMinimapBlipType.HiveFifthBio
                end
            end
        else
            if maturityLevel < 0.34 then 
                if occupied then 
                    blipType = kMinimapBlipType.HiveFreshOccupied
                else 
                    blipType = kMinimapBlipType.HiveFresh
                end

            elseif maturityLevel > 0.65 then 
                if occupied then 
                    blipType = kMinimapBlipType.HiveMatureOccupied
                else 
                    blipType = kMinimapBlipType.HiveMature
                end

            else 
                if occupied then 
                    blipType = kMinimapBlipType.HiveOccupied
                else 
                    blipType = kMinimapBlipType.Hive
                end
            end
        end

        return success, blipType, blipTeam, isAttacked, isParasited

    elseif self:isa("Armory") then
        blipTeam = self:GetTeamNumber()  
        
        if self:GetIsAdvanced() then 
            blipType = kMinimapBlipType.AdvancedArmory
        else
            blipType = kMinimapBlipType.Armory
        end
        return success, blipType, blipTeam, isAttacked, isParasited

    elseif self:isa("DIS") then
        blipTeam = self:GetTeamNumber()  

        if self:GetPlayIdleSound() then
            blipType = kMinimapBlipType.DIS
        else
            blipType = kMinimapBlipType.DISDeployed
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited

    elseif self:isa("ARC") then
        blipTeam = self:GetTeamNumber()  

        if self:GetPlayIdleSound() then
            blipType = kMinimapBlipType.ARC
        else
            blipType = kMinimapBlipType.ARCDeployed
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited
    
    elseif self:isa("SentryBattery") then
        blipTeam = self:GetTeamNumber()  
        
        if techId == kTechId.ShieldBattery then
            blipType = kMinimapBlipType.ShieldedSentryBattery
        else
            blipType = kMinimapBlipType.SentryBattery
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited
            
    elseif self:isa("Observatory") then
        blipTeam = self:GetTeamNumber()  
        
        if techId == kTechId.AdvancedObservatory then
            blipType = kMinimapBlipType.AdvancedObservatory
        else
            blipType = kMinimapBlipType.Observatory
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited
    
    elseif self:isa("RoboticsFactory") then
        blipTeam = self:GetTeamNumber()  
        
        if techId == kTechId.ARCRoboticsFactory then
            blipType = kMinimapBlipType.ARCRoboticsFactory
        else
            blipType = kMinimapBlipType.RoboticsFactory
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited
    
    elseif self:isa("PrototypeLab") then
        blipTeam = self:GetTeamNumber()  
        
        if techId == kTechId.InfantryPrototypeLab then
            blipType = kMinimapBlipType.InfantryPrototypeLab
        elseif techId == kTechId.ExoPrototypeLab then
            blipType = kMinimapBlipType.ExoPrototypeLab
        else
            blipType = kMinimapBlipType.PrototypeLab
        end
      
        return success, blipType, blipTeam, isAttacked, isParasited
        
    end

    return success, blipType, blipTeam, isAttacked, isParasited

end

function MapBlipMixin:DestroyBlip()

    local mapBlip = self.mapBlipId and Shared.GetEntity(self.mapBlipId)
    if mapBlip then

        DestroyEntity(mapBlip)
        self.mapBlipId = nil

    end

end

function MapBlipMixin:DetachFogEntity()
    if self:isa("FogOfWarEntity") then
        local idx = nil
        for i, e in ipairs(kFogOfWarEntsPool) do -- Remove ourselves from the pool
            if e:GetId() == self:GetId() then
                idx = i
                break
            end
        end
        if idx then
            table.remove(kFogOfWarEntsPool, idx)
        end
    else -- Detach the entity from the fog
        local hostId = self:GetId()
        local fogEntity = kFogOfWarEnts_hostToFog[hostId]
        if fogEntity then
            -- Log("OnDestroy(%s) -- detaching fog %s-%s", self, fogEntity, EnumToString(kMinimapBlipType, fogEntity.blipType))
            kFogOfWarEnts_fogToHost[fogEntity:GetId()] = nil
        end
        kFogOfWarEnts_hostToFog[hostId] = nil
    end
end

function MapBlipMixin:OnKill()

    self:DetachFogEntity()
    if not self.GetDestroyMapBlipOnKill or self:GetDestroyMapBlipOnKill() then
        self:DestroyBlip()
        UpdateEntityForTeamBrains(self, true)
    end

end

function MapBlipMixin:OnDestroy()

    self:DetachFogEntity()
    self:DestroyBlip()
    UpdateEntityForTeamBrains(self, true)
end

Event.Hook("UpdateServer", MapBlipMixinOnUpdateServer)
