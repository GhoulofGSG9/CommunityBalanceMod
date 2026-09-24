-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Alien\Web.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- Spit attack on primary.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Globals.lua")
Script.Load("lua/TechMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/LOSMixin.lua")
Script.Load("lua/OwnerMixin.lua")
Script.Load("lua/ClogFallMixin.lua")
Script.Load("lua/Mixins/BaseModelMixin.lua")
Script.Load("lua/Mixins/ModelMixin.lua")
Script.Load("lua/EffectsMixin.lua")

class 'Web' (Entity)

Web.kMapName = "web"

local kWebModelName = PrecacheAsset("models/alien/gorge/web.model")

local kAnimationGraph = PrecacheAsset("models/alien/gorge/web.animation_graph")

local kWebBabblerTickleDamage = 1 -- Tickle damage (so the enemy makes an "outch" sound)
local kWebBabblerReactInterval = 0.8
local kWebPanicDuration = 4.5

local networkVars =
{
    endPoint = "vector",
    length = "float",
    variant = "enum kGorgeVariants",
    chargeScalingFactor = "float (0 to 3 by 0.01)",
    numWebbedBabblers = "integer (0 to " .. kWebMaxBabblers .. ")"
}

local kWebDistortMaterial = PrecacheAsset("models/alien/gorge/web_distort.material")
local kWebCloakedMaterial = PrecacheAsset("cinematics/vfx_materials/cloaked.material")

AddMixinNetworkVars(TechMixin, networkVars)
AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ModelMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(LOSMixin, networkVars)

local precached = PrecacheAsset("models/alien/gorge/web.surface_shader")
local kWebMaterial = PrecacheAsset("models/alien/gorge/web.material")

function EntityFilterNonWebables()
    return function(test) return not HasMixin(test, "Webable") end
end

function Web:GetWebAxis()

    if self.endPoint == nil then
        return nil
    end

    local origin = self:GetOrigin()

    local cachedOrigin = self.webAxisCacheOrigin
    if cachedOrigin and cachedOrigin.x == origin.x and cachedOrigin.y == origin.y and cachedOrigin.z == origin.z then
        return origin, self.webAxisCacheDir, self.webAxisCacheLength
    end

    local axis = self.endPoint - origin
    local length = axis:GetLength()

    if length < kEpsilon then
        self.webAxisCacheOrigin = nil
        return nil
    end

    axis:Scale(1 / length)

    self.webAxisCacheOrigin = origin
    self.webAxisCacheDir = axis
    self.webAxisCacheLength = length

    return origin, axis, length

end

function Web:SpaceClearForEntity(_)
    return true
end

function Web:OnAdjustModelCoords(modelCoords)

    local result = modelCoords

    if result then
        result.xAxis = result.xAxis * self.chargeScalingFactor
        result.yAxis = result.yAxis * self.chargeScalingFactor
    end

    return result

end

function Web:GetNumWebbedBabblers()

    return self.numWebbedBabblers or 0

end

local function CheckWebablesInRange(self)

    local webables = GetEntitiesWithMixinForTeamWithinRange("Webable", GetEnemyTeamNumber(self:GetTeamNumber()), self:GetOrigin(), self.checkRadius)
    self.enemiesInRange = #webables > 0

    return true

end

local function AddWebCharge(self)

    self.numCharges = Clamp(self.numCharges + 1, 1, kWebMaxCharges)

    self.chargeScalingFactor = self.chargeScalingFactor + kWebChargeScaleAdditive
    self:SetCoords(self:GetCoords())

    self:TriggerEffects("web_charge")

    return self.numCharges < kWebMaxCharges

end

function Web:OnCreate()

    Entity.OnCreate(self)

    InitMixin(self, TechMixin)
    InitMixin(self, EffectsMixin)
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ModelMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LOSMixin)

    InitMixin(self, ClogFallMixin)

    if Server then

        InitMixin(self, InvalidOriginMixin)
        InitMixin(self, OwnerMixin)

        self:AddTimedCallback(CheckWebablesInRange, 0.3) --FIXME Should be moved to trigger or collision as this prevents melee capsule trace from hitting webs
        self:AddTimedCallback(AddWebCharge, kWebSecondsPerCharge)

        self.triggerSpawnEffect = false
        self.webbedBabblers = {}

    end

    self.numCharges = 1
    self.chargeScalingFactor = 1.0
    self.numWebbedBabblers = 0
    self.variant = kGorgeVariants.normal

    self:SetUpdates(true, kDefaultUpdateRate)
    self:SetRelevancyDistance(25) --kMaxRelevancyDistance)

end

function Web:OnInitialized()

    self:SetModel(kWebModelName, kAnimationGraph)
    
    self:SetPhysicsType(PhysicsType.Kinematic)
    self:SetPhysicsGroup(PhysicsGroup.WebsGroup)

    if Server then
        -- Deferred: SetEndPoint is called after OnInitialized by the ability,
        -- so we can't compute the strand axis yet.
        self:AddTimedCallback(Web.AttachInitialBabblers, 0)
    end

end

if Server then

    function Web:AttachInitialBabblers()

        for _ = 1, math.min(kWebNumBabblers, kWebMaxBabblers) do
            local babbler = CreateEntity(Babbler.kMapName, self:GetOrigin(), self:GetTeamNumber())
            if babbler then
                -- These belong to the web, not to a player: they have no owner, so
                -- the usual "kill babblers whose owner went away" path never fires.
                -- Babbler:DetachFromWeb uses this flag to clean them up.
                babbler.webSpawned = true

                if not babbler.AttachToWeb or not babbler:AttachToWeb(self, self:GetOrigin()) then
                    -- Web full / no axis yet: don't leave an ownerless babbler
                    -- loose in the map forever.
                    DestroyEntity(babbler)
                end
            end
        end

        return false -- one-shot callback

    end

    function Web:SetEndPoint(endPoint)
    
        self.endPoint = Vector(endPoint)
        local origin = self:GetOrigin()
        local toEnd = origin - self.endPoint
        local rawLength = toEnd:GetLength()

        self.length = Clamp(rawLength, kMinWebLength, kMaxWebLength)

        local coords = Coords.GetIdentity()
        coords.origin = origin
        coords.zAxis = GetNormalizedVector(toEnd)
        coords.xAxis = coords.zAxis:GetPerpendicular()
        coords.yAxis = coords.zAxis:CrossProduct(coords.xAxis)
        
        self:SetCoords(coords)
        
        self.checkRadius = rawLength * .5 + 1
        
    end

end


if Server then

    function Web:AddWebbedBabbler(babbler)
        if not babbler or self.numWebbedBabblers >= kWebMaxBabblers then
            return
        end

        local babblerId = babbler:GetId()
        if self.webbedBabblers[babblerId] then
            return
        end

        local owner = babbler:GetOwner()
        if owner and not babbler.babblerBombSpawned and HasMixin(owner, "BabblerCling") then
            owner:WebBabblerAdded()
        end
        self.webbedBabblers[babblerId] = true
        self.numWebbedBabblers = self.numWebbedBabblers + 1
    end

    function Web:RemoveWebbedBabbler(babbler)
        if not babbler then
            return
        end

        local babblerId = babbler:GetId()
        if not self.webbedBabblers[babblerId] then
            return
        end

        local owner = babbler:GetOwner()
        if owner and not babbler.babblerBombSpawned and HasMixin(owner, "BabblerCling") then
            owner:WebBabblerRemoved()
        end
        self.webbedBabblers[babblerId] = nil
        self.numWebbedBabblers = math.max(0, self.numWebbedBabblers - 1)
    end

    function Web:DetachAllWebbedBabblers()

        for babblerId, _ in pairs(self.webbedBabblers) do
            local babbler = Shared.GetEntity(babblerId)
            if babbler and babbler.DetachFromWeb then
                babbler:DetachFromWeb()
            end
        end

        self.webbedBabblers = {}
        self.numWebbedBabblers = 0

    end

    -- Finds the closest point on the web's line segment to the given world position,
    -- used to pin a babbler roughly where the owner pressed use.
    function Web:GetClosestPointOnWeb(position)

        local origin = self:GetOrigin()
        local webVector = self.endPoint - origin
        local webLength = webVector:GetLength()

        if webLength < kEpsilon then
            return Vector(origin)
        end

        webVector:Scale(1 / webLength)
        local t = Clamp(webVector:DotProduct(position - origin), 0, webLength)

        return origin + webVector * t

    end

end

function Web:GetIsFlameAble()
    return true
end

function Web:OverrideCheckVision()
    return false
end

function Web:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint)

    -- webs can't be destroyed with bullet weapons
    if doer ~= nil and not (doer:isa("Axe") or doer:isa("Submachinegun") or doer:isa("Grenade") or doer:isa("ClusterGrenade") or doer:isa("Flamethrower") or damageType == kDamageType.Flame) then
        damageTable.damage = 0
    end

end

if Server then

    function Web:GetDestroyOnKill()
        return true
    end

    function Web:OnKill()
        self:DetachAllWebbedBabblers()
        self:TriggerEffects("death")
    end

    function Web:SetVariant(gorgeVariant)
        self.variant = 1 -- No other skins exist for webs. This causes massive console spam with gorgeVariant!!!
    end

end

local function TriggerWebDestroyEffects(self)

    local coords = self:GetCoords()
    local startPoint = coords.origin
    local zAxis = -coords.zAxis
    
    for i = 1, 20 do

        local effectPoint = startPoint + zAxis * 0.36 * i
        
        if (effectPoint - startPoint):GetLength() >= self.length then
            break
        end
        
        coords.origin = effectPoint

        self:TriggerEffects("web_destroy", { effecthostcoords = coords })    
    
    end

end

function Web:OnDestroy()

    Entity.OnDestroy(self)
    
    if self.webRenderModel then
    
        DynamicMesh_Destroy(self.webRenderModel)
        self.webRenderModel = nil
        
    end
    
    -- TODO
    -- Shouldn't this be in OnKill, not OnDestroy???
    if Server then
        self:DetachAllWebbedBabblers()
        TriggerWebDestroyEffects(self)
    end

end

function Web:GetDistortMaterialName()
    return kWebDistortMaterial
end

if Client then
    
    function Web:OnUpdateRender()
        
        if self.webRenderModel then
            if self.variant == kGorgeVariants.toxin then
                self._renderModel:SetMaterialParameter("textureIndex", 1 )
            else
                self._renderModel:SetMaterialParameter("textureIndex", 0 )
            end
        end
        
        local player = Client.GetLocalPlayer()
        local model = self:GetRenderModel()

        if player and model and self.endPoint then

            local isFriendly = GetAreFriends(self, player)

            local selfOrigin = self:GetOrigin()
            local playerOrigin = player:GetOrigin()

            -- Try distances from both endpoints and the middle, and use the shortest one.
            -- We compare the midpoint and the origin distance first, since the midpoint is the most common case in-game (from close range)
            local midPoint = (selfOrigin + self.endPoint) * 0.5
            local midDistance = (midPoint - playerOrigin):GetLengthSquared()
            local originDistance = (selfOrigin - playerOrigin):GetLengthSquared()

            local distance = midDistance

            -- Since midpoint will never be the furthest point, we can potentially eliminate a length calculation.
            if originDistance <= midDistance then
                distance = originDistance
            else
                -- Either the endpoint or midpoint is closest
                local endDistance = (self.endPoint - playerOrigin):GetLengthSquared()
                if endDistance < midDistance then
                    distance = endDistance
                end
            end

            distance = math.sqrt(distance)
            local opaque = Clamp((distance - kWebFullVisDistance) / (kWebZeroVisDistance - kWebFullVisDistance), 0, 1)

            if isFriendly then
                if not self.cloakedMaterial then
                    self.cloakedMaterial = AddMaterial(model, kWebCloakedMaterial)
                end

                if self.distortMaterial then
                    RemoveMaterial(model, self.distortMaterial)
                    self.distortMaterial = nil
                end
            else
                if not self.distortMaterial then
                    self.distortMaterial = AddMaterial(model, kWebDistortMaterial)
                    self.distortMaterial:SetParameter("noVisDist", kWebDistortionZeroVisDistance)
                    self.distortMaterial:SetParameter("fullVisDist", kWebDistortionFullVisDistance)
                    self.distortMaterial:SetParameter("distortionIntensity", kWebDistortionIntensity)
                end

                if self.cloakedMaterial then
                    RemoveMaterial(model, self.cloakedMaterial)
                    self.cloakedMaterial = nil
                end
            end

            if self.cloakedMaterial then
                self:SetOpacity(1 - opaque, "cloak")
                self.cloakedMaterial:SetParameter("cloakAmount", Clamp(opaque, 0, 0.2))
            end

            if self.distortMaterial then
                self:SetOpacity(1 - opaque, "cloak")
            end
        end
        
    end
    
end

function Web:GetIsCamouflaged()
    return true
end

local function GetDistance(coords, fromPlayer)

    local tranformCoords = coords:GetInverse()
    local relativePoint = tranformCoords:TransformPoint(fromPlayer:GetOrigin())

    return math.abs(relativePoint.x), relativePoint.y

end

local function AlertWebbedBabblers(self, fromPlayer)

    local now = Shared.GetTime()
    if self.timeLastBabblerReact and now - self.timeLastBabblerReact < kWebBabblerReactInterval then
        return
    end
    self.timeLastBabblerReact = now

    if not fromPlayer or not fromPlayer:GetIsAlive() then return end

    local extents = fromPlayer:GetExtents()
    local torsoPoint = fromPlayer:GetOrigin() + Vector(0, extents.y, 0)
    local contactPoint = self:GetClosestPointOnWeb(torsoPoint)

    for babblerId, _ in pairs(self.webbedBabblers) do
        local babbler = Shared.GetEntity(babblerId)
        if babbler and babbler:GetIsAlive() then

            babbler:PanicFromWeb(kWebPanicDuration)

            local separation = (babbler:GetOrigin() - contactPoint):GetLength()
            if separation < 2.5 then
                babbler:TriggerEffects("babbler_engage")
                fromPlayer:TakeDamage(kWebBabblerTickleDamage, babbler, babbler,
                        contactPoint, nil, 0, kWebBabblerTickleDamage, kDamageType.Normal)
            end
        end
    end

end

local function RemoveWebCharge(self, fromPlayer)

    self.numCharges = self.numCharges - 1
    local isAlive = self.numCharges > 0

    if isAlive then
        self.chargeScalingFactor = self.chargeScalingFactor - kWebChargeScaleAdditive
    end

    AlertWebbedBabblers(self, fromPlayer)

    return isAlive

end

local function CheckForIntersection(self, fromPlayer)

    if fromPlayer then

        -- need to manually check for intersection here since the local players physics are invisible and normal traces would fail
        local coords = self:GetCoords()
        local playerOrigin = fromPlayer:GetOrigin()
        local extents = fromPlayer:GetExtents()
        local fromWebVec = playerOrigin - coords.origin
        local webDirection = -coords.zAxis
        local dotProduct = webDirection:DotProduct(fromWebVec)

        local minDistance = - extents.z
        local maxDistance = self.length + extents.z

        if dotProduct >= minDistance and dotProduct < maxDistance then

            local horizontalDistance, verticalDistance = GetDistance(coords, fromPlayer)

            local horizontalOk = horizontalDistance <= extents.z
            local verticalOk = verticalDistance >= 0 and verticalDistance <= extents.y * 2

            if horizontalOk and verticalOk and HasMixin(fromPlayer, "Webable") then

                local shouldPlayEffects = false
                if not fromPlayer.lastWebbedSource or fromPlayer.lastWebbedSource ~= self:GetId() then
                    shouldPlayEffects = true
                end

                fromPlayer.lastWebbedSource = self:GetId()
                fromPlayer:SetWebbed(kWebbedDuration, shouldPlayEffects)

                if Server and shouldPlayEffects then

                    if not RemoveWebCharge(self, fromPlayer) then
                        self:Kill(nil, nil, coords.origin)
                    end

                end
            else
                if fromPlayer.lastWebbedSource and fromPlayer.lastWebbedSource == self:GetId() then
                    fromPlayer.lastWebbedSource = nil
                end
            end
        end

    elseif Server then

        self.webbedEntityCache = self.webbedEntityCache or {}

        local origin = self:GetOrigin()
        local trace = Shared.TraceRay(origin, self.endPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterNonWebables())
        if trace.entity and not trace.entity:isa("Player") and trace.entity.SetWebbed then

            local entityId = trace.entity:GetId()
            local shouldPlayEffects = false
            if not self.webbedEntityCache[entityId] then
                self.webbedEntityCache[entityId] = true
                shouldPlayEffects = true
            end

            trace.entity:SetWebbed(kWebbedDuration, shouldPlayEffects)

            if shouldPlayEffects then

                if not RemoveWebCharge(self) then
                    self:Kill(nil, nil, origin)
                end

            end

        else
            self.webbedEntityCache = {}
        end

    end

end

local kWebAttachMargin = 0.2
function Web:GetFreeBabblerAttachPointOrigin(babbler)
    local startPoint, axis, length = self:GetWebAxis()

    if not axis then
        return nil
    end

    -- Do not go to the edges of the web (they can be buried in geometry)
    local margin = math.min(kWebAttachMargin, length * 0.25)
    local usable = math.max(length - margin * 2, 0)

    local fraction = 0.5
    if babbler and babbler.GetId then
        -- Golden-ratio scatter: consecutive entity ids land far apart
        fraction = (babbler:GetId() * 0.618033988749895) % 1
    end

    return startPoint + axis * (margin + usable * fraction)
end

-- TODO: somehow the pose params dont work here when using clientmodelmixin. should figure out why this is broken and switch to clientmodelmixin
function Web:OnUpdatePoseParameters()
    -- Model is a bit longer, scale length down
    self:SetPoseParam("scale", self.length * 0.8425)
end

-- called by the players so they can predict the web effect
function Web:UpdateWebOnProcessMove(fromPlayer)
    CheckForIntersection(self, fromPlayer)
end

if Server then

    function Web:TriggerWebSpawnEffects()

        local coords = self:GetCoords()
        local startPoint = coords.origin
        local zAxis = -coords.zAxis
        
        for i = 1, 20 do

            local effectPoint = startPoint + zAxis * 0.36 * i
            
            if (effectPoint - startPoint):GetLength() >= self.length then
                break
            end

            self:TriggerEffects("web_create", { effecthostcoords = Coords.GetTranslation(effectPoint) })    
        
        end
    
    end

    -- OnUpdate is only called when entities are in interest range, players are ignored here since they need to predict the effect
    function Web:OnUpdate(deltaTime)

        if self.enemiesInRange then
            CheckForIntersection(self)
        end

        if not self.triggerSpawnEffect then
            self:TriggerWebSpawnEffects()
            self.triggerSpawnEffect = true
        end

    end
    
    function Web:GetSendDeathMessageOverride()
        return false
    end

end

Shared.LinkClassToMap("Web", Web.kMapName, networkVars)
