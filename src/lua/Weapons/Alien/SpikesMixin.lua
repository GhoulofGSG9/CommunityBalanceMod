-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Alien\SpikesMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

SpikesMixin = CreateMixin( SpikesMixin )
SpikesMixin.type = "Spikes"

-- GetHasSecondary and GetSecondaryEnergyCost should completely override any existing
-- same named function defined in the object.
SpikesMixin.overrideFunctions =
{
    "GetHasSecondary",
    "GetSecondaryEnergyCost",
    "GetBarrelPoint",
    "OnSecondaryAttack",
    "OnSecondaryAttackEnd",
    "GetTracerEffectName"
    
}

SpikesMixin.networkVars =
{
    shootingSpikes = "boolean",
    -- need to use a network variable for silence upgrade here, since the marines do not know the alien tech tree
    silenced = "boolean"
}

function SpikesMixin:PostDoDamage(target, damage)

    if Server then

        local parent = self:GetParent()
        local steamId = parent and parent.GetSteamId and parent:GetSteamId()
        if not steamId then return end

        if target and GetAreEnemies(parent, target) then
            StatsUI_AddAccuracyStat(steamId, self:GetSecondaryTechId(), true, target:isa("Onos"), parent:GetTeamNumber())
            GetBotAccuracyTracker():AddAccuracyStat(parent:GetClient(), true, kBotAccWeaponGroup.LerkSpikes)
        else
            StatsUI_AddAccuracyStat(steamId, self:GetSecondaryTechId(), false, false, parent:GetTeamNumber())
            GetBotAccuracyTracker():AddAccuracyStat(parent:GetClient(), false, kBotAccWeaponGroup.LerkSpikes)
        end

    end

    if self.primaryAttacking then return end

end

function SpikesMixin:FireSpikes()

    local player = self:GetParent()
    local viewAngles = player:GetViewAngles()
    viewAngles.roll = NetworkRandom() * math.pi * 2

    -- Filter ourself out of the trace so that we don't hit ourselves.
    local filter = EntityFilterOneAndIsa(player, "Babbler")
    local range = kSpikesRange

    local numSpikes = kSpikesPerShot
    local startPoint = player:GetEyePos()

    local viewCoords = player:GetViewCoords()

    self.spiked = true
    self.silenced = GetHasSilenceUpgrade(player) and player:GetVeilLevel() > 0

    for _ = 1, numSpikes do

        -- Calculate spread for each shot, in case they differ
        local spreadDirection = CalculateSpread(viewCoords, kSpikeSpread, NetworkRandom)

        local endPoint = startPoint + spreadDirection * range
        local targets, trace, hitPoints = GetBulletTargets(startPoint, endPoint, spreadDirection, kSpikeSize, filter)        
        local damage = kSpikeDamage
        local direction = (trace.endPoint - startPoint):GetUnit()
        local hitOffset = direction * kHitEffectOffset        
        local impactPoint = trace.endPoint - hitOffset
        local showTracer = math.random() < 0.75
        local numTargets = #targets
        
        if numTargets == 0 then
            self:DoDamage(damage, nil, impactPoint, direction, trace.surface, true, showTracer)
        else
            for i = 1, numTargets do

                local target = targets[i]
                local hitPoint = hitPoints[i]                                     

                self:DoDamage(damage, target, hitPoint - hitOffset, direction, trace.surface, true, showTracer)

            end
        end

    end

end

function SpikesMixin:GetTracerEffectName()
    return kSpikeTracerEffectName
end

function SpikesMixin:GetTracerResidueEffectName()

    local parent = self:GetParent()
    if parent and parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
        return kSpikeTracerFirstPersonResidueEffectName
    else
        return kSpikeTracerResidueEffectName
    end 
    
end

function SpikesMixin:OnSecondaryAttack(player)

    if player:GetEnergy() >= self:GetSecondaryEnergyCost() and not self.primaryAttacking then
        self.shootingSpikes = true
    else
        self.shootingSpikes = false
        self.secondaryAttacking = false
    end
    
end

function SpikesMixin:OnSecondaryAttackEnd(player)

    Ability.OnSecondaryAttackEnd(self, player)    
    self.secondaryAttacking = false
    self.shootingSpikes = false

end

function SpikesMixin:OnHolster()
    self.shootingSpikes = false
end

function SpikesMixin:GetHasSecondary(player)
    return true
end

function SpikesMixin:GetSecondaryEnergyCost()
    return kSpikeEnergyCost
end

function SpikesMixin:GetBarrelPoint()

    local player = self:GetParent()
    
    if player then
    
        local viewCoords = player:GetViewCoords()
        local barrelPoint = viewCoords.origin + viewCoords.zAxis * 2 - viewCoords.yAxis * 0.1
        
        if self.shootLeft then
            barrelPoint = barrelPoint - viewCoords.xAxis * 0.4
        else
            barrelPoint = barrelPoint + viewCoords.xAxis * 0.4
        end
        
        self.shootLeft = not self.shootLeft
        
        return barrelPoint
        
    end

end

function SpikesMixin:OnTag(tagName)

    PROFILE("SpikesMixin:OnTag")

    if self.shootingSpikes and tagName == "shoot" then

        local player = self:GetParent()
        if player and player:GetEnergy() > self:GetSecondaryEnergyCost() then

            self:FireSpikes()
            self:GetParent():DeductAbilityEnergy(self:GetSecondaryEnergyCost())
            self.secondaryAttacking = true

        else
            self.shootingSpikes = false
            self.secondaryAttacking = false
        end

    end

end

function SpikesMixin:OnUpdateAnimationInput(modelMixin)

    PROFILE("SpikesMixin:OnUpdateAnimationInput")

    local player = self:GetParent()
    if player and self.shootingSpikes and player:GetEnergy() >= self:GetSecondaryEnergyCost() then
        modelMixin:SetAnimationInput("activity", "secondary")
    end
    
end

function SpikesMixin:GetIsSecondaryBlocking()
    return self.secondaryAttacking
end

function SpikesMixin:OnClientSecondaryAttacking()

    if not self.silenced then
        self:TriggerEffects("spikes_attack")
    end
    
end

function SpikesMixin:GetTriggerSecondaryEffects()

    local parent = self:GetParent()
    return parent ~= nil and parent:GetIsAlive()

end

function SpikesMixin:GetDamageType()
    return kSpikeDamageType
end
