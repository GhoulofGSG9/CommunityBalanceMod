-- ======= Copyright (c) 2013, Unknown Worlds Entertainment, Inc. All rights reserved. ==========
--
-- lua\GUIRailgun.lua
--
-- Created by: Brian Cronin (brianc@unknownworlds.com)
--
-- Displays the charge amount for the Exo's Railgun.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/GUIDial.lua")

local kTexture = "models/marine/exosuit/exosuit_view_panel_rail2.dds"

local kWarnTime = 0.75
local kChargingColor = Color(1, 1, 1, 1)
local kReadyColor = Color(0.25, 1, 1, 1)
local kWarnColor = Color(1, 0, 0, 1)

local chargeCircle
local shootSquares = { }
local cooldownSquares = { }
local time = 0

-- Set through SetGlobal by Railgun:OnUpdateRender when it creates this view;
-- the vanilla values are the fallback.
refireTime = refireTime or 1.4
chargeTime = chargeTime or 2
forceShootTime = forceShootTime or 2.5

function UpdateCharge(dt, chargeHeld, timeSinceLastShot)

    PROFILE("GUIRailgun:UpdateCharge")
    
    local chargeAmount = math.min(1, chargeHeld / chargeTime)
    local color = kChargingColor
    if chargeAmount >= 1 then

        if chargeHeld >= forceShootTime - kWarnTime then

            local pulseAmt = (1 + math.cos(time * 20)) * 0.25
            kWarnColor.g = pulseAmt
            kWarnColor.b = pulseAmt
            color = kWarnColor

        else
            color = kReadyColor
        end

    end
    chargeCircle:GetLeftSide():SetColor(color)
    chargeCircle:GetRightSide():SetColor(color)
    
    for s = 1, #cooldownSquares do
        cooldownSquares[s]:SetIsVisible(timeSinceLastShot < (s * refireTime / 4))
    end
    
    chargeCircle:SetPercentage(chargeAmount)
    chargeCircle:Update(dt)
    
    time = time + dt
    
end

local kWidth = 246
local kHeight = 256
local kTexWidth = 450
local kTexHeight = 452
function Initialize()

    GUI.SetSize(kWidth, kHeight)
    
    local chargeCircleSettings = { }
    chargeCircleSettings.BackgroundWidth = kWidth
    chargeCircleSettings.BackgroundHeight = kHeight
    chargeCircleSettings.BackgroundAnchorX = GUIItem.Left
    chargeCircleSettings.BackgroundAnchorY = GUIItem.Bottom
    chargeCircleSettings.BackgroundOffset = Vector(0, 0, 0)
    chargeCircleSettings.BackgroundTextureName = kTexture
    chargeCircleSettings.BackgroundTextureX1 = 0
    chargeCircleSettings.BackgroundTextureY1 = 0
    chargeCircleSettings.BackgroundTextureX2 = kTexWidth
    chargeCircleSettings.BackgroundTextureY2 = kTexHeight
    chargeCircleSettings.ForegroundTextureName = kTexture
    chargeCircleSettings.ForegroundTextureWidth = kTexWidth
    chargeCircleSettings.ForegroundTextureHeight = kTexHeight
    chargeCircleSettings.ForegroundTextureX1 = kTexWidth
    chargeCircleSettings.ForegroundTextureY1 = 0
    chargeCircleSettings.ForegroundTextureX2 = kTexWidth * 2
    chargeCircleSettings.ForegroundTextureY2 = kTexHeight
    chargeCircleSettings.InheritParentAlpha = true
    chargeCircle = GUIDial()
    chargeCircle:Initialize(chargeCircleSettings)
    chargeCircle:GetBackground():SetIsVisible(true)
    
    local x = 80
    for s = 1, 4 do
    
        table.insert(shootSquares, GUIManager:CreateGraphicItem())
        table.insert(cooldownSquares, GUIManager:CreateGraphicItem())
        
        shootSquares[s]:SetSize(Vector(20, 48, 0))
        cooldownSquares[s]:SetSize(Vector(20, 48, 0))
        shootSquares[s]:SetTexturePixelCoordinates(900, 0, 936, 87)
        cooldownSquares[s]:SetTexturePixelCoordinates(900, 89, 936, 176)
        shootSquares[s]:SetPosition(Vector(x, 100, 0))
        cooldownSquares[s]:SetPosition(Vector(x, 100, 0))
        x = x + 22
        shootSquares[s]:SetTexture(kTexture)
        cooldownSquares[s]:SetTexture(kTexture)
        
        cooldownSquares[s]:SetIsVisible(false)
        
    end
    
end

Initialize()