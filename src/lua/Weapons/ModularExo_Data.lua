Script.Load("lua/Weapons/Marine/ExoWeaponHolder.lua")
Script.Load("lua/Weapons/Marine/Claw.lua")
Script.Load("lua/Weapons/Marine/ExoShield.lua")
Script.Load("lua/Weapons/Marine/PlasmaLauncher.lua")
Script.Load("lua/Weapons/Marine/ExoFlamer.lua")
Script.Load("lua/Weapons/Marine/Minigun.lua")
Script.Load("lua/Weapons/Marine/Railgun.lua")

kExoModuleCategories = enum {
    "Weapon",
    "Utility",
    "Ability",
}
-- The slots that modules go in
kExoModuleSlots = enum {
    "RightArm",
    "LeftArm",
    "Utility",
    "Ability",
}

-- Slot data
kExoModuleSlotsData = {
    [kExoModuleSlots.LeftArm]  = {
        category = kExoModuleCategories.Weapon,
        required = true,
    },
    [kExoModuleSlots.RightArm] = {
        category = kExoModuleCategories.Weapon,
        required = true,
    },
    [kExoModuleSlots.Utility]  = {
        category = kExoModuleCategories.Utility,
        required = false,
    },
    [kExoModuleSlots.Ability]  = {
        category = kExoModuleCategories.Ability,
        required = false,
    },
}

-- Module types
kExoModuleTypes = enum {
    "None",
    "Shield",
    "Minigun",
	"Railgun",
    "Flamethrower",
	"PlasmaLauncher",
	"Claw",
    "Armor",
    "NanoRepair",
    "NanoShield",
    "Thrusters",
    --"PhaseModule",
    "CatPack",
	"EjectionSeat",
}

-- Information to decide which model to use for weapon combos
kExoArmTypes = enum {
    "Claw",
    "Minigun",
    "Railgun",
	"PlasmaLauncher",
}

kExoArmNames = {
    "Claw",
    "Minigun",
    "Railgun",
	"PlasmaLauncher",
	"Blowtorch",
    "Shield",
}

-- Module type data
if kCBMaddon then
	kExoModuleTypesData = {
		
		-- Weapon modules
		[kExoModuleTypes.Claw]       = {
			category     = kExoModuleCategories.Weapon,
			powerCost    = 0,
			resourceCost = kClawCost,
			mapName      = Claw.kMapName,
			armType      = kExoArmTypes.Claw,
			weight       = kClawWeight,
			armorValue   = kClawArmor,
			leftArmOnly  = true,
			singleRightArmOnly = false,
		},
		[kExoModuleTypes.Minigun]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kMinigunCost,
			mapName        = Minigun.kMapName,
			armType        = kExoArmTypes.Minigun,
			weight         = kMinigunWeight,
			armorValue     = kMinigunArmor,
			requiredTechId = kMinigunTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		[kExoModuleTypes.Railgun]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kRailgunCost,
			mapName        = Railgun.kMapName,
			armType        = kExoArmTypes.Railgun,
			weight         = kRailgunWeight,
			armorValue     = kRailgunArmor,
			requiredTechId = kRailgunTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		[kExoModuleTypes.PlasmaLauncher]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kPlasmaLauncherCost,
			mapName        = PlasmaLauncher.kMapName,
			armType        = kExoArmTypes.PlasmaLauncher,
			weight         = kPlasmaLauncherWeight,
			armorValue     = kPlasmaLauncherArmor,
			requiredTechId = kPlasmaLauncherTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		--[[[kExoModuleTypes.Flamethrower] = {
			category 	   = kExoModuleCategories.Weapon,
			powerCost 	   = 0,
			resourceCost   = kExoFlamerCost,
			mapName 	   = ExoFlamer.kMapName,
			armType 	   = kExoArmTypes.Railgun,
			weight 		   = kExoFlamerWeight,
			armorValue     = kExoFlamerWelderArmor,
			requiredTechId = kExoFlamerTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		--]]
		--},
		--[kExoModuleTypes.Shield] = {
		--    category = kExoModuleCategories.Weapon,
		--    powerCost = 0,
		--	resourceCost = kExoShieldCost,
		--    mapName = ExoShield.kMapName,
		--    armType = kExoArmTypes.Claw,
		--    weight = kExoShieldWeight,
		--    armorValue     = kThrustersArmor,
		--	requiredTechId = kExoShieldTech,
		--    leftArmOnly  = true
		--},		
		
		-- Utility modules
		[kExoModuleTypes.Thrusters]  = {
			category       = kExoModuleCategories.Utility,
			powerCost      = 0,
			resourceCost   = kThrustersCost,
			weight         = kThrustersWeight,
			armorValue     = kThrustersArmor,
			requiredTechId = kExoThrusterModuleTech
			
		},
		--	[kExoModuleTypes.PhaseModule] = {
		--    category = kExoModuleCategories.Utility,
		--    powerCost = 0,
		--	resourceCost = kPhaseModuleCost,
		--    weight = kPhaseModuleWeight,
		--	requiredTechId = kPhaseModuleTech
		--
		--},
		
		--[kExoModuleTypes.Armor]      = {
		--    category       = kExoModuleCategories.Utility,
		--    powerCost      = 0,
		--    resourceCost   = kArmorModuleCost,
		--    armorValue     = kArmorModuleArmor,
		--    weight         = kArmorModuleWeight,
		--    requiredTechId = kArmorModuleTech
		--},
		
		--[kExoModuleTypes.NanoRepair] = {
		--    category     = kExoModuleCategories.Utility,
		--    powerCost    = 0,
		--    resourceCost = kNanoModuleCost,
		--    weight       = kNanoRepairWeight,
		--    armorValue   = kNanoRepairArmor,
		--    
		--},
		
		--[kExoModuleTypes.NanoShield] = {
		--    category     = kExoModuleCategories.Ability,
		--    powerCost    = 0,
		--    resourceCost = kExoNanoShieldCost,
		--    weight       = kNanoShieldWeight,
		--    
		--},
		--[kExoModuleTypes.CatPack]    = {
		--    category     = kExoModuleCategories.Ability,
		--    powerCost    = 0,
		--    resourceCost = kExoCatPackCost,
		--    weight       = kCatPackWeight,
		--    armorValue   = kCatPackArmor,
		--    
		--},
		
		[kExoModuleTypes.EjectionSeat]  = {
		category       = kExoModuleCategories.Utility,
		powerCost      = 0,
		resourceCost   = kEjectionSeatCost,
		weight         = kEjectionSeatWeight,
		armorValue     = kEjectionSeatArmor,
		requiredTechId = kEjectionSeatModuleTech
		},
		
		[kExoModuleTypes.None]       = { },
	}
else
	kExoModuleTypesData = {
		
		-- Weapon modules
		[kExoModuleTypes.Claw]       = {
			category     = kExoModuleCategories.Weapon,
			powerCost    = 0,
			resourceCost = kClawCost,
			mapName      = Claw.kMapName,
			armType      = kExoArmTypes.Claw,
			weight       = kClawWeight,
			armorValue   = kClawArmor,
			leftArmOnly  = true,
			singleRightArmOnly = false,
		},
		[kExoModuleTypes.Minigun]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kMinigunCost,
			mapName        = Minigun.kMapName,
			armType        = kExoArmTypes.Minigun,
			weight         = kMinigunWeight,
			armorValue     = kMinigunArmor,
			requiredTechId = kMinigunTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		[kExoModuleTypes.Railgun]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kRailgunCost,
			mapName        = Railgun.kMapName,
			armType        = kExoArmTypes.Railgun,
			weight         = kRailgunWeight,
			armorValue     = kRailgunArmor,
			requiredTechId = kRailgunTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		[kExoModuleTypes.PlasmaLauncher]    = {
			category       = kExoModuleCategories.Weapon,
			powerCost      = 0,
			resourceCost   = kPlasmaLauncherCost,
			mapName        = PlasmaLauncher.kMapName,
			armType        = kExoArmTypes.PlasmaLauncher,
			weight         = kPlasmaLauncherWeight,
			armorValue     = kPlasmaLauncherArmor,
			requiredTechId = kPlasmaLauncherTech,
			leftArmOnly    = false,
			singleRightArmOnly = true,
		},
		-- Utility modules
		[kExoModuleTypes.Thrusters]  = {
			category       = kExoModuleCategories.Utility,
			powerCost      = 0,
			resourceCost   = kThrustersCost,
			weight         = kThrustersWeight,
			armorValue     = kThrustersArmor,
			requiredTechId = kExoThrusterModuleTech
			
		},		
		[kExoModuleTypes.EjectionSeat]  = {
		category       = kExoModuleCategories.Utility,
		powerCost      = 0,
		resourceCost   = kEjectionSeatCost,
		weight         = kEjectionSeatWeight,
		armorValue     = kEjectionSeatArmor,
		requiredTechId = kEjectionSeatModuleTech
		},
		
		[kExoModuleTypes.None]       = { },
	}
end

-- Model data for weapon combos (data[rightArmType][leftArmType])
kExoWeaponRightLeftComboModels = {
    [kExoArmTypes.Minigun] = {
        isValid                = true,
        [kExoArmTypes.Minigun] = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_mm.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_mm.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_mm_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_mm_view.animation_graph"),
        },
        [kExoArmTypes.Railgun] = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_rm.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_rm.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_rm_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_rm_view.animation_graph"),
        },
		[kExoArmTypes.PlasmaLauncher] = {
            isValid = false,
        },
        [kExoArmTypes.Claw]    = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_cm.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_cm.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_cm_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_cm_view.animation_graph"),
        },
    },
    [kExoArmTypes.Railgun] = {
        isValid                = true,
        [kExoArmTypes.Minigun] = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_mr.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_mr.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_mr_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_mr_view.animation_graph"),
        },
        [kExoArmTypes.Railgun] = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_rr.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_rr.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_rr_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_rr_view.animation_graph"),
        },
		[kExoArmTypes.PlasmaLauncher] = {
            isValid        = true,
            worldModel     = "models/railgun/exosuit_pr.model",
            worldAnimGraph = "models/railgun/exosuit_pr.animation_graph",
            viewModel      = "models/railgun/exosuit_pr_view.model",
            viewAnimGraph  = "models/railgun/exosuit_pr_view.animation_graph",
        },
        [kExoArmTypes.Claw]    = {
            isValid        = true,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_cr.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_cr.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_cr_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_cr_view.animation_graph"),
        },
    },
    [kExoArmTypes.Claw]    = {
        isValid                = true,
        
        [kExoArmTypes.Minigun] = {
            isValid = true,
        },
        [kExoArmTypes.Railgun] = {
            isValid = true,
        },
		[kExoArmTypes.PlasmaLauncher] = {
            isValid = true,
        },
        [kExoArmTypes.Claw]    = {
            isValid        = false,
            worldModel     = PrecacheAsset("models/marine/exosuit/exosuit_cm.model"),
            worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_cm.animation_graph"),
            viewModel      = PrecacheAsset("models/marine/exosuit/exosuit_cm_view.model"),
            viewAnimGraph  = PrecacheAsset("models/marine/exosuit/exosuit_cm_view.animation_graph"),
        }, -- NOT A VALID MODEL!
    },
	[kExoArmTypes.PlasmaLauncher] = {
        isValid                = true,
        [kExoArmTypes.Minigun] = {
            isValid = false,
        },
        [kExoArmTypes.Railgun] = {
            isValid        = true,
            worldModel     = "models/railgun/exosuit_rp.model",
            worldAnimGraph = "models/railgun/exosuit_rp.animation_graph",
            viewModel      = "models/railgun/exosuit_rp_view.model",
            viewAnimGraph  = "models/railgun/exosuit_rp_view.animation_graph",
        },
		[kExoArmTypes.PlasmaLauncher] = {
            isValid        = true,
            worldModel     = "models/plasma/exosuit_pp.model",
            worldAnimGraph = "models/plasma/exosuit_pp.animation_graph",
            viewModel      = "models/plasma/exosuit_pp_view.model",
            viewAnimGraph  = "models/plasma/exosuit_pp_view.animation_graph",
        },
        [kExoArmTypes.Claw]    = {
            isValid        = true,
            worldModel     = "models/claw/exosuit_cp.model",
            worldAnimGraph = "models/claw/exosuit_cp.animation_graph",
            viewModel      = "models/claw/exosuit_cp_view.model",
            viewAnimGraph  = "models/claw/exosuit_cp_view.animation_graph",
        },
    },
}

-- Dual claws reuse the existing Claw module in both arm slots.
kExoModuleTypesData[kExoModuleTypes.Claw].leftArmOnly = false
kExoWeaponRightLeftComboModels[kExoArmTypes.Claw].isValid = true
kExoWeaponRightLeftComboModels[kExoArmTypes.Claw][kExoArmTypes.Claw] = {
    isValid = true,
    worldModel = PrecacheAsset("models/marine/exosuit/exosuit_cc.model"),
    worldAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_cc.animation_graph"),
    viewModel = PrecacheAsset("models/marine/exosuit/exosuit_cc_view.model"),
    viewAnimGraph = PrecacheAsset("models/marine/exosuit/exosuit_cc_view.animation_graph"),
}

-- Right-claw loadouts use mirrored models and hand-swapped native CBM graphs.
local function MakeRightClawModelData(pair)
    local base = "models/marine/exosuit/" .. (pair=="pc" and "exosuit_charged_" or "exosuit_") .. pair
    return {
        isValid = true,
        worldModel = PrecacheAsset(base .. ".model"),
        worldAnimGraph = PrecacheAsset(base .. ".animation_graph"),
        viewModel = PrecacheAsset(base .. "_view.model"),
        viewAnimGraph = PrecacheAsset(base .. "_view.animation_graph"),
    }
end
kExoWeaponRightLeftComboModels[kExoArmTypes.Claw][kExoArmTypes.Minigun] = MakeRightClawModelData("mc")
kExoWeaponRightLeftComboModels[kExoArmTypes.Claw][kExoArmTypes.Railgun] = MakeRightClawModelData("rc")
kExoWeaponRightLeftComboModels[kExoArmTypes.Claw][kExoArmTypes.PlasmaLauncher] = MakeRightClawModelData("pc")

-- Plasma launcher pairings use the charged arm models.
local plasmaArms = { c = kExoArmTypes.Claw, m = kExoArmTypes.Minigun,
    r = kExoArmTypes.Railgun, p = kExoArmTypes.PlasmaLauncher }
for leftCode, leftType in pairs(plasmaArms) do
    for rightCode, rightType in pairs(plasmaArms) do
        if leftCode == "p" or rightCode == "p" then
            local base = "models/marine/exosuit/exosuit_charged_" .. leftCode .. rightCode
            kExoWeaponRightLeftComboModels[rightType] = kExoWeaponRightLeftComboModels[rightType] or {}
            kExoWeaponRightLeftComboModels[rightType].isValid = true
            kExoWeaponRightLeftComboModels[rightType][leftType] = {
                isValid = true, worldModel = PrecacheAsset(base .. ".model"),
                worldAnimGraph = PrecacheAsset(base .. ".animation_graph"),
                viewModel = PrecacheAsset(base .. "_view.model"),
                viewAnimGraph = PrecacheAsset(base .. "_view.animation_graph"),
            }
        end
    end
end


-- Lightweight barrier: one emitter on the left arm, compatible with every
-- selectable right-hand weapon. The claw arm supplies the mounting pose.
kExoModuleTypesData[kExoModuleTypes.Shield] = {
    category = kExoModuleCategories.Weapon, powerCost = 0,
    resourceCost = kExoShieldCost, mapName = ExoShield.kMapName,
    armType = kExoArmTypes.Claw, weight = 0.08, armorValue = 0,
    requiredTechId = kExoShieldTech, leftArmOnly = false,
    singleRightArmOnly = false,
}

-- Shield variants retain each loadout rig and replace only its equipped hand.
kExoShieldModelVariants = {}
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cc.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cc.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cc_view.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_cc.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_cc.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_cc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_cc_view.model")
kExoShieldModelVariants["lr:models/marine/exosuit/exosuit_cc.model"] = PrecacheAsset("models/marine/exosuit/shield_lr_exosuit_cc.model")
kExoShieldModelVariants["lr:models/marine/exosuit/exosuit_cc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_lr_exosuit_cc_view.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cm.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cm.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cm_view.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cm_view.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cr.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cr.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_cr_view.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_cr_view.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_charged_cp.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_charged_cp.model")
kExoShieldModelVariants["l:models/marine/exosuit/exosuit_charged_cp_view.model"] = PrecacheAsset("models/marine/exosuit/shield_l_exosuit_charged_cp_view.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_mc.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_mc.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_mc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_mc_view.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_rc.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_rc.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_rc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_rc_view.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_charged_pc.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_charged_pc.model")
kExoShieldModelVariants["r:models/marine/exosuit/exosuit_charged_pc_view.model"] = PrecacheAsset("models/marine/exosuit/shield_r_exosuit_charged_pc_view.model")
