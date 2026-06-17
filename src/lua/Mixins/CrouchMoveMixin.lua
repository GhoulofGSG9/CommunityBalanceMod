-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Mixins\CrouchMoveMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

CrouchMoveMixin = CreateMixin( CrouchMoveMixin )
CrouchMoveMixin.type = "CrouchMove"

CrouchMoveMixin.networkVars =
{
    crouching = "compensated boolean",
    timeOfCrouchChange = "compensated time",
    crouchScalarAtTime = "compensated float"
}

CrouchMoveMixin.expectedCallbacks =
{
    GetCrouchSpeedScalar = ""
}

CrouchMoveMixin.optionalCallbacks =
{
    GetCrouchCameraAnimationAllowed = "Return false from this callback to prevent camera animation from crouching.",
	GetCanCrouchOverride = "Return false from this is crouch movement should not be allowed"
}

local kCrouchAnimationTime = 0.25

function CrouchMoveMixin:__initmixin()
    
    PROFILE("CrouchMoveMixin:__initmixin")
    
    self.crouching = false
    self.timeOfCrouchChange = 0

end

function CrouchMoveMixin:GetExtentsOverride()

    local extents = self:GetMaxExtents()
    if self.crouching then
        extents.y = extents.y * (1 - self:GetExtentsCrouchShrinkAmount())
    end
    return extents

end

local kCrouchCameraAnimationAllowedTable = { allowed = true }
function CrouchMoveMixin:OnUpdateCamera(deltaTime)

    if self.GetCrouchCameraAnimationAllowed then
    
        kCrouchCameraAnimationAllowedTable.allowed = true
        self:GetCrouchCameraAnimationAllowed(kCrouchCameraAnimationAllowedTable)
        if not kCrouchCameraAnimationAllowedTable.allowed then
            return
        end
        
    end
    
    -- Update view offset from crouching
    local offset = -self:GetCrouchShrinkAmount() * self:GetCrouchAmount()
    self:SetCameraYOffset(offset)
    
end

function CrouchMoveMixin:GetCrouching()
    return self.crouching
end

local kAirCrouchTransistionTime = 0.25

local function GetDeltaTimeNetvar(startTime, rateOfChange, initialValue)
    local deltaTime = Shared.GetTime() - startTime
    return initialValue + rateOfChange * deltaTime
end

-- this is *not* the amount crouched, it's how far in the animation we are
function CrouchMoveMixin:GetCrouchScalar()
    local rateOfChange = (self.crouching and 1 or -1) / kCrouchAnimationTime
    return Clamp(GetDeltaTimeNetvar(self.timeOfCrouchChange, rateOfChange, self.crouchScalarAtTime), 0, 1)
end

--
-- Returns a value between 0 and 1 indicating how much the player has crouched
-- visually (actual crouching is binary).
--
function CrouchMoveMixin:GetCrouchAmount()

    -- Get 0-1 scalar of time since crouch changed
    local crouchScalar = 0
    if self.GetCanCrouchOverride then
        if not self:GetCanCrouchOverride() then
            return 0
        end
    end

    if self.timeOfCrouchChange > 0 then

        -- this is needed because the crouch amount does not follow a linear rate of change
        local delta = Shared.GetTime() - self.timeOfCrouchChange
        if delta >= kCrouchAnimationTime then
            return self.crouching and 1 or 0
        end

        local rateOfChange = (self.crouching and 1 or -1) / kCrouchAnimationTime

        -- todo: remove clamp after making sure it's not required
        crouchScalar = Clamp(math.sin(math.pi * 0.5 * GetDeltaTimeNetvar(self.timeOfCrouchChange, rateOfChange, self.crouchScalarAtTime)), 0, 1)

    end

    return crouchScalar

end

function CrouchMoveMixin:GetCrouchAirFraction()
    local transistionTime = kAirCrouchTransistionTime
    local groundFraction = Clamp((Shared.GetTime() - self.timeGroundTouched) / transistionTime, 0, 1)

    return groundFraction
end

function CrouchMoveMixin:SetCrouching(isCrouching, force)

    PROFILE("CrouchMoveMixin:SetCrouching")

    -- Setting crouching with force will lock it unless it get released again with force
    if self.crouchForced and not force then return end
    self.crouchForced = force and isCrouching

    if isCrouching == self.crouching then return end

    if self.GetCanCrouchOverride then
        if not self:GetCanCrouchOverride() then
            return
        end
    end

    if not isCrouching then
        local scalar = self:GetCrouchScalar()

        -- Check if there is room for us to stand up.
        self.crouching = false
        self:UpdateControllerFromEntity()

        if self:GetIsColliding() then
            self.crouching = true
            self:UpdateControllerFromEntity()
        else
            self.crouchScalarAtTime = scalar
            self.timeOfCrouchChange = Shared.GetTime()
        end

    elseif self:GetCanCrouch() then
        self.crouchScalarAtTime = self:GetCrouchScalar()
        self.crouching = true
        self.timeOfCrouchChange = Shared.GetTime()
        self:UpdateControllerFromEntity()
    end
end

function CrouchMoveMixin:ModifyMaxSpeed(maxSpeedTable)

    if self:GetIsOnGround() then
        local crouchMod = 1 - self:GetCrouchAmount() * self:GetCrouchSpeedScalar()
        maxSpeedTable.maxSpeed = maxSpeedTable.maxSpeed * crouchMod
    end

end

function CrouchMoveMixin:HandleButtons(input)

    PROFILE("CrouchMoveMixin:HandleButtons")

    local crouchDesired = InputIsPressingCrouch(input)
    self:SetCrouching(crouchDesired)

end

function CrouchMoveMixin:OnAdjustModelCoords(modelCoords)
    if not self:GetIsOnGround() then
        modelCoords.origin = modelCoords.origin - Vector(0, self:GetExtentsCrouchShrinkAmount() * self:GetCrouchAirFraction() * self:GetCrouchAmount(),0)
    end

    return modelCoords
end
