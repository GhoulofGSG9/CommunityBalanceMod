-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Alien\StompMixin.lua
--
--    Created by:   Andreas Urwalek (a_urwa@sbox.tugraz.at)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Alien/Shockwave.lua")

StompMixin = CreateMixin( StompMixin  )
StompMixin.type = "Stomp"

-- local kMaxPlayerVelocityToStomp = 6
-- local kDisruptRange = kStompRange
-- local kStompVerticalRange = 1.5

-- local kStompRadius = 2

local kAttackDurationStomp = Shared.GetAnimationLength("models/alien/onos/onos_view.model", "stomp")

local kStompExpiryMargin = 0.15
local kStompExpiry = kAttackDurationStomp + kStompExpiryMargin
local kStompMinEndFraction = 0.25

-- GetHasSecondary and GetSecondaryEnergyCost should completely override any existing
-- same named function defined in the object.
StompMixin.overrideFunctions =
{
    "GetHasSecondary",
    "GetSecondaryEnergyCost",
    "GetSecondaryTechId",
    "OnSecondaryAttack",
    "OnSecondaryAttackEnd",
    "PerformSecondaryAttack"
}

StompMixin.networkVars =
{
}

function StompMixin:__initmixin()
    
    PROFILE("StompMixin:__initmixin")
    
    if Server then
        self.shockwaveEntIds = {}
    end

end

function StompMixin:GetIsStomping()

    if self.secondaryAttacking == true and self.secondaryAttackStartTime ~= nil and
            Shared.GetTime() > self.secondaryAttackStartTime + kStompExpiry then
        self:CancelStomp()
    end

    return self.secondaryAttacking == true

end

function StompMixin:GetIsStompRunning()
    return self:GetIsStomping() and self.secondaryAttackStartTime ~= nil
end


function StompMixin:CancelStomp(player)

    self.secondaryAttacking = false
    self.stompHitReceived = false
    self.stompInputActive = false

    player = player or self:GetParent()
    if player then
        player.stomping = false
    end

end

function StompMixin:GetSecondaryTechId()
    return kTechId.Stomp
end

function StompMixin:GetHasSecondary(player)
    return player:GetHasThreeHives()
end

function StompMixin:GetSecondaryEnergyCost()
    return kStompEnergyCost
end

function StompMixin:PerformStomp(player)

    local stompOrigin = player:GetOrigin()

    if Server then

        local direction = GetNormalizedVectorXZ(player:GetViewCoordsZAxis())
        local shockwaveOrigin = stompOrigin + Vector.yAxis * 0.2 + direction * 0.4

        local shockwave = CreateEntity(Shockwave.kMapName, shockwaveOrigin, self:GetTeamNumber())
        shockwave:SetOwner(player)

        local coords = Coords.GetLookIn(shockwaveOrigin, direction)
        shockwave:SetCoords(coords)

        local shockwaveId = shockwave:GetId()
        table.insert(self.shockwaveEntIds, shockwaveId)

    end

    -- discrupt minigun exos in range as well
    --[[
    local enemyTeamNum = GetEnemyTeamNumber(self:GetTeamNumber())
    for index, exo in ipairs(GetEntitiesForTeamWithinRange("Exo", enemyTeamNum, stompOrigin, kStompRadius)) do

        if math.abs(exo:GetOrigin().y - stompOrigin.y) < 1.2 then
            exo:Disrupt()
        end

    end
    --]]

end

function StompMixin:OnSecondaryAttack(player)

    if player:GetTimeOfLastWeaponSwitch() > (self.stompButtonReleasedTime or 0) and
            player:GetSecondaryAttackLastFrame() then
        return
    end

    local switchPending = self.GetHasPendingWeaponSwitch and self:GetHasPendingWeaponSwitch()
    local canStart = not switchPending and not self:GetIsStompRunning() and
            player:GetEnergy() >= kStompEnergyCost and player:GetIsOnGround()

    local primaryBusy = self.primaryAttacking or (self.GetIsPrimaryAttackInProgress and self:GetIsPrimaryAttackInProgress())

    if canStart and primaryBusy and self.GetCanInterruptPrimaryForStomp and self:GetCanInterruptPrimaryForStomp() then
        self:InterruptPrimaryForStomp(player)
        primaryBusy = false
    end

    if canStart and not primaryBusy then
        self.stompInputActive = true
        self.secondaryAttacking = true
        self.stompHitReceived = false
        self.secondaryAttackStartTime = Shared.GetTime()
        player.stomping = true
    end

end

function StompMixin:OnSecondaryAttackEnd(_)
    self.stompButtonReleasedTime = Shared.GetTime()
end

function StompMixin:OnTag(tagName)

    PROFILE("StompMixin:OnTag")

    if self.secondaryAttacking and tagName == "stomp_hit" then

        if self.stompHitReceived then
            return
        end

        local stompPlayer = self:GetParent()
        if stompPlayer and stompPlayer:GetEnergy() < kStompEnergyCost then
            self:CancelStomp(stompPlayer)
            return
        end

        self.stompHitReceived = true

        local player = self:GetParent()

        if player then

            self:PerformStomp(player)
            player:TriggerEffects("stomp_attack", { effecthostcoords = player:GetCoords() })
            player:DeductAbilityEnergy(kStompEnergyCost)

        end

    elseif tagName == "end" and self.secondaryAttacking and
            Shared.GetTime() >= (self.secondaryAttackStartTime or 0) + kAttackDurationStomp * kStompMinEndFraction then
        self:CancelStomp()
    end

end

function StompMixin:OnUpdateAnimationInput(modelMixin)
    if self:GetIsStomping() and self.stompInputActive ~= false then
        modelMixin:SetAnimationInput("activity", "secondary")
    end
end

function StompMixin:UnregisterShockwave(shockwave)
    table.removevalue(self.shockwaveEntIds, shockwave:GetId())
end

function StompMixin:OnProcessMove(input)

    if self.secondaryAttacking and self.secondaryAttackStartTime and
            Shared.GetTime() > self.secondaryAttackStartTime + kStompExpiry then

        self:CancelStomp()

    end

end

if Server then

    function StompMixin:ProcessMoveOnOwnedEntities(deltaTime)

        local ids = self.shockwaveEntIds

        for i = #ids, 1, -1 do

            local shockwave = Shared.GetEntity(ids[i])
            if shockwave then
                shockwave:UpdateShockwave(deltaTime)
            else
                table.remove(ids, i)
            end

        end

    end

end

if Server then

    function StompMixin:OnDestroy()

        self:CancelStomp()

        local ids = self.shockwaveEntIds

        for i = #ids, 1, -1 do

            local shockwave = Shared.GetEntity(ids[i])
            if shockwave then
                DestroyEntity(shockwave)
            end

        end

    end

end
