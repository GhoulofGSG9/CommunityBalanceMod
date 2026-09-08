--======= Copyright (c) 2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIExoEject.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

local kButtonPos
local kTextOffset

-- The Support Ability hint is the same key badge + caption, sitting to the right of the
-- eject hint on the same baseline. Each caption is centred under its own badge, so the
-- badges have to stand far enough apart that the two widest captions cannot meet.
-- 260 unscaled units clears the English worst case ("Eject - deploying" beside
-- "Adrenaline Field  120 s") and is the floor; Initialize() widens it when the locale in
-- use needs more, measured from the real strings (see GetWidestCaptionWidth).
local kAbilityButtonOffset
local kCaptionGap

local kFontName = Fonts.kAgencyFB_Small

-- Both badges are dimmed while what they trigger is unavailable: the Support Ability
-- while it recharges, the eject while the exo may not eject. Matches the way unavailable
-- hints are drawn elsewhere in the marine HUD.
local kHintReadyColor = Color(1, 1, 1, 1)
local kHintUnavailableColor = Color(0.5, 0.5, 0.5, 1)

class 'GUIExoEject' (GUIScript)

-- Built lazily so this file does not depend on kExoModuleTypes existing at load time.
-- Module types without an activated ability (None included) are simply absent.
local gAbilityLocaleKeys

local function GetSupportAbilityLocaleKey(moduleType)

    if not gAbilityLocaleKeys then

        gAbilityLocaleKeys =
        {
            [kExoModuleTypes.NanoShield] = "EXO_ABILITY_NANOSHIELD_FIELD",
            [kExoModuleTypes.CatPack]    = "EXO_ABILITY_ADRENALINE_FIELD",
            [kExoModuleTypes.NanoRepair] = "EXO_ABILITY_REGEN_FIELD",
        }

    end

    return gAbilityLocaleKeys[moduleType]

end

local kEjectReasonKeys =
{
    "EXO_EJECT_REASON_COMBAT",
    "EXO_EJECT_REASON_AIRBORNE",
    "EXO_EJECT_REASON_DEPLOYING",
    "EXO_EJECT_REASON_BASE",
}

-- Every caption the eject badge can ever show, so the layout is sized from the longest
-- one the active locale actually has instead of from a guess about the English strings.
local function GetEjectCaptions()

    local captions =
    {
        Locale.ResolveString("EXO_EJECT_HOLD_HINT"),
        string.format(Locale.ResolveString("EXO_EJECT_HOLD_PROGRESS"), 100),
    }

    local blockedFormat = Locale.ResolveString("EXO_EJECT_BLOCKED_FORMAT")
    for i = 1, #kEjectReasonKeys do
        table.insert(captions, string.format(blockedFormat, Locale.ResolveString(kEjectReasonKeys[i])))
    end

    return captions

end

-- Same for the Support Ability badge: every module name, ready and on cooldown. The
-- longest cooldown in Balance.lua is 120 seconds, so three digits is the worst case.
local function GetAbilityCaptions()

    -- Force the lazy table above to exist before walking it.
    GetSupportAbilityLocaleKey(kExoModuleTypes.None)

    local cooldownFormat = Locale.ResolveString("EXO_ABILITY_COOLDOWN_FORMAT")
    local captions = {}

    for _, localeKey in pairs(gAbilityLocaleKeys) do

        local name = Locale.ResolveString(localeKey)
        table.insert(captions, name)
        table.insert(captions, string.format(cooldownFormat, name, 120))

    end

    return captions

end

-- On screen width of the widest of the given captions, drawn with this text item's own
-- font and scale. GUIMakeFontScale() may have replaced both, so ask the item, not
-- GetScaledVector().
local function GetWidestCaptionWidth(textItem, captions)

    local widest = 0
    for i = 1, #captions do
        widest = math.max(widest, textItem:GetTextWidth(captions[i]))
    end

    return widest * textItem:GetScale().x

end

local function UpdateItemsGUIScale(self)

    local player = Client.GetLocalPlayer()
    if player and player:isa("Exo") and Client.kHideViewModel == true then
        kButtonPos = GUIScale(Vector(490, -100, 0))
    else
        kButtonPos = GUIScale(Vector(180, -120, 0))
    end

    kTextOffset = GUIScale(Vector(0, 20, 0))
    kAbilityButtonOffset = GUIScale(Vector(260, 0, 0))
    kCaptionGap = GUIScale(16)
end

function GUIExoEject:OnResolutionChanged(oldX, oldY, newX, newY)
    UpdateItemsGUIScale(self)
    
    self:Uninitialize()
    self:Initialize()
end

function GUIExoEject:Initialize()

    UpdateItemsGUIScale(self)
    
    self.button, self.buttonKeyText = GUICreateButtonIcon("Drop")
    self.button:SetAnchor(GUIItem.Left, GUIItem.Bottom)
    self.button:SetPosition(kButtonPos)
    self.button:SetScale(GetScaledVector())

    self.text = GetGUIManager():CreateTextItem()
    self.text:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    self.text:SetTextAlignmentX(GUIItem.Align_Center)
    self.text:SetTextAlignmentY(GUIItem.Align_Center)
    self.text:SetPosition(kTextOffset)
    self.text:SetScale(GetScaledVector())
    self.text:SetFontName(kFontName)
    GUIMakeFontScale(self.text)
    self.text:SetColor(kMarineFontColor)

    self.button:AddChild(self.text)
    self.button:SetIsVisible(false)

    -- Support Ability hint, same badge and caption, to the right of the eject hint on
    -- the same baseline. Placed once both captions exist, see below.
    self.abilityButton, self.abilityButtonText = GUICreateButtonIcon("Reload")
    self.abilityButton:SetAnchor(GUIItem.Left, GUIItem.Bottom)
    self.abilityButton:SetScale(GetScaledVector())

    self.abilityText = GetGUIManager():CreateTextItem()
    self.abilityText:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    self.abilityText:SetTextAlignmentX(GUIItem.Align_Center)
    self.abilityText:SetTextAlignmentY(GUIItem.Align_Center)
    self.abilityText:SetPosition(kTextOffset)
    self.abilityText:SetScale(GetScaledVector())
    self.abilityText:SetFontName(kFontName)
    GUIMakeFontScale(self.abilityText)
    self.abilityText:SetColor(kMarineFontColor)

    self.abilityButton:AddChild(self.abilityText)
    self.abilityButton:SetIsVisible(false)

    -- Both badges are the same width and both captions are centred on their own badge,
    -- so the left edges have to be half of each widest caption apart, plus a gap.
    local captionSpacing = (GetWidestCaptionWidth(self.text, GetEjectCaptions()) +
            GetWidestCaptionWidth(self.abilityText, GetAbilityCaptions())) * 0.5 + kCaptionGap

    self.abilityButton:SetPosition(kButtonPos + Vector(math.max(kAbilityButtonOffset.x, captionSpacing), 0, 0))

    self.lastAbilityModuleType = nil
    self.lastAbilitySecondsLeft = nil

    -- false, not nil: nil is a valid "eject is available" reason value.
    self.lastEjectReason = false
    self.lastEjectPercent = nil

    self.visible = true

end

function GUIExoEject:SetIsVisible(state)
    
    self.visible = state
    self:Update(0)
    
end

function GUIExoEject:GetIsVisible()
    
    return self.visible
    
end


function GUIExoEject:Uninitialize()

    if self.button then
        GUI.DestroyItem(self.button)
        self.button = nil
    end

    if self.abilityButton then
        GUI.DestroyItem(self.abilityButton)
        self.abilityButton = nil
    end

    self.text = nil
    self.buttonKeyText = nil
    self.abilityText = nil
    self.abilityButtonText = nil

end

function GUIExoEject:Update(deltaTime)
                  
    PROFILE("GUIExoEject:Update")

    if not self.button then
        return
    end

    local player = Client.GetLocalPlayer()
    local hudVisible = player ~= nil and Client.GetIsControllingPlayer() and not MainMenu_GetIsOpened()
    local inExo = hudVisible and player:isa("Exo") and player:GetIsPlaying()

    self.button:SetIsVisible(inExo and self.visible)

    -- Eject: the badge is lit while the exo may eject and carries the hold progress in
    -- its caption while the drop key is held. It is dimmed with a one word reason while
    -- the eject is refused, the same way the Support Ability badge is dimmed on cooldown.
    if inExo then

        local reason = PlayerUI_GetExoEjectBlockedReason()
        local percent = reason and 0 or math.floor(PlayerUI_GetExoEjectHoldFraction() * 100 + 0.5)

        if reason ~= self.lastEjectReason or percent ~= self.lastEjectPercent then

            local fontColor = reason and kHintUnavailableColor or kMarineFontColor

            self.button:SetColor(reason and kHintUnavailableColor or kHintReadyColor)
            self.buttonKeyText:SetColor(fontColor)
            self.text:SetColor(fontColor)

            local caption
            if reason then
                caption = string.format(Locale.ResolveString("EXO_EJECT_BLOCKED_FORMAT"), Locale.ResolveString(reason))
            elseif percent > 0 then
                caption = string.format(Locale.ResolveString("EXO_EJECT_HOLD_PROGRESS"), percent)
            else
                caption = Locale.ResolveString("EXO_EJECT_HOLD_HINT")
            end

            self.text:SetText(caption)

            self.lastEjectReason = reason
            self.lastEjectPercent = percent

        end

    end

    -- Support Ability: name of the equipped module, plus the seconds left while it is
    -- recharging. Nothing is drawn when no ability module is equipped.
    local moduleType, secondsUntilReady = PlayerUI_GetExoSupportAbility()
    local localeKey = GetSupportAbilityLocaleKey(moduleType)
    local secondsLeft = math.ceil(secondsUntilReady or 0)

    self.abilityButton:SetIsVisible(localeKey ~= nil and hudVisible and self.visible)

    if localeKey and (moduleType ~= self.lastAbilityModuleType or secondsLeft ~= self.lastAbilitySecondsLeft) then

        local ready = secondsLeft <= 0
        local fontColor = ready and kMarineFontColor or kHintUnavailableColor

        self.abilityButton:SetColor(ready and kHintReadyColor or kHintUnavailableColor)
        self.abilityButtonText:SetColor(fontColor)
        self.abilityText:SetColor(fontColor)

        local name = Locale.ResolveString(localeKey)
        self.abilityText:SetText(ready and name or
                string.format(Locale.ResolveString("EXO_ABILITY_COOLDOWN_FORMAT"), name, secondsLeft))

        self.lastAbilityModuleType = moduleType
        self.lastAbilitySecondsLeft = secondsLeft

    end

end