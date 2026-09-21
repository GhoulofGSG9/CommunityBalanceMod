-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua/GUIExoThruster.lua
--
-- Created by: Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

class 'GUIExoThruster' (GUIScript)

local kIconTexture = "ui/buildmenu.dds"
local kNotReadyColor = Color(1, 0, 0, 1)
local kNotAvailableColor = Color(0.5, 0.5, 0.5, 1)
local kReadyColor = kIconColors[kMarineTeamType]
local kActiveColor = Color(0, 1, 0, 1)

local kThrustersTechId = kTechId.Jetpack

local kBackgroundOffset
local kBackgroundPadding
local kBackgroundColor = Color(0.8, 0.9, 1, 0.1)

local kPadding
local kPadWidth
local kPadHeight
local kPadActiveColor = Color(0.8, 0.9, 1, 0.8)
local kPadInactiveColor = Color(0.0, 0.0, 0.1, 0.4)
local kNumPads = 12

-- Size of the fuel bar (backdrop + pads). The whole HUD group is laid out
-- relative to this, whether the bar itself is shown or not.
local kBarSize

-- Thruster icon cluster, drawn beside the fuel bar when Thrusters are equipped.
local kModuleIconSize
local kModuleClusterGap
local kModuleTextOffset

local kLabelColor = Color(0.8, 0.8, 1, 0.8)

local function UpdateItemsGUIScale(self)

    kBackgroundOffset = GUIScale(Vector(0, -100, 0))
    kBackgroundPadding = GUIScale(10)
    kPadding = math.max(1, math.round(GUIScale(3)))
    kPadWidth = math.round(GUIScale(13))
    kPadHeight = GUIScale(9)

    kBarSize = Vector(kNumPads * kPadWidth + (kNumPads - 1) * kPadding + 2 * kBackgroundPadding,
                      2 * kBackgroundPadding + kPadHeight, 0)

    kModuleIconSize = GUIScale(Vector(56, 56, 0))
    kModuleClusterGap = GUIScale(16)
    kModuleTextOffset = GUIScale(12)

end

function GUIExoThruster:OnResolutionChanged(oldX, oldY, newX, newY)
    self:Uninitialize()
    self:Initialize()
end

local function CreateModuleIcon(self, techId)

    local icon = GetGUIManager():CreateGraphicItem()
    icon:SetTexture(kIconTexture)
    icon:SetAnchor(GUIItem.Left, GUIItem.Center)
    icon:SetSize(kModuleIconSize)
    icon:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(techId, true)))
    icon:SetIsVisible(false)
    self.moduleFrame:AddChild(icon)
    table.insert(self.hideableItems, icon)

    local text = GetGUIManager():CreateTextItem()
    text:SetFontName(Fonts.kAgencyFB_Small)
    text:SetAnchor(GUIItem.Left, GUIItem.Center)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Center)
    text:SetColor(kLabelColor)
    text:SetIsVisible(false)
    self.moduleFrame:AddChild(text)
    table.insert(self.hideableItems, text)

    return icon, text

end

function GUIExoThruster:Initialize()

    UpdateItemsGUIScale(self)

    self.hideableItems = {}
    self.thrusterFraction = 1
    self.visible = true

    -- Invisible root, sized and placed like the old bar backdrop so that every
    -- child keeps its position whether or not the fuel bar is shown.
    self.background = GetGUIManager():CreateGraphicItem()
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    self.background:SetSize(kBarSize)
    self.background:SetPosition(-kBarSize * 0.5 + kBackgroundOffset)
    self.background:SetColor(Color(0, 0, 0, 0))

    -- Fuel bar group: backdrop and pads together, hidden as a unit when the
    -- Thrusters core is not equipped.
    self.barBackground = GetGUIManager():CreateGraphicItem()
    self.barBackground:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.barBackground:SetPosition(Vector(0, 0, 0))
    self.barBackground:SetSize(kBarSize)
    self.barBackground:SetColor(kBackgroundColor)
    self.background:AddChild(self.barBackground)
    table.insert(self.hideableItems, self.barBackground)

    self.pads = {}
    for i = 1, kNumPads do

        local pos = Vector((i - 1) * (kPadding + kPadWidth) + kBackgroundPadding, -kPadHeight * 0.5, 0)
        local pad = GetGUIManager():CreateGraphicItem()
        pad:SetPosition(pos)
        pad:SetIsVisible(true)
        pad:SetColor(kPadActiveColor)
        pad:SetAnchor(GUIItem.Left, GUIItem.Center)
        pad:SetSize(Vector(kPadWidth, kPadHeight, 0))

        self.barBackground:AddChild(pad)
        table.insert(self.pads, pad)

    end

    -- Module icons live in their own anchor so they stay visible and correctly
    -- placed when the fuel bar is gone.
    self.moduleFrame = GetGUIManager():CreateGraphicItem()
    self.moduleFrame:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.moduleFrame:SetSize(Vector(0, 0, 0))
    self.moduleFrame:SetColor(Color(0, 0, 0, 0))
    self.background:AddChild(self.moduleFrame)
    table.insert(self.hideableItems, self.moduleFrame)

    self.thrustersIcon, self.thrustersIconText = CreateModuleIcon(self, kThrustersTechId)

    self.thrustersIconText:SetText(BindingsUI_GetInputValue("MovementModifier"))

    self:UpdateModuleLayout()

end

function GUIExoThruster:Uninitialize()

    if self.background then

        GUI.DestroyItem(self.background)
        self.background = nil

    end

    self.barBackground = nil
    self.moduleFrame = nil
    self.pads = nil
    self.hideableItems = nil

end

function GUIExoThruster:SetIsVisible(state)

    self.visible = state

    self.background:SetIsVisible(state)

    if state then

        self:UpdateModuleLayout()

    else

        for i = 1, #self.hideableItems do
            self.hideableItems[i]:SetIsVisible(false)
        end

    end

end

function GUIExoThruster:GetIsVisible()
    return self.visible
end

-- The fuel bar and the thruster icon beside it only exist when the Thrusters core is
-- equipped. The eject hint and the Support Ability hint are both key badges, drawn by
-- GUIExoEject in the lower left corner.
function GUIExoThruster:UpdateModuleLayout()

    local hasThrusters = PlayerUI_GetHasThrusters()

    self.barBackground:SetIsVisible(hasThrusters)
    self.moduleFrame:SetIsVisible(hasThrusters)
    self.thrustersIcon:SetIsVisible(hasThrusters)
    self.thrustersIconText:SetIsVisible(hasThrusters)

    if not hasThrusters then
        return
    end

    self.moduleFrame:SetPosition(Vector(-(kModuleIconSize.x + kModuleClusterGap), 0, 0))

    self.thrustersIcon:SetPosition(Vector(0, -kModuleIconSize.y * 0.5, 0))
    self.thrustersIconText:SetPosition(Vector(kModuleIconSize.x * 0.5, kModuleIconSize.y * 0.5 + kModuleTextOffset, 0))

end

function GUIExoThruster:UpdateExoThrusters(thrustersAvailable, thrustersReady, thrustersActive)

    if thrustersActive then
        self.thrustersIcon:SetColor(kActiveColor)
    elseif thrustersReady then
        self.thrustersIcon:SetColor(kReadyColor)
    elseif thrustersAvailable then
        self.thrustersIcon:SetColor(kNotReadyColor)
    else
        self.thrustersIcon:SetColor(kNotAvailableColor)
    end

end

function GUIExoThruster:Update(deltaTime)

    PROFILE("GUIExoThruster:Update")

    if not self.visible then
        return
    end

    local player = Client.GetLocalPlayer()
    local desiredThrusterFraction = (player and player.GetFuel) and player:GetFuel() or 0

    self.thrusterFraction = Slerp(self.thrusterFraction, desiredThrusterFraction, deltaTime * 1.7)

    for i = 1, kNumPads do

        local padFraction = i / kNumPads
        self.pads[i]:SetColor(padFraction <= self.thrusterFraction and kPadActiveColor or kPadInactiveColor)

    end

    local thrustersAvailable, thrustersReady, thrustersActive = PlayerUI_GetExoThrustersAvailable()

    if thrustersAvailable ~= self.lastThrustersAvailable or thrustersReady ~= self.lastThrustersReady or self.lastThrustersActive ~= thrustersActive then

        self:UpdateExoThrusters(thrustersAvailable, thrustersReady, thrustersActive)
        self.lastThrustersAvailable = thrustersAvailable
        self.lastThrustersReady = thrustersReady
        self.lastThrustersActive = thrustersActive

    end

    local hasThrusters = PlayerUI_GetHasThrusters()
    if hasThrusters ~= self.lastHasThrusters then

        self:UpdateModuleLayout()
        self.lastHasThrusters = hasThrusters

    end

end
