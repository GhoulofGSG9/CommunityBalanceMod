Script.Load("lua/ScriptActor.lua")

Script.Load("lua/TeamMixin.lua")
Script.Load("lua/MapBlipMixin.lua")

class 'FogOfWarEntity' (ScriptActor)

FogOfWarEntity.kMapName = "fogOfwarentity"

kFogPlayerBlipLifetime = 30
kFogPlayerBlipFadeTime = 2

local networkVars =
{
    visible = "boolean",
    blipType = "enum kMinimapBlipType",
    blipTeam = string.format("integer (%s to %s)", kTeamInvalid, kSpectatorIndex),
    isActive = "boolean",
    isPlayerBlip = "boolean",
    fogExpireTime = "time"
}

AddMixinNetworkVars(TeamMixin, networkVars)

local kFogEntRelevancyDist = kPlayerLOSDistance

local kFogEndUpdateInterval = 0.8

function FogOfWarEntity:OnCreate()
	ScriptActor.OnCreate(self)

    InitMixin(self, TeamMixin)

    self:SetFogEntMapBlipInfo(false, kMinimapBlipType.Undefined, -1, true)
    self.lastSetRelevancyMask = nil

    self:SetUpdates(false)--kUpdateIntervalMinimal) 
    self:SetRelevancyDistance(kFogEntRelevancyDist)
    self:SetExcludeRelevancyMask( 0 )

end

function FogOfWarEntity:OnUpdate()

    if not self:IsMapBlipVisible() then
        Log("Error: OnUpdate() still on for %s-%s", self, EnumToString(kMinimapBlipType, self.blipType))
        self:SetUpdates(false)
        return
    end

    if self.isPlayerBlip and self.fogExpireTime and Shared.GetTime() >= self.fogExpireTime then
        self:SetFogEntMapBlipInfo(false)
        return
    end

    --Log("%s-%s -- OnUpdate(team: %s)", self, EnumToString(kMinimapBlipType, self.blipType), self.blipTeam)
    --DebugCapsule( self:GetOrigin(), self:GetOrigin(), 0.5, 0.0, 0.25)

    local orig = self:GetOrigin()
    local enemyTeam = GetEnemyTeamNumber(self.blipTeam)
    local fetchDist = kFogEntRelevancyDist
    local entities = GetEntitiesWithMixinForTeamWithinXZRange("LOS", enemyTeam, orig, fetchDist)
    for _, e in ipairs(entities) do
        local orig2 = e:GetOrigin()

        if e:isa("Scan") then
            orig2.y = orig.y -- Cancel scan elevation, sees everything
        end

        -- A bit less than actual vision to prevent flickering when entering LOS
        local inViewRange = not e.GetVisionRadius or orig:GetDistanceTo(orig2) <= (e:GetVisionRadius() - 2)
        if inViewRange and GetIsUnitActive(e) then
            local seen = self:OverrideCheckVisibilty(e)
            if seen then
                self:SetFogEntMapBlipInfo(false)
                return
            end
        end
    end
end

--function FogOfWarEntity:OnDestroy()
    --Log("%s-%s -- DESTROY", self, EnumToString(kMinimapBlipType, self.blipType))
--end

function FogOfWarEntity:OnInitializedMapBlipMixin()
    if not HasMixin(self, "MapBlip") then
        InitMixin(self, MapBlipMixin)
    end
end

function FogOfWarEntity:IsMapBlipVisible()
    return self.visible
end


function FogOfWarEntity:SetFogEntMapBlipInfo(visible, blipType, blipTeam, isActive, isPlayerBlip)
    local wasVisible = self.visible
    self.visible = visible

    if blipType ~= nil then
	   self.blipType = blipType
    end

    if blipTeam ~= nil then
	   self.blipTeam = blipTeam
       self:SetTeamNumber(blipTeam)
    end

    if isActive ~= nil then
       self.isActive = isActive
    end

    if isPlayerBlip ~= nil then
       self.isPlayerBlip = isPlayerBlip
    end

    if visible and self.isPlayerBlip and not wasVisible then
        self.fogExpireTime = Shared.GetTime() + kFogPlayerBlipLifetime + kFogPlayerBlipFadeTime
    elseif not visible then
        self.fogExpireTime = nil
    end

    --Log("%s-%s -- Set visible: %s, active: %s/%s", self, self.blipType and EnumToString(kMinimapBlipType, self.blipType), visible, isActive, self.isActive)

    if Server then

        -- Mirror onto the MapBlip itself: MapBlip has infinite relevancy distance while
        -- this entity is distance-limited (see OnCreate), so a client can lose relevancy
        -- to this FogOfWarEntity mid-fade while its MapBlip is still shown on the minimap.
        local mapBlip = self.mapBlipId and Shared.GetEntity(self.mapBlipId)
        if mapBlip then
            mapBlip.fogExpireTime = self.fogExpireTime
        end

        self:UpdateRelevancy()
        self:SetUpdates(self.visible, kFogEndUpdateInterval)
        -- Stash the entity if we are not linked anymore
        -- Also check for if mapBlip has been initialized
        if not visible and HasMixin(self, "MapBlip") and self:IsFogEntityDetached() then
            -- Set the type and active to something big,
            -- so if anything messes up we will see it instantly
            self.blipType = kMinimapBlipType.CommandStation
            self.isActive = false
            self:StashFogEntity()
        end
    end
end

if Server then
    function FogOfWarEntity:UpdateRelevancy()
        local mask = 0
        if self:IsMapBlipVisible() then
            if (self.blipTeam == kTeam2Index) then
                mask = kRelevantToTeam1
            elseif (self.blipTeam == kTeam1Index) then
                mask = kRelevantToTeam2
            end
        end

        if self.lastSetRelevancyMask ~= mask then
            self:SetExcludeRelevancyMask( mask )
            self.lastSetRelevancyMask = mask

            local mapBlip = self.mapBlipId and Shared.GetEntity(self.mapBlipId)
            --Log("Set relevancy at %s for %s (mapBlip: %s-%s - %s)", mask, self, mapBlip, self.mapBlipId, EnumToString(kMinimapBlipType, self.blipType))
            if mapBlip then
                local sighted = not self:IsMapBlipVisible()
                mapBlip:UpdateRelevancy( self, sighted )
            end
        end
    end
end

function FogOfWarEntity:OnGetMapBlipInfo()
    --Log("%s-%s -- visible %s", self, EnumToString(kMinimapBlipType, self.blipType), self:IsMapBlipVisible())
    return self:IsMapBlipVisible(), self.blipType, self.blipTeam, false, false
end

local toEntity = Vector()
local function isWithinFov(targetEntity, seeingEntity)
    local withinFOV = true
    -- Anything that has the GetFov method supports FOV checking.
    if seeingEntity.GetFov ~= nil then

        local eyePos = GetEntityEyePos(seeingEntity)
        local targetOrigin = targetEntity:GetOrigin()

        -- Reuse vector
        toEntity.x = targetOrigin.x - eyePos.x
        toEntity.y = targetOrigin.y - eyePos.y
        toEntity.z = targetOrigin.z - eyePos.z

        -- Normalize vector
        local toEntityLength = math.sqrt(toEntity.x * toEntity.x + toEntity.y * toEntity.y + toEntity.z * toEntity.z)
        if toEntityLength > kEpsilon then

            toEntity.x = toEntity.x / toEntityLength
            toEntity.y = toEntity.y / toEntityLength
            toEntity.z = toEntity.z / toEntityLength

        end

        local seeingEntityAngles = GetEntityViewAngles(seeingEntity)
        local normViewVec = seeingEntityAngles:GetCoords().zAxis
        local dotProduct = Math.DotProduct(toEntity, normViewVec)
        local fov = seeingEntity:GetFov()

        -- players have separate fov for marking enemies as sighted
        if seeingEntity.GetMinimapFov then
            fov = seeingEntity:GetMinimapFov(targetEntity)
        end

        local halfFov = math.rad(fov / 2)
        local s = math.acos(dotProduct)
        withinFOV = s < halfFov

    end
    return withinFOV
end

function FogOfWarEntity:OverrideCheckVisibilty(viewer)

    if not Server or not self:IsMapBlipVisible() then
        return false
    end

    if viewer:isa("Scan") then
        local hasExpired = (Shared.GetTime() - viewer:GetCreationTime()) > viewer:GetLifeSpan()
        if not hasExpired then
            return true
        end
    end
    
    local eyePos = GetEntityEyePos(viewer)
    local withinFov = isWithinFov(self, viewer)

    if withinFov then
        local filter = EntityFilterAllButIsa("Door")
        local trace = Shared.TraceRay(eyePos, self:GetOrigin(), CollisionRep.LOS, PhysicsMask.All, filter)

        local viewDistTolerance = 1
        if trace.endPoint:GetDistanceTo(self:GetOrigin()) < viewDistTolerance then
            return true
        end
    end
    return false
end

function FogOfWarEntity:OverrideCheckVision()
    return false
end

Shared.LinkClassToMap("FogOfWarEntity", FogOfWarEntity.kMapName, networkVars)
