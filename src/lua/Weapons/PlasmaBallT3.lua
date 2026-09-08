--=============================================================================
--
-- lua\Weapons\Alien\PlasmaT3.lua
--
-- Created by Charlie Cleveland (charlie@unknownworlds.com)
-- Copyright (c) 2011, Unknown Worlds Entertainment, Inc.
--
-- Plasma projectile
--
--=============================================================================

Script.Load("lua/Weapons/Projectile.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/DamageMixin.lua")
Script.Load("lua/FireMixin.lua")
Script.Load("lua/Mixins/ModelMixin.lua")

Script.Load("lua/Weapons/DotMarker.lua")
Script.Load("lua/MarineWeaponEffects.lua")
Script.Load("lua/Weapons/PierceProjectile.lua")

local precached1 = PrecacheAsset("models/marine/exosuit/plasma_effect.surface_shader")
local precached2 = PrecacheAsset("cinematics/modularexo/plasma_impact_small.cinematic")

class 'PlasmaT3' (PierceProjectile)

PlasmaT3.kMapName            = "PlasmaT3"

PlasmaT3.kModelName            = PrecacheAsset("models/marine/exosuit/plasma.model")
-- used PredictedProjectile.lua
PlasmaT3.kProjectileCinematic  = PrecacheAsset("cinematics/modularexo/plasma_fly_t3.cinematic")

PlasmaT3.kClearOnImpact      = true
PlasmaT3.kClearOnEnemyImpact = true

-- The max amount of time a Plasma can last for
local kPlasmaT3Lifetime = kPlasmaT3LifeTime

local networkVars = { }

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ModelMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)

function PlasmaT3:OnCreate()
    
    PierceProjectile.OnCreate(self)
    
	InitMixin(self, DamageMixin)
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ModelMixin)

    if Server then
        self:AddTimedCallback(PlasmaT3.TimeUp, kPlasmaT3Lifetime)
    end

end

function PlasmaT3:GetIsAffectedByWeaponUpgrades()
    return true
end

function PlasmaT3:GetDeathIconIndex()
    return kDeathMessageIcon.EMPBlast
end

function PlasmaT3:GetDamageType()
    return kPlasmaDamageType
end

if Server then

    local function NoFalloff(distanceFraction)
        return 0 
    end

    -- Shared explosion body. A contact hit and the fuse running out must produce the
    -- exact same blast, so both go through here. self.detonated makes a second call a
    -- no-op, so a bomb can never go off twice.
    local function Detonate(self, position, surfaceNormal, surface, targetHit, shotDamage, shotDOTDamage)

        if self.detonated then
            return
        end
        self.detonated = true

        local center = position + surfaceNormal * 0.2
        local owner = self:GetOwner()

        local hitEntities = GetEntitiesWithMixinWithinRange("Live", center, kPlasmaBombDamageRadius)
        table.removevalue(hitEntities, self)
        table.removevalue(hitEntities, owner)

        local dotMarker = CreateEntity(DotMarker.kMapName, center, self:GetTeamNumber())
        dotMarker:SetDamageType(kPlasmaDamageType)
        dotMarker:SetLifeTime(kPlasmaDOTDuration)
        dotMarker:SetDamage(shotDOTDamage)
        dotMarker:SetRadius(kPlasmaBombDamageRadius)
        dotMarker:SetDamageIntervall(kPlasmaDOTInterval)
        dotMarker:SetDotMarkerType(DotMarker.kType.Static)
        dotMarker:SetDeathIconIndex(kDeathMessageIcon.EMPBlast)
        dotMarker:SetOwner(owner)
        dotMarker:SetDebuff('pulse')
        dotMarker:SetFallOffFunc(NoFalloff)
        dotMarker:SetLoSCheck(true)

        for _, entity in ipairs(hitEntities) do

            self:DoDamage(shotDamage, entity, position, GetNormalizedVector(entity:GetOrigin() - position), "none")

            -- Same crowd control the pulse grenade applies: drain energy by distance and
            -- electrify, which cuts alien attack speed and stops regeneration. Only the
            -- shooter's enemies get it; the damage query above is left alone because the
            -- damage rules already decide friendly fire.
            if GetAreEnemies(self, entity) then

                if entity.GetEnergy and entity.SetEnergy then

                    local targetPoint = HasMixin(entity, "Target") and entity:GetEngagementPoint() or entity:GetOrigin()
                    local energyToDrain = kPlasmaBombEnergyDamage * (1 - Clamp((targetPoint - position):GetLength() / kPlasmaBombDamageRadius, 0, 1))
                    entity:SetEnergy(entity:GetEnergy() - energyToDrain)

                end

                if entity.SetElectrified then
                    entity:SetElectrified(kPulseElectrifiedDuration)
                end

            end

        end

        local params = { surface = surface }
        if not targetHit then
            params[kEffectHostCoords] = Coords.GetLookIn( position, self:GetCoords().zAxis)
        end

        self:TriggerEffects("pulse_grenade_explode", params)

        CreateExplosionDecals(self)

    end

    function PlasmaT3:ProcessHit(targetHit, surface, normal, hitPoint, shotDamage, shotDOTDamage, shotDamageRadius, ChargePercent)

        Detonate(self, self:GetOrigin(), normal, surface, targetHit, shotDamage, shotDOTDamage)
        DestroyEntity(self)

    end

    -- Fuse ran out before hitting anything: go off where the bomb is instead of just
    -- vanishing. Same blast as a contact hit, with the nominal bomb damage values.
    function PlasmaT3:TimeUp(currentRate)

        Detonate(self, self:GetOrigin(), Vector.yAxis, nil, nil, kPlasmaBombDamage, kPlasmaBombDOTDamage)
        DestroyEntity(self)
        return false

    end
end

function PlasmaT3:GetNotifiyTarget()
    return false
end

Shared.LinkClassToMap("PlasmaT3", PlasmaT3.kMapName, networkVars)