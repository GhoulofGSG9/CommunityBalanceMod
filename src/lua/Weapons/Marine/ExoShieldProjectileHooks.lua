if Server then
    Script.Load("lua/Weapons/Alien/Bomb.lua")
    Script.Load("lua/WhipBomb.lua")
end
if gExoBarrierHooksInstalled then return end
gExoBarrierHooksInstalled = true

-- Friendly weapon traces ignore their own team's barrier, while enemy traces
-- still hit its single collision body. Keep the original filter semantics.
local function ShieldFriendlyFilter(filter, entity)
    if (gExoBarrierInstanceCount or 0) == 0 then return filter end
    if not entity or not entity.GetTeamNumber then return filter end
    local team = entity:GetTeamNumber()
    if team ~= kTeam1Index then return filter end
    return function(candidate)
        return filter(candidate) or (candidate and candidate:isa("ExoShield") and candidate:GetTeamNumber() == team)
    end
end
function ExoShieldFilterFriendlyTrace(filter, entity)
    return ShieldFriendlyFilter(filter, entity)
end
local originalFilterOne = EntityFilterOne
function EntityFilterOne(entity)
    return ShieldFriendlyFilter(originalFilterOne(entity), entity)
end
local originalFilterTwo = EntityFilterTwo
function EntityFilterTwo(a, b)
    return ShieldFriendlyFilter(originalFilterTwo(a, b), a and a.GetTeamNumber and a or b)
end
local originalFilterOneAndIsa = EntityFilterOneAndIsa
function EntityFilterOneAndIsa(entity, className)
    return ShieldFriendlyFilter(originalFilterOneAndIsa(entity, className), entity)
end

if Server then
    local function IsShieldImpact(projectile, target)
        return target and target:isa("ExoShield") and target:GetIsShieldActive()
            and target:GetTeamNumber() ~= projectile:GetTeamNumber()
    end
    -- Consume incoming bombs before their normal splash/DOT marker is created.
    if Bomb and Bomb.ProcessHit then
        local original = Bomb.ProcessHit
        function Bomb:ProcessHit(target, surface, normal)
            if IsShieldImpact(self, target) then
                target:AbsorbProjectile(self)
                DestroyEntity(self)
                return
            end
            return original(self, target, surface, normal)
        end
    end
    if WhipBomb and WhipBomb.ProcessHit then
        local original = WhipBomb.ProcessHit
        function WhipBomb:ProcessHit(target)
            if IsShieldImpact(self, target) then
                target:AbsorbProjectile(self)
                DestroyEntity(self)
                return
            end
            return original(self, target)
        end
    end
end

-- A transparent barrier must not make a marine vanish from a hydra's LOS target check.
-- This filter is used only for acquisition. Hydra spike damage traces still hit the barrier.
if Hydra_EntityFilterTwoAndIsaTwo then
    local nativeHydraLOSFilter = Hydra_EntityFilterTwoAndIsaTwo
    function Hydra_EntityFilterTwoAndIsaTwo(a,b,classA,classB)
        local original = nativeHydraLOSFilter(a,b,classA,classB)
        return function(candidate)
            return original(candidate) or (candidate and candidate:isa("ExoShield"))
        end
    end
end
