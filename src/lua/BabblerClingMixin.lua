-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\BabblerClingMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
--    Handles babblers attaching to units.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

-- TODO: create better effect
PrecacheAsset("cinematics/vfx_materials/parasited.surface_shader")
local kMaterialName = PrecacheAsset("cinematics/vfx_materials/parasited.material")

BabblerClingMixin = CreateMixin(BabblerClingMixin)
BabblerClingMixin.type = "BabblerCling"

BabblerClingMixin.expectedMixins =
{
    Usable = "For babbler donation"
}

local kBabblerAttachPoints =
{
    "babbler_attach1",
    "babbler_attach2",
    "babbler_attach3",
    "babbler_attach4",
    "babbler_attach5",
    "babbler_attach6",
}
local kMaxClingedBabblers = #kBabblerAttachPoints

BabblerClingMixin.kAmountDonatedForPoints = 6
BabblerClingMixin.kDonationScoreAdded = 0.5

local kMaxShield = kBabblerShieldMaxAmount
BabblerClingMixin.networkVars =
{
    numBabblers = "integer (0 to 6)",
    babblerShieldRemaining = string.format("float (0 to %f by 0.0625)", kMaxShield)
}

function BabblerClingMixin:__initmixin()
    
    PROFILE("BabblerClingMixin:__initmixin")
    
    self.attachedBabblers = {}
    self.freeAttachPoints = {}
    table.copy(kBabblerAttachPoints, self.freeAttachPoints)

    self.numBabblers = 0
    self.babblerShieldRemaining = 0

    local babblerShieldPercent = self.GetBabblerShieldPercentage and self:GetBabblerShieldPercentage() or kBabblerShieldPercent
    self.babblerShieldMaxAmount = math.min(math.round(self:GetBaseHealth() * babblerShieldPercent), kMaxShield)
    self.babblerShieldPerBabbler = math.max(self.babblerShieldMaxAmount / kMaxClingedBabblers, kEpsilon)
end

function BabblerClingMixin:GetNumClingedBabblers()
    return self.numBabblers
end

function BabblerClingMixin:GetMaxClingedBabblers()
    return kMaxClingedBabblers
end

function BabblerClingMixin:GetCanAttachBabbler()
    local numClingedBabbler = self:GetNumClingedBabblers()
    local numAttachPoints = self:GetMaxClingedBabblers()

    return (not self.isHallucination and numClingedBabbler < numAttachPoints and not self:isa("Hallucination"))
end

-- How many more babblers this entity can actually end up with, right now.
function BabblerClingMixin:GetNumFreeDonationSpots()

    local freeSpots = self:GetMaxClingedBabblers() - self:GetNumClingedBabblers()

    if HasMixin(self, "BabblerOwner") then
        freeSpots = math.min(freeSpots, self:GetMaxBabblers() - self:GetBabblerCount())
    end

    freeSpots = freeSpots - GetNumBabblersEnRouteToCling(self)

    return math.max(freeSpots, 0)

end

function BabblerClingMixin:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint, weapon)
    local damage = damageTable.damage or 0
    if damage > 0 and self:GetApplyBabblerShield(damageType) then
        local amount = math.min(damage, self.babblerShieldRemaining)

        if Server then
            self.babblerShieldRemaining = math.max(0, self.babblerShieldRemaining - amount)

            local perBabbler = self.babblerShieldPerBabbler
            local toDestroy = math.floor((self.numBabblers * perBabbler - self.babblerShieldRemaining) / perBabbler)
            self:DestroyNumClingedBabbler(Clamp(toDestroy, 0, self.numBabblers))

            if HitSound_IsEnabledForWeapon( weapon ) then
                -- Damage message will be sent at the end of OnProcessMove by the HitSound system
                HitSound_RecordHit( attacker, self, amount, hitPoint, 0, weapon )
            else
                SendDamageMessage( attacker, self:GetId(), amount, hitPoint, 0, weapon )
            end

            if self.OnTakeDamage then
                self:OnTakeDamage(amount, attacker, doer, hitPoint, nil, damageType, false)
            end
        end

        damageTable.damage = damage - amount
    end
end

local kBabblerShieldIgnoreDamageTypes = {
    [kDamageType.NerveGas] = true,
    [kDamageType.Corrode] = true,
    [kDamageType.ArmorOnly] = true,
    [kDamageType.StructuresOnly] = true,
    [kDamageType.Splash] = true
}
function BabblerClingMixin:GetApplyBabblerShield(damageType)
    return self:GetHasBabblerShield() and not kBabblerShieldIgnoreDamageTypes[damageType]
end

function BabblerClingMixin:GetHasBabblerShield()
    return self.numBabblers > 0
end

function BabblerClingMixin:GetBabblerShieldAmount()
    return self.babblerShieldRemaining
end

function BabblerClingMixin:GetMaxBabblerShieldAmount()
    return self.babblerShieldMaxAmount
end

function BabblerClingMixin:GetCanBeUsed(entity, useSuccessTable)

    local success = true

    if not GetAreFriends(self, entity) or not HasMixin(self, "BabblerCling") or not HasMixin(entity, "BabblerCling") then
        success = false
    end

    if success and not self:GetCanAttachBabbler() then
        success = false
    end

    if success and self:GetNumFreeDonationSpots() <= 0 then
        success = false
    end

    if success and (not entity.GetNumClingedBabblers or entity:GetNumClingedBabblers() == 0) then
        success = false
    end

    useSuccessTable.useSuccess = success
    
end

function BabblerClingMixin:OnUse(player, elapsedTime, useSuccessTable)
    if Server then

        -- See GetNumFreeDonationSpots: bounds by free attach points, the owner cap, and
        -- babblers already en route here, so this loop can't over-commit past what self can
        -- really end up holding once everything arrives.
        local freeSpots = self:GetNumFreeDonationSpots()

        if freeSpots <= 0 then
            return
        end

        for _, babbler in ipairs(player:GetClingedBabblers()) do

            if freeSpots <= 0 then
                break
            end

            if babbler:GetIsAlive() then

                self:TriggerEffects(math.random() < 0.5 and "babbler_wag_begin" or "babbler_jump") 
                babbler:OrderCling(self)
                freeSpots = freeSpots - 1

            end
        end
    end
end

if Server then

    function BabblerClingMixin:AttachBabbler(babbler, disablePoints)

        if not babbler or not babbler:GetIsAlive() then return false end
        if not self:GetIsAlive() or not self:GetCanAttachBabbler() then return false end

        local babblerId = babbler:GetId()

        if self.attachedBabblers[babblerId] then return false end

        local previousOwner = babbler:GetOwner()

        -- A donation (attaching a babbler self doesn't already own) must also respect the
        -- owner's overall babbler cap - cling attach points alone aren't enough, since a
        -- BabblerOwner can have babblers roaming free (not clinged) that still count against
        -- GetMaxBabblers(). Skip this when self already owns the babbler (e.g. it's one of
        -- self's own hatchlings walking up to cling) since that babbler was already counted
        -- against the cap the moment it was created/assigned to self.
        if previousOwner ~= self and HasMixin(self, "BabblerOwner") and self:GetBabblerCount() >= self:GetMaxBabblers() then
            return false
        end

        local freeAttachPoint = #self.freeAttachPoints > 0 and table.remove(self.freeAttachPoints)
        if freeAttachPoint then

            self.attachedBabblers[babblerId] = freeAttachPoint
            self.numBabblers = self.numBabblers + 1
            self.babblerShieldRemaining = self.babblerShieldRemaining + self.babblerShieldPerBabbler

            -- Do not count babblers you attach on yourself
            if previousOwner and previousOwner ~= self and not disablePoints
                    and previousOwner.AddContinuousScore then
                local amountGiven = 1
                previousOwner:AddContinuousScore("BabblerDonation", amountGiven, BabblerClingMixin.kAmountDonatedForPoints, BabblerClingMixin.kDonationScoreAdded)
            end

            babbler:SetParent(self)
            babbler:SetOwner(self)
            babbler:SetAttachPoint(freeAttachPoint)

            babbler.clinged = true
            babbler.attacking = false
            babbler.jumping = false
            babbler.targetId = self:GetId()
            babbler:DestroyHitbox()
            babbler:UpdateJumpPhysicsBody()

            return true

        end

        return false

    end

    function BabblerClingMixin:GetAttachedOrigin(babbler)
        local babblerId = babbler:GetId()
        local usedAttachPoint = self.attachedBabblers[babblerId]
        local origin = self:GetAttachPointOrigin(usedAttachPoint)
        return origin
    end

    function BabblerClingMixin:DetachBabbler(babbler)

        if not babbler then return end

        local babblerId = babbler:GetId()
        local usedAttachPoint = self.attachedBabblers[babblerId]

        self.attachedBabblers[babblerId] = nil
        babbler:SetParent(nil)

        if usedAttachPoint then
            table.insert(self.freeAttachPoints, usedAttachPoint)
            local origin = self:GetAttachPointOrigin(usedAttachPoint)
            if origin then
                babbler:SetOrigin(origin)
            end

            self.numBabblers = math.max(0, self.numBabblers - 1)
            self.babblerShieldRemaining = math.min(self.babblerShieldRemaining, self.numBabblers * self.babblerShieldPerBabbler)
        end

        babbler.clinged = false
        babbler:CreateHitBox(Coords.GetTranslation(babbler:GetOrigin()))
        babbler:UpdateJumpPhysicsBody()

    end

    function BabblerClingMixin:GetClingedBabblers()
        return GetChildEntities(self, "Babbler")
    end

    function BabblerClingMixin:DestroyNumClingedBabbler(num)
        if not num or num <= 0 then return end

        local babblers = GetChildEntities(self, "Babbler")
        num = math.min(#babblers, num)

        for i = 1, num do
            local babbler = babblers[i]
            babbler:Kill()
        end
    end

    function BabblerClingMixin:DestroyAllClingedBabbler()
        local babblers = GetChildEntities(self, "Babbler")

        for i = 1, #babblers do
            local babbler = babblers[i]
            babbler:Kill()
        end
    end

    function BabblerClingMixin:DetachAll()

        local babblers = GetChildEntities(self, "Babbler")
        for i = 1, #babblers do
            local babbler = babblers[i]
            babbler:Detach(true)
        end

        self.attachedBabblers = {}
        self.numBabblers = 0
        self.babblerShieldRemaining = 0

        self.freeAttachPoints = {}
        table.copy(kBabblerAttachPoints, self.freeAttachPoints)

    end

    function BabblerClingMixin:OnKill()
        self:DestroyAllClingedBabbler()
    end

    function BabblerClingMixin:Reset()
        self:DestroyAllClingedBabbler()
    end

    function BabblerClingMixin:TriggerCloak()
        local babblers = GetChildEntities(self, "Babbler")
        for i = 1, #babblers do
            local babbler = babblers[i]
            babbler:TriggerCloak()
        end
    end

    function BabblerClingMixin:TriggerUncloak()
        local babblers = GetChildEntities(self, "Babbler")
        for i = 1, #babblers do
            local babbler = babblers[i]
            babbler:TriggerUncloak()
        end
    end

    function BabblerClingMixin:GetFreeBabblerAttachPointOrigin()

        local freeAttachPoint = #self.freeAttachPoints > 0 and self.freeAttachPoints[1]
        if freeAttachPoint then
            return self:GetAttachPointOrigin(freeAttachPoint)
        end

    end

end
