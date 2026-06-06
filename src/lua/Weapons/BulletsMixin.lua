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

-- check for umbra and play local hit effects (bullets only)
function BulletsMixin:ApplyBulletGameplayEffects(player, target, endPoint, direction, damage, surface, showTracer, weaponAccuracyGroupOverride)

    -- Handle Stats
    if Server then

        local parent = self and self.GetParent and self:GetParent()
        if parent and self.GetTechId then

            -- Drifters, buildings and teammates don't count towards accuracy as hits or misses
            if (target and target:isa("Player") and GetAreEnemies(parent, target)) or target == nil then

                local steamId = parent:GetSteamId()
                if steamId then
                    StatsUI_AddAccuracyStat(steamId, self:GetTechId(), target ~= nil, target and target:isa("Onos"), parent:GetTeamNumber())
                end
            end
            GetBotAccuracyTracker():AddAccuracyStat(parent:GetClient(), target ~= nil, weaponAccuracyGroupOverride or kBotAccWeaponGroup.Bullets)
        end
    end

    local blockedByUmbra = GetBlockedByUmbra(target)
    
    if blockedByUmbra then
        surface = "umbra"
    end

    -- deals damage or plays surface hit effects
    self:DoDamage(damage, target, endPoint, direction, surface, false, showTracer)
    
end