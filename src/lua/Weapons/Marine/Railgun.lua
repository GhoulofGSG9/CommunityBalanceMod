-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\Weapons\Marine\Railgun.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/BulletsMixin.lua")
Script.Load("lua/Weapons/Marine/ExoWeaponSlotMixin.lua")
Script.Load("lua/TechMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/AchievementGiverMixin.lua")
Script.Load("lua/EffectsMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")

class 'Railgun' (Entity)

Railgun.kMapName = "railgun"

local kChargeTime = 1 -- Changed from vanilla value 2
-- The Railgun will automatically shoot if it is charged for too long.
local kChargeForceShootTime = 4 --  vanilla value 2.5
-- kRailgunRange lives in Balance.lua next to kRelevancyRangeCap.
local kRailgunSpread = Math.Radians(0)
local kBulletSize = 0.3

local kRailgunChargeTime = 1 -- Vanilla 1.4

local kChargeSound = PrecacheAsset("sound/NS2.fev/marine/heavy/railgun_charge")
local kChargeReadySound = PrecacheAsset("sound/NS2.fev/common/checkbox_on")
local kQueuedSound = PrecacheAsset("sound/NS2.fev/common/hovar")
local kResonanceSound = PrecacheAsset("sound/NS2.fev/common/ping")

local precached1 = PrecacheAsset("cinematics/vfx_materials/alien_frag.surface_shader")
local precached2 = PrecacheAsset("cinematics/vfx_materials/decals/railgun_hole.surface_shader")

local networkVars =
{
    timeChargeStarted = "time",
    railgunAttacking = "boolean",
    timeOfLastShot = "time",
    railgunQueued = "boolean"
}

AddMixinNetworkVars(TechMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(ExoWeaponSlotMixin, networkVars)

function Railgun:OnCreate()

    Entity.OnCreate(self)
    
    InitMixin(self, TechMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, DamageMixin)
    InitMixin(self, BulletsMixin)
    InitMixin(self, ExoWeaponSlotMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, AchievementGiverMixin)
    InitMixin(self, EffectsMixin)
    
    self.timeChargeStarted = 0
    self.railgunAttacking = false
    self.timeOfLastShot = 0
    self.railgunQueued = false
    self.resonanceHits = { }
    
    if Client then
    
        InitMixin(self, ClientWeaponEffectsMixin)
        self.chargeSound = Client.CreateSoundEffect(Shared.GetSoundIndex(kChargeSound))
        self.chargeSound:SetParent(self:GetId())
        
    end

end

function Railgun:OnDestroy()

    Entity.OnDestroy(self)
    
    if self.chargeSound then
    
        Client.DestroySoundEffect(self.chargeSound)
        self.chargeSound = nil
        
    end
    
    if self.chargeDisplayUI then
    
        Client.DestroyGUIView(self.chargeDisplayUI)
        self.chargeDisplayUI = nil

    end

    if self.chargeLight then

        Client.DestroyRenderLight(self.chargeLight)
        self.chargeLight = nil
        
    end
    
end

function Railgun:PostDoDamage(target, damage)

    if Server then

        -- Railgun calls DoDamage at the end of a shoot for tracer effect with damage == 0
        if damage == 0 then
            local numTargets = self.numTargets and self.numTargets or 0
            local isOnos = numTargets == 1 and self.hitOnos

            local parent = self.GetParent and self:GetParent()
            local steamId = parent and parent:GetSteamId()

            StatsUI_AddAccuracyStat(steamId, self:GetTechId(), numTargets > 0, isOnos, parent:GetTeamNumber())
            GetBotAccuracyTracker():AddAccuracyStat(parent:GetClient(), numTargets > 0, kBotAccWeaponGroup.Bullets)

            self.hitOnos = false
            self.numTargets = 0

        elseif target then
            self.numTargets = self.numTargets and self.numTargets + 1 or 1
            if target:isa("Onos") then
                self.hitOnos = true
            end
        end

    end

end

local function GetDualRail(self, player)

    local holder = player and player:GetActiveWeapon()
    if not holder or not holder.GetHasDualRails or not holder:GetHasDualRails() then
        return nil
    end
    local other = self:GetIsLeftSlot() and holder:GetRightSlotWeapon() or holder:GetLeftSlotWeapon()
    return other ~= self and other or nil

end

local function GetRefireTime(other)
    return other and kDualRailRefire or kRailgunChargeTime
end

-- Dual-rail slugs leave at least kDualRailSpacing apart.
local function GetFireAllowedTime(other)
    return other and other.timeOfLastShot + kDualRailSpacing or 0
end

-- Charging time that counts towards the forced shot: a dual arm only starts the count once it may fire,
-- but no later than one spacing into the hold, so cycling the other arm cannot hold a charge forever.
local function GetHoldStart(self, other)
    return math.min(math.max(self.timeChargeStarted, GetFireAllowedTime(other) - kChargeTime), self.timeChargeStarted + kDualRailSpacing)
end

function Railgun:OnPrimaryAttack(player)

    self.railgunQueued = false
    if self.timeOfLastShot + GetRefireTime(GetDualRail(self, player)) <= Shared.GetTime() then

        if not self.railgunAttacking then
            self.timeChargeStarted = Shared.GetTime()
        end
        self.railgunAttacking = true
    
    end

end

function Railgun:GetIsThrusterAllowed()
    return true
end

function Railgun:GetWeight()
    return kRailgunWeight
end

-- A dual-rail release inside the spacing stays charged and fires once allowed (ProcessMoveOnWeapon). The slug
-- itself only leaves at the shoot tag a few ticks later, so the spacing is stamped at release.
function Railgun:OnPrimaryAttackEnd(player)

    if not self.railgunAttacking then
        return
    end
    if Shared.GetTime() < GetFireAllowedTime(GetDualRail(self, player)) then
        self.railgunQueued = true
        return
    end
    self.railgunQueued = false
    self.timeOfLastShot = Shared.GetTime()
    self.railgunAttacking = false

end

function Railgun:GetBarrelPoint()

    local player = self:GetParent()
    if player then
    
        if player:GetIsLocalPlayer() then
        
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

function Railgun:GetTracerEffectName()
    return kRailgunTracerEffectName
end

function Railgun:GetTracerResidueEffectName()
    return kRailgunTracerResidueEffectName
end

function Railgun:GetTracerEffectFrequency()
    return 1
end

function Railgun:GetDeathIconIndex()
    return kDeathMessageIcon.Railgun
end

function Railgun:GetChargeAmount()
    return self.railgunAttacking and math.min(1, (Shared.GetTime() - self.timeChargeStarted) / kChargeTime) or 0
end

local function TriggerSteamEffect(self, player)

    if self:GetIsLeftSlot() then
        player:TriggerEffects("railgun_steam_left")
    elseif self:GetIsRightSlot() then
        player:TriggerEffects("railgun_steam_right")
    end
    
end

function Railgun:GetIsAffectedByWeaponUpgrades()
    return true
end

local function GetIsResonant(target)
    return target:isa("Lerk") or target:isa("Fade")
end

local function GetResonanceScalar(self, other, target, now, primes)

    if not other or not GetIsResonant(target) then
        return 1
    end
    local id = target:GetId()
    local otherTime = other.resonanceHits[id]
    if primes then
        self.resonanceHits[id] = now
        if Server then
            target:SetRailResonance()
        end
    end
    if otherTime and otherTime < now and now - otherTime <= kRailResonanceWindow then
        return 1 + kRailResonanceBonus
    end
    return 1

end

local function GetIsPrimedFor(self, player, target)

    local other = GetDualRail(self, player)
    local hitTime = other and other.resonanceHits[target:GetId()]
    return hitTime ~= nil and Shared.GetTime() - hitTime <= kRailResonanceWindow

end

local function ExecuteShot(self, startPoint, endPoint, player)

    -- Filter ourself out of the trace so that we don't hit ourselves.
    local filter = EntityFilterTwo(player, self)
    local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterAllButIsa("Tunnel"))
    local hitPointOffset = trace.normal * 0.3
    local direction = (endPoint - startPoint):GetUnit()
    local charge = math.min(1, (Shared.GetTime() - self.timeChargeStarted) / kChargeTime)
    local damage = kRailgunDamage + charge * kRailgunChargeDamage
    
    local now = Shared.GetTime()
    local dualRail = GetDualRail(self, player)
    for id, time in pairs(self.resonanceHits) do
        if now - time > kRailResonanceWindow then
            self.resonanceHits[id] = nil
        end
    end

    local extents = GetDirectedExtentsForDiameter(direction, kBulletSize)

    local hitEntities = {}
    local resonated = false
    for _ = 1, 20 do

        local capsuleTrace = Shared.TraceBox(extents, startPoint, trace.endPoint, CollisionRep.Damage, PhysicsMask.Bullets, filter)
        if capsuleTrace.entity and damage > 0 then

            if not table.find(hitEntities, capsuleTrace.entity) then
                table.insert(hitEntities, capsuleTrace.entity)
                local scalar = GetResonanceScalar(self, dualRail, capsuleTrace.entity, now, charge >= 1)
                resonated = resonated or scalar > 1
                self:DoDamage(damage * scalar, capsuleTrace.entity, capsuleTrace.endPoint + hitPointOffset, direction, capsuleTrace.surface, false, false)
				
				if capsuleTrace.entity:isa("Onos") then
					if capsuleTrace.entity:GetIsBoneShieldActive() and capsuleTrace.entity:GetHitsBoneShield(self, capsuleTrace.endPoint + hitPointOffset) then
						break
					end
				end
            end		
        end

        -- Stop looping early if we've reached the end.
        if (capsuleTrace.endPoint - trace.endPoint):GetLength() <= extents.x then
            break
        end

        -- use new start point
        startPoint = Vector(capsuleTrace.endPoint) + direction * extents.x * 3
    end

    if Client and resonated and player == Client.GetLocalPlayer() and not Shared.GetIsRunningPrediction() then
        StartSoundEffect(kResonanceSound)
    end

    local effectFrequency = self:GetTracerEffectFrequency()
    local showTracer = (math.random() < effectFrequency)

    -- Tell other players in relevancy to show the tracer. Does not tell the shooting player.
    self:DoDamage(0, nil, trace.endPoint + hitPointOffset, direction, trace.surface, false, showTracer)

    -- Tell the player who shot to show the tracer.
    if Client and showTracer then
        TriggerFirstPersonTracer(self, trace.endPoint)
    end

end

local function Shoot(self, leftSide)

    local player = self:GetParent()
    
    -- We can get a shoot tag even when the clip is empty if the frame rate is low
    -- and the animation loops before we have time to change the state.
    if player then
    
        player:TriggerEffects("railgun_attack")
        
        local viewAngles = player:GetViewAngles()
        local shootCoords = viewAngles:GetCoords()
        
        local startPoint = player:GetEyePos()
        
        local spreadDirection = CalculateSpread(shootCoords, kRailgunSpread, NetworkRandom)
        
        local endPoint = startPoint + spreadDirection * kRailgunRange
        ExecuteShot(self, startPoint, endPoint, player)
        
        if Client then
            TriggerSteamEffect(self, player)
        end
        
    end
    
end

if Server then

    function Railgun:OnParentKilled(attacker, doer, point, direction)
    end
    
    -- 
    -- The Railgun explodes players. We must bypass the ragdoll here.
    -- 
    function Railgun:OnDamageDone(doer, target)
    
        if doer == self then
        
            if HasMixin(target, "Ragdoll") and target:isa("Player") and not target:GetIsAlive() then
                target:SetBypassRagdoll(true)
            end
            
        end
        
    end
    
end

function Railgun:ProcessMoveOnWeapon(player, input)

    if self.railgunAttacking then
    
        if self.railgunQueued or Shared.GetTime() - GetHoldStart(self, GetDualRail(self, player)) >= kChargeForceShootTime then
            self:OnPrimaryAttackEnd(player)
        end
        
    end
    
end

local kActivityInput = ExoWeaponSlotMixin.kActivityInput
local kChargeAmountKey = ExoWeaponSlotMixin.GetSlotKeyTable("chargeAmount")
local kChargeHeldKey = ExoWeaponSlotMixin.GetSlotKeyTable("chargeHeld")
local kTimeSinceLastShotKey = ExoWeaponSlotMixin.GetSlotKeyTable("timeSinceLastShot")
local kRailgunTextureKey = ExoWeaponSlotMixin.GetSlotKeyTable("*exo_railgun_")

function Railgun:OnUpdateRender()

    PROFILE("Railgun:OnUpdateRender")
    
    local chargeAmount = self:GetChargeAmount()
    local parent = self:GetParent()
    if parent and parent:GetIsLocalPlayer() then
    
        local viewModel = parent:GetViewModelEntity()
        if viewModel and viewModel:GetRenderModel() then
        
            viewModel:InstanceMaterials()
            local renderModel = viewModel:GetRenderModel()
            local slot = self.exoWeaponSlot
            renderModel:SetMaterialParameter(kChargeAmountKey[slot], chargeAmount)
            renderModel:SetMaterialParameter(kTimeSinceLastShotKey[slot], Shared.GetTime() - self.timeOfLastShot)
            
        end
        
        local chargeDisplayUI = self.chargeDisplayUI
        if not chargeDisplayUI then
        
            chargeDisplayUI = Client.CreateGUIView(246, 256)
            chargeDisplayUI:Load("lua/GUI" .. self:GetExoWeaponSlotName():gsub("^%l", string.upper) .. "RailgunDisplay.lua")
            chargeDisplayUI:SetTargetTexture(kRailgunTextureKey[self.exoWeaponSlot])
            chargeDisplayUI:SetGlobal("forceShootTime", kChargeForceShootTime)
            self.chargeDisplayUI = chargeDisplayUI
            
        end
        
        local slot = self.exoWeaponSlot
        local now = Shared.GetTime()
        chargeDisplayUI:SetGlobal(kChargeAmountKey[slot], chargeAmount)
        local other = GetDualRail(self, parent)
        chargeDisplayUI:SetGlobal(kChargeHeldKey[slot], self.railgunAttacking and now - GetHoldStart(self, other) or 0)

        chargeDisplayUI:SetGlobal("reserve", math.min(1, (now - self.timeOfLastShot) / GetRefireTime(other)))

        -- A full arm waiting out the spacing drains from the moment it had to wait.
        local fireAllowed = GetFireAllowedTime(other)
        local fuse = 0
        if chargeAmount >= 1 and now < fireAllowed then
            fuse = (fireAllowed - now) / (fireAllowed - math.max(self.timeChargeStarted + kChargeTime, other.timeOfLastShot))
        end
        chargeDisplayUI:SetGlobal("fuse", fuse)

        local ready = chargeAmount >= 1 and now >= fireAllowed
        chargeDisplayUI:SetGlobal("ready", ready and 1 or 0)
        if ready and not self.railgunQueued and not self.chargeReadyCued then
            StartSoundEffect(kChargeReadySound)
        end
        self.chargeReadyCued = ready
        if self.railgunQueued and not self.queueCued then
            StartSoundEffect(kQueuedSound)
        end
        self.queueCued = self.railgunQueued
        
    else
    
        if self.chargeDisplayUI then
        
            Client.DestroyGUIView(self.chargeDisplayUI)
            self.chargeDisplayUI = nil
            
        end
        
    end
    
    if self.chargeSound then
    
        local playing = self.chargeSound:GetIsPlaying()
        if not playing and chargeAmount > 0 then
            self.chargeSound:Start()
        elseif playing and chargeAmount <= 0 then
            self.chargeSound:Stop()
        end
        
        self.chargeSound:SetParameter("charge", chargeAmount, 1)
        
    end

    self:UpdateChargeLight(chargeAmount, parent)
    
end

function Railgun:OnTag(tagName)

    PROFILE("Railgun:OnTag")
    
    if self:GetIsLeftSlot() then
    
        if tagName == "l_shoot" then
            Shoot(self, true)
        end
        
    elseif not self:GetIsLeftSlot() then
    
        if tagName == "r_shoot" then
            Shoot(self, false)
        end
        
    end
    
end


function Railgun:OnUpdateAnimationInput(modelMixin)

    local activity = "none"
    if self.railgunAttacking then
        activity = "primary"
    end
    modelMixin:SetAnimationInput(kActivityInput[self.exoWeaponSlot], activity)
    
end

function Railgun:UpdateViewModelPoseParameters(viewModel)

    local chargeParam = "charge_" .. (self:GetIsLeftSlot() and "l" or "r")
    local chargeAmount = self:GetChargeAmount()
    viewModel:SetPoseParam(chargeParam, chargeAmount)
    
end

if Client then

    -- NOTE(Salads): The railgun exo has different attach point names for both viewmodel and the regular model. FIXME
    local kFirstPersonAttachPoints = { [ExoWeaponHolder.kSlotNames.Left] = "fxnode_l_railgun_muzzle", [ExoWeaponHolder.kSlotNames.Right] = "fxnode_r_railgun_muzzle" }
    local kThirdPersonAttachPoints = { [ExoWeaponHolder.kSlotNames.Left] = "fxnode_lrailgunmuzzle", [ExoWeaponHolder.kSlotNames.Right] = "fxnode_rrailgunmuzzle" }
    local kMuzzleEffectName = PrecacheAsset("cinematics/marine/railgun/muzzle_flash.cinematic")
    local kChargeLightColor = Color(0.4, 0.75, 1, 1)
    local kChargeLightRadius = 2.5
    local kChargeLightIntensity = 10

    function Railgun:UpdateChargeLight(chargeAmount, parent)

        local attachPoint = -1
        if chargeAmount > 0 and parent and parent:GetIsAlive() and parent:GetIsVisible() and not (parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson()) then
            attachPoint = parent:GetAttachPointIndex(kThirdPersonAttachPoints[self.exoWeaponSlot])
        end

        local light = self.chargeLight
        if attachPoint < 0 then

            if light then
                light:SetIsVisible(false)
            end
            return

        end

        if not light then

            light = Client.CreateRenderLight()
            light:SetType(RenderLight.Type_Point)
            light:SetCastsShadows(false)
            light:SetColor(kChargeLightColor)
            light:SetRadius(kChargeLightRadius)
            self.chargeLight = light

        end

        light:SetIntensity(kChargeLightIntensity * chargeAmount)
        light:SetCoords(parent:GetAttachPointCoords(attachPoint))
        light:SetIsVisible(true)

    end

    function Railgun:OnClientPrimaryAttackEnd()
    
        local parent = self:GetParent()
        
        if parent then

            local attachPoint
            if parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
                attachPoint = kFirstPersonAttachPoints[self:GetExoWeaponSlot()]
            else
                attachPoint = kThirdPersonAttachPoints[self:GetExoWeaponSlot()]
            end

            CreateMuzzleCinematic(self, kMuzzleEffectName, kMuzzleEffectName, attachPoint, parent, nil, true)
        end
        
    end
    
    function Railgun:GetSecondaryAttacking()
        return false
    end
    
    function Railgun:GetIsActive()
        return true
    end    
    
    function Railgun:GetPrimaryAttacking()
        return self.railgunAttacking
    end

    local kFilterRailgunTarget = EntityFilterAllButMixin("RailgunTarget")
    local kFilterTunnel = EntityFilterAllButIsa("Tunnel")
    function Railgun:OnProcessMove(input)

        Entity.OnProcessMove(self, input)
        
        local player = self:GetParent()
        
        if player then
    
            -- trace and highlight first target
            local filter = kFilterRailgunTarget
            local viewAngles = player:GetViewAngles()
            local shootCoords = viewAngles:GetCoords()          
            local startPoint = player:GetEyePos()
            local spreadDirection = CalculateSpread(shootCoords, 0, NetworkRandom) -- Assume spread is zero...
            local endPoint = startPoint + spreadDirection * kRailgunRange
            local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, kFilterTunnel)
            
            if trace.entity then
                trace.entity:SetRailgunTarget(GetIsPrimedFor(self, player, trace.entity))
                self.railgunTargetId = trace.entity:GetId()
                return
            end

            local direction = (endPoint - startPoint):GetUnit()
            local extents = GetDirectedExtentsForDiameter(direction, kBulletSize)
            local distance = (trace.endPoint - startPoint):GetLength()
            local distIncrement = 1.5
            local maxAttempts = 20 -- Just for edge cases
            
            self.railgunTargetId = nil
            
            -- Looping is required to deal with capsule getting stuck on geometry.
            for _ = 1, maxAttempts do
                local capsuleTrace = Shared.TraceBox(extents, startPoint, trace.endPoint, CollisionRep.Damage, PhysicsMask.Bullets, filter)
                -- If we found an entity, leave
                if capsuleTrace.entity then
                    capsuleTrace.entity:SetRailgunTarget(GetIsPrimedFor(self, player, capsuleTrace.entity))
                    self.railgunTargetId = capsuleTrace.entity:GetId()
                    break
                end

                -- If we reached the endpoint, leave
                if (capsuleTrace.endPoint - trace.endPoint):GetLength() <= distIncrement then
                    break
                end

                VectorCopy(capsuleTrace.endPoint, startPoint)
                startPoint = startPoint + direction * distIncrement
            end
        end
    end
    
    function Railgun:GetTargetId()
        return self.railgunTargetId
    end
    
end

Shared.LinkClassToMap("Railgun", Railgun.kMapName, networkVars)