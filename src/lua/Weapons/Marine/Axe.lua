-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Axe.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Weapon.lua")
Script.Load("lua/AxeVariantMixin.lua")

class 'Axe' (Weapon)

Axe.kMapName = "axe"

Axe.kModelName = PrecacheAsset("models/marine/axe/axe.model")

local kViewModels = GenerateMarineViewModelPaths("axe")
local kAnimationGraph = PrecacheAsset("models/marine/axe/axe_view.animation_graph")

Axe.kRange = 1
Axe.kFloorRange = 0.8

local idleTime = 0
local animFrequency = 10

local networkVars =
{
    sprintAllowed = "boolean",
}
AddMixinNetworkVars(AxeVariantMixin, networkVars)

function Axe:OnCreate()

    Weapon.OnCreate(self)
    
    InitMixin(self, AxeVariantMixin)
    
    self.sprintAllowed = true
    
end

function Axe:OnInitialized()

    Weapon.OnInitialized(self)
    
    self:SetModel(Axe.kModelName)
    
end

function Axe:GetViewModelName(sex, variant)
    return kViewModels[sex][variant]
end

function Axe:GetAnimationGraphName()
    return kAnimationGraph
end

function Axe:GetHUDSlot()
    return kTertiaryWeaponSlot
end

function Axe:GetRange()
	local player = self:GetParent()
	local floorAim = player and player:GetViewCoords().zAxis.y or 0
	floorAim = floorAim * floorAim
    return Axe.kRange + Clamp(floorAim,0,1) * Axe.kFloorRange
end

function Axe:GetShowDamageIndicator()
    return true
end

function Axe:GetSprintAllowed()
    return self.sprintAllowed
end

function Axe:GetDeathIconIndex()
    return kDeathMessageIcon.Axe
end

function Axe:GetIdleAnimations(index)
    local animations = {"idle", "idle_toss", "idle_toss"}
    return animations[index]
end

function Axe:OnDraw(player, previousWeaponMapName)

    Weapon.OnDraw(self, player, previousWeaponMapName)
    
    -- Attach weapon to parent's hand
    self:SetAttachPoint(Weapon.kHumanAttachPoint)
    
    idleTime = Shared.GetTime()
    
end

function Axe:OnHolster(player)

    Weapon.OnHolster(self, player)
    
    self.sprintAllowed = true
    self.primaryAttacking = false
    
end

function Axe:OnPrimaryAttack(player)

    if not self.attacking then
        
        self.sprintAllowed = false
        self.primaryAttacking = true
        
    end

end

function Axe:OnPrimaryAttackEnd(player)
    self.primaryAttacking = false
    idleTime = Shared.GetTime()
end

local toEntity = Vector()
local function withinFoV(seeingEntity, hitFov, targetOrigin, eyePos)
    local withinFOV = true
    
    -- Calculate vector from eye to target
    toEntity.x = targetOrigin.x - eyePos.x
    toEntity.y = targetOrigin.y - eyePos.y  
    toEntity.z = targetOrigin.z - eyePos.z
    
    -- Early exit for very close targets (they're always visible)
    local toEntityLength = math.sqrt(toEntity.x * toEntity.x + 
                                     toEntity.y * toEntity.y + 
                                     toEntity.z * toEntity.z)
    if toEntityLength <= kEpsilon then
        return true
    end

    -- Normalize
    local invLength = 1.0 / toEntityLength
    toEntity.x = toEntity.x * invLength
    toEntity.y = toEntity.y * invLength
    toEntity.z = toEntity.z * invLength

    -- View direction
    local seeingEntityAngles = GetEntityViewAngles(seeingEntity)
    local forwardVec = seeingEntityAngles:GetCoords().zAxis
    
    local dotProduct = Math.DotProduct(toEntity, forwardVec)
    dotProduct = math.max(-1, math.min(1, dotProduct)) -- Safety clamp
    
    local halfFovRad = math.rad(hitFov / 2)
    local angle = math.acos(dotProduct)
    
    withinFOV = angle <= halfFovRad
    
    return withinFOV
end

function Axe:Axe_WebHitCheck(coords, player)
    -- Longer range for webs (less frustrating, avoids having to be so close we trigger it)
    local range = self:GetRange() * 1.5
    local hitFov = 55 -- Reasonable coverage compared to the swing

    local enemyTeamNumber = GetEnemyTeamNumber(self:GetTeamNumber())
    local playerPos = player:GetEyePos()
    
    -- Fetch webs in expanded range for FOV consideration
    local webs = GetEntitiesForTeamWithinRange("Web", enemyTeamNumber, 
                                              playerPos, kMaxWebLength * 2)
    
    for _, web in ipairs(webs) do
        local closestWebPoint = web:GetClosestPointOnWeb(playerPos + coords.zAxis * (range / 2))
        
        -- Check distance first (cheaper than FOV)
        local distance = closestWebPoint:GetDistanceTo(playerPos)
        local isWithinHitFoV = withinFoV(player, hitFov, closestWebPoint, playerPos)        
        if distance <= range and isWithinHitFoV then
            -- Final raycheck to be sure there are no walls
            local rayTrace = Shared.TraceRay(playerPos, closestWebPoint, CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, EntityFilterTwo(player, self))
            if rayTrace.entity and rayTrace.entity:isa("Web") then
                self:DoDamage(kAxeDamage, web, closestWebPoint, coords.yAxis, "organic", false)
                return true, web
            end
        end
    end
    return false, nil
end

-- local swipeStart = nil
-- local axeHitDelay = nil
function Axe:OnTag(tagName)

    PROFILE("Axe:OnTag")
    
    if tagName == "swipe_sound" then
    
        local player = self:GetParent()
        if player then
            player:TriggerEffects("axe_attack")
        end
        
    elseif tagName == "hit" then
    
        local player = self:GetParent()
        local coords = player:GetViewAngles():GetCoords()

        -- Check webs first (so we don't hit clogs around it if we aim for it)
        local didHit, target = self:Axe_WebHitCheck(coords, player)
        if not (didHit and target) and coords then
            didHit, target = AttackMeleeCapsule(self, player, kAxeDamage, self:GetRange())
        end
        
    elseif tagName == "attack_end" then
        self.sprintAllowed = true
    elseif tagName == "deploy_end" then
        self.sprintAllowed = true
    elseif tagName == "idle_toss_start" then
        self:TriggerEffects("axe_idle_toss")
    elseif tagName == "idle_fiddle_start" then
        self:TriggerEffects("axe_idle_fiddle")
    end
    
end

function Axe:OnUpdateAnimationInput(modelMixin)

    PROFILE("Axe:OnUpdateAnimationInput")
    
    local player = self:GetParent()
    if player and player:GetIsIdle() then
        local totalTime = math.round(Shared.GetTime() - idleTime)
        if totalTime >= animFrequency*3 then
            idleTime = Shared.GetTime()
        elseif totalTime >= animFrequency*2 and self:GetIdleAnimations(3) then
            modelMixin:SetAnimationInput("idleName", self:GetIdleAnimations(3))
        elseif totalTime >= animFrequency and self:GetIdleAnimations(2) then
            modelMixin:SetAnimationInput("idleName", self:GetIdleAnimations(2))
        elseif totalTime < animFrequency then
            modelMixin:SetAnimationInput("idleName", self:GetIdleAnimations(1))
        end
        
    else
        idleTime = Shared.GetTime()
        modelMixin:SetAnimationInput("idleName", "idle")
    end
    
    local activity = "none"
    if self.primaryAttacking then
        activity = "primary"
    end
    modelMixin:SetAnimationInput("activity", activity)
    
end

function Axe:UseLandIntensity()
    return true
end

Shared.LinkClassToMap("Axe", Axe.kMapName, networkVars)
