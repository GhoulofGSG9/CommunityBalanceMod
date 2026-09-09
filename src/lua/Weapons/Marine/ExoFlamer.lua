Script.Load("lua/Weapons/Marine/Flame.lua")
Script.Load("lua/Weapons/Weapon.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/Weapons/Marine/ExoWeaponHolder.lua")
Script.Load("lua/Weapons/Marine/ExoWeaponSlotMixin.lua")
Script.Load("lua/TechMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/EffectsMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/Weapons/BulletsMixin.lua")

class 'ExoFlamer'(Entity)

ExoFlamer.kMapName = "exoflamer"

if Client then
    Script.Load("lua/Weapons/Marine/ExoFlamer_Client.lua")
end

ExoFlamer.kDamageRadius = kFlamethrowerDamageRadius

ExoFlamer.kModelName = PrecacheAsset("models/marine/flamethrower/flamethrower.model")
local kAnimationGraph = PrecacheAsset("models/marine/flamethrower/flamethrower_view.animation_graph")
local kFireLoopingSound = PrecacheAsset("sound/NS2.fev/marine/flamethrower/attack_loop")

local kHeatUISoundName = PrecacheAsset("sound/NS2.fev/marine/heavy/heat_UI")
local kOverheatedSoundName = PrecacheAsset("sound/NS2.fev/marine/heavy/overheated")

local networkVars = {
    createParticleEffects = "boolean",
    animationDoneTime     = "float",
    range                 = "integer (0 to 11)",
    isShooting            = "boolean",
    loopingSoundEntId     = "entityid",
    heatAmount            = "float (0 to 1 by 0.01)",
    overheated            = "private boolean",
    heatUISoundId         = "private entityid"
    
}

AddMixinNetworkVars(ExoWeaponSlotMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(TechMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(PointGiverMixin, networkVars)

function ExoFlamer:OnCreate()
    Entity.OnCreate(self)
    
    self.lastAttackApplyTime = 0
    
    self.isShooting = false
    InitMixin(self, ExoWeaponSlotMixin)
    InitMixin(self, TechMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, DamageMixin)
    InitMixin(self, BulletsMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, EffectsMixin)
    
    self.loopingSoundEntId = Entity.invalidId
    self.heatAmount = 0
    self.overheated = false
    
    if Server then
        self.lastAttackApplyTime = 0
        
        self.createParticleEffects = false
        self.loopingFireSound = Server.CreateEntity(SoundEffect.kMapName)
        self.loopingFireSound:SetAsset(kFireLoopingSound)
        -- SoundEffect will automatically be destroyed when the parent is destroyed (the ExoFlamer).
        self.loopingFireSound:SetParent(self)
        self.loopingSoundEntId = self.loopingFireSound:GetId()
        
        self.heatUISound = Server.CreateEntity(SoundEffect.kMapName)
        self.heatUISound:SetAsset(kHeatUISoundName)
        self.heatUISound:SetParent(self)
        self.heatUISound:Start()
        self.heatUISoundId = self.heatUISound:GetId()
    
    elseif Client then
        self:SetUpdates(true)
        self.lastAttackEffectTime = 0.0
        self.lastAttackApplyTime = 0
    end
end

function ExoFlamer:OnInitialized()
    Entity.OnInitialized(self)
end

function ExoFlamer:OnDestroy()
    Entity.OnDestroy(self)
    if Server then
        self.loopingFireSound = nil
    elseif Client then
        if self.trailCinematic then
            Client.DestroyTrailCinematic(self.trailCinematic)
            self.trailCinematic = nil
        end
        if self.pilotCinematic then
            Client.DestroyCinematic(self.pilotCinematic)
            self.pilotCinematic = nil
        end
        if self.heatDisplayUI then
            
            Client.DestroyGUIView(self.heatDisplayUI)
            self.heatDisplayUI = nil
        end
    end
end

function ExoFlamer:OnUpdateAnimationInput(modelMixin)
    PROFILE("ExoFlamer:OnUpdateAnimationInput")
    local parent = self:GetParent()
    local activity = self.isShooting and "primary" or "none"
    -- modelMixin:SetAnimationInput("activity_" .. self:GetExoWeaponSlotName(), activity)
end

function ExoFlamer:GetIsAffectedByWeaponUpgrades()
    return true
end

function ExoFlamer:CreatePrimaryAttackEffect(player)
    -- Remember this so we can update gun_loop pose param
    self.timeOfLastPrimaryAttack = Shared.GetTime()
end

function ExoFlamer:GetRange()
    return kExoFlamerRange
end

local kBurnStepLength = 2
local kBurnMaxSteps = 5
local kSporeCloudTag = "class:SporeCloud"

-- Cloud classes, in the order the merged list used to be built in. Only the
-- tags are constant; the radii are class fields a mod can change, so they are
-- re-read on every call into the reusable scratch table below.
local kBurnCloudTags =
{
    "class:CragUmbra",
    "class:StormCloud",
    "class:MucousMembrane",
    "class:EnzymeCloud",
}
local kBurnCloudCount = #kBurnCloudTags

local gBurnCloudRadii = {}
local gBurnCloudPresent = {}
local gBurnCloudSweep = {}

local function UpdateBurnCloudRadii()

    gBurnCloudRadii[1] = CragUmbra.kRadius
    gBurnCloudRadii[2] = StormCloud.kRadius
    gBurnCloudRadii[3] = MucousMembrane.kRadius
    gBurnCloudRadii[4] = EnzymeCloud.kRadius

end

function ExoFlamer:BurnSporesAndUmbra(startPoint, endPoint)
    
    PROFILE("ExoFlamer:BurnSporesAndUmbra")
    
    local toTarget = endPoint - startPoint
    local distanceToTarget = toTarget:GetLength()
    toTarget:Normalize()
    
    local stepLength = kBurnStepLength
    
    -- Same sample points as before: up to five steps of 2 m, stopping short
    -- of the end point.
    local numSteps = math.floor(distanceToTarget / stepLength)
    if numSteps > kBurnMaxSteps then
        numSteps = kBurnMaxSteps
    end
    
    if numSteps < 1 then
        return
    end
    
    -- One sweep per cloud class over a sphere that contains every sample
    -- point plus that class' radius. It is a strict superset of the per-point
    -- queries, so a class that misses here cannot hit any sample point and its
    -- five per-point queries can be skipped. Nothing burns on the vast
    -- majority of flame ticks, which used to cost 25 range queries and three
    -- table.copy each.
    local sweepCenter = startPoint + toTarget * ((numSteps + 1) * 0.5 * stepLength)
    local sweepSpan = (numSteps - 1) * 0.5 * stepLength
    
    local sporeSweep = Shared.GetEntitiesWithTagInRange(kSporeCloudTag, sweepCenter, sweepSpan + kSporesDustCloudRadius)
    local sporesPossible = #sporeSweep > 0
    local anyPossible = sporesPossible
    
    -- Radii are read here, not cached at first use, so a mod that changes a
    -- cloud radius at runtime still gets the right query.
    UpdateBurnCloudRadii()
    
    for q = 1, kBurnCloudCount do
        
        local sweep = Shared.GetEntitiesWithTagInRange(kBurnCloudTags[q], sweepCenter, sweepSpan + gBurnCloudRadii[q])
        gBurnCloudSweep[q] = sweep
        gBurnCloudPresent[q] = #sweep > 0
        anyPossible = anyPossible or gBurnCloudPresent[q]
        
    end
    
    if not anyPossible then
        return
    end
    
    -- With a single sample point the sweep sphere is that point with that
    -- class' own radius, so the sweep result is the per-point result and the
    -- query does not have to be repeated.
    local sweepIsSamplePoint = numSteps == 1
    
    for i = 1, numSteps do
        
        local checkAtPoint = startPoint + toTarget * (i * stepLength)
        local burnSpent = false
        
        if sporesPossible then
            
            local spores = sweepIsSamplePoint and sporeSweep
                or Shared.GetEntitiesWithTagInRange(kSporeCloudTag, checkAtPoint, kSporesDustCloudRadius)
            for s = 1, #spores do
                local spore = spores[s]
                self:TriggerEffects("burn_spore", { effecthostcoords = Coords.GetTranslation(spore:GetOrigin()) })
                DestroyEntity(spore)
                burnSpent = true
            end
            
        end
        
        for q = 1, kBurnCloudCount do
            
            if gBurnCloudPresent[q] then
                
                local clouds = sweepIsSamplePoint and gBurnCloudSweep[q]
                    or Shared.GetEntitiesWithTagInRange(kBurnCloudTags[q], checkAtPoint, gBurnCloudRadii[q])
                for c = 1, #clouds do
                    local cloud = clouds[c]
                    self:TriggerEffects("burn_umbra", { effecthostcoords = Coords.GetTranslation(cloud:GetOrigin()) })
                    DestroyEntity(cloud)
                    burnSpent = true
                end
                
            end
            
        end
        
        if burnSpent then
            break
        end
    
    end

end

function ExoFlamer:GetMeleeOffset()
    
    return 0

end

function ExoFlamer:ApplyConeDamage(player)

    local eyePos = player:GetEyePos()
    local DamageEnts = {}
    local kTraceOrder = { 4, 1, 3, 5, 7, 0, 2, 6, 8 }

    local coords = player:GetViewAngles():GetCoords()
    local fireDirection = player:GetViewCoords().zAxis
    local extents = Vector(kExoFlamerConeWidth/6, kExoFlamerConeWidth/6, kExoFlamerConeWidth/6)
    local range = self:GetRange()

    local startPoint = Vector(eyePos)
    local filterEnts = { self, player }

    -- The first entry of kTraceOrder is the centre of the cone. That trace stands in for the
    -- marine flamethrower's single trace when burning clouds and when dropping a ground flame,
    -- so the cone does that work once per tick instead of once per trace point.
    local burnEndPoint = eyePos + fireDirection * range

    for _, pointIndex in ipairs(kTraceOrder) do

        local dx = pointIndex % 3 - 1
        local dy = math.floor(pointIndex / 3) - 1
        local point = eyePos + coords.xAxis * (dx * kExoFlamerConeWidth / 3) + coords.yAxis * (dy * kExoFlamerConeWidth / 3)
        local trace = TraceMeleeBox(self, point, fireDirection, extents, range, PhysicsMask.Flame, EntityFilterList(filterEnts))

        local endPoint = trace.endPoint
        local isCenterTrace = pointIndex == 4

        if isCenterTrace then
            burnEndPoint = endPoint
        end

        if trace.fraction ~= 1 then

            local traceEnt = trace.entity
            if traceEnt and HasMixin(traceEnt, "Live") and traceEnt:GetCanTakeDamage() and traceEnt:GetTeamNumber() ~= self:GetTeamNumber() then
                if not table.find(DamageEnts, traceEnt) then
                    table.insert(DamageEnts, traceEnt)
                end
            end

        end
    end

    -- Check for spores in the way.
    if Server then
        self:BurnSporesAndUmbra(startPoint, burnEndPoint)
    end

    for i = 1, #DamageEnts do

        local ent = DamageEnts[i]
        local enemyOrigin = ent:GetModelOrigin()

        if ent ~= player and enemyOrigin then

            local toEnemy = GetNormalizedVector(enemyOrigin - eyePos)

            local health = ent:GetHealth()
            self:DoDamage(kExoFlamerExoFlamerDamage, ent, enemyOrigin, toEnemy)

            -- Only light on fire if we successfully damaged them
            if ent:GetHealth() ~= health and HasMixin(ent, "Fire") then
                ent:SetOnFire(player, self)
            end
        end
    end
end

function ExoFlamer:GetBarrelPoint()
    local player = self:GetParent()
    if player then
        if Client and player:GetIsLocalPlayer() then
            local origin = player:GetEyePos()
            local viewCoords = player:GetViewCoords()
            
            if self:GetIsLeftSlot() then
                return origin + viewCoords.zAxis * 0.9 + viewCoords.xAxis * 0.65 + viewCoords.yAxis * -0.19
            else
                return origin + viewCoords.zAxis * 0.9 + viewCoords.xAxis * -0.65 + viewCoords.yAxis * -0.19
            end
        else
            local origin = player:GetEyePos()
            local viewCoords = player:GetViewCoords()
            
            if self:GetIsLeftSlot() then
                return origin + viewCoords.zAxis * 0.9 + viewCoords.xAxis * 0.35 + viewCoords.yAxis * -0.15
            else
                return origin + viewCoords.zAxis * 0.9 + viewCoords.xAxis * -0.35 + viewCoords.yAxis * -0.15
            end
        end
    end
    return self:GetOrigin()
end

function ExoFlamer:ShootFlame(player)
    
    local viewAngles = player:GetViewAngles()
    local viewCoords = viewAngles:GetCoords()
    
    viewCoords.origin = self:GetBarrelPoint(player) + viewCoords.zAxis * (-0.4) + viewCoords.xAxis * (-0.2)
    local endPoint = self:GetBarrelPoint(player) + viewCoords.xAxis * (-0.2) + viewCoords.yAxis * (-0.3) + viewCoords.zAxis * self:GetRange()
    
    local trace = Shared.TraceRay(viewCoords.origin, endPoint, CollisionRep.Damage, PhysicsMask.Flame, EntityFilterAll())
    
    local range = (trace.endPoint - viewCoords.origin):GetLength()
    if range < 0 then
        range = range * (-1)
    end
    
    if trace.endPoint ~= endPoint and trace.entity == nil then
        local angles = Angles(0, 0, 0)
        angles.yaw = GetYawFromVector(trace.normal)
        angles.pitch = GetPitchFromVector(trace.normal) + (math.pi / 2)
        
        local normalCoords = angles:GetCoords()
        normalCoords.origin = trace.endPoint
        range = range - 3
    end
    
    self:ApplyConeDamage(player)
end

function ExoFlamer:FirePrimary(player)
    self:ShootFlame(player)
end

function ExoFlamer:OnTag(tagName)
    PROFILE("ExoFlamer:OnTag")
    if not self:GetIsLeftSlot() then
        if tagName == "deploy_end" then
            self.deployed = true
        end
    end
end

function ExoFlamer:OnPrimaryAttack(player)
    
    PROFILE("ExoFlamer:OnPrimaryAttack")
	
    if not self.overheated then
        if not self.isShooting then
            if not self.createParticleEffects then
                if self:GetIsLeftSlot() then
                    player:TriggerEffects("leftexoflamer_muzzle")
                elseif self:GetIsRightSlot() then
                    player:TriggerEffects("rightexoflamer_muzzle")
                end
            end
            self.createParticleEffects = true
            if Server and not self.loopingFireSound:GetIsPlaying() then
                self.loopingFireSound:Start()
            end
        end
        
        self.isShooting = true
    end
    
    if Client and self.createParticleEffects and self.lastAttackEffectTime + kExoFlamerFireRate < Shared.GetTime() then
        if self:GetIsLeftSlot() then
            player:TriggerEffects("leftexoflamer_muzzle")
        elseif self:GetIsRightSlot() then
            player:TriggerEffects("rightexoflamer_muzzle")
        end
        self.lastAttackEffectTime = Shared.GetTime()
    end
    if not self.overheated and self.lastAttackApplyTime + kExoFlamerFireRate < Shared.GetTime() then
        self:ShootFlame(player)
        self.lastAttackApplyTime = Shared.GetTime()
    end
end

local function UpdateOverheated(self, player)
    
    if not self.overheated and self.heatAmount == 1 then
        
        self.overheated = true
        self:OnPrimaryAttackEnd(player)
        
        --[[        if self:GetIsLeftSlot() then
                    player:TriggerEffects("minigun_overheated_left")
                elseif self:GetIsRightSlot() then
                    player:TriggerEffects("minigun_overheated_right")
                end    ]]
        
        StartSoundEffectForPlayer(kOverheatedSoundName, player)
    
    end
    
    if self.overheated and self.heatAmount == 0 then
        self.overheated = false
    end

end

function ExoFlamer:AddHeat(amount)
    self.heatAmount = self.heatAmount + amount

end

function ExoFlamer:GetDeathIconIndex()
    return kDeathMessageIcon.Flamethrower
end

function ExoFlamer:OnPrimaryAttackEnd(player)
    if self.isShooting then
        self.createParticleEffects = false
        if Server then
            self.loopingFireSound:Stop()
        end
    end
    self.isShooting = false

end

function ExoFlamer:OnReload(player)
    if self:CanReload() then
        if Server then
            self.createParticleEffects = false
            self.loopingFireSound:Stop()
        end
        self:TriggerEffects("reload")
        self.reloading = true
    end
end

function ExoFlamer:ProcessMoveOnWeapon(player, input)
    local dt = input.time
    local addAmount = self.isShooting and (dt * kExoFlamerHeatUpRate) or -(dt * kExoFlamerCoolDownRate)
    self.heatAmount = math.min(1, math.max(0, self.heatAmount + addAmount))
    
    UpdateOverheated(self, player)
    
    --[[if self.isShooting and not self.overheated then
        
        local exoWeaponHolder = player:GetActiveWeapon()
        if exoWeaponHolder then
            
            local otherSlotWeapon = self:GetExoWeaponSlot() == ExoWeaponHolder.kSlotNames.Left and exoWeaponHolder:GetRightSlotWeapon() or exoWeaponHolder:GetLeftSlotWeapon()
            if otherSlotWeapon and otherSlotWeapon:isa("ExoFlamer") then
                otherSlotWeapon:AddHeat(dt * kExoFlamerDualGunHeatUpRate)
            end
        
        end
    end]]
    
    if Client and not Shared.GetIsRunningPrediction() then
        
        if player:GetIsLocalPlayer() then
            
            --local heatUISound = Shared.GetEntity(self.heatUISoundId)
            -- heatUISound:SetParameter("heat", self.heatAmount, 1)
        
        end
    
    end

end

function ExoFlamer:GetNotifiyTarget()
    return false
end

function ExoFlamer:ModifyDamageTaken(damageTable, attacker, doer, damageType)
    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end
end

Shared.LinkClassToMap("ExoFlamer", ExoFlamer.kMapName, networkVars)
