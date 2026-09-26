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

-- Longer range/wider FOV for webs than the axe's normal swing (less frustrating, avoids
-- having to be so close we trigger it).
local kAxeWebHitFov = 55 -- Reasonable coverage compared to the swing
function Axe:Axe_WebHitCheck(coords, player)
    return PerformMeleeWebHitCheck(self, player, kAxeDamage, self:GetRange() * 1.5, kAxeWebHitFov)
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
