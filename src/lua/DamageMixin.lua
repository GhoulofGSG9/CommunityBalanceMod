-- ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. ============
--
-- lua\DamageMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

DamageMixin = CreateMixin(DamageMixin)
DamageMixin.type = "Damage"

-- These may be optionally implemented.
DamageMixin.optionalCallbacks =
{
    PostDoDamage = "Call for when damage has been applied and the function is about to return."
}

function DamageMixin:__initmixin()
    PROFILE("DamageMixin:__initmixin")
end

local function _GetAttackerInfo(self)
    local attacker = self

    if self:isa("Player") then
        attacker = self
    else
        if self:GetParent() and self:GetParent():isa("Player") then
            attacker = self:GetParent()
        elseif HasMixin(self, "Owner") and self:GetOwner() and self:GetOwner():isa("Player") then
            attacker = self:GetOwner()
        end
    end
    return attacker
end

local function _GetWeaponInfo(self, attacker)
    local weapon = nil
    
    if not self:isa("Player") then
        if self:GetParent() and self:GetParent():isa("Player") then
            if attacker:isa("Alien") and (self.secondaryAttacking or self.shootingSpikes) then
                weapon = attacker:GetActiveWeapon():GetSecondaryTechId()
            else
                weapon = self:GetTechId()
            end
        elseif HasMixin(self, "Owner") and self:GetOwner() and self:GetOwner():isa("Player") then
            if self.GetWeaponTechId then
                weapon = self:GetWeaponTechId()
            elseif self.GetTechId then
                weapon = self:GetTechId()
            end
        end
    end

    return weapon
end

local function _GetAttackInfo(self, damage)
    local attacker = _GetAttackerInfo(self)
    local currentComm = nil
    local damageType = kDamageType.Normal
    local weapon = _GetWeaponInfo(self, attacker)
    
    if not self:isa("Player") then
        if HasMixin(self, "Owner") and self:GetOwner() and self:GetOwner():isa("Player") then
            -- If it's one of these doing damage, send the damage message to the current commander instead
            -- The original owner remains the same
            if self:isa("Whip") or self:isa("WhipBomb") or self:isa("ARC") or self:isa("Sentry") or self:isa("MAC") or self:isa("Drifter") then
                local commanders = GetEntitiesForTeam("Commander", self:GetTeamNumber())
                if commanders and commanders[1] then
                    currentComm = commanders[1]
                end
            end
        end
    end

    -- Only fetch info if we actually do damages
    if attacker and damage > 0 then
        -- Get damage type from source
        if self.GetDamageType then
            damageType = self:GetDamageType()
        elseif HasMixin(self, "Tech") then
            damageType = LookupTechData(self:GetTechId(), kTechDataDamageType, kDamageType.Normal)
        end
    end

    return weapon, damageType, currentComm
end

local function _DealDamage(self, attacker, weapon, damage, damageType, target, direction, point)
    local doer = self
    local armorUsed = 0
    local healthUsed = 0
    local overshieldDamage = 0

    local damageDone = 0
    local rawDamage = damage
    
    if target and HasMixin(target, "Live") and damage > 0 then  

        damage, armorUsed, healthUsed, overshieldDamage = GetDamageByType(target, attacker, doer, damage, damageType, point, weapon)

        overshieldDamage = overshieldDamage or 0 -- Just in case mods alter damage rules in a way that this becomes nil
        rawDamage = damage + overshieldDamage

        -- Get the target entity id before takedamage so we can add the killing shot damage to our damage total.
        local targetEntityId = target:GetId()
        killedFromDamage, damageDone = target:TakeDamage(damage + overshieldDamage, attacker, doer, point, direction, armorUsed, healthUsed, damageType, nil)

        if rawDamage > 0 then
                            
            -- Many types of damage events are server-only, such as grenades.
            -- Send the player a message so they get feedback about what damage they've done.
            -- We use messages to handle multiple-hits per frame, such as splash damage from grenades.
            if Server and attacker:isa("Player") then
            
                local areEnemies = GetAreEnemies( attacker, target )
                if areEnemies then
                
                    local amount = (killedFromDamage or target:GetCanTakeDamage()) and (damageDone + overshieldDamage) or 0 -- actual damage done
                    local overkill = healthUsed + armorUsed * 2 -- the full amount of potential damage, including overkill
                    
                    if HitSound_IsEnabledForWeapon( weapon ) then
                        -- Damage message will be sent at the end of OnProcessMove by the HitSound system
                        HitSound_RecordHit( attacker, target, amount, point, overkill, weapon )
                    else
                        SendDamageMessage( currentComm or attacker, targetEntityId, amount, point, overkill, weapon )
                    end
                    
                    SendMarkEnemyMessage( attacker, target, amount, weapon )
                
                end
                
                -- This makes the cross hair turn red. Show it when hitting enemies only
                if areEnemies and (not doer.GetShowHitIndicator or doer:GetShowHitIndicator()) then
                    attacker.giveDamageTime = Shared.GetTime()
                end
                
            end

            --------------------------------------
            -- The callbacks, at last

            if self.OnDamageDone then
                self:OnDamageDone(doer, target)
            end
            if attacker and attacker.OnDamageDone then
                attacker:OnDamageDone(doer, target)
            end
        end
    end

    return killedFromDamage, damageDone, rawDamage
end

--local totalMsgCount = 0
local function _DealEffects__Server(self, surface, attacker, weapon, rawDamage, target, point, direction, altMode, showtracer)

    PROFILE("DamageMixin:DealEffects__Server")

    local now = Shared.GetTime()
    if target then    
        -- A single target can only display impact effects from others every X amount of time
        -- This greatly reduces the amount of messages from targets under heavy firing (Onos, PvE, Hives)
        -- Note: The client deals with its own effects, so he sees all of its hits (it is only from others here)    
        if target.kTimeLastDamageEffectShown and target.kTimeLastDamageEffectShown + 0.2 > now then
            return
        end
        
    end

    local doer = self
    local isHit = target ~= nil
    local hitRelevancyDist = kHitEffectRelevancyDistance
    local hitRelevancyPoint = point
    local isFullAutoGun = weapon and (weapon == kTechId.Rifle or weapon == kTechId.Submachinegun or weapon == kTechId.HeavyMachineGun)
    --(doer and doer:isa("ClipWeapon")) and doer:GetClipSize() >= 50 or false -- rifle/smg/hmg
    local regulateEffects = isFullAutoGun and (not (doer and doer:GetClip() % 3 == 0)) or false -- Only do one out of X (like tracert random)

    --Log("Regulate full auto ? %s/%s(%s), fullauto:%s / Allow effect: %s", doer:GetAmmo(), doer:GetClip(), doer:GetClipSize(), isFullAutoGun, (not regulateEffects))

    if not regulateEffects and GetShouldSendHitEffect() then

        if target then
            target.kTimeLastDamageEffectShown = now
        end
        local toPlayers = GetEntitiesWithinRange("Player", hitRelevancyPoint, hitRelevancyDist) -- kHitEffectRelevancyDistance)
        
        -- No need to send to the attacker if this is a child of the attacker.
        -- Children such as weapons are simulated on the Client as well so they will
        -- already see the hit effect.
        local isChildOfAttacker = attacker and self:GetParent() == attacker and not attacker.serverBlood

        --Log("Entering heavy loops:")
        local message = nil
        local sent = 0
        local maxSendCount = 6
        local targetId = target and target:GetId() or 0
        for i, player in ipairs(toPlayers) do
            -- The target cannot see it's own body, no need to send it shots on him
            if not (isChildOfAttacker and player == attacker) and not (targetId == player:GetId()) then

                -- Only do a network message if the actual player can see/damage the point (saves a lot of network messages)
                local trace = nil
                local canSeePoint = true
                local doTrace = true
                if doTrace then
                    trace = Shared.TraceRay(point, player:GetEyePos(), CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(player))
                    canSeePoint = (trace.fraction >= 0.95)
                end

                if (canSeePoint) then
                    if message == nil then -- Only build if we have to send it to others, otherwise nothing
                        local directionVectorIndex = direction and GetIndexFromVector(direction) or 1
                        message = BuildHitEffectMessage(point, doer, surface, target, showtracer, altMode, rawDamage, directionVectorIndex)
                    end
                    Server.SendNetworkMessage(player, "HitEffect", message, false)

                    sent = sent + 1
                    --totalMsgCount = totalMsgCount + 1
                    --Log("-Sending network message: %s", totalMsgCount)
                    --if (player:isa("Spectator")) then
                    --    DebugLine(player:GetEyePos(), point, 3, 0, 1, 0, 1)
                    --end
                else
                    --if (player:isa("Spectator")) then
                    --    DebugLine(point, player:GetEyePos(), 3, 1, 0, 0, 1)
                    --end
                end

            end
            if (sent >= maxSendCount) then
                break
            end
        end
    end
end

local function _DealEffects__Client(self, surface, attacker, weapon, rawDamage, target, point, direction, altMode, showtracer)
    local doer = self
    local player = Client.GetLocalPlayer()

    if not player.serverBlood then

        if GetIsPointOnInfestation(point) then
            surface = "infestation"
        end
        if not surface or surface == "" then
            surface = "metal"
        end
        HandleHitEffect(point, doer, surface, target, showtracer, altMode, rawDamage, direction)
    end
    
    -- If we are far away from our target, trigger a private sound so we can hear we hit something
    if target then
        
        if attacker.MarkEnemyFromClient then
            attacker:MarkEnemyFromClient( target, weapon )
        end
        
        if (point - attacker:GetOrigin()):GetLength() > 5 then
            attacker:TriggerEffects("hit_effect_local")
        end
        
    end
end

local function _DealEffects(self, surface, attacker, weapon, damageDone, rawDamage, damageType, target, direction, point, altMode, showtracer)

    PROFILE("DamageMixin:DealEffects")

    -- trigger damage effects (damage, deflect) with correct surface
    if surface ~= "none" then
        --local armorMultiplier = ConditionalValue(damageType == kDamageType.Light, 4, 2)
        --armorMultiplier = ConditionalValue(damageType == kDamageType.Heavy, 1, armorMultiplier)
        -- local playArmorEffect = armorUsed * armorMultiplier > healthUsed 

        if target then
            if target and HasMixin(target, "NanoShieldAble") and target:GetIsNanoShielded() then    
                surface = "nanoshield"
            elseif target and HasMixin(target, "Fire") and target:GetIsOnFire() then
                surface = "flame"
            elseif target:isa("Marine") and target.variant and table.icontains( kRoboticMarineVariantIds, target.variant) then
                surface = "robot"
            elseif not surface or surface == "" then
                surface = GetIsAlienUnit(target) and "organic" or "metal"
                -- define metal_thin, rock, or other
                if target.GetSurfaceOverride then
                    surface = target:GetSurfaceOverride(damageDone) or surface
                elseif GetAreEnemies(self, target) then
                    if target:isa("Alien") then
                        surface = "organic"
                    elseif target:isa("Exo") then
                        surface = "robot"
                    elseif target:isa("Marine") then
                        surface = "flesh"
                    else
                        if HasMixin(target, "Team") then
                            if target:GetTeamType() == kAlienTeamType then
                                surface = "organic"
                            else
                                surface = "metal"
                            end
                        end
                    end
                end
            end
        end

        -- Send to all players in range, except to attacking player, he will predict the hit effect
        if Server then
            _DealEffects__Server(self, surface, attacker, weapon, rawDamage, target, point, direction, altMode, showtracer)
        elseif Client then
            _DealEffects__Client(self, surface, attacker, weapon, rawDamage, target, point, direction, altMode, showtracer)
        end
    end 
end

local function _DoHitShot(self, damage, target, point, direction, surface, altMode, showtracer)
    PROFILE("DamageMixin:_DoHitShot")

    direction = direction or Vector(0, 0, 1)

    local attacker = _GetAttackerInfo(self)
    local weapon, damageType, currentComm = _GetAttackInfo(self, damage)
    local killedFromDamage, damageDone, rawDamage = _DealDamage(self, attacker, weapon, damage, damageType, target, direction, point)
    
    return killedFromDamage, weapon, damageDone, rawDamage
end

-- damage type, doer and attacker don't need to be passed. that info is going to be fetched here. pass optional surface name
-- pass surface "none" for not hit/flinch effect
function DamageMixin:DoDamage(damage, target, point, direction, surface, altMode, showtracer)

    PROFILE("DamageMixin:DoDamage")

    local killedFromDamage = false
    local attacker = _GetAttackerInfo(self)
    local weapon = nil
    local damageDone = 0
    local rawDamage = 0

    -- No prediction if the Client is spectating another player.
    if Client and not Client.GetIsControllingPlayer() then
        return false
    end
    
    if (target) then -- HIT
        if target:isa("Ragdoll") or not (target.GetCanTakeDamage and target:GetCanTakeDamage()) then
            return false
        end
        killedFromDamage, weapon, damageDone, rawDamage = _DoHitShot(self, damage, target, point, direction, surface, altMode, showtracer)
    else -- MISS
    --[[
        if GetIsPointOnInfestation(point) then
            surface = "infestation"
        end
        if not surface or surface == "" then
            surface = "metal"
        end
        --]]
        weapon = _GetWeaponInfo(self, attacker)
    end

    if surface ~= "none" then
        _DealEffects(self, surface, attacker, weapon, damageDone, rawDamage, damageType, target, direction, point, altMode, showtracer)
    end

    if self.PostDoDamage then
        self:PostDoDamage(target, damageDone)
    end
    
    return killedFromDamage
end
