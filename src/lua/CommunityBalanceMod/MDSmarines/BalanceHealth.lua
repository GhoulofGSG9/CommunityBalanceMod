-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======        
--        
-- lua\BalanceHealth.lua        
--        
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)            
--        
-- ========= For more information, visit us at http://www.unknownworlds.com =====================        



kBabblerEggHealth = 230
kMatureBabblerEggHealth = 360

-- all structures health incresed by roughly 15%

-- kHiveHealth = 4000    kHiveArmor = 750    kHivePointValue = 30
kHiveHealth = 4600    kHiveArmor = 863

-- kMatureHiveHealth = 6000 kMatureHiveArmor = 1400
kMatureHiveHealth = 6900 kMatureHiveArmor = 1610
        
-- kHarvesterHealth = 2000 kHarvesterArmor = 200 kHarvesterPointValue = 15
-- kMatureHarvesterHealth = 2300 kMatureHarvesterArmor = 320
kHarvesterHealth = 2300 kHarvesterArmor = 230
kMatureHarvesterHealth = 2645 kMatureHarvesterArmor = 368

-- kShellHealth = 600     kShellArmor = 150     kShellPointValue = 12
-- kMatureShellHealth = 700     kMatureShellArmor = 200
kShellHealth = 690    kShellArmor = 173 
kMatureShellHealth = 805     kMatureShellArmor = 230

-- kCragHealth = 480    kCragArmor = 160    kCragPointValue = 10
-- kMatureCragHealth = 560    kMatureCragArmor = 272    kMatureCragPointValue = 10
kCragHealth = 518    kCragArmor = 184
kMatureCragHealth = 644    kMatureCragArmor = 313
        
-- kWhipHealth = 650    kWhipArmor = 175    kWhipPointValue = 10
-- kMatureWhipHealth = 720    kMatureWhipArmor = 240    kMatureWhipPointValue = 10
kWhipHealth = 748    kWhipArmor = 201
kMatureWhipHealth = 828    kMatureWhipArmor = 276
        
-- kSpurHealth = 800     kSpurArmor = 50     kSpurPointValue = 12
-- kMatureSpurHealth = 900  kMatureSpurArmor = 100  kMatureSpurPointValue = 12
kSpurHealth = 920     kSpurArmor = 58
kMatureSpurHealth = 1035  kMatureSpurArmor = 115

-- kShiftHealth = 600    kShiftArmor = 60    kShiftPointValue = 10
-- kMatureShiftHealth = 880    kMatureShiftArmor = 120    kMatureShiftPointValue = 10
kShiftHealth = 690    kShiftArmor = 69
kMatureShiftHealth = 1012    kMatureShiftArmor = 138

-- kVeilHealth = 900     kVeilArmor = 0     kVeilPointValue = 12
-- kMatureVeilHealth = 1100     kMatureVeilArmor = 0     kVeilPointValue = 12
kVeilHealth = 1035     kVeilArmor = 0     
kMatureVeilHealth = 1265     kMatureVeilArmor = 0

-- kShadeHealth = 600    kShadeArmor = 0    kShadePointValue = 10
-- kMatureShadeHealth = 1200    kMatureShadeArmor = 0    kMatureShadePointValue = 10
kShadeHealth = 690    kShadeArmor = 0    
kMatureShadeHealth = 1380    kMatureShadeArmor = 0

-- kHydraHealth = 125    kHydraArmor = 5  
-- kMatureHydraHealth = 160   kMatureHydraArmor = 20   
-- kHydraHealthPerBioMass = 16
kHydraHealth = 144    kHydraArmor = 6    
kMatureHydraHealth = 184   kMatureHydraArmor = 23
kHydraHealthPerBioMass = 18


-- kClogHealth = 250  kClogArmor = 0 kClogPointValue = 0
-- kClogHealthPerBioMass = 4
kClogHealth = 288  kClogArmor = 0 kClogPointValue = 0
kClogHealthPerBioMass = 5

-- kWebHealth = 10
kWebHealth = 10

-- kCystHealth = 50    kCystArmor = 1
-- kMatureCystHealth = 400    kMatureCystArmor = 1    kCystPointValue = 1
-- kMinMatureCystHealth = 200 kMinCystScalingDistance = 48 kMaxCystScalingDistance = 120
kCystHealth = 58    kCystArmor = 1
kMatureCystHealth = 460    kMatureCystArmor = 1    
kMinMatureCystHealth = 230 

-- kBoneWallHealth = 100 kBoneWallArmor = 0    kBoneWallHealthPerBioMass = 100
-- kContaminationHealth = 1500 kContaminationArmor = 0    kContaminationPointValue = 2
kBoneWallHealth = 115 kBoneWallArmor = 0    kBoneWallHealthPerBioMass = 115
kContaminationHealth = 1725 kContaminationArmor = 0

-- kTunnelEntranceHealth = 1000   kTunnelEntranceArmor = 100    kTunnelEntrancePointValue = 5
-- kMatureTunnelEntranceHealth = 1400    kMatureTunnelEntranceArmor = 250
kTunnelEntranceHealth = 1150   kTunnelEntranceArmor = 115
kMatureTunnelEntranceHealth = 1610    kMatureTunnelEntranceArmor = 288

-- kInfestedTunnelEntranceHealth = 1250    kInfestedTunnelEntranceArmor = 200
-- kMatureInfestedTunnelEntranceHealth = 1400    kMatureInfestedTunnelEntranceArmor = 250
kInfestedTunnelEntranceHealth = 1438    kInfestedTunnelEntranceArmor = 230
kMatureInfestedTunnelEntranceHealth = 1610    kMatureInfestedTunnelEntranceArmor = 288

-- kTunnelStartingHealthScalar = 0.18
kTunnelStartingHealthScalar = 0.18 --Percentage of kTunnelEntranceHealth & kTunnelEntranceArmor newly placed Tunnel has

