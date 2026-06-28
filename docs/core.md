---
title: Core Edition Changelog
---
<!-- AUTO-GENERATED from src/lua/GUIBetaBalanceChangelogData.lua by tools/gen-changelog.py. Do not edit by hand - your changes will be overwritten. -->

# Community Balance Mod &mdash; Core Edition

*Changes versus vanilla NS2. This page is the balance, QoL, performance and bugfix changes only - the vanilla NS2 roster is kept (Carapace, no new units or weapons).*

[&larr; Back to overview](./)

Welcome to the Community Balance Mod (CBM): Core Edition, a project built by the community, for the community.
This version only enables the balance, QoL, performance optimizations, and bugfixes of the CBM suite.
Ping me, @Shifter (project lead) or @NexZone30 (dev lead), in any of the NS2 discords,
or start a conversation in beta-balance-feedback on the official discord to let us know
you think! Below are the changes this mod introduces:

# TLDR of Recent Release (v3.5):

## Balance Changes
- Nerfs to exosuit movement and thruster.
- Claw armor increased from 75 to 115.
- Jetpack tech cost reduced from 25 to 20.
- Mines can no longer be placed inside the center of gates.
- Pulse nade now deals 15 from 10 damage (to one shot babblers).
- Boneshield blocks shots from railgun from piercing and doing health pool damage.

## Bugfixes and Enhanced Performance
- Vanilla bugfixes to ARC and whip ragdoll related server hitching and crashes.
- Vanilla bugfix to welder stopping welding when accidently aiming at a target's weapon.
- Vanilla bugfix to static DoTs (bile affected) that decreased target acquisition time by >0.5s.
- Vanilla bugfix to cyst popping on expanding across the map.
- Vanilla bugfix to nil error on phasegates.
- Vanilla bugfix for mine being triggered outside of damage range and improved responsiveness of detection.
- Extensive lua code refactor and debottlenecking, improving client/server performance (see CBM discord for extensive breakdown).
- Vanilla bugfixes related to game rate increases.
- Vanilla bugfixes to collisions:
  - Not affected by rate changes.
  - Better for PvP (less getting stuck / phasing through people).
  - Better when hitting geometry (many stuck spots fixed)
- Note: Server owners are encouraged to try increase game rates based on our recommendations (see CBM discord).

### Be sure to thank Katzenfleisch for his amazing work on the NS2 codebase optimizations!

# TLDR of Community Balance Mod (v3.5) vs. Vanilla:

![MARINE](./assets/images/Marine_Banner.webp "MARINE")

## MARINE
- Reworks to existing marines structures (sentry, sentry battery, and prototype lab).
- Full rework and rebalance of exosuits. New optional exosuit upgrades and claw arm.
- Weapon upgrades further increase structure damage.
- Rebalance of pulse grenades and extension to electrify debuff (works on PvE).

![ALIEN](./assets/images/Alien_Banner.webp "ALIEN")

## ALIEN
- Rebalance of existing alien support structures (reduced eHP, cost, and size; increased movement speed).
- Rework and bugfixes to onos stomp.
- Rework of cloak and carapace replacement (rage).

![GENERAL](./assets/images/Global_Banner.webp "GENERAL")

## GENERAL
- Complete rewrite of MAC and drifter AI with updated command card.
- New map icons for structures and units.
- Updated locale, new ui elements, and improved tech maps for new (and old) features.
- Custom skins and cinematics for new content.
- Various QoL, game improvements, and bugfixes.
- Refactor and optimization of lua codebase (major client and server performance improvements).

# Full Changelog:
## GENERAL
### Structure Damage Rework
- Buffed clogs, hydras, harvester, tunnels, and upgrade chambers eHP by ~15%.
- Balanced hive and support structure eHP (see alien section for details).
- Adjusted ARC damage, cluster grenade damage, and gorge healing to be consistent with vanilla.
- Every weapon upgrade does +20% structure damage (instead of + 10%)
  - W1 → +20% to structures (costs 20 tres)
  - W2 → +40% to structures (costs 30 tres)
  - W3 → +60% to structures (costs 40 tres)
- W0 GL → 65 Player / 260 Structure from 74.4 Player Damage
- W0 FT → 9 Player / 18 Structure from 9.9 Player Damage

### Status Icons
- New status icon for webbed status (web, stomp, whip webbing).
- Display status icons even with minimal hud elements.

### QoL / General Improvements
- Player and structure highlight shader made more pronounced to improve visual acuity.
- Changed point rewards for building structures from 4 points to be tied to the build time.
- Removed point reward for building hydras.
- Rerouted techs to illustrate proper tech and structure requirements.
- Replaced babblertech and webs with nutrient mist at bio 1.
- Improved nanoshield surface shader so that it more clearly appears on all entities.
- Updated locale, new ui elements, and improved tech maps for new (and old) features.
  - Marine tech map rearranged to better delineate tech progression and dependencies (purple lines).
- Improved blueprint placement (options -> mods -> CBM: Accessibility Options).
- Hotkeyed units are underlined for commanders when attacked for better visibility.

### Minimap Updates
- Players are able to see if a hive is at <34%, <67% or <=100% maturity
- Added Icon for occupied Hive/Chair
- Added Icon for Jetpackers
- Added Icon for matured Whips
- Added Icon for Drifter Eggs
- Added Icon for deployed ARCS
- Added Icon for Advanced Armory
- Alien Commander is able to see parasited mines

### Vanilla Bugfixes
- Web variant nil value console spam should no longer occur.
- Electrify no longer applies energy regeneration debuff.
- ARC trigger effect triggering on EVERY live entity in the game instead of just applicable damage targets.
- Fixed ARC error / crash when manually targeting clogs.
- Robotics factory rollout crash fixed.
- Armslabs while researching will show a rotating hologram.
- Fixed various visual bugs with updating tech.
- Jetpackers will no longer be affected by stomp when slightly above the ground.
- Jetpackers are able to replenish fuel when empty when holding space bar.
- Alien PvE bounces/glitches less during and after moving.
- Flying flamethrowers in rare cases should not crash the server anymore.
- Fixed cinematics of projectiles desyncing and disappearing.
- Fixed shotgun trace source location to be consistent (was random).
- Fixed issue with projectiles visually disappearing from the client.
- Fixed ARCs causing server hitching / crash on loss of orders when orders were queued.
- Fixed welders stopping welding when accidently aimed at a marine weapon.
- Fixed collisions being dependent tick/move rate (now based on time).
- Fixed whips causing server hitching / crash on death due to ragdolls.
- Fixed cyst popping on expanding across the map.
- Fixed nil error on phasegates.
- Fixed mine being triggered outside of damage range and improved responsiveness of detection.

### Vanilla Codebase Optimizations
- Refactored and optimized the way the game processes and confirms damage, collisions, and movement.
- Entity OnUpdates() and callback routines have been optimized.
- Optimized droppacks (meds/ammo/catpacks), bonewall, RTs, PvE, mines, and webs.
- Optimized to not calculate gravity when already on the ground.
- Optimized randomization calls and logic.
- Optimized shaders and cloak to less negatively impact performance.
- Optimized sound calls.
- Optimized bitmasks and bitmask calls.
- Optimized bot functions and calls.
- Optimized pregame functions and calls.
- Optimized spectate related functions and calls.

## MARINE - PLAYER
### Modular Exosuits
- Exosuits changed to have swappable arms and cores (pres refunds disabled when swapping arms/cores).
- Base kit thruster replaced with jump (exos can no longer sprint by default).
- Base Armor is 170 (+40 per armor level) and base speed is 6 m/s (speed capped at 7.5 m/s).
- Additional armor/weight(inverse of speed)/pres cost is dependent on selected arms:
  - Railgun: 25/0.12/25
  - Minigun: 75/0.2/25
  - Claw: 75/0.08/15
- Cores (optional upgrade):
  - Ejection Seat: Auto-ejects marine on exosuit reaching 0 armor (+0.025 Weight / Costs 5 pres).
    - Requires valid ejection spot.
    - Empty exosuit will spawn with 50 armor upon automatic ejection (minus overflow damage).
    - Empty exosuit must have >50 armor to enter exosuit after automatic ejection.
  - Thruster: Increases movement speed and allows for flight at the cost of energy (+0.05 Weight / Costs 5 pres).
    - Min 25% activation energy required and initial 12.5% fuel cost when activated.
    - Vertical boost automatically activates upon holding space bar and stacks with base jump.
    - Vertical boost has high initial acceleration, but slows down over time.
    - Flying uses twice the amount of energy as moving along the ground.
- Settings to make duals fire both arms upon primary attack (options -> mods -> CBM: Accessibility Options)

### Railgun
- Railgun reworked to be more forgiving and less "bursty".
- Firing cooldown set to 1s from 1.4s.
- Charge time to 1s from 2s.
- Shots can be stored for 2s.
- Base damage range is now 35 (0% charge) to 70 (100% charge) from 10/150.
  - Maximum burst is 140 (280 for structures) at W0. Down from ~170 (340) in vanilla.
  - Maximum DPS is 70 (140 for structures) at W0. Down from ~88 (176) in vanilla.
- Maximum range set to 30 m and falloff removed.
- Dual railgun now allows simultaneous firing of both arms.
- Target highlighting now works on all lifeforms and alien structures (red).
- Target highlighting now matches maximum range of railgun.

### Claw
- Reintroduced into the game.
- Deals 50 structural damage.
  - Scales with weapon upgrades!
- Range is 2.8 (2.2 in vanilla).
- Pierces through multiple targets in range.

### Jetpack
- Min 6% activation energy required (bugfix).
- No longer affected by stomp when slightly above the ground (bugfix).
- Tech unlock cost to 20 from 25 tres.

### Hand Grenades
- Self damage reduced by 66% (grenades/mines).
- Pulse Grenades:
  - Debuff range increased by 50%.
  - Base damage set to 15 from 50.
  - Debuff duration is now 3.5s from 5s.
  - No longer reduces energy regeneration (bugfix).
- Cluster Grenades:
  - Cluster damage type modifier increased from 2.5 to 2.875 (net neutral with structure eHP changes).
  - Cluster grenade range and fragment range reduced by 20%.

### Electrify Debuff (pulse/plasma/SPARC)
- TLDR: Disables passives, reduces movement speed, and slows alien attacks and abilities.
- Electrify slow on players increased to 30% from 20% (vanilla).
- Electrify now works on structures (including Advanced variants):
  - Whips: Prevents slapping / bombarding, reduces movement speed.
  - Hydra: Prevents spiking.
  - Crag: Prevents healing and douse, reduces movement speed.
  - Shift: Prevents energize and stormcloud, reduces movement speed.
  - Shade: Prevents cloaking and sonar, reduces movement speed.
  - Hive: Reduces healing by 25%.
  - Shell: Prevents healing.
  - Spur: Prevents movement.
  - Veils: Prevents cloaking.
- NOTE: Active abilities can still be used if electrified!

### Mines
- Can no longer be placed overlapping.
- Can no longer be placed inside the center of gates.
- Will more reliably trigger on valid targets.

### Axe
- Changed to 27.5 damage from 25 (+10% DPS from rifle).

### Welder
- Autopickup for welders reduced from 5 to 1 second.

## MARINE - COMMANDER / STRUCTURES
### Prototype Lab
- Exosuit tech changed to upgrade prototype lab into exosuit prototype lab.
  - The research is tied to the exosuit prototype lab (lost when structure is destroyed or recycled).
- While exosuit prototype lab is researching, a rotating exo hologram will appear above the prototype lab.
  - When completed, the hologram will become static and the map icon will become purple.

### Arc (Robotics) Factory
- New skin and is purple on the map.
- Research time increased to 30s from 20s.

### ARC
- Build time is now 12.5s from 10s.
- Can no longer damage other ARCS (bugfix).
- Can manually target hydras and cysts.
- No more than 5 arcs can exist at once (exploit fix).
- Buffed damage by 15% (net neutral with structure eHP changes).

### MACS
- MACs move 40% faster (7, 5.5 in combat) and have half the line of sight as a drifter.
  - MACs do not turn instantly while in combat.
- Allow MACs to be welded while taking damage.
- MACs are 25% smaller (model size).
- Rollout speed multiplier increased from 2 to 5.
- MACs can be recycled.
- MAC repair rate reduced from 50/s to 30/s (matches MAC build efficacy).
- MAC combat repair rate reduction (90%) removed.
- AI Changes:
  - Taking damage no longer prevents MAC from welding.
  - Marine and Exo can request busy MACs for a weld with "use" key or using the "Need Weld" voice over.
  - MAC won't try to circle behind a Marine who has a welder, or if MAC is far from its leash anchor.
  - MAC stops following marines who phased.
  - Auto search new target to follow if the original died or isn't available.
  - Reduced default order search radius to 12m. Hold position order reduces it to 3m.
  - MAC now prioritizes its closest target first.
  - Reduced follow order secondary job search radius to 6m and snaps to marines with 2m.
  - Enabled and enhanced MAC basic order commands such as Move, Stop, Patrol and Hold position.
  - Multiple MACs can now repair PvE targets simultaneously

### Sentry
- Attack cone increased to 360 degrees from 135 degrees.
- Requires room power instead of sentry battery.
- Sentry supply cost reduced from 15 to 10.
- Cost 7 tres.
- 8s build time.
- Limited to 1.
- Removed weld override (welds at same rate as other structures).
- Increased spread (3 to 7.5 rad).
- Shoots 2x3.5 damage bullets.
- Deals light damage (deals half damage against armor).
- Increased target aquire time (0.15s to 0.4s) and made cooldown trigger on target swap.
- Babblers are now treated as player targets (same priority).

### Observatory
- Provides low resolution motion tracking on aliens within range (improved version of vanilla's).

### Advanced Support
- Advanced support is now 15 tres.
- Catpacked marines now build and weld faster 12.5%.
- Nanoshield cost reduced to 2 from 5.
- Nanoshield snap range decreased to 4 from 6.
- Nanoshield MAC priority put last.

### Commander Drops
- Dropping mines cost 5 tres (from 7 tres).
- Dropping welders cost 2 tres (from 3 tres).

## ALIEN - PLAYER
### Chamber Trait Reworks / Rebelance
- Trait Swapping: (cost reduction)
  - Skulk: 0 (Same as vanilla)
  - Gorge: 1 (Same as vanilla)
  - Lerk: 2 (Changed)
  - Fade: 3 (Changed)
  - Onos: 4 (Changed)
- Carapace:
  - Kept as in vanilla (the Rage replacement is Content Edition only).
- Aura:
  - No longer reveals health information (moved to Advanced Shade)
  - Icon is always yellow.
- Camouflage:
  - Shaders completely reworked to ensure camo is competitive with other upgrades.
  - Cloaking reveal range and rate depend more heavily on veil amount.
  - Onos are silent when crouching with cloak.
  - UI icon only appears when fully cloaked.
- Focus:
  - Properly affects Stab ability now.
  - Fixed bug which slowed Gore by 57% instead of 33%.
  - Gorges now get a 1.5x damage buff instead of a 1.33x buff.

### Gorges
- Babblers
  - Babblers will now detach around the gorge instead of everyone at same location above the gorge.
  - Babblers will stay out for at least the duration of the babbler ball.
  - Babblers are now affected by crush upgrade.
- Hydras and Bilemine cost 30% less energy
- Bile damage accelerates weapon expiration
  - 1 Bile ~ 5 seconds
- Buffed gorge structure healing by 15% (net neutral with structure eHP changes).

### Stomp (onos)
- No longer knocks down marines.
- Applies web debuff.
- Damage increased from 40 to 50 heavy damage.
- Improved terrain pathing.
- Added proper check for marine jumping.

### Boneshield (onos)
- Now blocks railgun shots from piercing through (still must be facing damage source).
- Now prevents health pool damage when blocking (still must be facing damage source).

### Stab (fade)
- Stab research cost reduced from 25 to 20 tres.
- Stab energy cost reduced by 16%.

### Skulk
- Improved movement on wall and ceilings by making fall checks more forgiving.

## ALIEN - COMMANDER / STRUCTURES
### Hives
- Based eHP decreased to be +7.5% of vanilla.
- Gains +2.5% eHP per hive biomass returned to current value after 3rd biomass upgrade.
- Maturation time increased to 260s from 220s.

### Veil/Spur/Shell
- Veils: Cloaked
- Spurs: Moveable (50% movement speed)
- Shells: Selfheal (1% each healingcycle)

### Base Support Structures
- Reduced cost to 8 tres (10 tres for whips) from 13 tres.
- Base speed increased by 25%.
- eHP changed to unify time to kill.
  - eHP for Shift/Crag/Shade/Whip is now 600/600/600/750 at 0% maturity.
  - eHP for Shift/Crag/Shade/Whip is now 1100/1100/1100/1100 at 100% maturity.
- GUIs updated to accommodate new passive icons.
- Added lag compensation to improve hit registration at higher pings.
- Crag:
  - Healwave replaced with Shieldwave.
  - Shieldwave applies full overshield to aliens over duration.
- Whip:
  - Fully matured whips attack without infestation.
  - Increased turning speed before moving.
  - Can order to attack a specific target.
- Shift:
  - Reduced energy regenerate rate by 50%

### Bonewall
- Buffed eHP per biomass from 115 to 140 (~25% increase).

### Drifter
- Unified AoE size of enymze, mucous, and cloaking haze.
- Before casting, a visual will appear denoting the ability and distance for nearby lifeforms.
- A lifeform can be selected to gain access to the drifter castables.
  - Using the buttons or hotkeys will remotely tell the nearest drifter to cast an ability.
- Will return to previous position, patrol path, or targeted lifeform upon using a castable.
- Will no longer follow echoed unfinished structures over the entire map (bugfix).
- Will no longer autobuild hydras or bilemines anymore (QoL).
- Can auto-build a cyst chain by holding shift and right clicking on them.
- Will attempt check for structures to grow nearby a move order (QoL).
- Following a lifeform will no longer result in the drifter standing still (will more closely follow lifeform movement).
- Stop order added.
- Cloaking Haze: (replaced hallucination cloud)
  - Cloaks players, eggs and drifters (including those in combat) for up to 5 seconds.
