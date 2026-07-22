-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\LiveMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/BalanceHealth.lua")

-- forces predicted health/armor to update after 1 second
local kSynchronizeDelay = 1

LiveMixin = CreateMixin(LiveMixin)
LiveMixin.type = "Live"

PrecacheAsset("cinematics/vfx_materials/heal_marine.surface_shader")
PrecacheAsset("cinematics/vfx_materials/heal_alien.surface_shader")
PrecacheAsset("cinematics/vfx_materials/heal_marine_view.surface_shader")
PrecacheAsset("cinematics/vfx_materials/heal_alien_view.surface_shader")

local kHealMaterials =
{
    [kMarineTeamType] = PrecacheAsset("cinematics/vfx_materials/heal_marine.material"),
    [kAlienTeamType] = PrecacheAsset("cinematics/vfx_materials/heal_alien.material"),
}

local kHealViewMaterials =
{
    [kMarineTeamType] = PrecacheAsset("cinematics/vfx_materials/heal_marine_view.material"),
    [kAlienTeamType] = PrecacheAsset("cinematics/vfx_materials/heal_alien_view.material"),
}

-- These may be optionally implemented.
LiveMixin.optionalCallbacks =
{
    OnTakeDamage = "A callback to alert when the object has taken damage.",
    PreOnKill = "A callback to alert before an object will be killed.",
    OnKill = "A callback to alert when the object has been killed.",
    GetDestroyOnKill = "Should return true if the entity should be destroyed after it has been killed",
    GetCanTakeDamageOverride = "Should return false if the entity cannot take damage. If this function is not provided it will be assumed that the entity can take damage.",
    GetCanDieOverride = "Should return false if the entity cannot die. If this function is not provided it will be assumed that the entity can die.",
    GetCanGiveDamageOverride = "Should return false if the entity cannot give damage to other entities. If this function is not provided it will be assumed that the entity cannot do damage.",
    GetSendDeathMessageOverride = "Should return false if the entity doesn't send a death message on death.",
    GetCanBeHealed = "Optionally prevent or allow healing.",
    OnGetIsSelectableOveride = "Should return true if the entity should be selectable."
}

LiveMixin.kHealth = 100
LiveMixin.kArmor = 0

LiveMixin.kMaxHealth = 8191 -- 2^13-1, Maximum possible value for maxHealth
LiveMixin.kMaxArmor  = 2045 -- 2^11-1, Maximum possible value for maxArmor

LiveMixin.kCombatDuration = 6

LiveMixin.networkVars =
{
    alive = "boolean",
    healthIgnored = "boolean",

    -- Note: health and armor must have exact integer representations so they can exactly match maxHealth and maxArmor
    -- otherwise aliens will never stop healing. 0.0625 is 1/16th
    health = string.format("float (0 to %f by 0.0625)", LiveMixin.kMaxHealth),
    maxHealth = string.format("integer (0 to %f)", LiveMixin.kMaxHealth),

    armor = string.format("float (0 to %f by 0.0625)", LiveMixin.kMaxArmor),
    maxArmor = string.format("integer (0 to %f)", LiveMixin.kMaxArmor),

    -- for heal effect
    timeLastVisuallyHealed = "time",
    timeLastHealed = "time",
    healedFromSelf = "boolean"

}


function LiveMixin:__initmixin()

    PROFILE("LiveMixin:__initmixin")

    self.lastDamageAttackerId = Entity.invalidId
    self.timeLastCombatAction = 0
    self.timeOfLastDamage = nil
    self.healedFromSelf = false

    if Server then

        self.health = LookupTechData(self:GetTechId(), kTechDataMaxHealth, 100)
        self:SetMaxHealth(self.health)
        assert(self.health ~= nil)
        assert(self.maxHealth < LiveMixin.kMaxHealth)

        self.timeLastVisuallyHealed = 0
        self.timeLastHealed = 0
        self:SetIsAlive(true)
        self.healthIgnored = false

        self.armor = LookupTechData(self:GetTechId(), kTechDataMaxArmor, 0)
        assert(self.armor ~= nil)
        self.maxArmor = self.armor
        assert(self.maxArmor < LiveMixin.kMaxArmor)

    elseif Client then

        self.clientTimeLastHealed = 0
        self.clientStateAlive = self.alive
        -- make sure that we kill all our children before OnUpdate (field changes are called before OnUpdate)
        self:AddFieldWatcher("alive", LiveMixin.OnAliveChange)

    end

    self.overkillHealth = 0

end

--
-- Health is disregarded in all calculations.
-- Only uses armor.
--
function LiveMixin:SetIgnoreHealth(setIgnoreHealth)
    self.healthIgnored = setIgnoreHealth
end

function LiveMixin:GetIgnoreHealth()
    return self.healthIgnored
end

-- Returns text and 0-1 scalar for health bar on commander HUD when selected.
function LiveMixin:GetHealthDescription()

    local armorString = ""

    local armor = self:GetArmor()
    local maxArmor = self:GetMaxArmor()

    if armor and maxArmor and armor > 0 and maxArmor > 0 then
        armorString = string.format("Armor %s/%s", ToString(math.ceil(armor)), ToString(maxArmor))
    end

    if self.healthIgnored then
        return armorString, self:GetArmorScalar()
    else
        return string.format("Health  %s/%s  %s", ToString(math.ceil(self:GetHealth())), ToString(math.ceil(self:GetMaxHealth())), armorString), self:GetHealthScalar()
    end

end

function LiveMixin:GetHealthFraction()

    local max = self:GetMaxHealth()

    if max == 0 or self:GetIgnoreHealth() then
        return 0
    else
        return self:GetHealth() / max
    end

end

function LiveMixin:GetHealthScalar()

    if self.healthIgnored then
        return self:GetArmorScalar()
    end

    local max = self:GetMaxHealth() + self:GetMaxArmor() * kHealthPointsPerArmor
    local current = self:GetHealth() + self:GetArmor() * kHealthPointsPerArmor

    if max == 0 then
        return 0
    end

    return current / max

end

function LiveMixin:SetHealth(health)
    self.health = Clamp(health, 0, self:GetMaxHealth())
end

function LiveMixin:GetMaxHealth()
    return self.maxHealth
end

function LiveMixin:SetMaxHealth(setMax)

    assert(setMax <= LiveMixin.kMaxHealth)
    assert(setMax > 0)

    self.maxHealth = setMax

end

-- instead of simply setting self.maxHealth the fraction of current health will be stored and health increased (so 100% health remains 100%)
function LiveMixin:AdjustMaxHealth(setMax)

    assert(setMax <= LiveMixin.kMaxHealth)
    assert(setMax > 0)

    if setMax ~= self:GetMaxHealth() then
        local healthFraction = self:GetHealthFraction()
        self:SetMaxHealth(setMax)
        self:SetHealth(self:GetMaxHealth() * healthFraction)
    end

end

function LiveMixin:GetArmorScalar()

    if self:GetMaxArmor() == 0 then
        return 0
    end

    return self:GetArmor() / self:GetMaxArmor()

end

function LiveMixin:SetArmor(armor, hideEffect)

    if Server then

        local prevArmor = self.armor
        self.armor = Clamp(armor, 0, self:GetMaxArmor())

        local time = Shared.GetTime()

        if prevArmor < self.armor and not hideEffect then
            self.timeLastVisuallyHealed = time
        end

        self.timeLastHealed = time

    end

end

function LiveMixin:GetMaxArmor()
    return self.maxArmor
end

function LiveMixin:SetMaxArmor(setMax)

    assert(setMax ~= nil)
    assert(setMax <= LiveMixin.kMaxArmor)
    assert(setMax >= 0)

    self.maxArmor = setMax

end

-- instead of simply setting self.maxArmor the fraction of current Armor will be stored and Armor increased (so 100% Armor remains 100%)
function LiveMixin:AdjustMaxArmor(setMax)

    assert(setMax <= LiveMixin.kMaxArmor)
    assert(setMax >= 0)

    local maxArmor = self:GetMaxArmor()
    if setMax ~= maxArmor then
        local armorFraction = 1
        if maxArmor > 0 then
            armorFraction = self:GetArmorScalar()
        end

        self:SetMaxArmor(setMax)
        self:SetArmor(self:GetMaxArmor() * armorFraction, true)
    end

end

function LiveMixin:Heal(amount)

    local healed = false

    local newHealth = math.min(math.max(0, self.health + amount), self:GetMaxHealth())
    if self.alive and self.health ~= newHealth then

        self.health = newHealth
        healed = true

    end

    return healed

end

function LiveMixin:GetIsAlive()
    return self.alive
end

function LiveMixin:SetIsAlive(state)
    self.alive = state
end

function LiveMixin:GetTimeOfLastDamage()
    return self.timeOfLastDamage
end

function LiveMixin:GetAttackerIdOfLastDamage()
    return self.lastDamageAttackerId
end

local function SetLastDamage(self, time, attacker)

    if attacker and attacker.GetId then

        self.timeOfLastDamage = time
        self.lastDamageAttackerId = attacker:GetId()

    end

    -- Track "combat" (for now only take damage, since we don't make a difference between harmful and passive abilities):
    self.timeLastCombatAction = Shared.GetTime()

end

function LiveMixin:GetCanTakeDamage()

    local canTakeDamage = (not self.GetCanTakeDamageOverride or self:GetCanTakeDamageOverride()) and (not self.GetCanTakeDamageOverrideMixin or self:GetCanTakeDamageOverrideMixin())
    return canTakeDamage and not GetIsRecycledUnit(self)

end

function LiveMixin:GetCanDie(byDeathTrigger)

    local canDie = (not self.GetCanDieOverride or self:GetCanDieOverride(byDeathTrigger)) and (not self.GetCanDieOverrideMixin or self:GetCanDieOverrideMixin(byDeathTrigger))
    return canDie

end

function LiveMixin:GetCanGiveDamage()

    if self.GetCanGiveDamageOverride then
        return self:GetCanGiveDamageOverride()
    end
    return false

end

--
-- Returns true if the damage has killed the entity.
--
function LiveMixin:TakeDamage(damage, attacker, doer, point, direction, armorUsed, healthUsed, damageType, preventAlert)

    -- Use AddHealth to give health.
    assert(damage >= 0)

    local killedFromDamage = false
    local oldHealth = self:GetHealth()
    local oldArmor = self:GetArmor()

    if self.OnTakeDamage then
        self:OnTakeDamage(damage, attacker, doer, point, direction, damageType, preventAlert)
    end

    -- Remember time we were last hurt to track combat
    SetLastDamage(self, Shared.GetTime(), attacker)

    -- Do the actual damage only on the server
    if Server then

        -- If a Hive dies, we'll log the biomass level (For Stats)
        local className
        local biomassLevel

        if self.GetClassName then

            className = self:GetClassName()

            if className == "Hive" then
                biomassLevel = self:GetTeam():GetBioMassLevel()-self:GetBioMassLevel()
            end
        end

        -- Damage types that do not ignore health give us leftover damage after armor depletion regardless of us ignoring health.
        if self.healthIgnored then
            healthUsed = 0
        end

        --[[
            NOTE(Salads): An entity's health/armor is set to zero when killed, so
            make sure to use the values as they were before the entity was killed so that
            the damage popup numbers do not add damage from health or armor that wasn't actually
            used.
        --]]
        local newArmor = math.max(0, self:GetArmor() - armorUsed)
        local newHealth = math.max(0, self:GetHealth() - healthUsed)
        self.armor = newArmor
        self.health = newHealth

        local killedFromHealth = oldHealth > 0 and self:GetHealth() == 0 and not self.healthIgnored
        local killedFromArmor = oldArmor > 0 and self:GetArmor() == 0 and self.healthIgnored
        if killedFromHealth or killedFromArmor then

            if not self.AttemptToKill or self:AttemptToKill(damage, attacker, doer, point) then

                self:Kill(attacker, doer, point, direction)
                killedFromDamage = true

            end

        end

        local damageDone = (oldHealth - newHealth) + ((oldArmor - newArmor) * 2)

        local targetTeam = self:GetTeamNumber()

        -- Handle Stats for killing stuff
        if killedFromDamage then

            if self:isa("ResourceTower") then

                StatsUI_AddRTStat(targetTeam, self:GetIsBuilt(), true)

            elseif not self:isa("Player") and not self:isa("Weapon") then

                if StatsUI_GetTechLoggedAsBuilding(self.GetTechId and self:GetTechId()) then
                    -- Destroyed drifter/tech
                    StatsUI_AddExportBuilding(self:GetTeamNumber(),
                        self.GetTechId and self:GetTechId(),
                        self:GetId(),
                        self:GetOrigin(),
                        StatsUI_kLifecycle.Destroyed,
                        true)
                end

                if className then

                    if not StatsUI_GetBuildingBlockedFromLog(className) then
                        StatsUI_AddBuildingStat(targetTeam, self.GetTechId and self:GetTechId(), true)
                    end

                    if StatsUI_GetBuildingLogged(className) then

                        StatsUI_AddTechStat(self:GetTeamNumber(), self.GetTechId and self:GetTechId(), self:GetIsBuilt(), true, false)

                        -- If a hive died, we add the biomass level to the tech log
                        -- If all hives died, we show biomass 1 as lost
                        -- This makes it possible to see the biomass level during the game
                        if biomassLevel then
                            StatsUI_AddTechStat(self:GetTeamNumber(), StatsUI_GetBiomassTechIdFromLevel(Clamp(biomassLevel, 1, 9)), true, biomassLevel == 0, false)
                        end
                    end
                end
            end
        end

        -- Handle stats for damage
        local attackerSteamId, attackerWeapon, attackerTeam = StatsUI_GetAttackerWeapon(attacker, doer)
        if attackerSteamId then

            -- Don't count friendly fire towards damage counts
            -- Check if there is a doer, because when alien structures are off infestation
            -- it will count as an attack for the last person that shot it, only log actual attacks
            if attackerTeam ~= targetTeam and damageDone and damageDone > 0 and doer then
                StatsUI_AddDamageStat(attackerSteamId, damageDone or 0, self and self:isa("Player") and not (self:isa("Hallucination") or self.isHallucination), attackerWeapon, attackerTeam)
            end
        end

        return killedFromDamage, damageDone

    end

    -- things only die on the server
    return false, false
end

function LiveMixin:GetEHP()

    local armorEHP = self:GetArmor() * kHealthPointsPerArmor

    if self.healthIgnored then
        return armorEHP
    end

    local health = self:GetHealth()

    return health + armorEHP

end


--
-- How damaged this entity is, ie how much healing it can receive.
--
function LiveMixin:AmountDamaged(useEHP)
    
    local armorAmount = self:GetMaxArmor() - self:GetArmor()
    if useEHP then
        armorAmount = armorAmount * kHealthPointsPerArmor
    end

    if self.healthIgnored then
        return armorAmount
    end

    local healthAmount = self:GetMaxHealth() - self:GetHealth()
    return healthAmount + armorAmount

end

-- used for situtations where we don't have an attacker. Always normal damage and normal armor use rate
function LiveMixin:DeductHealth(damage, attacker, doer, healthOnly, armorOnly, preventAlert)

    local armorUsed = 0
    local healthUsed = damage

    if self.healthIgnored or armorOnly then

        armorUsed = damage / kHealthPointsPerArmor
        healthUsed = 0

    elseif not healthOnly then

        -- old method effectively used kHealthPointsPerArmor = 1 and kBaseArmorUseFraction = 0.35
        local healthPointsBlocked = math.min( self:GetArmor() * kHealthPointsPerArmor, damage * kBaseArmorUseFraction )
        armorUsed = healthPointsBlocked / kHealthPointsPerArmor
        healthUsed = healthUsed - healthPointsBlocked

    end

    local engagePoint = HasMixin(self, "Target") and self:GetEngagementPoint() or self:GetOrigin()
    return self:TakeDamage(damage, attacker, doer, engagePoint, nil, armorUsed, healthUsed, kDamageType.Normal, preventAlert)

end

function LiveMixin:GetCanBeHealed()

    if self.GetCanBeHealedOverride then
        return self:GetCanBeHealedOverride()
    end

    return self:GetIsAlive()

end

function LiveMixin:AddArmor(armor, playSound, hideEffect, healer )
    assert(armor >= 0)

    if self.GetCanBeHealed and not self:GetCanBeHealed() then
        return 0
    end

    local total = 0

    if self:AmountDamaged() > 0 then

        total = math.min(math.max(0, self:GetArmor() + armor), self:GetMaxArmor()) - self:GetArmor()

        -- Add health first, then armor if we're full
        self:SetArmor(math.min(math.max(0, self:GetArmor() + armor), self:GetMaxArmor()), hideEffect)

        if total > 0 then

            if Server then

                if not hideEffect then

                    self.timeLastVisuallyHealed = Shared.GetTime()

                end

                self.timeLastHealed = Shared.GetTime()

            end

        end

    end

    if total > 0 and self.OnHealed then
        self:OnHealed()
    end

    return total
end

-- Reduce all healing for aliens that goes beyond a relative cap
-- defined by kHealingClampMaxHPAmount and kHealingClampInterval.
function LiveMixin:ClampHealing( healAmount, healer )
    -- Don't clamp system healing (growth/spawning)
    if not healer then return healAmount end

    -- Only clamp healing for aliens
    local isAlien = HasMixin( self, "Team") and self:GetTeamType() == kAlienTeamType
    if not isAlien then return healAmount end

    -- Make sure Crag doesn't get heal-rate capped.
    if healer and healer:isa("Crag") then
        return healAmount
    end

    local now = Shared.GetTime()

    -- Init history
    if not self.healHistory then
        self.healHistory = {
            lastUpdate = now,
            healingReceived = 0
        }
    end

    local ehpMax = self:GetMaxHealth() + self:GetMaxArmor() * kHealthPointsPerArmor
    local ehpSoftCap = ehpMax * kHealingClampMaxHPAmount / kHealingClampInterval -- Maximum amount of ehp that can be received un-taxed

    -- Amortize for time past since last heal
    local timeDiff = now - self.healHistory.lastUpdate
    if timeDiff > 0 then
        self.healHistory.healingReceived = math.max( self.healHistory.healingReceived - timeDiff * ehpSoftCap, 0)
    end

    -- Amount of ehp that can be added before we start getting taxed.
    local ehpRemainUntilCap = math.max(ehpSoftCap - self.healHistory.healingReceived, 0)

    -- Split heal amount into two sums: amount that pushes us up to the cap (if enough), and amount over the cap.
    local nonTaxableHealAmount = math.min(healAmount, ehpRemainUntilCap)
    local taxableHealAmount = healAmount - nonTaxableHealAmount
    assert(nonTaxableHealAmount >= 0)
    assert(taxableHealAmount >= 0)

    healAmount = nonTaxableHealAmount + taxableHealAmount * kHealingClampReductionScalar

    self.healHistory.healingReceived = self.healHistory.healingReceived + healAmount
    self.healHistory.lastUpdate = now

    return healAmount

    
end

-- Return the amount of health we added
function LiveMixin:AddHealth(health, playSound, noArmor, hideEffect, healer, useEHP)

    if self.OnAddHealth then self:OnAddHealth() end

    self.healedFromSelf = healer == self

    -- TakeDamage should be used for negative values.
    assert(health >= 0)

    local total = 0

    if self.GetCanBeHealed and not self:GetCanBeHealed() then
        return 0
    end

    if self.ModifyHeal then

        local healTable = { health = health }
        self:ModifyHeal(healTable)

        health = healTable.health

    end

    if healer and healer.ModifyHealingDone then
        health = healer:ModifyHealingDone(health)
    end

    if self:AmountDamaged(useEHP) > 0 then

        -- Add health first, then armor if we're full
        local healthAdded = math.min(health, self:GetMaxHealth() - self:GetHealth())
        self:SetHealth(self:GetHealth() + self:ClampHealing(healthAdded, healer))

        local healthToAddToArmor = 0
        if not noArmor then

            healthToAddToArmor = health - healthAdded
    
            if useEHP then
                healthToAddToArmor = healthToAddToArmor / kHealthPointsPerArmor
            end
            
            if healthToAddToArmor > 0 then
                healthToAddToArmor = healthToAddToArmor * kArmorHealScalar
                self:SetArmor(self:GetArmor() + self:ClampHealing(healthToAddToArmor, healer), hideEffect)
            end

        end

        total = healthAdded + healthToAddToArmor

        if total > 0 then

            if Server then

                local time = Shared.GetTime()

                if not hideEffect then

                    self.timeLastVisuallyHealed = time

                end

                self.timeLastHealed = time

            end

        end

    end

    if total > 0 and self.OnHealed then
        self:OnHealed()
    end

    return total

end

function LiveMixin:Kill(attacker, doer, point, direction)

    -- Do this first to make sure death message is sent
    if self:GetIsAlive() and self:GetCanDie() then

        if self.PreOnKill then
            self:PreOnKill(attacker, doer, point, direction)
        end

        self.health = 0
        self.armor = 0
        self:SetIsAlive(false)

        if Server then
            GetGamerules():OnEntityKilled(self, attacker, doer, point, direction)
            NotifyAlienBotCommanderOfStructureDeath(self)
        end

        if self.OnKill then
            self:OnKill(attacker, doer, point, direction)
        end

        if Server and self.GetDestroyOnKill and self:GetDestroyOnKill() then
            DestroyEntity(self)
        end

    end

end

-- This function needs to be tested.
function LiveMixin:GetSendDeathMessage(messageViewerTeam, killer)

    if self.GetSendDeathMessageOverride then
        return self:GetSendDeathMessageOverride(messageViewerTeam, killer)
    end

    return true
end

--
-- Entities using LiveMixin are only selectable when they are alive.
--
function LiveMixin:OnGetIsSelectable(result, byTeamNumber)
    if self.OnGetIsSelectableOveride then
        result.selectable = self:OnGetIsSelectableOveride(result, byTeamNumber)
        return
    end

    result.selectable = result.selectable and self:GetIsAlive()
end

function LiveMixin:GetIsHealable()

    if self.GetIsHealableOverride then
        return self:GetIsHealableOverride()
    end

    return self:GetIsAlive()

end

function LiveMixin:OnUpdateAnimationInput(modelMixin)

    PROFILE("LiveMixin:OnUpdateAnimationInput")

    if self.OnUpdateAnimationInputLiveMixinOverride then
        self:OnUpdateAnimationInputLiveMixinOverride(modelMixin)
    else
        modelMixin:SetAnimationInput("alive", self:GetIsAlive())
    end

end

if Server then

    local function UpdateHealerTable(self)

        local cleanupIds = unique_set()
        local numHealers = 0

        local now = Shared.GetTime()
        for entityId, timeExpired in pairs(self.healerTable) do

            if timeExpired <= now then
                cleanupIds:Insert(entityId)
            else
                numHealers = numHealers + 1
            end

        end

        for _, cleanupId in ipairs(cleanupIds:GetList()) do
            self.healerTable[cleanupId] = nil
        end

        return numHealers

    end

    --Currently deprecated. Before usage please refactor UpdateHealerTable to not use pairs if still NYI
    function LiveMixin:RegisterHealer(healer, expireTime)

        if not self.healerTable then
            self.healerTable = {}
        end

        local numHealers = UpdateHealerTable(self)

        if numHealers >= 3 then
            return false
        else
            self.healerTable[healer:GetId()] = expireTime
            return true
        end

    end

elseif Client then

    local function OnKillClientChildren(self)

        -- also call this for all children
        local numChildren = self:GetNumChildren()
        for i = 1,numChildren do
            local child = self:GetChildAtIndex(i - 1)
            if child.OnKillClient then
                child:OnKillClient()
            end
        end

    end

    function LiveMixin:OnAliveChange()

        PROFILE("LiveMixin:OnAliveChange")

        if self.alive ~= self.clientStateAlive then

            self.clientStateAlive = self.alive

            if not self.alive then

                if self.OnKillClient then
                    self:OnKillClient()
                end

                OnKillClientChildren(self)

            end

        end

        return true;

    end

    function LiveMixin:OnDestroy()

        if self.clientStateAlive then

            if self.OnKillClient then
                self:OnKillClient()
            end

            OnKillClientChildren(self)

        end

        self:SetIsAlive(false)

    end

end



function LiveMixin:GetHealth()
    return self.health
end

function LiveMixin:GetArmor()
    return self.armor
end


function LiveMixin:GetCanBeNanoShieldedOverride(resultTable)
    resultTable.shieldedAllowed = resultTable.shieldedAllowed and self:GetIsAlive()
end

-- Change health and max health when changing techIds
function LiveMixin:UpdateHealthValues(newTechId)

    -- Change current and max hit points
    local prevMaxHealth = LookupTechData(self:GetTechId(), kTechDataMaxHealth, 100)
    local newMaxHealth = LookupTechData(newTechId, kTechDataMaxHealth)

    if newMaxHealth == nil then

        Print("%s:UpdateHealthValues(%d): Couldn't find health for id", self:GetClassName(), tostring(newTechId))

        return false

    elseif prevMaxHealth ~= newMaxHealth and prevMaxHealth > 0 and newMaxHealth > 0 then

        -- Calculate percentage of max health and preserve it
        local percent = self.health / prevMaxHealth
        self.health = newMaxHealth * percent

        -- Set new max health
        self:SetMaxHealth(newMaxHealth)

    end

    return true

end

function LiveMixin:GetCanBeUsed(player, useSuccessTable)

    if not self:GetIsAlive() and (not self.GetCanBeUsedDead or not self:GetCanBeUsedDead()) then
        useSuccessTable.useSuccess = false
    end

end

local function GetHealMaterialName(self)

    if HasMixin(self, "Team") then
        return kHealMaterials[self:GetTeamType()]
    end

end

local function GetHealViewMaterialName(self)

    if self.OverrideHealViewMateral then
        return self:OverrideHealViewMateral()
    end

    if HasMixin(self, "Team") then
        return kHealViewMaterials[self:GetTeamType()]
    end

end

function LiveMixin:OnUpdateRender()

    local model = HasMixin(self, "Model") and self:GetRenderModel()

    local localPlayer = Client.GetLocalPlayer()
    local showHeal = not HasMixin(self, "Cloakable") or not self:GetIsCloaked() or not GetAreEnemies(self, localPlayer)

    -- Do healing effects for the model
    if model then

        if self.healMaterial and self.loadedHealMaterialName ~= GetHealMaterialName(self) then

            RemoveMaterial(model, self.healMaterial)
            self.healMaterial = nil

        end

        if not self.healMaterial then

            self.loadedHealMaterialName = GetHealMaterialName(self)
            if self.loadedHealMaterialName then
                self.healMaterial = AddMaterial(model, self.loadedHealMaterialName)
            end

        else
            self.healMaterial:SetParameter("timeLastHealed", showHeal and self.timeLastVisuallyHealed or 0)
        end

    end

    -- Do healing effects for the view model
    if self == localPlayer then

        local viewModelEntity = self:GetViewModelEntity()
        local viewModel = viewModelEntity and viewModelEntity:GetRenderModel()
        if viewModel then

            if self.healViewMaterial and self.loadedHealViewMaterialName ~= GetHealViewMaterialName(self) then

                RemoveMaterial(viewModel, self.healViewMaterial)
                self.healViewMaterial = nil

            end

            if not self.healViewMaterial then

                self.loadedHealViewMaterialName = GetHealViewMaterialName(self)
                if self.loadedHealViewMaterialName then
                    self.healViewMaterial = AddMaterial(viewModel, self.loadedHealViewMaterialName)
                end

            else
                self.healViewMaterial:SetParameter("timeLastHealed", self.timeLastVisuallyHealed)
            end

        end

    end

    if self.timeLastVisuallyHealed ~= self.clientTimeLastHealed then

        self.clientTimeLastHealed = self.timeLastVisuallyHealed

        if showHeal and (not self:isa("Player") or not self:GetIsLocalPlayer()) then
            self:TriggerEffects("heal", { isalien = GetIsAlienUnit(self) })
        end

        self:TriggerEffects("heal_sound", { isalien = GetIsAlienUnit(self), regen = self.healedFromSelf })

    end

end

function LiveMixin:OnEntityChange(oldId, newId)

    if self.healerTable and self.healerTable[oldId] then
        self.healerTable[oldId] = nil
    end

end
