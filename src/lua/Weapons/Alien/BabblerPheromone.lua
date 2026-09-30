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
        self.currentBounceCount = 0
        self.maxBounceRegistered = 3

    end

    self.radius = 0.125
    self.mass = 3
    self.linearDamping = 0
    self.restitution = 0.55 -- How hard it bouncves
    self:SetGroupFilterMask(PhysicsMask.NoBabblers)

end

-- Gathers every babbler this ball's owner can command, closest first, with
-- already-loose babblers preferred over ones still riding the owner (so a
-- hit doesn't yank a babbler off the owner if a free one nearby can do the
-- job instead).
local function CollectBabblers(self)

    local owner = self:GetOwner()
    local searchOrigin = owner and owner:GetOrigin() or self:GetOrigin()

    local recruits = {}

    local ownerId = self:GetOwnerId()
    if not ownerId or ownerId == Entity.invalidId then
        return recruits
    end

    local babblers = GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), searchOrigin, kBabblerSearchRange)

    local sortKeys = {}
    local fieldBabblerPriorityRatio = 2.5

    for _, babbler in ipairs(babblers) do
        if babbler:GetOwnerId() == ownerId and babbler:GetIsAlive() and not babbler:GetIsOnWeb() then
            table.insert(recruits, babbler)
            sortKeys[babbler] = babbler:GetOrigin():GetDistanceTo(searchOrigin)
                    * (babbler:GetIsClinged() and fieldBabblerPriorityRatio or 1)
        end
    end

    table.sort(recruits, function(a, b)
        return sortKeys[a] < sortKeys[b]
    end)

    return recruits

end

local function DispatchBabblers(babblers, order, entity, position, spots)

    if not position then
        return
    end

    for _, babbler in ipairs(babblers) do

        if spots ~= nil and spots <= 0 then break end

        local isClinged = babbler:GetIsClinged()

        local alreadyThere = order == kBabblerMoveType.Cling
                and entity ~= nil
                and isClinged
                and babbler:GetParent() == entity

        if not alreadyThere then

            if isClinged then
                babbler:Detach()
            end

            if order == kBabblerMoveType.Cling then
                babbler:OrderCling(entity, position)
            elseif order == kBabblerMoveType.Attack then
                babbler:OrderAttack(entity, position)
            else
                babbler:OrderMove(Vector(position.x + (math.random() - 0.5) / 2,
                                         position.y + math.random() / 2,
                                         position.z + (math.random() - 0.5) / 2))
            end

            babbler:RefreshFreeRoam()

        end

        if spots ~= nil then
            spots = spots - 1
        end

    end

end

-- Immediate response on throw: give babblers a head start toward
-- whatever's in the owner's view before the ball has even had a
-- chance to physically hit anything.
function BabblerPheromone:InitialDispatch()

    local owner = self:GetOwner()
    if owner and HasMixin(owner, "Live") and not owner:GetIsAlive() then
        owner = nil
    end

    local dirPos
    if owner and owner.GetViewCoords then
        local forwardViewDir = GetNormalizedVectorXZ(owner:GetViewCoords().zAxis)
        -- Looking straight up or down normalizes to (0,0,0); fall back to
        -- the owner's own position rather than ordering everyone onto it.
        if forwardViewDir:GetLengthSquared() > kEpsilon then
            dirPos = owner:GetOrigin() + forwardViewDir * 5
        else
            dirPos = Vector(owner:GetOrigin())
        end
    end

    local target = owner and self:GetTarget(owner)
    local order = target and GetBabblerBallOrder(owner, target) or kBabblerMoveType.Move
    local position = target and GetEngagementOrOrigin(target) or dirPos

    DispatchBabblers(CollectBabblers(self), order, target, position)

end

local kBabblerTargetLateralPenalty = 2
local kUpVector = Vector(0, 0.5, 0)
function BabblerPheromone:GetTarget(owner)
    local orig = self:GetOrigin()
    local ownerOrig = owner:GetOrigin()
    local midWayOrig = (orig + ownerOrig) * 0.5

    local dir = orig - ownerOrig
    local dirLength = dir:GetLength()

    if dirLength < kEpsilon then -- Too close
        return nil
    end

    local searchRange = dirLength * 0.5 + kBabblerTargetSearchRange
    dir:Scale(1 / dirLength)

    local enemyTeamNumber = GetEnemyTeamNumber(self:GetTeamNumber())
    local nearestTargets = GetEntitiesForTeamWithinRange("Player", enemyTeamNumber, midWayOrig, searchRange)

    local bestEnt, bestScore = nil, nil

    for _, ent in ipairs(nearestTargets) do

        if ent then

            local entOrigin = ent:GetOrigin()

            if not GetWallBetween(ownerOrig + kUpVector, entOrigin + kUpVector, ent) then

                local toEnt = entOrigin - ownerOrig

                local alongDir = Math.DotProduct(toEnt, dir)

                if alongDir > 0 then

                    local lateral = (toEnt - dir * alongDir):GetLength()
                    local score = alongDir + lateral * kBabblerTargetLateralPenalty

                    if not bestScore or score < bestScore then
                        bestEnt = ent
                        bestScore = score
                    end

                end

            end

        end

    end

    return bestEnt
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

        local destinationEntity = self.destinationEntityId and self.destinationEntityId ~= Entity.invalidId
                and Shared.GetEntity(self.destinationEntityId)

        if destinationEntity then
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

    -- Room left on a clingable host; nil = no cap (Move/Attack, or a target
    -- that hosts no limited cling room). Callers treat nil as unbounded.
    local function GetClingSpotsCount(owner, entity)
        if not entity then return nil end

        if entity:isa("Web") then
            return math.max(kWebMaxBabblers - entity:GetNumWebbedBabblers() - GetNumBabblersEnRouteToCling(entity), 0)
        elseif HasMixin(entity, "BabblerCling") and owner ~= entity then
            return entity:GetNumFreeDonationSpots()
        end
        return nil -- No restriction
    end

    -- directAim is true only when BabblerAbility resolved the hit itself from the
    -- player's crosshair. A ball that ballistically collides with a web is not a
    -- deliberate cling order, so it's treated as if nothing was hit.
    function BabblerPheromone:ProcessHit(entity, surface, normal, endPoint, directAim)

        if self.babblerOrderingDisabled then
            return false
        end

        if entity and not directAim and entity:isa("Web") then
            entity = nil
        end

        --self.firstUpdate = true
        local orig = self:GetOrigin()

        -- If we bounce close enough to our own owner, treat it as hitting
        -- them (don't wait for the small ball hitbox to register a real
        -- touch) - this is how throwing the ball at your own feet reclaims
        -- babblers.
        local owner = self:GetOwner()
        local selfSnappingDist = 0.75
        if not entity and owner and orig:GetDistanceTo(owner:GetOrigin()) < selfSnappingDist then
            entity = owner
        end

        if not entity then

            -- Nothing hit yet: give a move order on the first few positions
            -- the ball bounces through, so babblers can path in behind
            -- corners instead of waiting for a direct hit that may never
            -- come. Capped so a long bounce doesn't spam orders every tick.
            self.currentBounceCount = self.currentBounceCount + 1
            if self.currentBounceCount <= self.maxBounceRegistered then

                local target = owner and self:GetTarget(owner)
                local order = target and GetBabblerBallOrder(owner, target) or kBabblerMoveType.Move
                local position = target and GetEngagementOrOrigin(target) or orig

                DispatchBabblers(CollectBabblers(self), order, target, position)

            end

            return false

        end

        local order = GetBabblerBallOrder(owner, entity)

        -- Hit something real but not worth an order (a corpse, a structure
        -- that can't host a cling, etc.) - let the ball keep flying rather
        -- than pop it on an irrelevant graze.
        if order == kBabblerMoveType.Move then
            return false
        end

        self.impact = true
        self.destinationEntityId = entity:GetId()
        self:SetModel(nil)
        self:TriggerEffects("babbler_pheromone_puff")
        self.triggeredPuff = true

        -- Cap how many babblers can pile onto a target with limited room;
        -- Attack has no such cap.
        DispatchBabblers(CollectBabblers(self), order, entity,
                endPoint or GetEngagementOrOrigin(entity), GetClingSpotsCount(owner, entity))

        DestroyEntity(self)
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
