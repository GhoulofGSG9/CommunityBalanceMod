-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\MarineTechMap.lua
--
-- Created by: Andreas Urwalek (and@unknownworlds.com)
--
-- Formatted marine tech tree.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/GUIUtility.lua")

kMarineTechMapYStart = 1
local kSpecialMarineTechColor = Color(0.7, 0.3, 1, 0.5)
local kFreeMarineTechColor = Color(1, 1, 1, 0.5)
local kUpgradeMarineTechColor = Color(0.2, 1, 0.2, 0.5)

if kCBMaddon then
	kMarineTechMap =
	{
			{ kTechId.CommandStation, 7, 1 }, { kTechId.InfantryPortal, 5, 1 }, { kTechId.Extractor, 9, 1 }, { kTechId.AdvancedMarineSupport, 7, 0 },

			{ kTechId.Observatory, 3.25, 3.0 }, { kTechId.AdvancedObservatory, 3.25, 5.0},
			{ kTechId.PhaseTech, 2.25, 3.0 }, { kTechId.PhaseGate, 2.25, 5.0 },
	  
			{ kTechId.Armory, 5.75, 3.0 }, { kTechId.AdvancedArmory, 5.75, 7.0 }, { kTechId.JetpackTech, 7, 7.0 },
			{ kTechId.Welder, 7, 3.0 }, { kTechId.GrenadeTech, 4.75, 4.0 }, { kTechId.MinesTech, 7, 4.0 }, { kTechId.SubmachinegunTech, 7, 5.0 }, { kTechId.ShotgunTech, 7, 6.0 }, { kTechId.AdvancedWeaponry, 4.75, 7.0 },
				
			{ kTechId.PrototypeLab, 8.25, 7.0 },
			{ kTechId.DualMinigunTech, 6.75, 8.5 }, { kTechId.AdvancedExoArmsTech, 7.75, 8.5 }, { kTechId.CoresExosuitTech, 8.75, 8.5 }, { kTechId.ExoAbilitiesTech, 9.75, 8.5 },
			
			{ kTechId.RoboticsFactory, 10.75, 3.0 }, { kTechId.ARCRoboticsFactory, 10.75, 5.0 }, 
			{ kTechId.Sentry, 11.75, 3.0 }, { kTechId.MAC, 11.75, 4.0}, { kTechId.BattleMAC, 11.75, 5.0 }, { kTechId.SentryBattery, 11.75, 6.0 }, { kTechId.ARC, 11.75, 7.0 }, { kTechId.DIS, 11.75, 8.0 },       
			
			{ kTechId.ArmsLab, 8.25, 3.0}, 
			{ kTechId.Armor1, 8.75, 4.0 }, { kTechId.Weapons1, 9.75, 4.0 },
			{ kTechId.Armor2, 8.75, 5.0 }, { kTechId.Weapons2, 9.75, 5.0 },
			{ kTechId.Armor3, 8.75, 6.0 }, { kTechId.Weapons3, 9.75, 6.0 },
		
			}

	kMarineLines = 
	{
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.Extractor, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.InfantryPortal, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.AdvancedMarineSupport),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.Armory, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.ArmsLab, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.RoboticsFactory, kFreeMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.InfantryPortal, kTechId.Observatory, kSpecialMarineTechColor),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.Welder, kFreeMarineTechColor),		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.GrenadeTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.MinesTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.SubmachinegunTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.ShotgunTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.AdvancedArmory, kUpgradeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.AdvancedArmory, kTechId.AdvancedWeaponry, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.AdvancedArmory, kTechId.JetpackTech),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.Weapons1),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Weapons1, kTechId.Weapons2),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Weapons2, kTechId.Weapons3),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.Armor1),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armor1, kTechId.Armor2),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armor2, kTechId.Armor3),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.PrototypeLab, kFreeMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.DualMinigunTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.AdvancedExoArmsTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.CoresExosuitTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.ExoAbilitiesTech),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.Observatory, kTechId.PhaseTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PhaseTech, kTechId.PhaseGate),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Observatory, kTechId.AdvancedObservatory, kUpgradeMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.Sentry, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.MAC, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.ARCRoboticsFactory, kUpgradeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.BattleMAC, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.ARC, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.DIS, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.SentryBattery, kFreeMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.AdvancedObservatory, kTechId.PhaseGate, kSpecialMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.Observatory, kFreeMarineTechColor),
				
		--For Advanced Support to AMAC:
		{7.0, 0.0, 12.5, 0.0, kSpecialMarineTechColor}, {12.5, 0.0, 12.5, 5.0, kSpecialMarineTechColor}, {12.5, 5.0, 11.75, 5.0, kSpecialMarineTechColor},
		
	}
else
	kMarineTechMap =
	{
			{ kTechId.CommandStation, 7, 1 }, { kTechId.InfantryPortal, 5, 1 }, { kTechId.Extractor, 9, 1 }, { kTechId.AdvancedMarineSupport, 7, 0 },

			{ kTechId.Observatory, 3.25, 3.0 }, { kTechId.PhaseTech, 3.25, 4.0 }, { kTechId.PhaseGate, 3.25, 5.0 },
	  
			{ kTechId.Armory, 5.75, 3.0 }, { kTechId.AdvancedArmory, 5.75, 7.0 },
			{ kTechId.Welder, 7, 3.0 }, { kTechId.GrenadeTech, 7, 4.0 }, { kTechId.MinesTech, 7, 5.0 }, { kTechId.ShotgunTech, 7.0, 6.0 }, { kTechId.AdvancedWeaponry, 4.75, 7.0 },
				
			{ kTechId.PrototypeLab, 8.25, 7.0 }, { kTechId.JetpackTech, 7.00, 7.0 },
			{ kTechId.DualMinigunTech, 6.75, 8.5 }, { kTechId.AdvancedExoArmsTech, 7.75, 8.5 }, { kTechId.CoresExosuitTech, 8.75, 8.5 }, { kTechId.ExoAbilitiesTech, 9.75, 8.5 },
			
			{ kTechId.RoboticsFactory, 10.75, 3.0 }, { kTechId.ARCRoboticsFactory, 10.75, 5.0 },
			{ kTechId.MAC, 11.75, 3.0},{ kTechId.Sentry, 11.75, 4.0 }, { kTechId.SentryBattery, 11.75, 5.0 }, { kTechId.ARC, 11.75, 6.0 }, 	      
			
			{ kTechId.ArmsLab, 8.25, 3.0}, 
			{ kTechId.Armor1, 8.75, 4.0 }, { kTechId.Weapons1, 9.75, 4.0 },
			{ kTechId.Armor2, 8.75, 5.0 }, { kTechId.Weapons2, 9.75, 5.0 },
			{ kTechId.Armor3, 8.75, 6.0 }, { kTechId.Weapons3, 9.75, 6.0 },
			
			}

	kMarineLines = 
	{
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.Extractor, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.InfantryPortal, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.AdvancedMarineSupport),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.Armory, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.ArmsLab, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.CommandStation, kTechId.RoboticsFactory, kFreeMarineTechColor),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.InfantryPortal, kTechId.Observatory, kSpecialMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.Welder, kFreeMarineTechColor),		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.GrenadeTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.MinesTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.ShotgunTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.AdvancedArmory, kUpgradeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.AdvancedArmory, kTechId.AdvancedWeaponry, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.AdvancedArmory, kTechId.JetpackTech),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.Weapons1),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Weapons1, kTechId.Weapons2),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Weapons2, kTechId.Weapons3),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.Armor1),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armor1, kTechId.Armor2),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armor2, kTechId.Armor3),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ArmsLab, kTechId.PrototypeLab, kFreeMarineTechColor),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.DualMinigunTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.AdvancedExoArmsTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.CoresExosuitTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PrototypeLab, kTechId.ExoAbilitiesTech),

		GetLinePositionForTechMap(kMarineTechMap, kTechId.Observatory, kTechId.PhaseTech),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.PhaseTech, kTechId.PhaseGate),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.Sentry, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.MAC, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.RoboticsFactory, kTechId.ARCRoboticsFactory, kUpgradeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.ARC, kFreeMarineTechColor),
		GetLinePositionForTechMap(kMarineTechMap, kTechId.ARCRoboticsFactory, kTechId.SentryBattery, kFreeMarineTechColor),
		
		GetLinePositionForTechMap(kMarineTechMap, kTechId.Armory, kTechId.Observatory, kFreeMarineTechColor),		
	}
end