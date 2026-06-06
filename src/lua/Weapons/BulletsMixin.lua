-- ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. ============
--
-- lua\BulletsMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

BulletsMixin = CreateMixin( BulletsMixin )
BulletsMixin.type = "Bullets"

BulletsMixin.expectedMixins =
{
    Damage = "Needed for dealing Damage."
}

BulletsMixin.networkVars =
{
}

function BulletsMixin:__initmixin()
end

function BulletsMixin:ApplyBulletStats(target, weaponAccuracyGroupOverride, numBullets)
    PROFILE("BulletsMixin:ApplyBulletGameplayEffects")

    -- Handle Stats
    if Server and numBullets > 0 then

        --Log("BulletsMixin:ApplyBulletStats - %s / %s", target, numBullets)

        local hasTarget = target ~= nil
        local isTargetEnemyPlayer = target and target:isa("Player") and GetAreEnemies(parent, target)
        local isTargetOnos = target and target:isa("Onos")

        local parent = self and self.GetParent and self:GetParent()
        if parent and self.GetTechId then

            -- Drifters, buildings and teammates don't count towards accuracy as hits or misses
            if isTargetEnemyPlayer or target == nil then

                local steamId = parent:GetSteamId()
                if steamId then
                    local techId = self:GetTechId()
                    local teamNumber = parent:GetTeamNumber()
                    for i = 1, numBullets do
                        StatsUI_AddAccuracyStat(steamId, techId, hasTarget, isTargetOnos, teamNumber)
                    end
                end
            end
            local client = parent:GetClient()
            local botAccuracyTracker = GetBotAccuracyTracker()
            for i = 1, numBullets do
                botAccuracyTracker:AddAccuracyStat(client, hasTarget, weaponAccuracyGroupOverride or kBotAccWeaponGroup.Bullets)
            end
        end
    end
end

-- check for umbra and play local hit effects (bullets only)
function BulletsMixin:ApplyBulletGameplayEffects(player, target, endPoint, direction, damage, surface, showTracer, weaponAccuracyGroupOverride)

    PROFILE("BulletsMixin:ApplyBulletGameplayEffects")
    
    if GetBlockedByUmbra(target) then
        surface = "umbra"
    end

    self:ApplyBulletStats(target, weaponAccuracyGroupOverride, 1)
    self:DoDamage(damage, target, endPoint, direction, surface, false, showTracer) -- deals damage or plays surface hit effects
end
