-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIMarineBuyMenu.lua
--
-- Created by: Andreas Urwalek (andi@unknownworlds.com)
--
-- Manages the marine buy/purchase menu.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/GUIAnimatedScript.lua")

class 'GUIMarineBuyMenu' (GUIAnimatedScript)

GUIMarineBuyMenu.kMockupSize = Vector(2880, 1620, 0)

local kArmoryBackgroundTexture         = PrecacheAsset("ui/buymenu_marine/armory_background.dds")
local kPrototypeLabBackgroundTexture   = PrecacheAsset("ui/buymenu_marine/prototypelab_background.dds")

local kButtonGroupFrame_Unlabeled_x2   = PrecacheAsset("ui/buymenu_marine/button_group_frame_unlabeled_x2.dds")
local kButtonGroupFrame_Labeled_x3     = PrecacheAsset("ui/buymenu_marine/button_group_frame_labeled_x3.dds")
local kButtonGroupFrame_Labeled_x4     = PrecacheAsset("ui/buymenu_marine/button_group_frame_labeled_x4.dds")
local kButtonGroupFrame_Labeled_x5     = PrecacheAsset("ui/buymenu_marine/button_group_frame_labeled_x5.dds")

local kButtonsTexture                  = PrecacheAsset("ui/buymenu_marine/buttons.dds")
local kButtonErrorFrame                = PrecacheAsset("ui/buymenu_marine/button_errorframe.dds")
local kButtonHighlightTexture          = PrecacheAsset("ui/buymenu_marine/button_highlight.dds")

local kResourceIcon_Lit                = PrecacheAsset("ui/buymenu_marine/resource_icon_lit.dds")
local kResourceIcon_Unlit              = PrecacheAsset("ui/buymenu_marine/resource_icon_unlit.dds")

local kWeaponButtonResIconTexture_Lit  = PrecacheAsset("ui/buymenu_marine/resource_lit.dds")
local kWeaponButtonTeamIconTexture     = PrecacheAsset("ui/buymenu_marine/team_icon.dds")

-- Right side "details" section textures.
local kResourceBigTexture_Unlit        = PrecacheAsset("ui/buymenu_marine/resourcebig_unlit.dds")
local kResourceBigTexture_Lit          = PrecacheAsset("ui/buymenu_marine/resourcebig_lit.dds")
local kArmoryBigPicturesTexture        = PrecacheAsset("ui/buymenu_marine/armory_bigicons.dds")
local kPrototypeLabBigPicturesTexture  = PrecacheAsset("ui/buymenu_marine/prototypelab_bigicons.dds")
local kSpecialsTexture                 = PrecacheAsset("ui/buymenu_marine/special_frames.dds")
local kVSBarTexture                    = PrecacheAsset("ui/buymenu_marine/stat_bar.dds")

GUIMarineBuyMenu.kCostTextColor_Free             = Color(97/255,  97/255, 97/255)
GUIMarineBuyMenu.kCostTextColor_HasEnoughMoney   = Color(1,       1,      1)
GUIMarineBuyMenu.kCostTextColor_NotEnoughMoney   = Color(174/255, 51/255, 51/255)

GUIMarineBuyMenu.kTeamTextColor_None             = Color(97/255,  97/255,  97/255)
GUIMarineBuyMenu.kTeamTextColor_HasPlayers       = Color(109/255, 158/255, 167/255)
GUIMarineBuyMenu.kSpecialTextContentColor        = Color(162/255, 195/255, 200/255)
GUIMarineBuyMenu.kSpecialTextContentColor_Debuff = Color(239/255, 94/255,  80/255)

GUIMarineBuyMenu.kErrorFrameTextPadding          = 10 -- X, both sides

-- Prototype lab layout anchors, shared by the vanilla item list and the modular exo panel.
-- The background art (prototypelab_background.dds, 1383x811) is chamfered at the top left,
-- so nothing may sit higher or further left than the item list already does.
local kPrototypeLabItemListPos = Vector(97, 149, 0)
local kPrototypeLabRightSidePos = Vector(580, 38, 0)

local kButtonShowState = enum({
    'Uninitialized',
    'NotHosted',
    'Occupied',
    'Equipped',
    'Unresearched',
    'InsufficientFunds',
    'Available',
    'Disabled', -- Tutorial should block 'Axe' purchasing, for example. Override 'GUIMarineBuyMenu:GetTechIDDisabled(techID)' for this.
})

local kButtonShowStateDefinitions =
{
    [kButtonShowState.Disabled] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_DISABLED",
        TextColor = Color(239/255, 94/255, 80/255)
    },

    [kButtonShowState.NotHosted] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_UNAVAILABLE",
        TextColor = Color(94/255, 116/255, 128/255)
    },

    [kButtonShowState.Occupied] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_OCCUPIED",
        TextColor = Color(94/255, 116/255, 128/255)
    },

    [kButtonShowState.Equipped] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_EQUIPPED",
        TextColor = Color(2/255, 230/255, 255/255)
    },

    [kButtonShowState.Unresearched] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_NOTRESEARCHED",
        TextColor = Color(94/255, 116/255, 128/255)
    },

    [kButtonShowState.InsufficientFunds] = {
        ShowError = true,
        Text = "BUYMENU_ERROR_INSUFFICIENTFUNDS",
        TextColor = Color(239/255, 94/255, 80/255)
    },

    [kButtonShowState.Available] = {
        ShowError = false,
    },
}

-- Table of unscaled button positions, for each of the weapon group frames.
local kWeaponGroupButtonPositions =
{

    [kButtonGroupFrame_Unlabeled_x2] =
    {
        Vector(4, 4, 0),
        Vector(4, 122, 0),
    },

    [kButtonGroupFrame_Labeled_x3] =
    {
        Vector(4, 20, 0),
        Vector(4, 140, 0),
        Vector(4, 258, 0),
    },

    [kButtonGroupFrame_Labeled_x4] =
    {
        Vector(4, 25, 0),
        Vector(4, 143, 0),
        Vector(4, 262, 0),
        Vector(4, 380, 0),
    },
	
	[kButtonGroupFrame_Labeled_x5] =
    {
        Vector(4, 25, 0),
        Vector(4, 143, 0),
        Vector(4, 262, 0),
        Vector(4, 380, 0),
		Vector(4, 498, 0),
    },

}

local kSpecial = enum(
{
    'Massive',
    'Electrify',
    'Burn'
})

local kSpecialDefinitions =
{
    [kSpecial.Massive] =
    {
        TextureCoordinates = { 0, 0, 717, 184 },
        Title = "BUYMENU_MASSIVE_TITLE",
        Specials =
        {
            "BUYMENU_MASSIVE_SPECIAL1",
            "BUYMENU_MASSIVE_SPECIAL2",
            "BUYMENU_MASSIVE_SPECIAL3",
            "BUYMENU_MASSIVE_SPECIAL4",
            "BUYMENU_MASSIVE_SPECIAL5",
        },
        SpecialsDebuffs = set
        {
            4, 5
        }
    },

    [kSpecial.Electrify] =
    {
        TextureCoordinates = { 0, 185, 717, 279 },
        Title = "BUYMENU_ELECTRIFY_TITLE",
        Specials =
        {
            "BUYMENU_ELECTRIFY_SPECIAL1",
        }
    },

    [kSpecial.Burn] =
    {
        TextureCoordinates = { 0, 370, 717, 464 },
        Title = "BUYMENU_BURN_TITLE",
        Specials =
        {
            "BUYMENU_BURN_SPECIAL1",
            "BUYMENU_BURN_SPECIAL2",
        }
    }
}

local kTechIdStats =
{
    [kTechId.Axe] =
    {
        LifeFormDamage = 0.1,
        StructureDamage = 0.7,
        Range = 0.1,
    },

    [kTechId.Welder] =
    {
        LifeFormDamage = 0.1,
        StructureDamage = 0.2,
        Range = 0.1,
    },

    [kTechId.Pistol] =
    {
        LifeFormDamage = 0.8,
        StructureDamage = 0.5,
        Range = 1,
    },

    [kTechId.Rifle] =
    {
        LifeFormDamage = 0.8,
        StructureDamage = 0.8,
        Range = 0.8,
    },

    [kTechId.Shotgun] =
    {
        LifeFormDamage = 1,
        StructureDamage = 0.8,
        Range = 0.4,
    },

    [kTechId.GrenadeLauncher] =
    {
        LifeFormDamage = 0.3,
        StructureDamage = 1,
        Range = 0.9,
    },

    [kTechId.HeavyMachineGun] =
    {
        LifeFormDamage = 1,
        StructureDamage = 0.6,
        Range = 0.7,
    },

    [kTechId.Flamethrower] =
    {
        LifeFormDamage = 0.6,
        StructureDamage = 1,
        Range = 0.4,
    },

    [kTechId.GasGrenade] =
    {
        LifeFormDamage = 0.4,
        StructureDamage = 0.6,
        Range = 0.7,
        RangeLabelOverride = "BUYMENU_GRENADES_RANGE_OVERRIDE",
    },

    [kTechId.ClusterGrenade] =
    {
        LifeFormDamage = 0.2,
        StructureDamage = 0.8,
        Range = 0.6,
        RangeLabelOverride = "BUYMENU_GRENADES_RANGE_OVERRIDE",
    },

    [kTechId.PulseGrenade] =
    {
        LifeFormDamage = 0.5,
        StructureDamage = 0.1,
        Range = 0.4,
        RangeLabelOverride = "BUYMENU_GRENADES_RANGE_OVERRIDE",
    },
	
    [kTechId.ScanGrenade] =
    {
        LifeFormDamage = 0.01,
        StructureDamage = 0.01,
        Range = 0.9,
        RangeLabelOverride = "BUYMENU_GRENADES_RANGE_OVERRIDE",
    },

    [kTechId.DualMinigunExosuit] =
    {
        LifeFormDamage = 0.9,
        StructureDamage = 0.8,
        Range = 0.7,
    },

    -- Prototype Lab "big" pictures are a seperate texture file.
    [kTechId.DualRailgunExosuit] =
    {
        LifeFormDamage = 1,
        StructureDamage = 0.6,
        Range = 1,
    },
	
    [kTechId.Submachinegun] =
    {
        LifeFormDamage = 0.9,
        StructureDamage = 0.9,
        Range = 0.7,
    },	
}

local function GetStatsForTechId(techId)


    local stats = kTechIdStats[techId]
    if stats then
        return stats
    end

    return nil

end

local kTechIdInfo =
{
    [kTechId.Pistol] =
    {
        ButtonTextureIndex = 0,
        BigPictureIndex = 0,
        Description = "PISTOL_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Pistol)
    },

    [kTechId.Rifle] =
    {
        ButtonTextureIndex = 1,
        BigPictureIndex = 1,
        Description = "RIFLE_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Rifle)
    },

    [kTechId.Shotgun] =
    {
        ButtonTextureIndex = 2,
        BigPictureIndex = 2,
        Description = "SHOTGUN_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Shotgun)
    },

    [kTechId.GrenadeLauncher] =
    {
        ButtonTextureIndex = 3,
        BigPictureIndex = 3,
        Description = "GRENADELAUNCHER_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.GrenadeLauncher)
    },

    [kTechId.Flamethrower] =
    {
        ButtonTextureIndex = 4,
        BigPictureIndex = 4,
        Description = "FLAMETHROWER_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Flamethrower),
        Special = kSpecial.Burn
    },

    [kTechId.HeavyMachineGun] =
    {
        ButtonTextureIndex = 5,
        BigPictureIndex = 5,
        Description = "HMG_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.HeavyMachineGun)
    },

    [kTechId.Axe] =
    {
        ButtonTextureIndex = 6,
        BigPictureIndex = 6,
        Description = "AXE_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Axe)
    },

    [kTechId.Welder] =
    {
        ButtonTextureIndex = 7,
        BigPictureIndex = 7,
        Description = "WELDER_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Welder)
    },

    [kTechId.GasGrenade] =
    {
        ButtonTextureIndex = 8,
        BigPictureIndex = 8,
        Description = "GASGRENADE_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.GasGrenade)
    },

    [kTechId.ClusterGrenade] =
    {
        ButtonTextureIndex = 9,
        BigPictureIndex = 9,
        Description = "CLUSTERGRENADE_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.ClusterGrenade)
    },

    [kTechId.PulseGrenade] =
    {
        ButtonTextureIndex = 10,
        BigPictureIndex = 10,
        Description = "PULSEGRENADE_BUYDESCRIPTION",
        Special = kSpecial.Electrify,
        Stats = GetStatsForTechId(kTechId.PulseGrenade)
    },

    [kTechId.ScanGrenade] =
    {
        ButtonTextureIndex = 18,
        BigPictureIndex = 10,
        Description = "SCANGRENADE_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.ScanGrenade)
    },

    [kTechId.LayMines] =
    {
        ButtonTextureIndex = 11,
        BigPictureIndex = 11,
        Description = "MINES_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.LayMines)
    },

    [kTechId.Submachinegun] =
    {
        ButtonTextureIndex = 17,
        BigPictureIndex = 14,
        Description = "SMG_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Submachinegun)
    },

    -- Prototype Lab "big" pictures are a seperate texture file.
    [kTechId.Jetpack] =
    {
        ButtonTextureIndex = 12,
        BigPictureIndex = 2,
        Description = "JETPACK_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.Jetpack)
    },

    [kTechId.DualRailgunExosuit] =
    {
        ButtonTextureIndex = 13,
        BigPictureIndex = 1,
        Description = "DUALRAILGUN_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.DualRailgunExosuit),
        Special = kSpecial.Massive
    },

    [kTechId.DualMinigunExosuit] =
    {
        ButtonTextureIndex = 14,
        BigPictureIndex = 0,
        Description = "DUALMINIGUN_BUYDESCRIPTION",
        Stats = GetStatsForTechId(kTechId.DualMinigunExosuit),
        Special = kSpecial.Massive
    },
}

--[[ (Z = lightning bolt icon, R = res icon)
                  0%|                                    80%-padding| |80%             |100% (Width)
    ╔═════════════╤═════════════════════════════════════════════════════════════════════╗ ─0%
    ║             │ ┌───────────────────────────────────────────────┐ ┌───────────────┐ ║ 
    ║ Jetpack     │ │ POWER MODULE                                  │ │     HEAVY     │ ║
    ║             │ │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │ │               │ ║ 
    ╟─────────────┤ │ │ +20P │ │ +20P │ │ +20P │ │ +20P │ │ +20P │  │ │     20Z/      │ ║ 
    ║             │ │ │ -40R │ │ -40R │ │ -40R │ │ -40R │ │ -40R │  │ │       /40Z    │ ║ 
    ║  │Exo│      │ │ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘  │ │               │ ║
    ║             │ └───────────────────────────────────────────────┘ └───────────────┘ ║ ─15%
    ╟─────────────┤ ┌───────────────┐                                 ┌───────────────┐ ║
    ║             │ │ RIGHT ARM     │                                 │ LEFT ARM      │ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ CLAW        ││                                 ││ CLAW        ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│                                 │└─────────────┘│ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ WELDER      ││                                 ││ WELDER      ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│             ( PIC )             │└─────────────┘│ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ SHIELD      ││                                 ││ SHIELD      ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│                                 │└─────────────┘│ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ MINIGUN     ││                                 ││ MINIGUN     ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│                                 │└─────────────┘│ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ RAILGUN     ││                                 ││ RAILGUN     ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│                                 │└─────────────┘│ ║
    ║             │ │┌─────────────┐│                                 │┌─────────────┐│ ║
    ║             │ ││ FLAMER      ││                                 ││ FLAMER      ││ ║
    ║             │ ││ 10Z    (PIC)││                                 ││ 10Z    (PIC)││ ║
    ║             │ │└─────────────┘│                                 │└─────────────┘│ ║
    ║             │ └───────────────┘                                 └───────────────┘ ║ ─15%+right/left arm panel height
    ║             │ ┌─────────────────────────────┐  ┌────────────────────────────────┐ ║ ─85%
    ║             │ │ ARMOR MODULE                │  │ UTILITY MODULE                 │ ║
    ║             │ │ ┌──────┐ ┌──────┐ ┌──────┐  │  │ ┌──────┐ ┌───────┐ ┌─────────┐ │ ║
    ║             │ │ │ +100 │ │ +100 │ │ +100 │  │  │ │ None │ │Scanner│ │Thrusters│ │ ║
    ║             │ │ │  10Z │ │  10Z │ │  10Z │  │  │ │      │ │  10Z  │ │  10Z    │ │ ║
    ║             │ │ └──────┘ └──────┘ └──────┘  │  │ └──────┘ └───────┘ └─────────┘ │ ║
    ║             │ └─────────────────────────────┘  └────────────────────────────────┘ ║ ─100% (Height-UpgradeButtonSize)
    ║             │                                                         ┌─────────┐ ║ 
    ║             │                                                    40R ─┤ UPGRADE │ ║
    ║             │                                                         └─────────┘ ║ ─
    ╚═════════════╧═════════════════════════════════════════════════════════════════════╝
                  0%|         0%+armor panel width|  |100%-utiltiy panel width         |100%
]]

--local GetBigIconPixelCoords = GetLocal(GUIMarineBuyMenu._InitializeContent, "GetBigIconPixelCoords")
--local GetSmallIconPixelCoordinates = GetLocal(GUIMarineBuyMenu._InitializeEquipped, "GetSmallIconPixelCoordinates")

local gBigIconIndex, bigIconWidth, bigIconHeight = nil, 400, 300
local function GetBigIconPixelCoords(techId, researched)
    if not gBigIconIndex then
        gBigIconIndex = {}
        gBigIconIndex[kTechId.Axe] = 0
        gBigIconIndex[kTechId.Pistol] = 1
        gBigIconIndex[kTechId.Rifle] = 2
        gBigIconIndex[kTechId.Shotgun] = 3
        gBigIconIndex[kTechId.GrenadeLauncher] = 4
        gBigIconIndex[kTechId.Flamethrower] = 5
        gBigIconIndex[kTechId.Jetpack] = 6
        gBigIconIndex[kTechId.Exosuit] = 7
        gBigIconIndex[kTechId.Welder] = 8
        gBigIconIndex[kTechId.LayMines] = 9
        gBigIconIndex[kTechId.DualMinigunExosuit] = 10
        gBigIconIndex[kTechId.UpgradeToDualMinigun] = 10
        gBigIconIndex[kTechId.ClawRailgunExosuit] = 11
        gBigIconIndex[kTechId.DualRailgunExosuit] = 11
        gBigIconIndex[kTechId.UpgradeToDualRailgun] = 11
        gBigIconIndex[kTechId.Submachinegun] = 17
		
        gBigIconIndex[kTechId.ClusterGrenade] = 12
        gBigIconIndex[kTechId.GasGrenade] = 13
        gBigIconIndex[kTechId.PulseGrenade] = 14
		gBigIconIndex[kTechId.ScanGrenade] = 14
    end
    local index = gBigIconIndex[techId] or 0
    local x1 = 0
    local x2 = bigIconWidth
    if not researched then
        x1 = bigIconWidth
        x2 = bigIconWidth * 2
    end
    local y1 = index * bigIconHeight
    local y2 = (index + 1) * bigIconHeight
    return x1, y1, x2, y2
end

local smallIconHeight = 64
local smallIconWidth = 128
local gSmallIconIndex = nil
local function GetSmallIconPixelCoordinates(itemTechId)
    if not gSmallIconIndex then
        gSmallIconIndex = {}
        
        gSmallIconIndex[kTechId.Claw] = 25
        
        gSmallIconIndex[kTechId.Axe] = 4
        gSmallIconIndex[kTechId.Pistol] = 3
        gSmallIconIndex[kTechId.Rifle] = 1
        gSmallIconIndex[kTechId.Shotgun] = 5
        gSmallIconIndex[kTechId.GrenadeLauncher] = 8
        gSmallIconIndex[kTechId.Flamethrower] = 6
        gSmallIconIndex[kTechId.Jetpack] = 24
        gSmallIconIndex[kTechId.Exosuit] = 26
        gSmallIconIndex[kTechId.Welder] = 10
        gSmallIconIndex[kTechId.LayMines] = 21
        gSmallIconIndex[kTechId.DualMinigunExosuit] = 26
        gSmallIconIndex[kTechId.UpgradeToDualMinigun] = 26
        gSmallIconIndex[kTechId.ClawRailgunExosuit] = 38
        gSmallIconIndex[kTechId.DualRailgunExosuit] = 38
        gSmallIconIndex[kTechId.UpgradeToDualRailgun] = 38
		gSmallIconIndex[kTechId.Submachinegun] = 51
        
        gSmallIconIndex[kTechId.ClusterGrenade] = 42
        gSmallIconIndex[kTechId.GasGrenade] = 43
        gSmallIconIndex[kTechId.PulseGrenade] = 44
		gSmallIconIndex[kTechId.ScanGrenade] = 52
    end
    local index = gSmallIconIndex[itemTechId]
    if not index then
        index = 0
    end
    local y1 = index * smallIconHeight
    local y2 = (index + 1) * smallIconHeight
    return 0, y1, smallIconWidth, y2
end

local function GetBuildIconPixelCoords(techId)
    local iconX, iconY = GetMaterialXYOffset(techId)
    return iconX * 80, iconY * 80, iconX * 80 + 80, iconY * 80 + 80
end

GUIMarineBuyMenu.kExoModuleData = {
    
    -- Weapon modules
    [kExoModuleTypes.Claw]         = {
        label          = "EXO_MODULE_CLAW", tooltip = "EXO_WEAPON_CLAW_TOOLTIP",
        image          = kInventoryIconsTexture,
        imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.Claw) },
    },
    --[kExoModuleTypes.Welder]       = {
    --    label          = "Welder", tooltip = "EXO_WEAPON_WELDER_TOOLTIP",
    --    image          = kInventoryIconsTexture,
    --    imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.Welder) },
    --},
    --[kExoModuleTypes.Shield]       = {
    --    label          = "Shield", tooltip = "EXO_WEAPON_SHIELD_TOOLTIP",
    --    image          = kInventoryIconsTexture,
    --    imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.PulseGrenade) },
    --},
    --[kExoModuleTypes.MarineStructureAbility] = {
    --    label = "Builder", tooltip = "EXO_WEAPON_SHIELD_TOOLTIP",
    --    image = kInventoryIconsTexture,
    --    imageTexCoords = {GetSmallIconPixelCoordinates(kTechId.Welder)},
    --},
    [kExoModuleTypes.Railgun]      = {
        label          = "RAILGUN", tooltip = "EXO_WEAPON_RAILGUN_TOOLTIP",
        image          = kInventoryIconsTexture,
        imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.ClawRailgunExosuit) },
    },
	[kExoModuleTypes.PlasmaLauncher]      = {
        label          = "EXO_MODULE_PLASMALAUNCHER", tooltip = "EXO_WEAPON_RAILGUN_TOOLTIP",
        image          = kInventoryIconsTexture,
        imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.PulseGrenade) },
    },
    [kExoModuleTypes.Minigun]      = {
        label          = "MINIGUN", tooltip = "EXO_WEAPON_MMINIGUN_TOOLTIP",
        image          = kInventoryIconsTexture,
        imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.Exosuit) },
    },
    [kExoModuleTypes.Flamethrower] = {
        label          = "FLAMETHROWER", tooltip = "EXO_WEAPON_FLAMETHROWER_TOOLTIP",
        image          = kInventoryIconsTexture,
        imageTexCoords = { GetSmallIconPixelCoordinates(kTechId.Flamethrower) },
    },
    
    -- Utility modules
    
    [kExoModuleTypes.Armor]        = {
        label          = "EXO_MODULE_ARMOR", tooltip = "EXO_MODULE_ARMOR_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.Armor1) },
    },
    
    [kExoModuleTypes.Thrusters]    = {
        label          = "EXO_MODULE_THRUSTERS", tooltip = "EXO_UTILITY_SCANNER_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.Jetpack) },
    },
	
    --[kExoModuleTypes.PhaseModule]  = {
    --    label          = "Phase", tooltip = "EXO_UTILITY_SCANNER_TOOLTIP",
    --    image          = "ui/buildmenu.dds",
    --    imageTexCoords = { GetBuildIconPixelCoords(kTechId.PhaseGate) },
    --},
	
    [kExoModuleTypes.EjectionSeat]      = {
        label          = "EXO_MODULE_EJECTIONSEAT", tooltip = "EXO_UTILITY_SCANNER_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.JetpackMarine) },
    },
    
    -- Ability modules

    [kExoModuleTypes.NanoShield]   = {
        label          = "EXO_ABILITY_NANOSHIELD_FIELD", tooltip = "EXO_ABILITY_NANOSHIELD_FIELD_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.NanoShield) },
    },

    [kExoModuleTypes.CatPack]      = {
        label          = "EXO_ABILITY_ADRENALINE_FIELD", tooltip = "EXO_ABILITY_ADRENALINE_FIELD_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.CatPack) },
    },

    [kExoModuleTypes.NanoRepair]   = {
        label          = "EXO_ABILITY_REGEN_FIELD", tooltip = "EXO_ABILITY_REGEN_FIELD_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.MedPack) },
    },

    [kExoModuleTypes.None]         = {
        label          = "EXO_MODULE_NONE", tooltip = "EXO_MODULE_NONE_TOOLTIP",
        image          = "ui/buildmenu.dds",
        imageTexCoords = { GetBuildIconPixelCoords(kTechId.Stop) },
    },
    
}

function GUIMarineBuyMenu:_GetPigPicturePixelCoordinatesForTechID(techId)

    -- NOTE(Salads): The texture file for purchase buttons have a column for "not hovered", and another for "hovered"

    local pictureWidth = 651 -- armory dimensions
    local pictureHeight = 319
    if self.hostStructure:isa("PrototypeLab") then
        pictureWidth = 403
        pictureHeight = 424
    end

    local index = kTechIdInfo[techId].BigPictureIndex
    assert(index, "Could not find index for techid")

    local x1 = 0
    local x2 = x1 + pictureWidth

    local y1 = pictureHeight * index
    local y2 = y1 + pictureHeight

    return { x1, y1, x2, y2 }

end

function GUIMarineBuyMenu:_GetButtonPixelCoordinatesForTechID(techId, isHover)

    -- NOTE(Salads): The texture file for purchase buttons have a column for "not hovered", and another for "hovered"

    local buttonIconWidth = 441
    local buttonIconHeight = 114
    local hoverAdd = isHover and buttonIconWidth or 0
    local index = kTechIdInfo[techId].ButtonTextureIndex
    assert(index, "Could not find index for techid")

    local x1 = hoverAdd
    local x2 = x1 + buttonIconWidth

    local y1 = buttonIconHeight * index
    local y2 = y1 + buttonIconHeight

    return { x1, y1, x2, y2 }

end

local function Desaturate(color, desaturateBy)

    local hue, sat, val = RGBToHSV(color)
    sat = sat - desaturateBy
    local result = HSVToRGB(hue, sat, val)

    return result
end

function GUIMarineBuyMenu:_UpdateSpecialSection(specialDefinition)

    local specialTextureCoords = specialDefinition.TextureCoordinates
    local specialTitle = specialDefinition.Title
    self.specialFrame:SetTexturePixelCoordinates(GUIUnpackCoords(specialTextureCoords))
    self.specialFrame:SetSize(GUIGetSizeFromCoords(specialTextureCoords))
    self.specialTitle:SetText(string.format("%s%s", Locale.ResolveString("BUYMENU_TITLE_PREFIX"), Locale.ResolveString(specialTitle)))

    local specialTextPadding = 30
    local startPos = self.specialTitle:GetPosition()
    local xPos = startPos.x
    local yPos = startPos.y + 35

    local specials = specialDefinition.Specials
    local numSpecials = #specials
    for i, specialText in ipairs(self.specialTexts) do

        if i <= numSpecials then
            specialText:SetText(Locale.ResolveString(specials[i]))

            local debuffIndicies = specialDefinition.SpecialsDebuffs
            if debuffIndicies and debuffIndicies[i] then
                specialText:SetColor(self.kSpecialTextContentColor_Debuff)
            else
                specialText:SetColor(self.kSpecialTextContentColor)
            end

        else
            specialText:SetText("")
        end

        specialText:SetPosition(Vector(xPos, yPos, 0))
        yPos = yPos + specialTextPadding

    end

end

function GUIMarineBuyMenu:_UpdateStatBar(barItem, stat)

    local statFullWidth = self.rangeBar:GetTextureWidth()
    local statFullHeight = self.rangeBar:GetTextureHeight()
    local statWidth = stat * statFullWidth
    local desaturateBy = 0.35
    local statColor
    if stat <= 0.5 then

        statColor = LerpColor(Desaturate(Color(1,0,0), desaturateBy), Desaturate(Color(1,1,0), desaturateBy), stat / 0.5)
    else
        statColor = LerpColor(Desaturate(Color(1,1,0), desaturateBy), Desaturate(Color(0,1,0), desaturateBy), (stat - 0.5) / 0.5)
    end

    barItem:SetSize(Vector(statWidth, statFullHeight, 0))
    barItem:SetTexturePixelCoordinates(0, 0, statWidth, statFullHeight)
    barItem:SetColor(statColor)

end

function GUIMarineBuyMenu:GetTechIDDisabled(techID)
    return false
end

function GUIMarineBuyMenu:_CreateButton(parent, buttonPosition, buttonTechId)

    local iconpaddingX = 18
    local iconPaddingY = 2
    local iconOffsetY = 3
    local buttonPixelCoordinates = self:_GetButtonPixelCoordinatesForTechID(buttonTechId, false)

    local buyButton = self:CreateAnimatedGraphicItem()
    buyButton:SetIsScaling(false)
    buyButton:AddAsChildTo(parent)
    buyButton:SetPosition(buttonPosition)
    buyButton:SetTexture(kButtonsTexture)
    buyButton:SetTexturePixelCoordinates(GUIUnpackCoords(buttonPixelCoordinates))
    buyButton:SetSize(GUIGetSizeFromCoords(buttonPixelCoordinates))
    buyButton:SetOptionFlag(GUIItem.CorrectScaling)

    local techCost = LookupTechData(buttonTechId, kTechDataCostKey, nil)
    local costHasPrice = false
    local costString
    if techCost then
        costString = string.format("%d", techCost)
        costHasPrice = techCost > 0
    else
        costString = "error"
    end

    local costIconGlowSize = 18 -- Space in the actual texture that's just glow
    local costIconSize = 30 + costIconGlowSize

    local costIcon = self:CreateAnimatedGraphicItem()
    costIcon:SetIsScaling(false)
    costIcon:AddAsChildTo(buyButton)
    costIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    costIcon:SetTexture(kResourceIcon_Lit)
    costIcon:SetSize(Vector(costIconSize, costIconSize, 0))
    costIcon:SetPosition(Vector(iconpaddingX - 9, -costIcon:GetSize().y - iconPaddingY - iconOffsetY + 9, 0))
    costIcon:SetOptionFlag(GUIItem.CorrectScaling)

    local kButtonNumberFontSize = 30

    local costText = self:CreateAnimatedTextItem()
    costText:SetIsScaling(false)
    costText:AddAsChildTo(costIcon)
    costText:SetPosition(Vector(-4, 0, 0))
    costText:SetAnchor(GUIItem.Right, GUIItem.Center)
    costText:SetTextAlignmentX(GUIItem.Align_Min)
    costText:SetTextAlignmentY(GUIItem.Align_Center)
    costText:SetText(costString)
    costText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(costText, "kAgencyFB", kButtonNumberFontSize)

    local teamIcon = self:CreateAnimatedGraphicItem()
    teamIcon:SetIsScaling(false)
    teamIcon:AddAsChildTo(buyButton)
    teamIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    teamIcon:SetTexture(kWeaponButtonTeamIconTexture)
    teamIcon:SetSizeFromTexture()
    teamIcon:SetPosition(Vector(iconpaddingX, iconPaddingY - iconOffsetY, 0))
    teamIcon:SetOptionFlag(GUIItem.CorrectScaling)

    local teamText = self:CreateAnimatedTextItem()
    teamText:SetIsScaling(false)
    teamText:AddAsChildTo(teamIcon)
    teamText:SetPosition(Vector(teamIcon:GetSize().x + 4, 2, 0))
    teamText:SetAnchor(GUIItem.Left, GUIItem.Center)
    teamText:SetTextAlignmentX(GUIItem.Align_Min)
    teamText:SetTextAlignmentY(GUIItem.Align_Center)
    teamText:SetFontName(Fonts.kAgencyFB_Tiny)
    teamText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(teamText, "kAgencyFB", kButtonNumberFontSize)

    -- y = 7, x: 0
    local errorFrame = self:CreateAnimatedGraphicItem()
    errorFrame:SetIsScaling(false)
    errorFrame:AddAsChildTo(buyButton)
    errorFrame:SetOptionFlag(GUIItem.CorrectScaling)
    errorFrame:SetPosition(Vector(0, 7, 0))
    errorFrame:SetTexture(kButtonErrorFrame)
    errorFrame:SetSizeFromTexture()

    local errorText = self:CreateAnimatedTextItem()
    errorText:SetIsScaling(false)
    errorText:AddAsChildTo(errorFrame)
    errorText:SetPosition(Vector(self.kErrorFrameTextPadding, 0, 0))
    errorText:SetAnchor(GUIItem.Left, GUIItem.Center)
    errorText:SetTextAlignmentX(GUIItem.Align_Min)
    errorText:SetTextAlignmentY(GUIItem.Align_Center)
    errorText:SetFontName(Fonts.kAgencyFB_Tiny)
    errorText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(errorText, "kAgencyFBBold", 33)

    return
    {
        TechID = buttonTechId,
        Button = buyButton,
        ErrorFrame = errorFrame,
        ErrorTextItem = errorText,
        Hosted = false,
        WeaponGroup = parent,
        TeamText = teamText,
        CostText = costText,
        Initialized = false,
        LastShowState = kButtonShowState.Uninitialized,
        Disabled = self:GetTechIDDisabled(buttonTechId)
    }

end

function GUIMarineBuyMenu:_InitializeWeaponGroup(groupItem, buttonPositions, purchasableTechIds)

    assert(groupItem)
    assert(type(buttonPositions) == "table")
    assert(type(purchasableTechIds) == "table")
    assert(#buttonPositions >= #purchasableTechIds, "Not enough button positions for purchasable tech ids!")

    for i = 1, #purchasableTechIds do

        local techId = purchasableTechIds[i]
        local buttonPos = buttonPositions[i]

        local buttonTable = self:_CreateButton(groupItem, buttonPos, techId)
        table.insert(self.buyButtons, buttonTable)

    end

end

function GUIMarineBuyMenu:SetHostStructure(hostStructure)

    assert(hostStructure)

    self.hostStructure = hostStructure

    if self.hostStructure:isa("Armory") then
        self:CreateArmoryUI()
    elseif self.hostStructure:isa("PrototypeLab") then
        self:CreatePrototypeLabUI()
    else
        Log(string.format("ERROR: No generator found for class: %s", self.hostStructure:GetClassName()))
    end
	
    if hostStructure:isa("PrototypeLab") then
        self:_InitializeExoModularButtons()
        -- A player who is already in an exo came to refit, so open straight on the
        -- configuration page; everyone else starts on the vanilla item list.
        local localPlayer = Client.GetLocalPlayer()
        self.exoConfigPageActive = localPlayer ~= nil and localPlayer:isa("Exo")
        self:_RefreshExoModularButtons()
    end	
end

function GUIMarineBuyMenu:CreatePrototypeLabUI()
    
    self.defaultTechId = kTechId.Jetpack
    
    self.background = self:CreateAnimatedGraphicItem()
    self.background:SetTexture(kPrototypeLabBackgroundTexture)
    self.background:SetSizeFromTexture()
    self.background:SetIsScaling(false)
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.background:SetHotSpot(Vector(0.5, 0.5, 0))
    self.background:SetScale(self.customScaleVector)
    self.background:SetOptionFlag(GUIItem.CorrectScaling)
    self.background:SetLayer(kGUILayerMarineBuyMenu)
    
    local buttonPositions = kWeaponGroupButtonPositions[kButtonGroupFrame_Unlabeled_x2]

    local buttonGroup = self:CreateAnimatedGraphicItem()
    buttonGroup:AddAsChildTo(self.background)
    buttonGroup:SetIsScaling(false)
    buttonGroup:SetPosition(Vector(kPrototypeLabItemListPos.x, kPrototypeLabItemListPos.y, 0))
    buttonGroup:SetTexture(kButtonGroupFrame_Unlabeled_x2)
    buttonGroup:SetSizeFromTexture()
    buttonGroup:SetOptionFlag(GUIItem.CorrectScaling)

    -- Vanilla item list: jetpack on top, exosuit below, in the order PrototypeLab:GetItemList
    -- hands them out. Both tiles look and behave like vanilla; the exosuit tile is the entry
    -- point to the modular configuration page instead of a purchase (see HandleItemClicked).
    self.itemListGroup = buttonGroup
    self:_InitializeWeaponGroup(buttonGroup, buttonPositions,
                                {
                                    kTechId.Jetpack,
                                    kTechId.DualMinigunExosuit,
                                })

    self:_CreateRightSide(Vector(kPrototypeLabRightSidePos.x, kPrototypeLabRightSidePos.y, 0))

end

function GUIMarineBuyMenu:CreateArmoryUI()

    local paddingX = 105 -- Start of content from left side of background.
    local paddingY = 36
    -- 449
    local paddingXWeaponGroups = 29
    -- 449
    local paddingYWeaponGroups = 6
    local paddingXWeaponGroupsToRightSide = 36 -- 724 after this till end. (not including end cap)

    self.defaultTechId = kTechId.Rifle

    self.background = self:CreateAnimatedGraphicItem()
    self.background:SetTexture(kArmoryBackgroundTexture)
    self.background:SetSizeFromTexture()
    self.background:SetIsScaling(false)
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.background:SetHotSpot(Vector(0.5, 0.5, 0))
    self.background:SetScale(self.customScaleVector)
    self.background:SetOptionFlag(GUIItem.CorrectScaling)
    self.background:SetLayer(kGUILayerMarineBuyMenu)

    local x2ButtonPositions = kWeaponGroupButtonPositions[kButtonGroupFrame_Unlabeled_x2]
    local x4ButtonPositions = kWeaponGroupButtonPositions[kButtonGroupFrame_Labeled_x4]
	local x5ButtonPositions = kWeaponGroupButtonPositions[kButtonGroupFrame_Labeled_x5]

    local weaponGroupTopLeft = self:CreateAnimatedGraphicItem()
    weaponGroupTopLeft:SetIsScaling(false)
    weaponGroupTopLeft:SetPosition(Vector(paddingX, paddingY, 0))
    weaponGroupTopLeft:SetTexture(kButtonGroupFrame_Unlabeled_x2)
    weaponGroupTopLeft:SetSizeFromTexture()
    weaponGroupTopLeft:SetOptionFlag(GUIItem.CorrectScaling)
    self.background:AddChild(weaponGroupTopLeft)
    self:_InitializeWeaponGroup(weaponGroupTopLeft, x2ButtonPositions,
    {
        kTechId.Pistol,
        kTechId.Rifle,
    })

	
    local weaponGroupBottomLeft = self:CreateAnimatedGraphicItem()
    weaponGroupBottomLeft:SetIsScaling(false)
    weaponGroupBottomLeft:SetPosition(Vector(paddingX, weaponGroupTopLeft:GetPosition().y + weaponGroupTopLeft:GetSize().y + paddingYWeaponGroups, 0))
    
	if kCBMaddon then
		weaponGroupBottomLeft:SetTexture(kButtonGroupFrame_Labeled_x5)
		weaponGroupBottomLeft:SetSizeFromTexture()
		weaponGroupBottomLeft:SetOptionFlag(GUIItem.CorrectScaling)
		self.background:AddChild(weaponGroupBottomLeft)
		self:_InitializeWeaponGroup(weaponGroupBottomLeft, x5ButtonPositions,
		{
			kTechId.Submachinegun,
			kTechId.Shotgun,
			kTechId.GrenadeLauncher,
			kTechId.Flamethrower,
			kTechId.HeavyMachineGun
		})
	else
		weaponGroupBottomLeft:SetTexture(kButtonGroupFrame_Labeled_x4)
		weaponGroupBottomLeft:SetSizeFromTexture()
		weaponGroupBottomLeft:SetOptionFlag(GUIItem.CorrectScaling)
		self.background:AddChild(weaponGroupBottomLeft)
		self:_InitializeWeaponGroup(weaponGroupBottomLeft, x4ButtonPositions,
		{
			kTechId.Shotgun,
			kTechId.GrenadeLauncher,
			kTechId.Flamethrower,
			kTechId.HeavyMachineGun
		})		
	end

    local x4LabelStartX = 335

    local labelItemBottomLeft = self:CreateAnimatedTextItem()
    labelItemBottomLeft:SetIsScaling(false)
    labelItemBottomLeft:AddAsChildTo(weaponGroupBottomLeft)
    labelItemBottomLeft:SetPosition(Vector(x4LabelStartX, 0, 0))
    labelItemBottomLeft:SetAnchor(GUIItem.Left, GUIItem.Top)
    labelItemBottomLeft:SetTextAlignmentX(GUIItem.Align_Min)
    labelItemBottomLeft:SetTextAlignmentY(GUIItem.Align_Min)
    labelItemBottomLeft:SetFontName(Fonts.kAgencyFB_Tiny)
    labelItemBottomLeft:SetText(Locale.ResolveString("BUYMENU_GROUPLABEL_WEAPONS"))
    labelItemBottomLeft:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(labelItemBottomLeft, "kAgencyFB", 24)

    local weaponGroupTopRight = self:CreateAnimatedGraphicItem()
    weaponGroupTopRight:SetIsScaling(false)
    weaponGroupTopRight:AddAsChildTo(self.background)
    weaponGroupTopRight:SetPosition(Vector(weaponGroupTopLeft:GetPosition().x + weaponGroupTopLeft:GetSize().x + paddingXWeaponGroups, paddingY, 0))
    weaponGroupTopRight:SetTexture(kButtonGroupFrame_Unlabeled_x2)
    weaponGroupTopRight:SetSizeFromTexture()
    weaponGroupTopRight:SetOptionFlag(GUIItem.CorrectScaling)
    self:_InitializeWeaponGroup(weaponGroupTopRight, x2ButtonPositions,
    {
        kTechId.Axe,
        kTechId.Welder
    })

    local weaponGroupBottomRight = self:CreateAnimatedGraphicItem()
    weaponGroupBottomRight:SetIsScaling(false)
    weaponGroupBottomRight:AddAsChildTo(self.background)
    weaponGroupBottomRight:SetPosition(Vector(weaponGroupTopRight:GetPosition().x, weaponGroupTopRight:GetPosition().y + weaponGroupTopRight:GetSize().y + paddingYWeaponGroups, 0))
	
	weaponGroupBottomRight:SetTexture(kButtonGroupFrame_Labeled_x4)
	weaponGroupBottomRight:SetSizeFromTexture()
	weaponGroupBottomRight:SetOptionFlag(GUIItem.CorrectScaling)
	self:_InitializeWeaponGroup(weaponGroupBottomRight, x4ButtonPositions,
	{
		kTechId.GasGrenade,
		kTechId.ClusterGrenade,
		kTechId.PulseGrenade,
		kTechId.LayMines
	})

    local labelItemBottomRight = self:CreateAnimatedTextItem()
    labelItemBottomRight:SetIsScaling(false)
    labelItemBottomRight:AddAsChildTo(weaponGroupBottomRight)
    labelItemBottomRight:SetPosition(Vector(x4LabelStartX, 0, 0))
    labelItemBottomRight:SetAnchor(GUIItem.Left, GUIItem.Top)
    labelItemBottomRight:SetTextAlignmentX(GUIItem.Align_Min)
    labelItemBottomRight:SetTextAlignmentY(GUIItem.Align_Min)
    labelItemBottomRight:SetFontName(Fonts.kAgencyFB_Tiny)
    labelItemBottomRight:SetText(Locale.ResolveString("BUYMENU_GROUPLABEL_UTILITY"))
    labelItemBottomRight:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(labelItemBottomRight, "kAgencyFB", 24)

    local rightSideStartPos = weaponGroupTopRight:GetPosition()
    rightSideStartPos.x = rightSideStartPos.x + weaponGroupTopRight:GetSize().x
    rightSideStartPos.x = rightSideStartPos.x + paddingXWeaponGroupsToRightSide
    self:_CreateRightSide(rightSideStartPos)

end

function GUIMarineBuyMenu:_CreateRightSide(startPos)

    -- This is created here to eliminate common code
    self.buyButtonHighlight = self:CreateAnimatedGraphicItem()
    self.buyButtonHighlight:SetIsScaling(false)
    self.buyButtonHighlight:AddAsChildTo(self.background)
    self.buyButtonHighlight:SetTexture(kButtonHighlightTexture)
    self.buyButtonHighlight:SetSizeFromTexture()
    self.buyButtonHighlight:SetIsVisible(false)
    self.buyButtonHighlight:SetOptionFlag(GUIItem.CorrectScaling)

    self.purchaseText = self:CreateAnimatedTextItem()
    self.purchaseText:SetIsScaling(false)
    self.purchaseText:AddAsChildTo(self.buyButtonHighlight)
    self.purchaseText:SetPosition(Vector(18, 89, 0))
    self.purchaseText:SetOptionFlag(GUIItem.CorrectScaling)
    self.purchaseText:SetText(Locale.ResolveString("BUYMENU_CLICKTOPURCHASE"))
    GUIMakeFontScale(self.purchaseText, "kAgencyFBBold", 21)

    self.rightSideRoot = self:CreateAnimatedGraphicItem()
    self.rightSideRoot:AddAsChildTo(self.background)
    self.rightSideRoot:SetIsScaling(false)
    self.rightSideRoot:SetPosition(startPos)
    self.rightSideRoot:SetColor(Color(0,0,0,0))
    self.rightSideRoot:SetOptionFlag(GUIItem.CorrectScaling)

    local y = 0
    self.itemTitle = self:CreateAnimatedTextItem()
    self.itemTitle:AddAsChildTo(self.rightSideRoot)
    self.itemTitle:SetIsScaling(false)
    self.itemTitle:SetPosition(Vector(0, y, 0))
    self.itemTitle:SetFontIsBold(true)
    self.itemTitle:SetColor(Color(1,1,1,1))
    self.itemTitle:SetFontName(Fonts.kAgencyFB_Large_Bold)
    self.itemTitle:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.itemTitle, "kAgencyFBBold", 55)

    y = y + self.itemTitle:GetTextHeight(self.itemTitle:GetText()) + 18

    self.costText = self:CreateAnimatedTextItem()
    self.costText:AddAsChildTo(self.rightSideRoot)
    self.costText:SetIsScaling(false)
    self.costText:SetPosition(Vector(0, y, 0))
    self.costText:SetColor(Color(164/255, 196/255, 201/255, 1))
    self.costText:SetFontName(Fonts.kAgencyFB_Large_Bold)
    self.costText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.costText, "kAgencyFBBold", 60)

    self.costTextIcon = self:CreateAnimatedGraphicItem()
    self.costTextIcon:AddAsChildTo(self.costText)
    self.costTextIcon:SetIsScaling(false)
    self.costTextIcon:SetAnchor(GUIItem.Right, GUIItem.Center)
    self.costTextIcon:SetTexture(kResourceIcon_Unlit)
    self.costTextIcon:SetSizeFromTexture()
    self.costTextIcon:SetScale(Vector(1,1,1) * 1.5)
    self.costTextIcon:SetHotSpot(Vector(0, 0.5, 0))
    self.costTextIcon:SetOptionFlag(GUIItem.CorrectScaling)
    self.costTextIcon:SetPosition(Vector(-9, 0, 0))

    self.currentMoneyText = self:CreateAnimatedTextItem()
    self.currentMoneyText:AddAsChildTo(self.rightSideRoot)
    self.currentMoneyText:SetIsScaling(false)
    self.currentMoneyText:SetPosition(Vector(354, y, 0))
    self.currentMoneyText:SetFontIsBold(true)
    self.currentMoneyText:SetColor(Color(2/255, 230/255, 255/255, 1))
    self.currentMoneyText:SetFontName(Fonts.kAgencyFB_Large_Bold)
    self.currentMoneyText:SetText(Locale.ResolveString("BUYMENU_CURRENTMONEY_PREFIX"))
    self.currentMoneyText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.currentMoneyText, "kAgencyFBBold", 60)

    self.currentMoneyTextIcon = self:CreateAnimatedGraphicItem()
    self.currentMoneyTextIcon:AddAsChildTo(self.currentMoneyText)
    self.currentMoneyTextIcon:SetIsScaling(false)
    self.currentMoneyTextIcon:SetAnchor(GUIItem.Right, GUIItem.Center)
    self.currentMoneyTextIcon:SetTexture(kResourceIcon_Lit)
    self.currentMoneyTextIcon:SetSizeFromTexture()
    self.currentMoneyTextIcon:SetScale(Vector(1,1,1) * 1.5)
    self.currentMoneyTextIcon:SetHotSpot(Vector(0, 0.5, 0))
    self.currentMoneyTextIcon:SetOptionFlag(GUIItem.CorrectScaling)
    self.currentMoneyTextIcon:SetPosition(Vector(-9, 0, 0))

    y = y + 80

    local vsXPos = 145
    local vsTextPadding = 32
    local vsBarXOffset = 30
    local vsTextFontSize = 33

    self.statBarsStartPosY = y

    self.rangeText = self:CreateAnimatedTextItem()
    self.rangeText:AddAsChildTo(self.rightSideRoot)
    self.rangeText:SetIsScaling(false)
    self.rangeText:SetPosition(Vector(vsXPos, y, 0))
    self.rangeText:SetColor(Color(1, 1, 1))
    self.rangeText:SetTextAlignmentX(GUIItem.Align_Max)
    self.rangeText:SetText(Locale.ResolveString("BUYMENU_RANGE"))
    self.rangeText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.rangeText, "kAgencyFB", vsTextFontSize)

    self.rangeBar = self:CreateAnimatedGraphicItem()
    self.rangeBar:AddAsChildTo(self.rightSideRoot)
    self.rangeBar:SetIsScaling(false)
    self.rangeBar:SetPosition(self.rangeText:GetPosition() + Vector(vsBarXOffset, 0, 0))
    self.rangeBar:SetTexture(kVSBarTexture)
    self.rangeBar:SetSizeFromTexture()
    self.rangeBar:SetOptionFlag(GUIItem.CorrectScaling)

    local rangeTextHeight = self.rangeText:GetTextHeight(self.rangeText:GetText())
    local rangeBarHeight = self.rangeBar:GetSize().y
    self.rangeBar:SetPosition(self.rangeBar:GetPosition() + Vector(0, (rangeTextHeight - rangeBarHeight) / 2, 0))

    y = y + vsTextPadding

    self.vsLifeformsText = self:CreateAnimatedTextItem()
    self.vsLifeformsText:AddAsChildTo(self.rightSideRoot)
    self.vsLifeformsText:SetIsScaling(false)
    self.vsLifeformsText:SetPosition(Vector(vsXPos, y, 0))
    self.vsLifeformsText:SetColor(Color(1, 1, 1))
    self.vsLifeformsText:SetTextAlignmentX(GUIItem.Align_Max)
    self.vsLifeformsText:SetText(Locale.ResolveString("BUYMENU_VSLIFEFORMS"))
    self.vsLifeformsText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.vsLifeformsText, "kAgencyFB", vsTextFontSize)

    self.vsLifeformBar = self:CreateAnimatedGraphicItem()
    self.vsLifeformBar:AddAsChildTo(self.rightSideRoot)
    self.vsLifeformBar:SetIsScaling(false)
    self.vsLifeformBar:SetPosition(self.vsLifeformsText:GetPosition() + Vector(vsBarXOffset, 0, 0))
    self.vsLifeformBar:SetTexture(kVSBarTexture)
    self.vsLifeformBar:SetSizeFromTexture()
    self.vsLifeformBar:SetOptionFlag(GUIItem.CorrectScaling)

    local lifeformTextHeight = self.vsLifeformsText:GetTextHeight(self.vsLifeformsText:GetText())
    local lifeformBarHeight = self.vsLifeformBar:GetSize().y
    self.vsLifeformBar:SetPosition(self.vsLifeformBar:GetPosition() + Vector(0, (lifeformTextHeight - lifeformBarHeight) / 2, 0))

    y = y + vsTextPadding

    self.vsStructuresText = self:CreateAnimatedTextItem()
    self.vsStructuresText:AddAsChildTo(self.rightSideRoot)
    self.vsStructuresText:SetIsScaling(false)
    self.vsStructuresText:SetPosition(Vector(vsXPos, y, 0))
    self.vsStructuresText:SetColor(Color(1, 1, 1))
    self.vsStructuresText:SetTextAlignmentX(GUIItem.Align_Max)
    self.vsStructuresText:SetText(Locale.ResolveString("BUYMENU_VSSTRUCTURES"))
    self.vsStructuresText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.vsStructuresText, "kAgencyFB", vsTextFontSize)

    self.vsStructuresBar = self:CreateAnimatedGraphicItem()
    self.vsStructuresBar:AddAsChildTo(self.rightSideRoot)
    self.vsStructuresBar:SetIsScaling(false)
    self.vsStructuresBar:SetPosition(self.vsStructuresText:GetPosition() + Vector(vsBarXOffset, 0, 0))
    self.vsStructuresBar:SetTexture(kVSBarTexture)
    self.vsStructuresBar:SetSizeFromTexture()
    self.vsStructuresBar:SetOptionFlag(GUIItem.CorrectScaling)

    local structuresTextHeight = self.vsStructuresText:GetTextHeight(self.vsStructuresText:GetText())
    local structuresBarHeight = self.vsStructuresBar:GetSize().y
    self.vsStructuresBar:SetPosition(self.vsStructuresBar:GetPosition() + Vector(0, (structuresTextHeight - structuresBarHeight) / 2, 0))

    y = y + 50

    self.itemDescriptionPositionY = y
    self.itemDescription = self:CreateAnimatedTextItem()
    self.itemDescription:AddAsChildTo(self.rightSideRoot)
    self.itemDescription:SetIsScaling(false)
    self.itemDescription:SetTextClipped(true, 687, -1)
    self.itemDescription:SetPosition(Vector(0, self.itemDescriptionPositionY, 0))
    self.itemDescription:SetColor(Color(164/255, 196/255, 201/255))
    self.itemDescription:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.itemDescription, "kAgencyFB", vsTextFontSize)

    y = y + 75

    local bigPicturesTexture = kArmoryBigPicturesTexture
    if self.hostStructure:isa("PrototypeLab") then
        bigPicturesTexture = kPrototypeLabBigPicturesTexture
    end

    self.bigPicturePositionY = y
    self.bigPicturePositionYDiff = 75

    self.bigPicture = self:CreateAnimatedGraphicItem()
    self.bigPicture:AddAsChildTo(self.rightSideRoot)
    self.bigPicture:SetIsScaling(false)
    self.bigPicture:SetPosition(Vector(0, y, 0))
    self.bigPicture:SetTexture(bigPicturesTexture)
    local bigPictureCoords = self:_GetPigPicturePixelCoordinatesForTechID(kTechId.Pistol)
    self.bigPicture:SetSize(GUIGetSizeFromCoords(bigPictureCoords))
    self.bigPictureDefaultSize = GUIGetSizeFromCoords(bigPictureCoords)
    self.bigPicture:SetTexturePixelCoordinates(GUIUnpackCoords(bigPictureCoords))
    self.bigPicture:SetOptionFlag(GUIItem.CorrectScaling)

    y = y + self.bigPicture:GetSize().y

    self.specialFrame = self:CreateAnimatedGraphicItem()
    self.specialFrame:SetIsScaling(false)
    self.specialFrame:SetTexture(kSpecialsTexture)
    self.specialFrame:SetSize(GUIGetSizeFromCoords(kSpecialDefinitions[kSpecial.Electrify].TextureCoordinates))
    self.specialFrame:SetTexturePixelCoordinates(GUIUnpackCoords(bigPictureCoords))
    self.specialFrame:SetOptionFlag(GUIItem.CorrectScaling)

    local buttonGroupX = 97
    local buttonGroupY = 149 + 373 + 20
    if self.hostStructure:isa("PrototypeLab") then

        self.specialFrame:AddAsChildTo(self.background)
        self.specialFrame:SetPosition(Vector(buttonGroupX, buttonGroupY, 0))

    elseif self.hostStructure:isa("Armory") then

        self.specialFrame:AddAsChildTo(self.rightSideRoot)
        self.specialFrame:SetPosition(Vector(0, y, 0))

    end

    self.specialTitle = self:CreateAnimatedTextItem()
    self.specialTitle:AddAsChildTo(self.specialFrame)
    self.specialTitle:SetIsScaling(false)
    self.specialTitle:SetPosition(Vector(90, 0, 0))
    self.specialTitle:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.specialTitle, "kAgencyFBBold", 32)

    self.specialTexts = {}

    local maxSpecials = 0
    if self.hostStructure:isa("Armory") then
        maxSpecials = 2
    elseif self.hostStructure:isa("PrototypeLab") then
        maxSpecials = 5
    end

    for _ = 1, maxSpecials do

        local specialText = self:CreateAnimatedTextItem()
        specialText:AddAsChildTo(self.specialFrame)
        specialText:SetIsScaling(false)
        specialText:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(specialText, "kAgencyFB", 25)

        table.insert(self.specialTexts, specialText)
    end

    if self.hostStructure:isa("PrototypeLab") then
        local buttonGroupX = 97
        local buttonGroupY = (149 + 373 + 20) + 150
        self.specialFrame:SetPosition(Vector(buttonGroupX, buttonGroupY, 0))
    end
end

function GUIMarineBuyMenu:OnClose()

    -- Check if GUIMarineBuyMenu is what is causing itself to close.
    if not self.closingMenu then
        -- Play the close sound since we didn't trigger the close.
        MarineBuy_OnClose()
    end

end

function GUIMarineBuyMenu:OnResolutionChanged(oldX, oldY, newX, newY)
    self:Uninitialize()
    self:Initialize()
    
    MarineBuy_OnClose()
end

function GUIMarineBuyMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    -- NOTE(Salads): UI is created when SetHostStructure is called.

    -- Art file is not based on 1920x1080, so we do our own scaling.
    self.customScale = (Client.GetScreenHeight() / self.kMockupSize.y)
    self.customScaleVector = Vector(1,1,1) * self.customScale

    self.mouseOverStates = { }
    self.buyButtons = { } -- stores all of the button guiItems that purchase things.
    self.specialTexts = { }

    self.hoveredBuyButton = nil

    self.initialized = false -- Don't want to start with the details section empty.
    self.defaultTechId = kTechId.None

    -- note: items buttons get initialized through SetHostStructure()
    MarineBuy_OnOpen()
    
    MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
    
end

--
-- Checks if the mouse is over the passed in GUIItem and plays a sound if it has just moved over.
--
local function GetIsMouseOver(self, overItem)

    local mouseX, mouseY = Client.GetCursorPosScreen()
    local mouseOver = GUIItemContainsPoint(overItem, mouseX, mouseY, true)
    if mouseOver and not self.mouseOverStates[overItem] then
        MarineBuy_OnMouseOver()
    end

    local changed = self.mouseOverStates[overItem] ~= mouseOver
    self.mouseOverStates[overItem] = mouseOver
    return mouseOver, changed
    
end

function GUIMarineBuyMenu:_SetDetailsSectionTechId(techId, techCost)

    self.initialized = true

    local displayName = LookupTechData(techId, kTechDataDisplayName, nil)
    self.itemTitle:SetText(string.upper(Locale.ResolveString(displayName or "NO NAME")))

    self.costText:SetText(string.format("%s: %d", Locale.ResolveString("BUYMENU_COST"), techCost))

    local description = kTechIdInfo[techId].Description
    self.itemDescription:SetText(Locale.ResolveString(description))

    local bigPictureCoords = self:_GetPigPicturePixelCoordinatesForTechID(techId)
    self.bigPicture:SetTexturePixelCoordinates(GUIUnpackCoords(bigPictureCoords))

    local stats = kTechIdInfo[techId].Stats

    if stats then

        self.rangeBar:SetIsVisible(true)
        self.vsStructuresBar:SetIsVisible(true)
        self.vsLifeformBar:SetIsVisible(true)

        self.rangeText:SetIsVisible(true)
        self.vsStructuresText:SetIsVisible(true)
        self.vsLifeformsText:SetIsVisible(true)

        -- Grenades override the "range" label to instead say "AOE Range"
        self.rangeText:SetText(stats.RangeLabelOverride and Locale.ResolveString("BUYMENU_GRENADES_RANGE_OVERRIDE") or Locale.ResolveString("BUYMENU_RANGE"))

        self:_UpdateStatBar(self.rangeBar, stats.Range)
        self:_UpdateStatBar(self.vsLifeformBar, stats.LifeFormDamage)
        self:_UpdateStatBar(self.vsStructuresBar, stats.StructureDamage)
        self.itemDescription:SetPosition(Vector(0, self.itemDescriptionPositionY, 0))
        self.bigPicture:SetPosition(Vector(0, self.bigPicturePositionY, 0))

    else

        self.rangeBar:SetIsVisible(false)
        self.vsStructuresBar:SetIsVisible(false)
        self.vsLifeformBar:SetIsVisible(false)

        self.rangeText:SetIsVisible(false)
        self.vsStructuresText:SetIsVisible(false)
        self.vsLifeformsText:SetIsVisible(false)

        self.itemDescription:SetPosition(Vector(0, self.statBarsStartPosY, 0))
        self.bigPicture:SetPosition(Vector(0, self.bigPicturePositionY - self.bigPicturePositionYDiff, 0))

    end


    -- Update the "special" stuff.
    local techSpecial = kTechIdInfo[techId].Special
    if techSpecial then

        local specialDefinition = kSpecialDefinitions[techSpecial]
        self:_UpdateSpecialSection(specialDefinition)

        self.specialFrame:SetIsVisible(true)
    else
        self.specialFrame:SetIsVisible(false)
    end
	
    -- The modular configuration page borrows these items and leaves them hidden, so hand
    -- them back to the vanilla details section whenever an item tile is hovered. The exosuit
    -- tile is an ordinary vanilla tile again: it keeps its own picture, cost, stat bars and
    -- "SPECIAL: Massive" box, and only its click is different (see HandleItemClicked).
    self.itemTitle:SetIsVisible(true)
    self.costText:SetIsVisible(true)
    self.itemDescription:SetIsVisible(true)
    self.bigPicture:SetIsVisible(true)
    self.currentMoneyText:SetIsVisible(true)
    self.currentMoneyTextIcon:SetIsVisible(true)

end

function GUIMarineBuyMenu:_UpdateRealTimeElements(buttonTable, techId, techAvailable, currentMoney, techCost)

    self.currentMoneyText:SetText(string.format("%s %s", Locale.ResolveString("BUYMENU_CURRENTMONEY_PREFIX"), ToString(currentMoney)))

    -- Update button availability state
    local costText = buttonTable.CostText
    local teamText = buttonTable.TeamText
    local buttonItem = buttonTable.Button
    if techAvailable then

        buttonItem:SetColor(Color(1,1,1))

        local costTextColor = self.kCostTextColor_HasEnoughMoney
        if techCost <= 0 then
            costTextColor = self.kCostTextColor_Free
        elseif techCost > currentMoney then
            costTextColor = self.kCostTextColor_NotEnoughMoney
        end

        costText:SetColor(costTextColor)

    else

        buttonItem:SetColor(Color(0,0,0))
        costText:SetColor(self.kCostTextColor_Free) -- This is grey, but yeah the naming is weird.

    end

    local teamInfo = GetTeamInfoEntity(kTeam1Index)
    local techMapName = self:_GetMapNameForNetvar(techId)
    assert(techMapName)

    if teamInfo and techMapName then
        local netVarName = TeamInfo_GetUserTrackerNetvarName(techMapName)
        local numUsers = teamInfo[netVarName]
        assert(numUsers, string.format("Netvar %s does not exist in MarineTeamInfo!", netVarName))
        teamText:SetText(string.format("%d", numUsers))
        teamText:SetColor(ConditionalValue(numUsers > 0, self.kTeamTextColor_HasPlayers, self.kTeamTextColor_None))
    end


end

function GUIMarineBuyMenu:_UpdateBuyButtonAvailability(buttonTable, hoverStateChanged, useHoverTexture, buttonState)

    assert(buttonState ~= kButtonShowState.Uninitialized)

    local buttonItem = buttonTable.Button
    local techId = buttonTable.TechID
    local lastShowState = buttonTable.LastShowState
    local buttonShowStateDef = kButtonShowStateDefinitions[buttonState]

    if lastShowState ~= buttonState then

        local showError = buttonShowStateDef.ShowError
        buttonTable.ErrorFrame:SetIsVisible(showError)
        if showError then
            buttonTable.ErrorTextItem:SetText(Locale.ResolveString(buttonShowStateDef.Text))
            buttonTable.ErrorTextItem:SetColor(buttonShowStateDef.TextColor)

            -- Resize the error text frame to the size of the text, plus some padding
            local textScale = buttonTable.ErrorTextItem:GetScale().x
            local textWidth = buttonTable.ErrorTextItem:GetTextWidth(buttonTable.ErrorTextItem:GetText()) * textScale
            local newFrameWidth = textWidth + (self.kErrorFrameTextPadding * 2)
            buttonTable.ErrorFrame:SetSize(Vector(newFrameWidth, buttonTable.ErrorFrame:GetSize().y, 0))
        end

        buttonTable.LastShowState = buttonState

    end

    if hoverStateChanged then
        local coords = self:_GetButtonPixelCoordinatesForTechID(techId, useHoverTexture)
        buttonItem:SetTexturePixelCoordinates(GUIUnpackCoords(coords))
    end

end

function GUIMarineBuyMenu:Update(deltaTime)

    -- Update all of the buy buttons.
    self.hoveredBuyButton = nil
    local hoveredTechAvailable = false
    local hoveredCanAfford = false

    -- The prototype lab menu has two pages: the vanilla item list and the modular exosuit
    -- configuration page. Only one of them is on screen, and only the one on screen takes
    -- hover and clicks, so the item tiles are skipped entirely while the config page is up.
    local configPageActive = self:_GetIsExoConfigPageActive()

    for i = 1, (configPageActive and 0 or #self.buyButtons) do

        local buttonTable = self.buyButtons[i]
        local buttonItem = buttonTable.Button
        local techId = buttonTable.TechID
        assert(buttonItem)

        local hovering, changed = GetIsMouseOver(self, buttonItem)
        local techResearched = self:_GetResearchInfo(techId)
        local hasTable = MarineBuy_GetHas(techId)
        local techAlreadyEquipped = hasTable.Has
        local techOccupied = hasTable.Occupied

        local hostTechId = self.hostStructure:GetTechId()
        if self.lastHostTechId ~= hostTechId or not buttonTable.Initialized then

            local isHosted = false

            for _, supportedTechId in ipairs(self.hostStructure:GetItemList(Client.GetLocalPlayer())) do
                if supportedTechId == techId then
                    isHosted = true
                    break
                end
            end

            self.lastHostTechId = hostTechId
            buttonTable.Hosted = isHosted

        end

        local initEvent = ((techId == self.defaultTechId) and not self.initialized)
        local techAvailable = techResearched and not (techAlreadyEquipped or techOccupied) and buttonTable.Hosted and not buttonTable.Disabled
        local currentMoney = math.floor(PlayerUI_GetPersonalResources() * 10) / 10
        local useHoverTexture = hovering and techAvailable

        -- Update details section.
        local techCost = LookupTechData(techId, kTechDataCostKey, -1)
        if (hovering and changed) or initEvent then
            self:_SetDetailsSectionTechId(techId, techCost)
        end

        -- Get the button's new state, then update it.
        local buttonState = kButtonShowState.Available

        if buttonTable.Disabled then
            buttonState = kButtonShowState.Disabled
        elseif not buttonTable.Hosted then
            buttonState = kButtonShowState.NotHosted
        elseif techOccupied then
            buttonState = kButtonShowState.Occupied
        elseif techAlreadyEquipped then
            buttonState = kButtonShowState.Equipped
        elseif not techResearched then
            buttonState = kButtonShowState.Unresearched
        elseif techCost > currentMoney then
            buttonState = kButtonShowState.InsufficientFunds
        end

        self:_UpdateBuyButtonAvailability(buttonTable, changed, useHoverTexture, buttonState)
        self:_UpdateRealTimeElements(buttonTable, techId, techAvailable, currentMoney, techCost)

        if hovering then
            self.hoveredBuyButton = buttonTable
            hoveredTechAvailable = techAvailable
            hoveredCanAfford = currentMoney >= techCost
        end

    end

    -- Update hover item.
    if self.hoveredBuyButton then
        self.buyButtonHighlight:SetPosition(self.hoveredBuyButton.WeaponGroup:GetPosition() + self.hoveredBuyButton.Button:GetPosition() + Vector(-5, -5, 0))
        self.buyButtonHighlight:SetIsVisible(true)
        self.purchaseText:SetIsVisible(hoveredTechAvailable and hoveredCanAfford)
    else
        -- purchaseText is a child of buyButtonHighlight, so the line above hides it too.
        self.buyButtonHighlight:SetIsVisible(false)
    end

	self:_UpdateExoModularButtons()
	self:_UpdateExoModularVisibility()
end

function GUIMarineBuyMenu:_GetMapNameForNetvar(techId)

    local rawMapName = LookupTechData(techId, kTechDataMapName, nil)
    if rawMapName ~= Exo.kMapName then
        return rawMapName, false
    end

    -- Exos all have the same player class "exo", which have a weapon called "ExoWeaponHolder", which then holds two weapons. (Railgun/Minigun)
    -- At the moment we only have dual-wield of the same weapon.
    local overriddenMapName = rawMapName
    if techId == kTechId.DualRailgunExosuit then
        overriddenMapName = string.format("%s+%s", Railgun.kMapName, Railgun.kMapName)
    elseif techId == kTechId.DualMinigunExosuit then
        overriddenMapName = string.format("%s+%s", Minigun.kMapName, Minigun.kMapName)
    else
        assert(false, "Invalid exo techId for user tracker!")
    end

    return overriddenMapName

end

function GUIMarineBuyMenu:Uninitialize()
    
    GUIAnimatedScript.Uninitialize(self)

    if self.background then
        self.background:Destroy()
    end
    
    MouseTracker_SetIsVisible(false)
    
end

function GUIMarineBuyMenu:_GetResearchInfo(techId)

    local researched = MarineBuy_IsResearched(techId)
    local researchProgress = 0
    local researching = false

    if not researched then
        researchProgress = MarineBuy_GetResearchProgress(techId)
    end

    if not (researchProgress == 0) then
        researching = true
    end

    return researched, researchProgress, researching

end

local function HandleItemClicked(self)
    
    if self.hoveredBuyButton then
        
        local item = self.hoveredBuyButton

        -- The exosuit tile never buys anything. It is the entry point to the modular
        -- configuration page, where the suit is put together and bought. It stays clickable
        -- while the tech is unresearched or already worn, so a player can look at a build or
        -- come back to refit one; the page's own BUY button is what refuses in those cases.
        if item.TechID == kTechId.DualMinigunExosuit then

            if item.Hosted and not item.Disabled then
                self.exoConfigPageActive = true
                MarineBuy_OnUpgradeSelected()
                return true, false
            end

            return false, false

        end
		        
        local researched = self:_GetResearchInfo(item.TechID)
        local itemCost = MarineBuy_GetCosts(item.TechID)
        local canAfford = PlayerUI_GetPlayerResources() >= itemCost
        local hasItem = PlayerUI_GetHasItem(item.TechID)
	
        if not item.Disabled and researched and canAfford and not hasItem then
            
			MarineBuy_PurchaseItem(item.TechID)
			MarineBuy_OnClose()
			
			return true, true
        end
    end
	
    if self:_GetIsExoConfigPageActive() then
        -- BACK returns to the item list. Checked before everything else so it wins over any
        -- module button the button art happens to overlap.
        if self.modularExoBackButton and GetIsMouseOver(self, self.modularExoBackButton) then
            self.exoConfigPageActive = false
            MarineBuy_OnUpgradeDeselected()
            return true, false
        end
        -- ModularExo_HandleExoModularBuy drops a request it does not like without telling
        -- anyone, so closing the menu on a refused buy looks exactly like a successful one.
        -- Test the same three things the server does - the lab, the configuration and the
        -- price - and leave the page up when any of them fails. Note this is the lab test,
        -- not _GetResearchInfo: the button paint and the server both gate on the host being
        -- an ExoPrototypeLab, and the click has to agree with them.
        if GetIsMouseOver(self, self.modularExoBuyButton) and self.hostStructure:GetTechId() == kTechId.ExoPrototypeLab then

            local isValid, _, resourceCost = ModularExo_GetIsConfigValid(self.exoConfig)
            if isValid and PlayerUI_GetPlayerResources() >= self:_GetExoConfigPrice(resourceCost) then
                Client.SendNetworkMessage("ExoModularBuy", ModularExo_ConvertConfigToNetMessage(self.exoConfig))
                MarineBuy_OnClose()
                return true, true
            end

            return false, false

        end
        for buttonI, buttonData in ipairs(self.modularExoModuleButtonList) do
            if GetIsMouseOver(self, buttonData.buttonGraphic) then
                if buttonData.state == "enabled" then
                    self.modularExoDetailsModule = buttonData.moduleType
                    self.exoConfig[buttonData.slotType] = buttonData.moduleType
                    if buttonData.forceToDefaultConfig then
                        self.exoConfig[kExoModuleSlots.RightArm] = kExoModuleTypes.Minigun
                        self.exoConfig[kExoModuleSlots.LeftArm] = kExoModuleTypes.Claw
                        self.exoConfig[kExoModuleSlots.Utility] = kExoModuleTypes.None
                        self.exoConfig[kExoModuleSlots.Ability] = kExoModuleTypes.None
                    end
					-- THIS IS FOR WHEN THE RIGHT ARM CONTROLS THE UI!
                    --[[if buttonData.forceLeftToDual then
                        --self.exoConfig[kExoModuleSlots.LeftArm] = kExoModuleTypes.Claw
						self.exoConfig[kExoModuleSlots.LeftArm] = self.exoConfig[kExoModuleSlots.RightArm]
                    end]]
					if buttonData.forceRightToDual then
						self.exoConfig[kExoModuleSlots.RightArm] = self.exoConfig[kExoModuleSlots.LeftArm]
                    end
                    self:_RefreshExoModularButtons()
                end
            end
        end
    end
    return false, false

end

function GUIMarineBuyMenu:SendKeyEvent(key, down)

    local closeMenu = false
    local inputHandled = false

    if key == InputKey.MouseButton0 and self.mousePressed ~= down then

        self.mousePressed = down

        if down then
            inputHandled, closeMenu = HandleItemClicked(self)
        end

    end

    -- No matter what, this menu consumes MouseButton0/1.
    if key == InputKey.MouseButton0 or key == InputKey.MouseButton1 then
        inputHandled = true
    end

    if InputKey.Escape == key and not down then

        closeMenu = true
        inputHandled = true
        MarineBuy_OnClose()

    end

    if closeMenu then
        MarineBuy_Close()
    end

    return inputHandled
    
end

-- %%% New CBM Functions %%% --
local kResourceIconTexture = "ui/pres_icon_big.dds"
local kButtonTexture = "ui/marine_buymenu_button.dds"
local kMenuSelectionTexture = "ui/buymenu_marine/button_highlight.dds"
local kResourceIconWidth = (32)
local kResourceIconHeight = (32)
local kBackgroundTeamMarine = "ui/buymenu_marine/team_icon.dds"

local kFont = Fonts.kAgencyFB_Small

local kCloseButtonColorHover = Color(1, 1, 1, 1)
local kCloseButtonColor = Color(0.82, 0.98, 1, 1)
local kTextColor = Color(kMarineFontColor)

local kDisabledColor = Color(0.82, 0.98, 1, 0.5)
local kCannotBuyColor = Color(0.98, 0.24, 0.17, 1)
local kEnabledColor = Color(1, 1, 1, 1)

-- Modular exo configuration page layout. Unscaled coordinates inside the buy menu background
-- (prototypelab_background.dds is 1383x811). Everything in the modular block is placed
-- relative to self.rightSideRoot, which sits at kPrototypeLabRightSidePos in that
-- background. All tunables for the page live here.
--
-- The page replaces the vanilla item list rather than sitting next to it, so the whole left
-- column is free: the module details get the space the item list used to take, and the arm
-- columns move out to the edges of a wider configuration area.
--
--  x  0    60  105                 540                                     1360   1383
--     +-----------------------------------------------------------------------------+ y 0
--     |  (the frame art is chamfered here, nothing can sit higher on the left)       |
--     |        +--------+                                                           | 118
--     |        |  BACK  |         Left Arm      [         ]      Right Arm          | 170
--     |        +--------+         +---------+   [   exo   ]    +---------+          |
--     |   MODULE NAME             | 5 arms  |   [  model  ]    | 4 arms  |          | 200
--     |   COST: 20                |         |   [ preview ]    |         |          |
--     |   +40 ARMOR  -4% SPEED    +---------+   [         ]    +---------+          | 474
--     |                                     Core Module                             |
--     |   Description, up to seven   +-------------------------------------+        | 480
--     |   lines across the whole            Support Ability                         |
--     |   left column                +-------------------------------------+        | 610
--     |                                   [ res | BUY | armour, speed ]             | 710
--     +-----------------------------------------------------------------------------+ 811
--
-- The configuration area is everything right of the module details column.
local kConfigAreaOffsetX = -40      -- background x 540, where the vanilla item list ended
local kConfigAreaWidth = 820        -- 540 .. 1360, out to the right edge of the frame
local kConfigAreaHeight = 770       -- 38 .. 808

-- Slot panels. Every panel is a labelled group: a title sitting above a framed box of
-- buttons, the way the vanilla WEAPONS / UTILITY groups read.
local kSlotPanelPadding = 8         -- inside a slot panel, around its buttons
local kSlotTitleOffsetY = -36       -- slot label, above its panel
local kSlotTitleFontSize = 36

local kArmColumnYp = 0.0494         -- 76, top of both vertical arm columns (the slot titles
                                    -- sit 36 above that, clear of the frame's top edge)
local kUtilityRowYp = 0.574         -- 480, core module row
local kAbilityRowYp = 0.7429        -- 610, support ability row
local kBuyButtonYp = 0.8727         -- 710, buy button / cost / armour readout, bottom centre

-- Same size family as the vanilla weapon buttons (441x114 cells out of buttons.dds), scaled
-- so two columns plus the model preview fit across the config area. The height is as large
-- as an arm column plus two module rows plus the buy row can be inside the frame.
local kModuleButtonSize = Vector(230, 70, 0)    -- button in a vertical arm column
local kModuleButtonSpacingY = 8                 -- breathing room between stacked buttons
local kRowButtonSize = Vector(192, 70, 0)       -- button in a horizontal module row
local kRowButtonSpacingX = 8
local kBuyButtonSize = Vector(720, 84, 0)

-- Inside a module button: the name runs along the top over the full width, the cost and the
-- team count sit bottom left, the module picture bottom right. Nothing else shares the name's
-- row, so a long label can never land on an icon.
local kModuleButtonPaddingX = 12
local kModuleButtonPaddingY = 4
local kModuleLabelFontSize = 26
local kModuleStatFontSize = 26
local kModuleStatIconSize = 22
local kModuleStatTextGap = 4
local kModuleTeamCountOffsetX = 84  -- team icon, right of the cost icon and its number
local kWeaponImageSize = Vector(68, 34, 0)  -- 2:1, the shape of an inventory icon cell
local kUtilityImageSize = Vector(34, 34, 0) -- square, the shape of a build menu icon

-- Centre column: the exo preview fills whatever the two arm columns leave between them,
-- worked out from the panels themselves once they are built.
local kExoModelPreviewMargin = 10

-- Module details own the left column, in the space the vanilla item list takes on the list
-- page. The whole column is free while the configuration page is up, so a description gets a
-- readable measure instead of three cramped lines. Background coordinates.
local kExoDetailsPos = Vector(60, 200, 0)
local kExoDetailsBoxWidth = 470             -- 60 .. 530, clear of the config area at 540
local kExoDetailsTitleY = 0
local kExoDetailsCostY = 50
local kExoDetailsStatsY = 88
local kExoDetailsDescY = 130
local kExoDetailsDescMaxLines = 7
local kExoDetailsTitleFontSize = 40
local kExoDetailsTextFontSize = 28
local kExoDetailsDescFontSize = 26   -- a notch under the stat line, so a description reads as body text

-- Vanilla values of the details items, restored when the modular panel is hidden again.
local kVanillaDetailTitleFontSize = 55
local kVanillaDetailCostFontSize = 60
local kVanillaDetailDescFontSize = 33
local kVanillaDetailDescClipWidth = 687

-- BACK button: top of the freed left column, above the module details, inside the frame's
-- upper left chamfer line.
local kExoConfigBackButtonPos = Vector(105, 118, 0)
local kExoConfigBackButtonSize = Vector(190, 52, 0)

local kSlotPanelBackgroundColor = Color(0, 0, 0, 0.6)
local kModuleButtonHoverColor = Color(0, 0.7, 1, 1)
-- Cannot pay for this module right now. Vanilla greys an item it will not sell and turns the
-- cost red instead of hiding it (see the UNAVAILABLE tiles in the armoury menu), so a module
-- gets the same treatment: grey name and picture, red cost, no hover, click ignored.
local kModuleUnaffordableColor = Color(0.55, 0.6, 0.64, 1)

-- Agency FB has no fixed advance and a module label has to sit inside a fixed button, so
-- measure what was actually set and step the size down until it fits.
local kMinFittedFontSize = 18
local function FitTextToWidth(item, fontFamily, fontSize, maxWidth)

    while fontSize > kMinFittedFontSize do

        GUIMakeFontScale(item, fontFamily, fontSize)

        if item:GetTextWidth(item:GetText()) * item:GetScale().x <= maxWidth then
            return
        end

        fontSize = fontSize - 2

    end

    GUIMakeFontScale(item, fontFamily, kMinFittedFontSize)

end

-- Arm weapons are vertical columns pinned to the left and right edge of the panel with the
-- exo model between them; the two module slots are horizontal rows centred underneath.
--
-- moduleOrder is the display order of a slot, listed explicitly instead of falling out of
-- kExoModuleTypes' declaration order: the claw has to sit at the top of the left column
-- because it is the base arm, and the flamethrower has to be in the right column even
-- though it is the last member of the enum. Modules the slot cannot take are still filtered
-- out at build time, so listing one here that does not fit is harmless.
GUIMarineBuyMenu.kExoSlotData = {
    [kExoModuleSlots.LeftArm]  = {
        label      = "EXO_MODULESLOT_LEFT_ARM",
        xp         = 0.0,
        yp         = kArmColumnYp,
        anchorX    = GUIItem.Left,
        isRow      = false,
        moduleOrder = {
            kExoModuleTypes.Claw,
            kExoModuleTypes.Minigun,
            kExoModuleTypes.Railgun,
            kExoModuleTypes.PlasmaLauncher,
            kExoModuleTypes.Flamethrower,
        },
        makeButton = function(self, moduleType, moduleTypeData, offsetX, offsetY)
            return self:MakeModuleButton(moduleType, moduleTypeData, offsetX, offsetY, kExoModuleSlots.LeftArm, false)
        end,
    },
    [kExoModuleSlots.RightArm] = {
        label      = "EXO_MODULESLOT_RIGHT_ARM",
        xp         = 1.0,
        yp         = kArmColumnYp,
        anchorX    = GUIItem.Right,
        isRow      = false,
        moduleOrder = {
            kExoModuleTypes.Minigun,
            kExoModuleTypes.Railgun,
            kExoModuleTypes.PlasmaLauncher,
            kExoModuleTypes.Flamethrower,
        },
        makeButton = function(self, moduleType, moduleTypeData, offsetX, offsetY)
            return self:MakeModuleButton(moduleType, moduleTypeData, offsetX, offsetY, kExoModuleSlots.RightArm, false)
        end,
    },

    [kExoModuleSlots.Utility]  = {
        label      = "EXO_MODULESLOT_UTILITY",
        xp         = 0.5,
        yp         = kUtilityRowYp,
        anchorX    = GUIItem.Middle,
        isRow      = true,
        moduleOrder = {
            kExoModuleTypes.None,
            kExoModuleTypes.Thrusters,
            kExoModuleTypes.EjectionSeat,
            kExoModuleTypes.Armor,
        },
        makeButton = function(self, moduleType, moduleTypeData, offsetX, offsetY)
            return self:MakeModuleButton(moduleType, moduleTypeData, offsetX, offsetY, kExoModuleSlots.Utility, true)
        end,
    },
    [kExoModuleSlots.Ability]  = {
        label      = "EXO_MODULESLOT_ABILITY",
        xp         = 0.5,
        yp         = kAbilityRowYp,
        anchorX    = GUIItem.Middle,
        isRow      = true,
        moduleOrder = {
            kExoModuleTypes.None,
            kExoModuleTypes.NanoShield,
            kExoModuleTypes.CatPack,
            kExoModuleTypes.NanoRepair,
        },
        makeButton = function(self, moduleType, moduleTypeData, offsetX, offsetY)
            return self:MakeModuleButton(moduleType, moduleTypeData, offsetX, offsetY, kExoModuleSlots.Ability, true)
        end,
    },
}

function GUIMarineBuyMenu:_InitializeExoModularButtons()
    local canHaveDualArm = true --GetHasTech(self,kTechId.DualMinigunTech)
	local canHaveUtilityModules = true --GetHasTech(self,kTechId.CoresExosuitTech)

    self.activeExoConfig = nil
    local player = Client.GetLocalPlayer()
    if player and player:isa("Exo") then
        self.activeExoConfig = ModularExo_ConvertNetMessageToConfig(player)
        -- isValid, badReason, resourceCost
        local _, _, resourceCost = ModularExo_GetIsConfigValid(self.activeExoConfig)
        self.activeExoConfigResCost = resourceCost

        -- A copy, not the table itself: the page edits self.exoConfig in place (and
        -- _RefreshExoModularButtons swaps modules in and out of it while pricing), which
        -- would otherwise rewrite the record of what the player is already wearing.
        self.exoConfig = {
            [kExoModuleSlots.RightArm] = self.activeExoConfig[kExoModuleSlots.RightArm],
            [kExoModuleSlots.LeftArm]  = self.activeExoConfig[kExoModuleSlots.LeftArm],
            [kExoModuleSlots.Utility]  = self.activeExoConfig[kExoModuleSlots.Utility],
            [kExoModuleSlots.Ability]  = self.activeExoConfig[kExoModuleSlots.Ability],
        }
    else
        self.activeExoConfig = {}
        self.activeExoConfigResCost = 0
        self.exoConfig = {
            [kExoModuleSlots.RightArm] = kExoModuleTypes.Minigun,
            [kExoModuleSlots.LeftArm]  = kExoModuleTypes.Claw,
            [kExoModuleSlots.Utility]  = kExoModuleTypes.None,
            [kExoModuleSlots.Ability]  = kExoModuleTypes.None,
        }
    end

    self.modularExoConfigActive = false
    self.modularExoGraphicItemsToDestroyList = {}
    self.modularExoModuleButtonList = {}
    self.exoButtonsPainted = false
    
    local kFontSize = 40
    -------UPGRADE/BUY Button ---
    local kButtonWidth = 220
    local bPadding = 0
    self.modularExoBuyButtonBackground = self:CreateAnimatedGraphicItem()
    table.insert(self.modularExoGraphicItemsToDestroyList, self.modularExoBuyButtonBackground)
    self.modularExoBuyButtonBackground:SetIsScaling(false)
    
    self.modularExoBuyButtonBackground:SetSize(Vector(kBuyButtonSize.x + bPadding * 2, kBuyButtonSize.y + bPadding * 2, 0))
    self.modularExoBuyButtonBackground:SetPosition(Vector(kConfigAreaOffsetX + kConfigAreaWidth/2.0 - kBuyButtonSize.x/2.0, kBuyButtonYp * kConfigAreaHeight, 0))
    self.modularExoBuyButtonBackground:SetTexture(kButtonTexture)
    self.modularExoBuyButtonBackground:SetColor(kSlotPanelBackgroundColor)
    self.modularExoBuyButtonBackground:SetOptionFlag(GUIItem.CorrectScaling)
    self.rightSideRoot:AddChild(self.modularExoBuyButtonBackground)
    
    self.modularExoBuyButton = self:CreateAnimatedGraphicItem()
    self.modularExoBuyButton:SetIsScaling(false)
    self.modularExoBuyButton:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.modularExoBuyButton:SetSize(kBuyButtonSize)
    self.modularExoBuyButton:SetPosition(Vector(bPadding, bPadding, 0))
    self.modularExoBuyButton:SetTexture(kMenuSelectionTexture)
    self.modularExoBuyButton:SetLayer(kGUILayerMarineBuyMenu)
    self.modularExoBuyButton:SetOptionFlag(GUIItem.CorrectScaling)
    self.modularExoBuyButtonBackground:AddChild(self.modularExoBuyButton)
    
    self.modularExoBuyButtonText = self:CreateAnimatedTextItem()
    self.modularExoBuyButtonText:SetIsScaling(false)
    self.modularExoBuyButtonText:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.modularExoBuyButtonText:SetPosition(Vector(0, 0, 0))
    self.modularExoBuyButtonText:SetFontName(kFont)
    self.modularExoBuyButtonText:SetTextAlignmentX(GUIItem.Align_Center)
    self.modularExoBuyButtonText:SetTextAlignmentY(GUIItem.Align_Center)
    self.modularExoBuyButtonText:SetText(Locale.ResolveString("BUY"))
    self.modularExoBuyButtonText:SetFontIsBold(true)
    self.modularExoBuyButtonText:SetColor(kCloseButtonColor)
    self.modularExoBuyButtonText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.modularExoBuyButtonText, "kAgencyFB", kFontSize + 12)
    self.modularExoBuyButton:AddChild(self.modularExoBuyButtonText)
    
	self.modularExoCostText = self:CreateAnimatedTextItem()
    self.modularExoCostText:SetIsScaling(false)
    self.modularExoCostText:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.modularExoCostText:SetPosition(Vector(kResourceIconWidth*1.5 + 25, 0, 0))
    self.modularExoCostText:SetFontName(kFont)
    self.modularExoCostText:SetTextAlignmentX(GUIItem.Align_Min)
    self.modularExoCostText:SetTextAlignmentY(GUIItem.Align_Center)
    self.modularExoCostText:SetText("0")
    self.modularExoCostText:SetFontIsBold(true)
    self.modularExoCostText:SetColor(kTextColor)
    self.modularExoCostText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.modularExoCostText, "kAgencyFB", kFontSize + 6)
    self.modularExoBuyButton:AddChild(self.modularExoCostText)
    
    self.modularExoCostIcon = self:CreateAnimatedGraphicItem()
    self.modularExoCostIcon:SetIsScaling(false)
    self.modularExoCostIcon:SetSize(Vector(kResourceIconWidth*1.5, kResourceIconHeight*1.5, 0))
    self.modularExoCostIcon:SetAnchor(GUIItem.Left, GUIItem.Center)
    self.modularExoCostIcon:SetPosition(Vector(20, -kResourceIconWidth * 0.75, 0))
    self.modularExoCostIcon:SetTexture(kResourceIconTexture)
    self.modularExoCostIcon:SetColor(kTextColor)
    self.modularExoCostIcon:SetOptionFlag(GUIItem.CorrectScaling)
    self.modularExoBuyButton:AddChild(self.modularExoCostIcon)

    self.modularExoArmorText = self:CreateAnimatedTextItem()
    self.modularExoArmorText:SetIsScaling(false)
    self.modularExoArmorText:SetAnchor(GUIItem.Right, GUIItem.Center)
    self.modularExoArmorText:SetPosition(Vector(-20, 0, 0))
    self.modularExoArmorText:SetFontName(kFont)
    self.modularExoArmorText:SetTextAlignmentX(GUIItem.Align_Max)
    self.modularExoArmorText:SetTextAlignmentY(GUIItem.Align_Center)
    self.modularExoArmorText:SetText("")
    self.modularExoArmorText:SetColor(kTextColor)
    self.modularExoArmorText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.modularExoArmorText, "kAgencyFB", kFontSize)
    self.modularExoBuyButton:AddChild(self.modularExoArmorText)

    -- Details section. Name, cost and description reuse the vanilla itemTitle / costText /
    -- itemDescription items; only the armour/weight line has no vanilla counterpart, so it
    -- gets its own item here. All four are moved into the exosuit details box by
    -- _UpdateExoModularVisibility, so the position set here does not matter.
    self.modularExoDetailsModule = self.exoConfig[kExoModuleSlots.LeftArm]
    self.modularExoDetailStats = self:CreateAnimatedTextItem()
    table.insert(self.modularExoGraphicItemsToDestroyList, self.modularExoDetailStats)
    self.modularExoDetailStats:SetIsScaling(false)
    self.modularExoDetailStats:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.modularExoDetailStats:SetPosition(Vector(0, 0, 0))
    self.modularExoDetailStats:SetFontName(kFont)
    self.modularExoDetailStats:SetTextAlignmentX(GUIItem.Align_Min)
    self.modularExoDetailStats:SetTextAlignmentY(GUIItem.Align_Min)
    self.modularExoDetailStats:SetText("")
    self.modularExoDetailStats:SetColor(GUIMarineBuyMenu.kSpecialTextContentColor)
    self.modularExoDetailStats:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.modularExoDetailStats, "kAgencyFB", kExoDetailsTextFontSize)
    self.rightSideRoot:AddChild(self.modularExoDetailStats)

    --BUY/UPGRADE BUTTON ENDS HERE

    -- BACK button: leaves the configuration page and puts the vanilla item list back. Built
    -- from the same parts as the buy button so the two read as one control set.
    self.modularExoBackButtonBackground = self:CreateAnimatedGraphicItem()
    table.insert(self.modularExoGraphicItemsToDestroyList, self.modularExoBackButtonBackground)
    self.modularExoBackButtonBackground:SetIsScaling(false)
    self.modularExoBackButtonBackground:SetSize(kExoConfigBackButtonSize)
    self.modularExoBackButtonBackground:SetPosition(kExoConfigBackButtonPos - self.rightSideRoot:GetPosition())
    self.modularExoBackButtonBackground:SetTexture(kButtonTexture)
    self.modularExoBackButtonBackground:SetColor(kSlotPanelBackgroundColor)
    self.modularExoBackButtonBackground:SetOptionFlag(GUIItem.CorrectScaling)
    self.rightSideRoot:AddChild(self.modularExoBackButtonBackground)

    self.modularExoBackButton = self:CreateAnimatedGraphicItem()
    self.modularExoBackButton:SetIsScaling(false)
    self.modularExoBackButton:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.modularExoBackButton:SetSize(kExoConfigBackButtonSize)
    self.modularExoBackButton:SetPosition(Vector(0, 0, 0))
    self.modularExoBackButton:SetTexture(kMenuSelectionTexture)
    self.modularExoBackButton:SetLayer(kGUILayerMarineBuyMenu)
    self.modularExoBackButton:SetOptionFlag(GUIItem.CorrectScaling)
    self.modularExoBackButtonBackground:AddChild(self.modularExoBackButton)

    self.modularExoBackButtonText = self:CreateAnimatedTextItem()
    self.modularExoBackButtonText:SetIsScaling(false)
    self.modularExoBackButtonText:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.modularExoBackButtonText:SetPosition(Vector(0, 0, 0))
    self.modularExoBackButtonText:SetFontName(kFont)
    self.modularExoBackButtonText:SetTextAlignmentX(GUIItem.Align_Center)
    self.modularExoBackButtonText:SetTextAlignmentY(GUIItem.Align_Center)
    self.modularExoBackButtonText:SetText(Locale.ResolveString("BACK"))
    self.modularExoBackButtonText:SetFontIsBold(true)
    self.modularExoBackButtonText:SetColor(kCloseButtonColor)
    self.modularExoBackButtonText:SetOptionFlag(GUIItem.CorrectScaling)
    GUIMakeFontScale(self.modularExoBackButtonText, "kAgencyFB", kFontSize)
    self.modularExoBackButton:AddChild(self.modularExoBackButtonText)
    local slotData
    local panelRects = {}
    if not canHaveUtilityModules then
        slotData = {
            [kExoModuleSlots.RightArm] = GUIMarineBuyMenu.kExoSlotData[kExoModuleSlots.RightArm],
            [kExoModuleSlots.LeftArm] = GUIMarineBuyMenu.kExoSlotData[kExoModuleSlots.LeftArm],
			}
	else
		slotData = GUIMarineBuyMenu.kExoSlotData
    end
	
    for slotType, slotGUIDetails in pairs(slotData) do
        local panelBackground = self:CreateAnimatedGraphicItem()
        table.insert(self.modularExoGraphicItemsToDestroyList, panelBackground)
        panelBackground:SetIsScaling(false)
        panelBackground:SetTexture(kButtonTexture)
        panelBackground:SetColor(kSlotPanelBackgroundColor)
        panelBackground:SetOptionFlag(GUIItem.CorrectScaling)
        local panelSize
        
        local slotTypeData = kExoModuleSlotsData[slotType]
        
        local panelTitle = self:CreateAnimatedTextItem()
        panelTitle:SetIsScaling(false)
        panelTitle:SetFontName(kFont)
        panelTitle:SetFontIsBold(true)
        panelTitle:SetPosition(Vector(0, kSlotTitleOffsetY, 0))
		panelTitle:SetAnchor(GUIItem.Center, GUIItem.Top)
		panelTitle:SetTextAlignmentX(GUIItem.Align_Center)			
        panelTitle:SetTextAlignmentY(GUIItem.Align_Min)
        panelTitle:SetColor(kTextColor)
        panelTitle:SetOptionFlag(GUIItem.CorrectScaling)
        panelTitle:SetText(Locale.ResolveString(slotGUIDetails.label))
        GUIMakeFontScale(panelTitle, "kAgencyFB", kSlotTitleFontSize)
        panelBackground:AddChild(panelTitle)
        local padding = kSlotPanelPadding
        local startOffsetX = padding
        local startOffsetY = padding
        local offsetX, offsetY = startOffsetX, startOffsetY
        -- Explicit per-slot order (see kExoSlotData.moduleOrder). Iterating kExoModuleTypes
        -- instead would tie the on-screen order to the enum's declaration order.
        for _, moduleType in ipairs(slotGUIDetails.moduleOrder) do
            local moduleTypeData = kExoModuleTypesData[moduleType]
            local isSameType = (moduleTypeData and moduleTypeData.category == slotTypeData.category)
            if moduleType == kExoModuleTypes.None and not slotTypeData.required then
                isSameType = true
                moduleTypeData = {}
            end
            -- excludes claw on secondary weapon (right) slot
            if isSameType and slotTypeData.category == kExoModuleCategories.Weapon and moduleTypeData.leftArmOnly and kExoModuleSlots.RightArm == slotType then
                isSameType = false
            end
            -- excludes right-arm-only modules (flamethrower) on the left slot
            if isSameType and slotTypeData.category == kExoModuleCategories.Weapon and moduleTypeData.rightArmOnly and kExoModuleSlots.LeftArm == slotType then
                isSameType = false
            end
						
            if isSameType and slotTypeData.category == kExoModuleCategories.Weapon and moduleTypeData.singleRightArmOnly and kExoModuleSlots.LeftArm == slotType and not canHaveDualArm then
                isSameType = false
            end
			
            if isSameType then
                local buttonGraphic, newOffsetX, newOffsetY = slotGUIDetails.makeButton(self, moduleType, moduleTypeData, offsetX, offsetY)
                offsetX, offsetY = newOffsetX, newOffsetY
                panelBackground:AddChild(buttonGraphic)
            end
        end
        -- The button layout leaves a trailing gap behind the last button; trim it so the
        -- panel hugs its contents, and give an empty slot a one-button sized box.
        local slotButtonSize = slotGUIDetails.isRow and kRowButtonSize or kModuleButtonSize
        if offsetX > startOffsetX then
            offsetX = offsetX - kRowButtonSpacingX
        else
            offsetX = offsetX + slotButtonSize.x
        end

        if offsetY > startOffsetY then
            offsetY = offsetY - kModuleButtonSpacingY
        else
            offsetY = offsetY + slotButtonSize.y
        end
        panelSize = Vector(offsetX + padding, offsetY + padding, 0)
        
        panelBackground:SetSize(panelSize)
        local panelX = kConfigAreaOffsetX + slotGUIDetails.xp * kConfigAreaWidth
        local panelY = slotGUIDetails.yp * kConfigAreaHeight
        if slotGUIDetails.anchorX == GUIItem.Right then
            panelX = panelX - panelSize.x
        elseif slotGUIDetails.anchorX == GUIItem.Middle then
            panelX = panelX - panelSize.x / 2
        end
        
        panelBackground:SetPosition(Vector(panelX, panelY, 0))
        self.rightSideRoot:AddChild(panelBackground)
        panelRects[slotType] = { x = panelX, y = panelY, size = panelSize }
    end

    -- The exo model preview fills whatever gap the two arm columns leave between them,
    -- keeping the big picture's own aspect. Derived from the panels instead of hard coded so
    -- it follows any change to the button sizes above.
    local leftPanel = panelRects[kExoModuleSlots.LeftArm]
    local rightPanel = panelRects[kExoModuleSlots.RightArm]
    if leftPanel and rightPanel and self.bigPictureDefaultSize then

        local gapX = leftPanel.x + leftPanel.size.x + kExoModelPreviewMargin
        local gapWidth = (rightPanel.x - kExoModelPreviewMargin) - gapX
        local gapHeight = math.max(leftPanel.size.y, rightPanel.size.y)
        local aspect = self.bigPictureDefaultSize.y / self.bigPictureDefaultSize.x

        local previewWidth = gapWidth
        local previewHeight = previewWidth * aspect
        if previewHeight > gapHeight then
            previewHeight = gapHeight
            previewWidth = previewHeight / aspect
        end

        self.exoModelPreviewSize = Vector(previewWidth, previewHeight, 0)
        self.exoModelPreviewPos = Vector(gapX + (gapWidth - previewWidth) / 2,
                                         leftPanel.y + (gapHeight - previewHeight) / 2, 0)

    end

    -- The details items hang off rightSideRoot, the details box is placed in the background.
    self.exoDetailsBoxPos = kExoDetailsPos - self.rightSideRoot:GetPosition()

    -- _UpdateExoModularVisibility re-asserts these four positions on every frame the page
    -- is up, so build the vectors here instead of allocating eight of them per frame.
    self.exoDetailsTitlePos = self.exoDetailsBoxPos + Vector(0, kExoDetailsTitleY, 0)
    self.exoDetailsCostPos  = self.exoDetailsBoxPos + Vector(0, kExoDetailsCostY, 0)
    self.exoDetailsStatsPos = self.exoDetailsBoxPos + Vector(0, kExoDetailsStatsY, 0)
    self.exoDetailsDescPos  = self.exoDetailsBoxPos + Vector(0, kExoDetailsDescY, 0)

end

-- isRow: true lays the slot's buttons out left to right (a module row), false stacks them
-- top to bottom (an arm column). Both use the same content layout so an arm and a core
-- module read alike; only the button size and the picture shape differ. The name owns the
-- top row on its own and is fitted to the button, so it can never land on an icon.
function GUIMarineBuyMenu:MakeModuleButton(moduleType, moduleTypeData, offsetX, offsetY, slotType, isRow)

    local moduleTypeGUIDetails = GUIMarineBuyMenu.kExoModuleData[moduleType]
    local buttonSize = isRow and kRowButtonSize or kModuleButtonSize
    local imageSize = isRow and kUtilityImageSize or kWeaponImageSize
    local padX = kModuleButtonPaddingX
    local padY = kModuleButtonPaddingY

    local buttonGraphic = self:CreateAnimatedGraphicItem()
    table.insert(self.modularExoGraphicItemsToDestroyList, buttonGraphic)
    buttonGraphic:SetIsScaling(false)
    buttonGraphic:SetSize(buttonSize)
    buttonGraphic:SetAnchor(GUIItem.Left, GUIItem.Top)
    buttonGraphic:SetPosition(Vector(offsetX, offsetY, 0))
    buttonGraphic:SetTexture(kMenuSelectionTexture)
    buttonGraphic:SetOptionFlag(GUIItem.CorrectScaling)

    local label = self:CreateAnimatedTextItem()
    label:SetIsScaling(false)
    label:SetFontName(kFont)
    label:SetAnchor(GUIItem.Left, GUIItem.Top)
    label:SetTextAlignmentX(GUIItem.Align_Min)
    label:SetTextAlignmentY(GUIItem.Align_Min)
    label:SetPosition(Vector(padX, padY, 0))
    label:SetColor(kTextColor)
    label:SetText(Locale.ResolveString(moduleTypeGUIDetails.label))
    label:SetOptionFlag(GUIItem.CorrectScaling)
    FitTextToWidth(label, "kAgencyFB", kModuleLabelFontSize, buttonSize.x - padX * 2)
    buttonGraphic:AddChild(label)

    -- Module picture, bottom right: below the name, right of the numbers.
    local image = self:CreateAnimatedGraphicItem()
    image:SetIsScaling(false)
    image:SetAnchor(GUIItem.Right, GUIItem.Bottom)
    image:SetSize(imageSize)
    image:SetPosition(Vector(-imageSize.x - padX, -imageSize.y - padY, 0))
    image:SetTexture(moduleTypeGUIDetails.image)
    image:SetTexturePixelCoordinates(unpack(moduleTypeGUIDetails.imageTexCoords))
    image:SetColor(Color(1, 1, 1, 1))
    image:SetOptionFlag(GUIItem.CorrectScaling)
    buttonGraphic:AddChild(image)

    local resourceCost = moduleTypeData.resourceCost or 0
    local icon, cost, teamIcon, teamNumber

    if resourceCost > 0 then

        icon = self:CreateAnimatedGraphicItem()
        icon:SetIsScaling(false)
        icon:SetAnchor(GUIItem.Left, GUIItem.Bottom)
        icon:SetSize(Vector(kModuleStatIconSize, kModuleStatIconSize, 0))
        icon:SetPosition(Vector(padX, -kModuleStatIconSize - padY, 0))
        icon:SetTexture(kResourceIconTexture)
        icon:SetColor(kTextColor)
        icon:SetOptionFlag(GUIItem.CorrectScaling)
        buttonGraphic:AddChild(icon)

        cost = self:CreateAnimatedTextItem()
        cost:SetIsScaling(false)
        cost:SetFontName(kFont)
        cost:SetAnchor(GUIItem.Left, GUIItem.Bottom)
        cost:SetTextAlignmentX(GUIItem.Align_Min)
        cost:SetTextAlignmentY(GUIItem.Align_Max)
        cost:SetPosition(Vector(padX + kModuleStatIconSize + kModuleStatTextGap, -padY, 0))
        cost:SetColor(kTextColor)
        cost:SetText(tostring(resourceCost))
        cost:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(cost, "kAgencyFB", kModuleStatFontSize)
        buttonGraphic:AddChild(cost)

    end

    if kExoModuleSlotsData[slotType].category == kExoModuleCategories.Weapon then

        teamIcon = self:CreateAnimatedGraphicItem()
        teamIcon:SetIsScaling(false)
        teamIcon:SetAnchor(GUIItem.Left, GUIItem.Bottom)
        teamIcon:SetSize(Vector(kModuleStatIconSize, kModuleStatIconSize, 0))
        teamIcon:SetPosition(Vector(kModuleTeamCountOffsetX, -kModuleStatIconSize - padY, 0))
        teamIcon:SetTexture(kBackgroundTeamMarine)
        teamIcon:SetColor(kTextColor)
        teamIcon:SetOptionFlag(GUIItem.CorrectScaling)
        buttonGraphic:AddChild(teamIcon)

        teamNumber = self:CreateAnimatedTextItem()
        teamNumber:SetIsScaling(false)
        teamNumber:SetFontName(kFont)
        teamNumber:SetAnchor(GUIItem.Left, GUIItem.Bottom)
        teamNumber:SetTextAlignmentX(GUIItem.Align_Min)
        teamNumber:SetTextAlignmentY(GUIItem.Align_Max)
        teamNumber:SetPosition(Vector(kModuleTeamCountOffsetX + kModuleStatIconSize + kModuleStatTextGap, -padY, 0))
        teamNumber:SetColor(kTextColor)
        teamNumber:SetText("0")
        teamNumber:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(teamNumber, "kAgencyFB", kModuleStatFontSize)
        buttonGraphic:AddChild(teamNumber)

    end

    if isRow then
        offsetX = offsetX + buttonSize.x + kRowButtonSpacingX
    else
        offsetY = offsetY + buttonSize.y + kModuleButtonSpacingY
    end

    table.insert(self.modularExoModuleButtonList, {
        slotType        = slotType,
        moduleType      = moduleType,
        buttonGraphic   = buttonGraphic,
        weaponLabel     = label,
        weaponImage     = image,
        costLabel       = cost,
        costIcon        = icon,
        teamNumber      = teamNumber,
        teamIcon        = teamIcon,
        thingsToRecolor = { label, image },
    })
    return buttonGraphic, offsetX, offsetY

end

-- Which of the prototype lab menu's two pages is up. self.exoConfigPageActive is the whole
-- state: false (or nil) is the vanilla item list, true is the modular configuration page.
-- It is set to true by clicking the exosuit tile and by opening the menu while already in an
-- exo, and back to false by the BACK button. Everything else - what is drawn, what takes
-- hover, and where a click goes - reads it through here.
function GUIMarineBuyMenu:_GetIsExoConfigPageActive()
    return self.modularExoGraphicItemsToDestroyList ~= nil and self.exoConfigPageActive == true
end

-- Shows/hides the modular exo configuration page. It is a page of its own: while it is up the
-- vanilla item list is hidden and the page owns the whole menu. The vanilla details items
-- (title, cost and description) plus the modular armour/weight line move into the left column
-- the item list left free and are filled from the hovered module, the stat bars and the
-- resource readout go away, and the big picture item is reused as the exo model preview
-- between the arm columns.
function GUIMarineBuyMenu:_UpdateExoModularVisibility()

    if not self.modularExoGraphicItemsToDestroyList then
        return
    end

    local showModular = self:_GetIsExoConfigPageActive()

    self.hoveringExo = showModular
    self.modularExoConfigActive = showModular

    if self.itemListGroup then
        self.itemListGroup:SetIsVisible(not showModular)
    end

    for _, element in ipairs(self.modularExoGraphicItemsToDestroyList) do
        element:SetIsVisible(showModular)
    end

    -- Items with no module equivalent. The title / cost / description are deliberately not
    -- in here: the modular panel writes module info into them instead.
    self.vanillaDetailItems = self.vanillaDetailItems or
    {
        self.currentMoneyText, self.currentMoneyTextIcon,
        self.rangeText, self.rangeBar,
        self.vsLifeformsText, self.vsLifeformBar,
        self.vsStructuresText, self.vsStructuresBar,
    }

    if self.modularExoPreviewActive ~= showModular then

        local leavingConfigPage = self.modularExoPreviewActive == true
        self.modularExoPreviewActive = showModular

        -- Both directions of the transition rewrite the details text (vanilla hovers on
        -- the way out, _SetDetailsSectionTechId below), so the module the box last showed
        -- no longer describes what is on screen. Force the next frame to repaint it.
        self.exoDetailsShownModule = nil

        -- Remember where vanilla put the details items so they can go back.
        self.vanillaDetailsLayout = self.vanillaDetailsLayout or
        {
            titlePos = self.itemTitle:GetPosition(),
            costPos  = self.costText:GetPosition(),
            descPos  = self.itemDescription:GetPosition(),
        }

        -- The big resource icon hanging off costText is sized for the vanilla 60pt cost
        -- line and dwarfs the module details, so it only belongs to the vanilla layout.
        self.costTextIcon:SetIsVisible(not showModular)

        if showModular then

            GUIMakeFontScale(self.itemTitle, "kAgencyFBBold", kExoDetailsTitleFontSize)
            GUIMakeFontScale(self.costText, "kAgencyFB", kExoDetailsTextFontSize)
            self.itemDescription:SetTextClipped(true, kExoDetailsBoxWidth, -1)
            GUIMakeFontScale(self.itemDescription, "kAgencyFB", kExoDetailsDescFontSize)

            local coords = self:_GetPigPicturePixelCoordinatesForTechID(kTechId.DualMinigunExosuit)
            self.bigPicture:SetTexturePixelCoordinates(GUIUnpackCoords(coords))
            self.bigPicture:SetAnchor(GUIItem.Left, GUIItem.Top)

        else

            self.itemTitle:SetPosition(self.vanillaDetailsLayout.titlePos)
            self.costText:SetPosition(self.vanillaDetailsLayout.costPos)
            self.itemDescription:SetPosition(self.vanillaDetailsLayout.descPos)

            GUIMakeFontScale(self.itemTitle, "kAgencyFBBold", kVanillaDetailTitleFontSize)
            GUIMakeFontScale(self.costText, "kAgencyFBBold", kVanillaDetailCostFontSize)
            self.itemDescription:SetTextClipped(true, kVanillaDetailDescClipWidth, -1)
            GUIMakeFontScale(self.itemDescription, "kAgencyFB", kVanillaDetailDescFontSize)

            if self.bigPictureDefaultSize then
                self.bigPicture:SetAnchor(GUIItem.Left, GUIItem.Top)
                self.bigPicture:SetSize(self.bigPictureDefaultSize)
            end

            -- The details section still holds whatever module the page last showed, and
            -- nothing repaints it until the mouse enters a tile. Put the exosuit's own
            -- vanilla details back, since that is the tile the player just came from.
            if leavingConfigPage then
                self:_SetDetailsSectionTechId(kTechId.DualMinigunExosuit,
                                              LookupTechData(kTechId.DualMinigunExosuit, kTechDataCostKey, -1))
            end

        end

    end

    if showModular then

        for _, element in ipairs(self.vanillaDetailItems) do
            element:SetIsVisible(false)
        end

        -- The exosuit's own "SPECIAL: Massive ..." box is 717 wide and would sit across the
        -- centred module rows, so it stays out of the modular layout entirely.
        self.specialFrame:SetIsVisible(false)

        -- _SetDetailsSectionTechId re-applies the vanilla layout to itemDescription and
        -- bigPicture on every vanilla hover change, and it runs earlier in Update than this
        -- does. Re-assert the modular layout every frame rather than only on the transition,
        -- otherwise one hover leaves the description and the model preview stranded in the
        -- middle of the panel.
        if self.exoDetailsTitlePos then
            self.itemTitle:SetPosition(self.exoDetailsTitlePos)
            self.costText:SetPosition(self.exoDetailsCostPos)
            self.modularExoDetailStats:SetPosition(self.exoDetailsStatsPos)
            self.itemDescription:SetPosition(self.exoDetailsDescPos)
        end

        if self.exoModelPreviewSize then
            self.bigPicture:SetSize(self.exoModelPreviewSize)
            self.bigPicture:SetPosition(self.exoModelPreviewPos)
        end

        local showModuleDetails = self.modularExoDetailsModule ~= nil
        self.itemTitle:SetIsVisible(showModuleDetails)
        self.costText:SetIsVisible(showModuleDetails)
        self.itemDescription:SetIsVisible(showModuleDetails)
        self.modularExoDetailStats:SetIsVisible(showModuleDetails)
        self.bigPicture:SetIsVisible(true)

        -- The box is a pure function of the module it shows, so it only needs repainting
        -- when that module changes - otherwise this ran string.format and WordWrap over
        -- the same text every frame. The transition above clears the record, so coming
        -- back to the page repaints even when the same module is still the hovered one.
        if self.modularExoDetailsModule ~= self.exoDetailsShownModule then
            self.exoDetailsShownModule = self.modularExoDetailsModule
            self:_SetDetailsSectionExoModule(self.modularExoDetailsModule)
        end

    end

end

-- Modular counterpart of _SetDetailsSectionTechId: fills the details section from an exo
-- module instead of a techId. Name, cost, the armour and weight the module contributes, and
-- a one line description out of EXO_MODULE_<NAME>_DESC.
function GUIMarineBuyMenu:_SetDetailsSectionExoModule(moduleType)

    if moduleType == nil or self.modularExoDetailStats == nil then
        return
    end

    local moduleGUIDetails = GUIMarineBuyMenu.kExoModuleData[moduleType]
    if moduleGUIDetails == nil then
        return
    end

    local moduleTypeData = kExoModuleTypesData[moduleType] or {}

    self.itemTitle:SetText(string.upper(Locale.ResolveString(moduleGUIDetails.label)))

    local resourceCost = moduleTypeData.resourceCost or 0
    self.costText:SetText(string.format("%s: %d", Locale.ResolveString("BUYMENU_COST"), resourceCost))

    -- Weight is an internal number; what a player cares about is the speed it costs.
    -- A module of weight w takes w of the exo's base speed away (see
    -- Exo:GetInventorySpeedScalar), so print that directly and drop the parts that are zero.
    local armorValue = moduleTypeData.armorValue or 0
    local speedPenalty = math.round((moduleTypeData.weight or 0) * 100)
    local statParts = {}
    if armorValue ~= 0 then
        table.insert(statParts, string.format(Locale.ResolveString("EXO_DETAILS_ARMOR_FORMAT"), armorValue))
    end
    if speedPenalty ~= 0 then
        table.insert(statParts, string.format(Locale.ResolveString("EXO_DETAILS_SPEED_FORMAT"), speedPenalty))
    end
    local statText = #statParts > 0 and table.concat(statParts, "    ") or Locale.ResolveString("EXO_DETAILS_NO_STAT_CHANGE")
    self.modularExoDetailStats:SetText(statText)

    local descriptionKey = string.format("EXO_MODULE_%s_DESC", string.upper(kExoModuleTypes[moduleType]))
    local description = Locale.ResolveString(descriptionKey)
    -- WordWrap returns three values (wrapped text, leftover text, line count). Passing it
    -- straight into SetText spills the extras into its time / animName arguments, which
    -- errors every frame, so keep only the first return.
    local wrappedDescription = WordWrap(self.itemDescription, description, 0, kExoDetailsBoxWidth, kExoDetailsDescMaxLines)
    self.itemDescription:SetText(wrappedDescription)

end

-- What buying the configuration on screen costs, priced exactly the way
-- ModularExo_HandleExoModularBuy charges for it: the whole configuration, less a refund
-- for the one the player is already wearing, never below zero. Pass a cost to price a
-- candidate; omit it for whatever _RefreshExoModularButtons last measured.
function GUIMarineBuyMenu:_GetExoConfigPrice(resourceCost)
    return math.max(0, (resourceCost or self.exoConfigResourceCost or 0) - (self.activeExoConfigResCost or 0))
end

function GUIMarineBuyMenu:_UpdateExoModularButtons()
    	
	if self:_GetIsExoConfigPageActive() then

        self:_RefreshExoModularButtons()
				
        -- local researched = self:_GetResearchInfo(kTechId.DualMinigunExosuit)
		local researched = self.hostStructure:GetTechId() == kTechId.ExoPrototypeLab
        if not researched or PlayerUI_GetPlayerResources() < self:_GetExoConfigPrice() then
            self.modularExoBuyButton:SetColor(Color(1, 0, 0, 1))
            self.modularExoBuyButtonText:SetColor(Color(0.5, 0.5, 0.5, 1))
            self.modularExoCostText:SetColor(kCannotBuyColor)
            self.modularExoCostIcon:SetColor(kCannotBuyColor)
        else
            if GetIsMouseOver(self, self.modularExoBuyButton) then
                self.modularExoBuyButton:SetColor(kCloseButtonColorHover)
                self.modularExoCostText:SetColor(kCloseButtonColorHover)
                self.modularExoCostIcon:SetColor(kCloseButtonColorHover)
                self.modularExoBuyButtonText:SetColor(kCloseButtonColorHover)
            else
                self.modularExoBuyButton:SetColor(kCloseButtonColor)
                self.modularExoCostText:SetColor(kCloseButtonColor)
                self.modularExoCostIcon:SetColor(kCloseButtonColor)
                self.modularExoBuyButtonText:SetColor(kCloseButtonColor)
            end
            
            --self.modularExoBuyButtonText:SetColor(kCloseButtonColor)
            --self.modularExoCostText:SetColor(kTextColor)
            --self.modularExoCostIcon:SetColor(kTextColor)
        end
        if self.modularExoBackButton then
            if GetIsMouseOver(self, self.modularExoBackButton) then
                self.modularExoBackButton:SetColor(kCloseButtonColorHover)
                self.modularExoBackButtonText:SetColor(kCloseButtonColorHover)
            else
                self.modularExoBackButton:SetColor(kCloseButtonColor)
                self.modularExoBackButtonText:SetColor(kCloseButtonColor)
            end
        end

        local hoveredModuleType = nil
        for buttonI, buttonData in ipairs(self.modularExoModuleButtonList) do
            if GetIsMouseOver(self, buttonData.buttonGraphic) then
                hoveredModuleType = buttonData.moduleType
                if buttonData.state == "enabled" then
                    buttonData.buttonGraphic:SetColor(kModuleButtonHoverColor)
                end
            else
                buttonData.buttonGraphic:SetColor(buttonData.col)
            end
        end

        -- The details box follows the mouse, and keeps the last module it was given so it
        -- never blanks out while the mouse travels between two buttons.
        if hoveredModuleType then
            self.modularExoDetailsModule = hoveredModuleType
        end
    end
end

-- Repaints every module button from the current configuration. Three things decide how a
-- button looks:
--   * selected  - this module is the one the configuration currently carries.
--   * valid     - putting this module in this slot leaves a configuration the exo can be
--                 built from (e.g. a claw cannot sit next to another claw).
--   * afforded  - the player has the resources the switch would cost.
-- Cost is measured exactly the way ModularExo_HandleExoModularBuy charges for it: the whole
-- candidate configuration is priced, the configuration the player is already wearing is
-- refunded, and what is left (never below zero) is what the switch costs. So for a marine on
-- foot every module costs its share of the full suit, while for an exo refitting at the lab a
-- module that is no more expensive than the one it replaces is free.
function GUIMarineBuyMenu:_RefreshExoModularButtons()

    -- How many of the team already carry each module. It moves on its own, has nothing to
    -- do with the configuration on screen and is cheap to read, so it stays outside the
    -- cache below; only the SetText is held back, since that is the part that allocates.
    local teamInfo = GetTeamInfoEntity(kTeam1Index)
    if teamInfo then
        for _, buttonData in ipairs(self.modularExoModuleButtonList) do
            if buttonData.teamNumber then
                local ArmType = kExoModuleTypes[buttonData.moduleType]
                if ArmType == "Flamethrower" then
                    ArmType = "Blowtorch"
                end
                local numUsers = teamInfo[ArmType]
                if not numUsers then
                    error(string.format("Netvar %s does not exist in MarineTeamInfo!", ArmType))
                end
                if buttonData.teamNumberValue ~= numUsers then
                    buttonData.teamNumberValue = numUsers
                    buttonData.teamNumber:SetText(string.format("%d", numUsers))
                end
            end
        end
    end

    local playerResources = PlayerUI_GetPlayerResources()
    local armorLevels = PlayerUI_GetArmorLevel and PlayerUI_GetArmorLevel() or 0

    -- Repainting the grid costs one ModularExo_GetIsConfigValid call per button plus a
    -- string per label, and this is called on every frame the page is up. None of it can
    -- change unless the configuration, the player's resources or the armour level changed,
    -- so hold still while they do. Hover is deliberately not part of this: the hover pass
    -- in _UpdateExoModularButtons re-applies colours from buttonData.col after every call,
    -- so it keeps working while this is skipped. The fields are compared one by one rather
    -- than hashed into a key, since building that key is the allocation being avoided.
    local rightArm = self.exoConfig[kExoModuleSlots.RightArm]
    local leftArm  = self.exoConfig[kExoModuleSlots.LeftArm]
    local utility  = self.exoConfig[kExoModuleSlots.Utility]
    local ability  = self.exoConfig[kExoModuleSlots.Ability]

    if self.exoButtonsPainted
    and self.exoButtonsPaintedResources == playerResources
    and self.exoButtonsPaintedArmorLevels == armorLevels
    and self.exoButtonsPaintedRightArm == rightArm
    and self.exoButtonsPaintedLeftArm == leftArm
    and self.exoButtonsPaintedUtility == utility
    and self.exoButtonsPaintedAbility == ability then
        return
    end

    self.exoButtonsPainted = true
    self.exoButtonsPaintedResources = playerResources
    self.exoButtonsPaintedArmorLevels = armorLevels
    self.exoButtonsPaintedRightArm = rightArm
    self.exoButtonsPaintedLeftArm = leftArm
    self.exoButtonsPaintedUtility = utility
    self.exoButtonsPaintedAbility = ability

    local _, _, resourceCost, _, _ = ModularExo_GetIsConfigValid(self.exoConfig)
    resourceCost = resourceCost or 0
    self.exoConfigResourceCost = resourceCost

    local currentConfigPrice = self:_GetExoConfigPrice()

    self.modularExoCostText:SetText(tostring(currentConfigPrice))
    if self.modularExoArmorText then
        local speedPercent = math.round(ModularExo_GetConfigSpeedFraction(self.exoConfig) * 100)
        self.modularExoArmorText:SetText(string.format(Locale.ResolveString("EXO_BUY_ARMOR_SPEED_FORMAT"),
                                                       ModularExo_GetConfigArmor(self.exoConfig, armorLevels),
                                                       speedPercent))
    end

    for buttonI, buttonData in ipairs(self.modularExoModuleButtonList) do

        local current = self.exoConfig[buttonData.slotType]
        local col = nil
        local canAfford = true

        if current == buttonData.moduleType then

            -- Already selected. It still has to be paid for as part of the whole
            -- configuration, so it can be selected and unaffordable at the same time.
            buttonData.state = "selected"
            canAfford = playerResources >= currentConfigPrice
            col = kEnabledColor

        else

            self.exoConfig[buttonData.slotType] = buttonData.moduleType
            local isValid, badReason, candidateCost = ModularExo_GetIsConfigValid(self.exoConfig)
            if buttonData.slotType == kExoModuleSlots.LeftArm and badReason == "bad model right" then

                -- Picking this left arm drags the right arm to the same module, so price the
                -- pair rather than the invalid half-configuration.
                isValid = true
                buttonData.forceRightToDual = true

                local restoreRightArm = self.exoConfig[kExoModuleSlots.RightArm]
                self.exoConfig[kExoModuleSlots.RightArm] = buttonData.moduleType
                local _, _, dualCost = ModularExo_GetIsConfigValid(self.exoConfig)
                candidateCost = dualCost or candidateCost
                self.exoConfig[kExoModuleSlots.RightArm] = restoreRightArm

            else
                buttonData.forceRightToDual = false
            end

            -- THIS IS FOR WHEN THE RIGHT ARM CONTROLS THE UI!
            --[[if buttonData.slotType == kExoModuleSlots.RightArm and badReason == "bad model left" then
                isValid = true
                buttonData.forceLeftToDual = true
            else
                buttonData.forceLeftToDual = false
            end]]

            if isValid then
                canAfford = playerResources >= self:_GetExoConfigPrice(candidateCost or 0)
                buttonData.state = canAfford and "enabled" or "unaffordable"
            else
                buttonData.state = "disabled"
            end
            col = kDisabledColor

            if not isValid and (badReason == "bad model right" or badReason == "bad model left") then
                col = Color(0.2, 0.2, 0.2, 0.4)
            end

            self.exoConfig[buttonData.slotType] = current

        end

        -- Unaffordable reads through the contents, not through the button frame, so that a
        -- module that is both selected and unaffordable still shows the selected highlight.
        local contentColor = col
        local costColor = col
        if not canAfford then
            contentColor = kModuleUnaffordableColor
            costColor = kCannotBuyColor
        end

        buttonData.col = col
        buttonData.buttonGraphic:SetColor(col)

        for thingI, thing in ipairs(buttonData.thingsToRecolor) do
            thing:SetColor(contentColor)
        end
        if buttonData.costLabel then
            buttonData.costLabel:SetColor(costColor)
        end
        if buttonData.costIcon then
            buttonData.costIcon:SetColor(costColor)
        end
        if buttonData.teamNumber then
            buttonData.teamNumber:SetColor(contentColor)
        end
        if buttonData.teamIcon then
            buttonData.teamIcon:SetColor(contentColor)
        end

    end

end