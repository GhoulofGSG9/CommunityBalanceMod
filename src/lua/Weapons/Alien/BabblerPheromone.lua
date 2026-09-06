-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\BabblerPheromone.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
--    Attracts babblers.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/TeamMixin.lua")

class 'BabblerPheromone' (Projectile)

BabblerPheromone.kMapName = "babblerpheromone"
BabblerPheromone.kModelName = PrecacheAsset("models/alien/babbler/babbler_ball.model")

local precached1 = PrecacheAsset("models/alien/babbler/babbler_ball.surface_shader")

local kBabblerTargetSearchRange = 15
local kBabblerSearchRange = 1000
local kBabblerPheromoneDuration = 5
local kPheromoneEffectInterval = 0.15

local networkVars =
{
    destinationEntityId = "entityid",
    impact = "boolean"
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ModelMixin, networkVars)

function BabblerPheromone:OnCreate()

    Projectile.OnCreate(self)
    
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ModelMixin)

    if Server then
    
        self.destinationEntityId = Entity.invalidId

        self:AddTimedCallback(BabblerPheromone.TimeUp, kBabblerPheromoneDuration)
        self.impact = false
        self.worldCollision = false

    end

    self.radius = 0.125
    self.mass = 3
    self.linearDamping = 0
    self.restitution = 0.55 -- How hard it bouncves
    self:SetGroupFilterMask(PhysicsMask.NoBabblers)

end

local kBabblerTargetLateralPenalty = 2
local kUpVector = Vector(0, 0.5, 0)
function BabblerPheromone:GetTarget(owner)
    local orig = self:GetOrigin()
    local ownerOrig = owner:GetOrigin()
    local midWayOrig = (orig + ownerOrig) * 0.5

    -- Direction from owner to pheromone
    local dir = orig - ownerOrig
    local dirLength = dir:GetLength()
    local searchRange = dir:GetLength() * 0.5 + kBabblerTargetSearchRange

    if dirLength < kEpsilon then -- Too close
        return nil
    end
    dir:Scale(1 / dirLength)

    local enemyTeamNumber = GetEnemyTeamNumber(self:GetTeamNumber())
    local nearestTargets = GetEntitiesForTeamWithinRange("Player", enemyTeamNumber, midWayOrig, searchRange)

    local bestEnt, bestScore = nil, nil

    for _, ent in ipairs(nearestTargets) do

        if ent and not GetWallBetween(ownerOrig + kUpVector, ent:GetOrigin() + kUpVector, ent) then

            local toEnt = ent:GetOrigin() - ownerOrig

            -- Projection along owner->pheromone axis
            local alongDir = Math.DotProduct(toEnt, dir)

            -- Only consider entities at or beyond the owner, in the pheromone's direction
            if alongDir > 0 then

                -- Perpendicular distance from the owner->pheromone ray
                local lateral = (toEnt - dir * alongDir):GetLength()

                -- Score: prioritize being on the owner->pheromone line, then closeness to owner
                local score = alongDir + lateral * kBabblerTargetLateralPenalty

                if not bestScore or score < bestScore then
                    bestEnt = ent
                    bestScore = score
                end

            end

        end

    end

    return bestEnt
end

-- Force order for all babblers to the same target
function BabblerPheromone:MoveBabblers()
	local orig = self:GetOrigin()
	local owner = self:GetOwner()
	local ownerId = self:GetOwnerId()
	
	local target = self:GetTarget(owner)
	local targetPos = target and (target.GetEngagementPoint and target:GetEngagementPoint() or target:GetOrigin())

	for _, babbler in ipairs(GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), orig, kBabblerSearchRange)) do
		if babbler:GetOwnerId() == ownerId and not babbler:GetIsOnWeb() then
			if babbler:GetIsClinged() and babbler:GetParent() == owner then
				babbler:Detach()
			end

			if target then
				-- Log("Attack group order issued by the bait toward %s", target)
				babbler:SetMoveType(kBabblerMoveType.Attack, target, targetPos, true)
			else --if babbler.moveType ~= kBabblerMoveType.Attack then
				-- Log("Move group order issued by the bait toward %s", target)
				babbler:SetMoveType(kBabblerMoveType.Move, nil, self:GetOrigin(), true)
			end

            babbler:RefreshFreeRoam()
		end
	end
end

function BabblerPheromone:GetProjectileModel()
    return BabblerPheromone.kModelName
end

function BabblerPheromone:OnDestroy()
    
    Projectile.OnDestroy(self)
    
    if Server and not self.triggeredPuff then
        self:TriggerEffects("babbler_pheromone_puff")  
    end
        
end

function BabblerPheromone:OnUpdateRender()

    if not self.timeLastPheromoneEffect or self.timeLastPheromoneEffect + kPheromoneEffectInterval < Shared.GetTime() then

        if self.destinationEntityId and self.destinationEntityId ~= Entity.invalidId and Shared.GetEntity(self.destinationEntityId) then
            
            local destinationEntity = Shared.GetEntity(self.destinationEntityId)
            destinationEntity:TriggerEffects("babbler_pheromone")
            
        else
            self:TriggerEffects("babbler_pheromone")
        end
        
        self.timeLastPheromoneEffect = Shared.GetTime()
    
    end
    
end

function BabblerPheromone:GetSimulatePhysics()
    return not self.impact
end

function BabblerPheromone:SetAttached(target)
    self.destinationEntityId = target:GetId()
end

if Server then

    function BabblerPheromone:OnUpdate(deltaTime)

        Projectile.OnUpdate(self, deltaTime)

        if not self.firstUpdate then

            self.firstUpdate = true

            local gorge = self:GetOwner()
            local gorgeId = self:GetOwnerId()
            for _, babbler in ipairs(GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), self:GetOrigin(), kBabblerSearchRange )) do

                if babbler:GetIsClinged() and babbler:GetOwnerId() == gorgeId and babbler:GetParent() == gorge then

                    babbler:Detach()

                end

            end

        end

    end

    local function CanGetAttach(self, entity)
        -- Can only attach to friends
        if not GetAreFriends(self, entity) then
            return false
        end

        -- Can only attach when there are attach points available
        if HasMixin(entity, "BabblerCling") and not entity:GetCanAttachBabbler() then
            return false
        end

        -- Don't attach to babbler owners that allready have max babblers
        -- Exclude current owner so gorge can reattack own bablers
        local owner = self:GetOwner()
        if entity ~= owner and HasMixin(entity, "BabblerOwner")
                and entity:GetBabblerCount() >= entity:GetMaxBabblers() then
            return false
        end

        return true
    end

    -- Helper function to adjust babbler move type
    local function GetMoveType(self, entity)
        local moveType = kBabblerMoveType.Move

        if CanGetAttach(self, entity) then
            moveType = kBabblerMoveType.Cling
        elseif GetAreEnemies(self, entity) and HasMixin(entity, "Live") and entity:GetIsAlive() and entity:GetCanTakeDamage() or ( entity:isa("PowerPoint") and entity:GetBuiltFraction() >= 0.009 ) then
            moveType = kBabblerMoveType.Attack
        end

        return moveType
    end

    local function CollectRecruits(self)

        local owner = self:GetOwner()
        local searchOrigin = owner and owner:GetOrigin() or self:GetOrigin()

        local recruits = {}
        local babblers = GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), searchOrigin, kBabblerSearchRange)
        Shared.SortEntitiesByDistance(searchOrigin, babblers)

        for _, babbler in ipairs(babblers) do
            if babbler:GetOwnerId() == self:GetOwnerId() and not babbler:GetIsOnWeb() then
                table.insert(recruits, babbler)
            end
        end

        table.sort(recruits, function(a, b)
            return (a:GetIsClinged() and 1 or 0) < (b:GetIsClinged() and 1 or 0)
        end)

        return recruits

    end

    local function SendBabblersToWeb(self, web, impactPoint, spots)

        for _, babbler in ipairs(CollectRecruits(self)) do
            if spots <= 0 then break end
            if babbler:GetIsClinged() then
                babbler:Detach()
            end
            -- SetWebOrder can refuse (dead web, already webbed); only count real dispatches
            if babbler:SetWebOrder(web, impactPoint) then
                spots = spots - 1
            end
        end

    end

    function BabblerPheromone:ProcessHit(entity, surface, normal, endPoint )

        if not entity then
            self:MoveBabblers() -- world bounce: recall the squad
            return false
        end

        -- Recalling the whole roster
        if not self.worldCollision then
            self.worldCollision = true
            if not entity:isa("Web") and not GetAreFriends(self, entity) then
                self:MoveBabblers()
            end
        end

        local isWeb = entity:isa("Web")
        local webSpotsLeft = isWeb and (kWebMaxBabblers - entity:GetNumWebbedBabblers()) or 0

        local isValidHit = ( entity:isa("PowerPoint") and entity:GetBuiltFraction() >= 0.009 )
                or ( isWeb )
                or ( (GetAreEnemies(self, entity) or HasMixin(entity, "BabblerCling"))
                        and HasMixin(entity, "Live") and entity:GetIsAlive() )

        if not isValidHit then        
            return false
        end

        self.impact = true
        if not (entity:GetCanTakeDamage() or isWeb) then
            return false
        end

        self.destinationEntityId = entity:GetId()
        self:SetModel(nil)
        self:TriggerEffects("babbler_pheromone_puff")
        self.triggeredPuff = true

        if isWeb then
            -- Only dispatch as many babblers as the strand has room for
            SendBabblersToWeb(self, entity, endPoint, webSpotsLeft)
        else

            local owner = self:GetOwner()
            local moveType = GetMoveType(self, entity)
            local position = HasMixin(entity, "Target") and entity:GetEngagementPoint() or entity:GetOrigin()

            local spots = kBabblerSearchRange
            if moveType == kBabblerMoveType.Cling then
                spots = math.max(entity:GetMaxClingedBabblers() - entity:GetNumClingedBabblers(), 0)
            end

            for _, babbler in ipairs(CollectRecruits(self)) do

                if spots <= 0 then break end

                local isRider = babbler:GetIsClinged() and babbler:GetParent() == owner

                -- Riders only join Cling dispatches (where a slot is budgeted
                -- for them); Attack/Move orders are for babblers already free
                if moveType == kBabblerMoveType.Cling or not isRider then

                    if isRider then
                        babbler:Detach()
                    end

                    babbler:SetMoveType(moveType, entity, position, true)
                    if moveType == kBabblerMoveType.Attack then
                        babbler:TriggerEffects("babbler_engage")
                    end

                    spots = spots - 1

                end

            end

        end

        DestroyEntity(self) -- Now handled inside CreateBabblerPheromone()
        return true

    end
    
    function BabblerPheromone:OnEntityChange(oldId)

        if oldId == self.destinationEntityId then
            DestroyEntity(self)
        end
         
    end

    function BabblerPheromone:GetIsAttached()
        return self.destinationEntityId ~= Entity.invalidId
    end
    
    function BabblerPheromone:TimeUp()
        DestroyEntity(self)
    end

end

Shared.LinkClassToMap("BabblerPheromone", BabblerPheromone.kMapName, networkVars)
