--=============================================================================
--
-- lua\Weapons\Alien\Shockwave.lua
--
-- Created by Andread Urwalek (andi@unknownworlds.com)
-- Copyright (c) 2011, Unknown Worlds Entertainment, Inc.
--
--=============================================================================

Script.Load("lua/Weapons/Projectile.lua")
Script.Load("lua/DamageMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/LOSMixin.lua")
Script.Load("lua/ScriptActor.lua")

class 'Shockwave' (ScriptActor)

Shockwave.OverrideCheckVision = function() return false end

Shockwave.kMapName = "Shockwave"
-- Shockwave.kModelName = PrecacheAsset("models/marine/rifle/rifle_grenade.model") -- for debugging
Shockwave.kRadius = 0.01
Shockwave.tFirst = true
local kShockwaveCrackMaterial = PrecacheAsset("cinematics/vfx_materials/decals/shockwave_crack.material")

local networkVars = { }

AddMixinNetworkVars(networkVars, TeamMixin)
AddMixinNetworkVars(networkVars, LOSMixin)

local kShockwaveLifeTime = 0.7
local kUpdateRate = 0.1
local kShockWaveVelocity = 24

-- The wave follows the floor: every move it is put back onto the floor, within these limits.
local kHeightAboveFloor = 0.2     -- same height the wave is created at
local kMaxStepUp = 0.8            -- highest rise per move the wave climbs (stairs, ramps)
local kMaxStepDown = 1.5          -- deepest drop per move the wave follows
local kWallCheckHeight = 0.3      -- the wall check runs this far above the wave

-- The wave only hurts what stands on the floor it travels over. These limits keep it from reaching targets that are
-- close in the horizontal plane but on another level (vents, ledges, rooms above/below, behind walls).
local kMaxGroundDeviation = 1.0   -- max height of the wave above the floor below it (it is over a gap/drop otherwise)
local kHitLineOfSightHeight = 0.4 -- height above the floor / above the target's feet the line-of-sight check uses

local function CreateCoords(xAxis, yAxis, zAxis)

    local coords = Coords()
    coords.xAxis = xAxis
    coords.yAxis = yAxis
    coords.zAxis = zAxis
    
    return coords

end

local kRotationCoords =
{
    CreateCoords(Vector.xAxis, Vector.yAxis, Vector.zAxis),
    CreateCoords(-Vector.xAxis, Vector.yAxis, -Vector.zAxis),
    CreateCoords(-Vector.xAxis, -Vector.yAxis, Vector.zAxis),
    CreateCoords(Vector.xAxis, -Vector.yAxis, -Vector.zAxis),
}

local function CreateEffect(self)
    local coords = self:GetCoords()
    local groundTrace = Shared.TraceRay(coords.origin, coords.origin - Vector.yAxis * 3, CollisionRep.Move, PhysicsMask.Movement, EntityFilterAllButIsa("Tunnel"))

    if groundTrace.fraction ~= 1 then
        coords.origin = groundTrace.endPoint
        
        coords.zAxis.y = 0
        coords.zAxis:Normalize()
        
        coords.xAxis.y = 0
        coords.xAxis:Normalize()
        
        coords.yAxis = coords.zAxis:CrossProduct(coords.xAxis)

        self:TriggerEffects("shockwave_trail", { effecthostcoords = coords })
        Client.CreateTimeLimitedDecal(kShockwaveCrackMaterial, coords * kRotationCoords[math.random(1, #kRotationCoords)], 2.7, 6)
    end
    
    return true
end

function Shockwave:OnCreate()

    ScriptActor.OnCreate(self)
    
    InitMixin(self, DamageMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LOSMixin)
    
    if Server then    
    
        self:AddTimedCallback(Shockwave.TimeUp, kShockwaveLifeTime)    
        self:AddTimedCallback(Shockwave.Detonate, 0.1)   
        self.damagedEntIds = {}
   
    end
    
    if Client then
        self:AddTimedCallback(CreateEffect, 0.1)
    end
    
end

local function DestroyShockwave(self)

    if Server then

        -- Can be reached more than once (life time callback and UpdateShockwave in the same frame).
        if self.isDestroyed then
            return
        end
        self.isDestroyed = true
    
        local owner = self:GetOwner()
        if owner then
        
            for i = 0, owner:GetNumChildren() - 1 do
            
                local child = owner:GetChildAtIndex(i)
                if HasMixin(child, "Stomp") then
                    child:UnregisterShockwave(self)
                end
                
            end
            
        end
        
        DestroyEntity(self)
        
    end
    
end

function Shockwave:TimeUp()

    DestroyShockwave(self)
    return false
    
end

function Shockwave:UpdateShockwave(deltaTime)

    if self.isDestroyed then
        return
    end

    local origin = self:GetOrigin()

    if not self.moveDirection then
        self.moveDirection = GetNormalizedVectorXZ(self:GetCoords().zAxis)
    end

    local filter = EntityFilterAllButIsa("Tunnel")
    local newPosition = origin + self.moveDirection * kShockWaveVelocity * deltaTime
    local floorTrace = Shared.TraceRay(newPosition + Vector.yAxis * kMaxStepUp, newPosition - Vector.yAxis * kMaxStepDown, CollisionRep.Move, PhysicsMask.Movement, filter)

    if floorTrace.fraction == 0 then
        DestroyShockwave(self)
        return
    elseif floorTrace.fraction < 1 then
        newPosition.y = floorTrace.endPoint.y + kHeightAboveFloor
    end

    local wallTrace = Shared.TraceRay(origin + Vector.yAxis * kWallCheckHeight, newPosition + Vector.yAxis * kWallCheckHeight, CollisionRep.Damage, PhysicsMask.Bullets, filter)
    if wallTrace.fraction < 1 then
        DestroyShockwave(self)
        return
    end

    self:SetOrigin(newPosition)

end

function Shockwave:Detonate()
    local origin = self:GetOrigin()

    local groundTrace = Shared.TraceRay(origin, origin - Vector.yAxis * 3, CollisionRep.Move, PhysicsMask.Movement, EntityFilterAllButIsa("Tunnel"))
    
    if Shared.GetTestsEnabled() then
        DebugLine(origin, groundTrace.endPoint, 2, 1, 0, 1, 1)
    end
    
    -- The wave follows the floor, so the surface right below it is the one it runs over. When it is over a gap or
    -- a drop it keeps its height and the trace would find a floor far below: nothing to hit there.
    local groundY = groundTrace.endPoint.y
    local onStompFloor = origin.y - groundY <= kMaxGroundDeviation

    if groundTrace.fraction < 1 and onStompFloor then
        local losOrigin = groundTrace.endPoint + Vector.yAxis * kHitLineOfSightHeight
        -- Only query entities once there is ground to damage on.
        local enemies = GetEntitiesWithMixinWithinRange("Live", groundTrace.endPoint, 2.2)

        -- never damage the owner
        local owner = self:GetOwner()
        if owner then
            table.removevalue(enemies, owner)
        end

        -- if Shared.GetTestsEnabled() then
        --     DebugBox(groundTrace.endPoint, groundTrace.endPoint, Vector(2.2,0.8,2.2), 5, 0, 0, 1, 1 )
        -- end
        
        for _, enemy in ipairs(enemies) do
            local enemyId = enemy:GetId()
            if GetAreEnemies(self, enemy) and enemy:GetIsAlive() and not self.damagedEntIds[enemyId] and math.abs(enemy:GetOrigin().y - groundTrace.endPoint.y) < 0.8 then

                local hasGroundMove = HasMixin(enemy, "GroundMove")
                
                -- Static geometry between the wave and the target (wall, floor, vent grate) blocks the hit.
                local losTrace = Shared.TraceRay(losOrigin, enemy:GetOrigin() + Vector.yAxis * kHitLineOfSightHeight, CollisionRep.Move, PhysicsMask.Movement, EntityFilterAllButIsa("Tunnel"))
                local hasLineOfSight = losTrace.fraction == 1

                -- all players have groundmove mixin.
                -- hit all players on the ground
                -- hit all except jetpackers slighty above the ground
                if hasLineOfSight and (not hasGroundMove or enemy:GetIsOnGround() or not enemy:isa("JetpackMarine")) then
                    self:TriggerEffects("shockwave_hit", { effecthostcoords = enemy:GetCoords() })

                    self:DoDamage(kStompDamage, enemy, enemy:GetOrigin(), GetNormalizedVector(enemy:GetOrigin() - groundTrace.endPoint), "none")
                     self.damagedEntIds[enemyId] = true

                     if HasMixin(enemy, "Webable") then
                        enemy:SetWebbed(kWebbedDuration, true)
                    end

                end

            end
        end
    end
    
    return true
end

function Shockwave:GetDeathIconIndex()
    return kDeathMessageIcon.Stomp
end

Shared.LinkClassToMap("Shockwave", Shockwave.kMapName, networkVars)
