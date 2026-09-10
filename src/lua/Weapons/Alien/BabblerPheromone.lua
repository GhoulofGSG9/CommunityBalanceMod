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

local kBabblerTargetLateralPenalty = 2
local kUpVector = Vector(0, 0.5, 0)
function BabblerPheromone:GetTarget(owner)
    local orig = self:GetOrigin()
    local ownerOrig = owner:GetOrigin()
    local midWayOrig = (orig + ownerOrig) * 0.5

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

    return bestEnt
end

-- Gathers every babbler this ball's owner can command, closest first, with
-- already-loose babblers preferred over ones still riding the owner (so a
-- hit doesn't yank a babbler off the owner if a free one nearby can do the
-- job instead).
local function CollectBabblers(self)

    local owner = self:GetOwner()
    local searchOrigin = owner and owner:GetOrigin() or self:GetOrigin()

    local recruits = {}
    local babblers = GetEntitiesForTeamWithinRange("Babbler", self:GetTeamNumber(), searchOrigin, kBabblerSearchRange)

    for _, babbler in ipairs(babblers) do
        if babbler:GetOwnerId() == self:GetOwnerId() and not babbler:GetIsOnWeb() then
            table.insert(recruits, babbler)
        end
    end

    local fieldBabblerPriorityRatio = 2.5
    table.sort(recruits, function(a, b)
        return a:GetOrigin():GetDistanceTo(searchOrigin) * (a:GetIsClinged() and fieldBabblerPriorityRatio or 1)
        < b:GetOrigin():GetDistanceTo(searchOrigin) * (b:GetIsClinged() and fieldBabblerPriorityRatio or 1)
    end)

    return recruits

end

local kDisptatchSpreadedPosition = Vector(0,0,0)
-- The single dispatch point for every order this ball ever gives. 'order'
-- is always one of the three outcomes from GetBabblerBallOrder (or plain
-- Move for "nothing worth clinging/attacking here, just walk over"). Clinged
-- babblers are detached first since a clinged babbler doesn't process
-- orders at all (see Babbler:UpdateBabbler's early-out) until it's free.
local function DispatchBabblers(babblers, order, entity, position, spots)

    for _, babbler in ipairs(babblers) do

        if spots ~= nil and spots <= 0 then break end

        if babbler:GetIsClinged() then
            babbler:Detach()
        end

        if order == kBabblerMoveType.Cling then
            babbler:OrderCling(entity, position)
        elseif order == kBabblerMoveType.Attack then
            babbler:OrderAttack(entity, position)
        else
            VectorCopy(position, kDisptatchSpreadedPosition)
            -- Spread a bit the order so babblers won't end up 100% stacked on the same position
            kDisptatchSpreadedPosition.x = kDisptatchSpreadedPosition.x + (math.random()-0.5)/2
            kDisptatchSpreadedPosition.z = kDisptatchSpreadedPosition.z + (math.random()-0.5)/2
            babbler:OrderMove(kDisptatchSpreadedPosition)
        end

        babbler:RefreshFreeRoam()

        if spots ~= nil then
            spots = spots - 1
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

    -- Room left on a clingable host; nil = no cap (Move/Attack, or a target
    -- that hosts no limited cling room). Callers treat nil as unbounded.
    local function GetClingSpotsCount(entity)
        if not entity then return nil end
        if entity:isa("Web") then
            return kWebMaxBabblers - entity:GetNumWebbedBabblers()
        elseif HasMixin(entity, "BabblerCling") then
            return math.max(entity:GetMaxClingedBabblers() - entity:GetNumClingedBabblers(), 0)
        end
        return nil
    end

    -- Immediate response on throw: give babblers a head start toward
    -- whatever's in the owner's view before the ball has even had a
    -- chance to physically hit anything.
    function BabblerPheromone:OnUpdate(deltaTime)

        Projectile.OnUpdate(self, deltaTime)

        if not self.firstUpdate then

            self.firstUpdate = true

            local owner = self:GetOwner()
            local forwardViewDir = owner and GetNormalizedVectorXZ(owner:GetViewCoords().zAxis)
            local dirPos = owner and owner:GetOrigin() + forwardViewDir * 5 or nil

            local target = owner and self:GetTarget(owner)
            local order = target and GetBabblerBallOrder(owner, target) or kBabblerMoveType.Move
            local position = target and GetEngagementOrOrigin(target) or dirPos

            DispatchBabblers(CollectBabblers(self), order, target, position)

        end

    end

    -- ===== The three ball-driven outcomes =====
    -- hit a player or a web    -> cling
    -- hit an enemy              -> attack
    -- hit nothing usable        -> move to where the ball ended up
    -- All three funnel through GetBabblerBallOrder (Babbler.lua) and
    -- Babbler:OrderCling/OrderAttack/OrderMove so there is exactly one
    -- place that decides "what does this hit mean".
    function BabblerPheromone:ProcessHit(entity, surface, normal, endPoint )

        if self.babblerOrderingDisabled then
            return false
        end

        -- If we bounce close enough to our own owner, treat it as hitting
        -- them (don't wait for the small ball hitbox to register a real
        -- touch) - this is how throwing the ball at your own feet reclaims
        -- babblers.
        local owner = self:GetOwner()
        local selfSnappingDist = 0.75
        if not entity and owner and self:GetOrigin():GetDistanceTo(owner:GetOrigin()) < selfSnappingDist then
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
                local position = target and GetEngagementOrOrigin(target) or self:GetOrigin()

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
        DispatchBabblers(CollectBabblers(self), order, entity, endPoint, GetClingSpotsCount(entity))

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
