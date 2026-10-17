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
PlasmaT3.kModelName = PrecacheAsset("models/marine/exosuit/purpla.model") -- Explicit bounded sphere; no cinematic actor.
-- used PredictedProjectile.lua
PlasmaT3.kProjectileCinematic = PrecacheAsset("cinematics/modularexo/plasma_charge_32.cinematic")
PlasmaT3.kClearOnImpact      = true
PlasmaT3.kClearOnEnemyImpact = true
-- The max amount of time a Plasma can last for
local kPlasmaT3Lifetime = kPlasmaT3LifeTime
-- Shared charge/flight radius; full charge is 10% larger than the accepted baseline.
function PlasmaT3.GetVisualRadius(charge)
    return .30*(.25+.75*math.max(0,math.min(1,charge or 0)))
end
function PlasmaT3.GetFlightVisualRadius(charge,distance)return PlasmaT3.GetVisualRadius(charge)end
-- Particle sizes grow once, in authored charge levels. Frame scale stays at full-size.
PlasmaT3.kEffectScale=.6
local chargeCinematics={}
for i=0,32 do chargeCinematics[i]=PrecacheAsset(string.format("cinematics/modularexo/plasma_charge_%02d.cinematic",i))end
function PlasmaT3.GetChargeCinematic(charge)
 return chargeCinematics[math.floor(math.max(0,math.min(1,charge or 0))*32+.5)]
end
function PlasmaT3.GetEffectVisualScale(charge)
 return PlasmaT3.GetVisualRadius(1)/.17776726*PlasmaT3.kEffectScale
end
local networkVars = { chargeFraction = "float (0 to 1 by 0.01)" }
AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ModelMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
function PlasmaT3:OnCreate()
    
    PierceProjectile.OnCreate(self)
    self.chargeFraction=1
    
	InitMixin(self, DamageMixin)
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ModelMixin)
    if Server then
        self:AddTimedCallback(PlasmaT3.TimeUp, kPlasmaT3Lifetime)
        -- A lobbed ball can land well past the normal 40 m relevancy range.
        self:SetRelevancyDistance(Math.infinity)
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
    -- Impact burst that every client receives, however far away it lands.
    local kImpactCinematic = "cinematics/modularexo/plasma_impact_small.cinematic"
    local function PlayImpact(self, normal)
        if self.plasmaImpactPlayed then return end
        self.plasmaImpactPlayed=true
        local up = normal and normal:GetLengthSquared() > 0.01 and normal or self:GetCoords().zAxis
        local effect = Shared.CreateEffect(nil, kImpactCinematic, nil, Coords.GetLookIn(self:GetOrigin()+up*.03, up))
        if effect and effect.SetRelevancyDistance then effect:SetRelevancyDistance(Math.infinity) end
    end

    function PlasmaT3:ProcessHit(targetHit, surface, normal, hitPoint, shotDamage, shotDOTDamage, shotDamageRadius, ChargePercent)
        if self.plasmaImpactPlayed then return end
        if hitPoint then self:SetOrigin(hitPoint) end
        -- Show the authoritative impact before splash/DOT callbacks can remove anything.
        PlayImpact(self, normal)
        
		local hitEntities = GetEntitiesWithMixinWithinRange("Live", self:GetOrigin() + normal*0.2, shotDamageRadius)
		table.removevalue(hitEntities, self)
		table.removevalue(hitEntities, self:GetOwner())
		local dotMarker = CreateEntity(DotMarker.kMapName, self:GetOrigin() + normal*0.2, self:GetTeamNumber())
		dotMarker:SetDamageType(kPlasmaDamageType)        
        dotMarker:SetLifeTime(kPlasmaDOTDuration)
        dotMarker:SetDamage(shotDOTDamage)
        dotMarker:SetRadius(shotDamageRadius)
        dotMarker:SetDamageIntervall(kPlasmaDOTInterval)
        dotMarker:SetDotMarkerType(DotMarker.kType.Static)
        dotMarker:SetDeathIconIndex(kDeathMessageIcon.EMPBlast)
        dotMarker:SetOwner(self:GetOwner())
		dotMarker:SetDebuff('pulse')
		dotMarker:SetFallOffFunc(NoFalloff)
		dotMarker:SetLoSCheck(true)
				
		for _, entity in ipairs(hitEntities) do
			self:DoDamage(shotDamage, entity, self:GetOrigin(), GetNormalizedVector(entity:GetOrigin() - self:GetOrigin()), "none")
			if entity.SetElectrified then
				entity:SetElectrified(kElectrifiedDuration)		
			end
		end
					
        CreateExplosionDecals(self)
		DestroyEntity(self)
    end
    
    function PlasmaT3:TimeUp(currentRate)
	
		PlayImpact(self, nil)
        DestroyEntity(self)
        return false
    
    end
end
function PlasmaT3:GetNotifiyTarget()
    return false
end
if Client then
    function PlasmaT3:UpdateChargedVisualScale()
        if not self.renderModel and not self.projectileCinematic then return end
        local c=self.renderCoords or self:GetCoords()
        if self.plasmaLastOrigin then
            self.plasmaTravelDistance=(self.plasmaTravelDistance or 0)+math.sqrt((c.origin-self.plasmaLastOrigin):GetLengthSquared())
        end
        self.plasmaLastOrigin=c.origin
        local scale=PlasmaT3.GetFlightVisualRadius(self.chargeFraction,self.plasmaTravelDistance)/.17776726
        local scaled=Coords.GetIdentity();scaled.origin=c.origin
        scaled.xAxis=c.xAxis*scale;scaled.yAxis=c.yAxis*scale;scaled.zAxis=c.zAxis*scale
        if self.renderModel then self.renderModel:SetCoords(scaled) end
        if self.projectileCinematic then
            local asset=PlasmaT3.GetChargeCinematic(self.chargeFraction)
            if self.plasmaChargeAsset~=asset then self.projectileCinematic:SetCinematic(asset);self.plasmaChargeAsset=asset end
            local effect=Coords.GetIdentity();effect.origin=scaled.origin
            effect.xAxis=scaled.xAxis:GetUnit()*PlasmaT3.GetEffectVisualScale(self.chargeFraction);effect.yAxis=scaled.yAxis:GetUnit()*PlasmaT3.GetEffectVisualScale(self.chargeFraction);effect.zAxis=scaled.zAxis:GetUnit()*PlasmaT3.GetEffectVisualScale(self.chargeFraction)
            self.projectileCinematic:SetCoords(effect)
        end
    end
    function PlasmaT3:OnInitialized()
        self.plasmaTravelDistance=0;self.plasmaLastOrigin=self:GetOrigin()
        PierceProjectile.OnInitialized(self)
        self:UpdateChargedVisualScale()
    end
    function PlasmaT3:OnUpdate(deltaTime)
        PierceProjectile.OnUpdate(self,deltaTime)
        self:UpdateChargedVisualScale()
    end
end
Shared.LinkClassToMap("PlasmaT3", PlasmaT3.kMapName, networkVars)