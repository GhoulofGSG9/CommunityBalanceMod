--[[ ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. ==========

 lua\GUIFlamer.lua

 Displays the heat amount for the Exo's Flamer arm.

 The flamer arm borrows the railgun cockpit art (exosuit_rr / exosuit_rp / exosuit_pr /
 exosuit_cf), so this display has to fit the railgun screen quad, not the minigun one. That quad
 is roughly square and its material (exosuit_view_panel_rail2 / exosuit_view_panel2_rail2) samples
 "*exo_railgun_left" / "*exo_railgun_right" over the full 0..1 UV range. Drawing the minigun
 layout here (242x720, exosuit_view_panel_mini2.dds) stretched a 1:3 bar across a 1:1 screen.
 Layout, render target size and source art therefore match GUIRailgun.lua exactly - see
 ExoFlamer_Client.lua, which must create the GUIView at the same size.

 ========= For more information, visit us at http://www.unknownworlds.com =====================]]

Script.Load("lua/GUIDial.lua")

local kTexture = "models/marine/exosuit/exosuit_view_panel_rail2.dds"

-- Must match the Client.CreateGUIView() size used in ExoFlamer_Client.lua.
local kWidth = 246
local kHeight = 256
local kTexWidth = 450
local kTexHeight = 452

local heatCircle
local heatSquares = { }
local overheatSquares = { }

local animHeatAmount = 0
local animHeatDir = 1
local time = 0

function UpdateOverHeat(dt, heatAmount)

    PROFILE("GUIFlamer:UpdateOverHeat")

    heatAmount = math.max(0, math.min(1, heatAmount or 0))

    local alertColor = Color(1, 1, 1, 1)
    if heatAmount > 0.5 then

        animHeatAmount = animHeatAmount + ((animHeatDir * dt) * 10 * heatAmount)
        if animHeatAmount > 1 then

            animHeatAmount = 1
            animHeatDir = -1

        elseif animHeatAmount < 0 then

            animHeatAmount = 0
            animHeatDir = 1

        end
        alertColor = Color(1, animHeatAmount * (1 - ((heatAmount - 0.5) / 0.5)), 0, 1)

    end

    heatCircle:GetLeftSide():SetColor(alertColor)
    heatCircle:GetRightSide():SetColor(alertColor)

    for s = 1, #overheatSquares do
        overheatSquares[s]:SetIsVisible(heatAmount >= (s / #overheatSquares))
    end

    heatCircle:SetPercentage(heatAmount)
    heatCircle:Update(dt)

    time = time + dt

end

function Initialize()

    GUI.SetSize(kWidth, kHeight)

    local heatCircleSettings = { }
    heatCircleSettings.BackgroundWidth = kWidth
    heatCircleSettings.BackgroundHeight = kHeight
    heatCircleSettings.BackgroundAnchorX = GUIItem.Left
    heatCircleSettings.BackgroundAnchorY = GUIItem.Bottom
    heatCircleSettings.BackgroundOffset = Vector(0, 0, 0)
    heatCircleSettings.BackgroundTextureName = kTexture
    heatCircleSettings.BackgroundTextureX1 = 0
    heatCircleSettings.BackgroundTextureY1 = 0
    heatCircleSettings.BackgroundTextureX2 = kTexWidth
    heatCircleSettings.BackgroundTextureY2 = kTexHeight
    heatCircleSettings.ForegroundTextureName = kTexture
    heatCircleSettings.ForegroundTextureWidth = kTexWidth
    heatCircleSettings.ForegroundTextureHeight = kTexHeight
    heatCircleSettings.ForegroundTextureX1 = kTexWidth
    heatCircleSettings.ForegroundTextureY1 = 0
    heatCircleSettings.ForegroundTextureX2 = kTexWidth * 2
    heatCircleSettings.ForegroundTextureY2 = kTexHeight
    heatCircleSettings.InheritParentAlpha = true
    heatCircle = GUIDial()
    heatCircle:Initialize(heatCircleSettings)
    heatCircle:GetBackground():SetIsVisible(true)
    heatCircle:SetPercentage(0)
    heatCircle:Update(0)

    local x = 80
    for s = 1, 4 do

        table.insert(heatSquares, GUIManager:CreateGraphicItem())
        table.insert(overheatSquares, GUIManager:CreateGraphicItem())

        heatSquares[s]:SetSize(Vector(20, 48, 0))
        overheatSquares[s]:SetSize(Vector(20, 48, 0))
        heatSquares[s]:SetTexturePixelCoordinates(900, 0, 936, 87)
        overheatSquares[s]:SetTexturePixelCoordinates(900, 89, 936, 176)
        heatSquares[s]:SetPosition(Vector(x, 100, 0))
        overheatSquares[s]:SetPosition(Vector(x, 100, 0))
        x = x + 22
        heatSquares[s]:SetTexture(kTexture)
        overheatSquares[s]:SetTexture(kTexture)

        overheatSquares[s]:SetIsVisible(false)

    end

end

Initialize()
