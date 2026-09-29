-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Alien\DropStructureAbility.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Alien/Ability.lua")
Script.Load("lua/Weapons/Alien/HydraAbility.lua")
Script.Load("lua/Weapons/Alien/ClogAbility.lua")
Script.Load("lua/Weapons/Alien/WebsAbility.lua")
Script.Load("lua/Weapons/Alien/BabblerEggAbility.lua")

class 'DropStructureAbility' (Ability)

local kMaxStructuresPerType = 20
local kDropCooldown = 1

DropStructureAbility.kMapName = "drop_structure_ability"

PrecacheAsset("sound/NS2.fev/alien/gorge/create_fail")
local kAnimationGraph = PrecacheAsset("models/alien/gorge/gorge_view.animation_graph")

DropStructureAbility.kSupportedStructures = { HydraStructureAbility, ClogAbility, WebsAbility, BabblerEggAbility }

local networkVars =
{
    numHydrasLeft = string.format("private integer (0 to %d)", kMaxStructuresPerType),
    numWebsLeft = string.format("private integer (0 to %d)", kMaxStructuresPerType),
    numClogsLeft = string.format("private integer (0 to %d)", kMaxStructuresPerType),
    numBabblersLeft = string.format("private integer (0 to %d)", kMaxStructuresPerType),
}

function DropStructureAbility:GetAnimationGraphName()
    return kAnimationGraph
end

function DropStructureAbility:GetActiveStructure()

    if self.activeStructure == nil then
        return nil
    else
        return DropStructureAbility.kSupportedStructures[self.activeStructure]
    end

end

function DropStructureAbility:OnCreate()

    Ability.OnCreate(self)

    self.dropping = false
    self.mouseDown = false
    self.activeStructure = nil

    -- for GUI
    self.numHydrasLeft = 0
    self.numWebsLeft = 0
    self.numClogsLeft = 0
    self.numBabblersLeft = 0
    self.lastClickedPosition = nil
    self.lastClickedPositionNormal = nil

    -- Result of the last ghost placement check (see OnProcessIntermediate).
    self.ghostCoords = nil
    self.ghostNormal = nil
    self.placementValid = false
    self.placementValidIgnoringCooldown = false

end

function DropStructureAbility:GetDeathIconIndex()
    return kDeathMessageIcon.Consumed
end

function DropStructureAbility:SetActiveStructure(structureNum)

    self.activeStructure = structureNum
    self.lastClickedPosition = nil
    self.lastClickedPositionNormal = nil
    self.ghostCoords = nil
    self.ghostNormal = nil
    self.placementValid = false
    self.placementValidIgnoringCooldown = false

end

function DropStructureAbility:GetHasDropCooldown()
    return self.timeLastDrop ~= nil and self.timeLastDrop + kDropCooldown > Shared.GetTime()
end

function DropStructureAbility:GetSecondaryTechId()
    return kTechId.Spray
end

function DropStructureAbility:GetNumStructuresBuilt(techId)

    if techId == kTechId.Hydra then
        return self.numHydrasLeft
    end

    if techId == kTechId.Clog then
        return self.numClogsLeft
    end

    if techId == kTechId.Web then
        return self.numWebsLeft
    end

    if techId == kTechId.BabblerEgg then
        return self.numBabblersLeft
    end

    -- unlimited
    return -1
end

function DropStructureAbility:OnPrimaryAttack(player)

    if Client then

        if self.activeStructure
                and not self.dropping
                and not self.mouseDown then

            self.mouseDown = true

            if player:GetEnergy() >= self:GetEnergyCost() then

                if self:PerformPrimaryAttack(player) then
                    self.dropping = true
                end

            else
                player:TriggerInvalidSound()
            end

        end

    end

end

function DropStructureAbility:OnPrimaryAttackEnd()

    if not Shared.GetIsRunningPrediction() then

        if Client and self.dropping then
            self:OnSetActive()
        end

        self.dropping = false
        self.mouseDown = false

    end

end

function DropStructureAbility:GetIsDropping()
    return self.dropping
end

function DropStructureAbility:GetEnergyCost()
    local activeStructure = self:GetActiveStructure()
    if activeStructure then
        return activeStructure:GetEnergyCost()
    end

    return kDropStructureEnergyCost
end

function DropStructureAbility:GetDamageType()
    return kHealsprayDamageType
end

function DropStructureAbility:GetHUDSlot()
    return 2
end

function DropStructureAbility:GetHasSecondary(player)
    return true
end

function DropStructureAbility:OnSecondaryAttack(player)

    if player and self.previousWeaponMapName and player:GetWeapon(self.previousWeaponMapName) then
        player:SetActiveWeapon(self.previousWeaponMapName)
    end

end

function DropStructureAbility:GetSecondaryEnergyCost()
    return 0
end

function DropStructureAbility:PerformPrimaryAttack(player)

    if self.activeStructure == nil then
        return false
    end

    local success = false

    local coords, normal = self.ghostCoords, self.ghostNormal
    local secondClick = true

    if LookupTechData(self:GetActiveStructure().GetDropStructureId(), kTechDataSpecifyOrientation, false) then
        secondClick = self.lastClickedPosition ~= nil
    end

    local valid
    if secondClick then
        valid = self.placementValid
    else
        valid = self.placementValidIgnoringCooldown
    end

    if secondClick then

        if valid and coords then

            -- Ensure they have enough resources.
            local cost = GetCostForTech(self:GetActiveStructure().GetDropStructureId())
            if player:GetResources() >= cost and not self:GetHasDropCooldown() then

                local message = BuildGorgeDropStructureMessage(player:GetEyePos(), player:GetViewCoordsZAxis(), self.activeStructure, self.lastClickedPosition, self.lastClickedPositionNormal, coords.origin, normal)
                Client.SendNetworkMessage("GorgeBuildStructure", message, true)
                self.timeLastDrop = Shared.GetTime()
                success = true

                self.lastClickedPosition = nil
                self.lastClickedPositionNormal = nil

            end

        end

    elseif valid and coords then
        self.lastClickedPosition = Vector(coords.origin)
        self.lastClickedPositionNormal = normal

    end

    if not valid then
        player:TriggerInvalidSound()
    end

    return success

end


local kGhostPlacementTolerance = 5
function DropStructureAbility:DropStructure(player, origin, direction, structureAbility, lastClickedPosition, lastClickedPositionNormal, ghostOrigin, ghostNormal)

    -- If we have enough resources
    if Server then

        local coords, valid, onEntity = self:GetPositionForStructure(origin, direction, structureAbility, lastClickedPosition, lastClickedPositionNormal)

        if valid and ghostOrigin and (ghostOrigin - coords.origin):GetLength() < kGhostPlacementTolerance then
            coords.origin = ghostOrigin
        end

        local techId = structureAbility:GetDropStructureId()

        local maxStructures = -1

        if not LookupTechData(techId, kTechDataAllowConsumeDrop, false) then
            maxStructures = LookupTechData(techId, kTechDataMaxAmount, 0)
        end

        valid = valid and self:GetNumStructuresBuilt(techId) ~= maxStructures -- -1 is unlimited

        local cost = LookupTechData(structureAbility:GetDropStructureId(), kTechDataCostKey, 0)
        local enoughRes = player:GetResources() >= cost
        local energyCost = structureAbility:GetEnergyCost()
        local enoughEnergy = player:GetEnergy() >= energyCost

        if valid and enoughRes and structureAbility:IsAllowed(player) and enoughEnergy and not self:GetHasDropCooldown() then

            -- Create structure
            local structure = self:CreateStructure(coords, player, structureAbility)

            if structure then

                structure:SetOwner(player)

                if HasMixin(structure, "ClogFall") then
                    if onEntity then
                        if onEntity:isa("Clog") then
                            onEntity:ConnectToClog(structure)
                        elseif structure:isa("Clog") and onEntity:isa("Web") then
                            onEntity:ConnectToClog(structure)
                        else
                            structure.fallWaiting = 0.0
                            structure:SetUpdates(true, kDefaultUpdateRate)
                        end
                    else
                        -- touching level, therefore can never move again, as the level doesn't move.
                        structure.doneFalling = true
                    end
                end

                player:GetTeam():AddGorgeStructure(player, structure)

                -- Check for space
                if structure:SpaceClearForEntity(coords.origin) then

                    local angles = Angles()

                    if structure:isa("BabblerEgg") and coords.yAxis.y > 0.8 then
                        angles.yaw = math.random() * math.pi * 2

                    elseif structure:isa("Clog") then

                        angles.yaw = math.random() * math.pi * 2
                        angles.pitch = math.random() * math.pi * 2
                        angles.roll = math.random() * math.pi * 2

                    else
                        angles:BuildFromCoords(coords)
                    end

                    structure:SetAngles(angles)
                    
                    if structure.SetVariant then
                        local client = player:GetClient()
                        if client and client.variantData then
                            local structureVariant = nil
                            if structure:isa("Clog") then
                                structureVariant = client.variantData.clogVariant
                            elseif structure:isa("BabblerEgg") then
                                structureVariant = client.variantData.babblerEggVariant
                            elseif structure:isa("Hydra") then
                                structureVariant = client.variantData.hydraVariant
                            end
                            structure:SetVariant(structureVariant)
                        end
                    end

                    if structure.OnCreatedByGorge then
                        structure:OnCreatedByGorge()
                    end

                    player:AddResources(-cost)

                    player:DeductAbilityEnergy(energyCost)
                    player:TriggerEffects("spit_structure", {effecthostcoords = Coords.GetLookIn(origin, direction)} )

                    if structureAbility.OnStructureCreated then
                        structureAbility:OnStructureCreated(structure, lastClickedPosition)
                    end

                    self.timeLastDrop = Shared.GetTime()

                    return true

                else

                    player:TriggerInvalidSound()
                    DestroyEntity(structure)

                end

            else
                player:TriggerInvalidSound()
            end

        else

            if not valid then
                player:TriggerInvalidSound()
            elseif not enoughRes then
                player:TriggerInvalidSound()
            end

        end

    end

    return true

end

function DropStructureAbility:OnDropStructure(origin, direction, structureIndex, lastClickedPosition, lastClickedPositionNormal, ghostOrigin, ghostNormal)

    local player = self:GetParent()

    if player then

        local structureAbility = DropStructureAbility.kSupportedStructures[structureIndex]
        if structureAbility then
            self:DropStructure(player, origin, direction, structureAbility, lastClickedPosition, lastClickedPositionNormal, ghostOrigin, ghostNormal)
        end

    end

end

function DropStructureAbility:CreateStructure(coords, player, structureAbility, lastClickedPosition)
    local created_structure = structureAbility:CreateStructure(coords, player, lastClickedPosition)
    if created_structure then
        return created_structure
    else
        return CreateEntity(structureAbility:GetDropMapName(), coords.origin, player:GetTeamNumber())
    end
end

local function FilterBabblersAndTwo(ent1, ent2)
    return function (test) return test == ent1 or test == ent2 or test:isa("Babbler") end
end

-- Clog bridge assist -------------------------------------------------------
local function GetBridgeFilter(player, weapon, ignoreClogs)
    return function(test)
        return test == player or test == weapon or test:isa("Babbler") or (ignoreClogs and test:isa("Clog"))
    end
end

-- Returns the clog to extend from and the new clog's center, or nil.
local function GetClogBridgeTarget(player, weapon, startPosition, direction, trace)
    local kBridgeMinLookDown = 0.6      -- view direction y must be below (-0.6  is ~37 deg down)
    local kBridgeMinNormalY = 0.3       -- when aimed directly at a clog, only its upward-facing part
    local kBridgeProbeAhead = 1.0       -- probe this far ahead on the horizontal plane
    local kBridgeProbeDrops = { 1.0, 1.6 }  -- ...then this far below the eye, then trace back
    local kBridgeProbeLength = 3.0
    local kBridgeGroundMargin = 0.3    -- aimed ground must be this far below the clog's bottom

    if direction.y > -kBridgeMinLookDown then
        return nil
    end

    -- Horizontal facing, derived from the passed-in direction so client and server agree.
    local flat = Vector(direction.x, 0, direction.z)
    if flat:GetLength() < 0.001 then
        flat = Angles(0, player:GetViewAngles().yaw, 0):GetCoords().zAxis
    else
        flat = GetNormalizedVector(flat)
    end

    local clog

    -- Aimed at ground / air: look for the tip clog under the gorge.
    -- Go ahead on the horizontal plane, drop down, then trace back toward the gorge.
    local filter = GetBridgeFilter(player, weapon)
    local ahead = startPosition + flat * kBridgeProbeAhead

    for i, drop in ipairs(kBridgeProbeDrops) do

        local from = ahead - Vector(0, drop, 0)
        local to = from - flat * kBridgeProbeLength
        local back = Shared.TraceRay(from, to, CollisionRep.Default, PhysicsMask.AllButPCsAndRagdollsAndBabblers, filter)

        if back.fraction < 1 and back.entity and back.entity:isa("Clog") then
            clog = back.entity
            break
        end

    end

    if not clog then
        return nil
    end

    -- If the aim ray hit ground, only snap when it is clearly below the bridge
    -- (aiming into the drop). Otherwise the gorge wants a normal ground placement.
    if trace.fraction < 1 and trace.endPoint.y > clog:GetOrigin().y - Clog.kRadius - kBridgeGroundMargin then
        return nil
    end

    local yVariation = 0.08 + math.sin(Shared.GetTime() / 4) / 14 -- to give a more uneven look to bridges
    local clogOrig = clog:GetOrigin() - Vector(0, (Clog.kRadius / 2) - yVariation, 0)
    local center = clogOrig + flat * (Clog.kRadius / 2)
    local target = clogOrig + flat * (Clog.kRadius * (1.65 + math.cos(Shared.GetTime() / 10) / 4))

    -- Sweep from the old clog to the new spot; if anything is in the way, fall back to normal placement.
    local e = Clog.kRadius * 0.6
    local check = Shared.TraceBox(Vector(e, e, e), center, target,
        CollisionRep.Default, PhysicsMask.AllButPCsAndRagdollsAndBabblers,
        GetBridgeFilter(player, weapon, true))
    if check.fraction < 1 then
        return nil
    end

    return clog, target

end

-- Given a gorge player's position and view angles, return a position and orientation
-- for structure. Used to preview placement via a ghost structure and then to create it.
-- Also returns bool if it's a valid position or not.
function DropStructureAbility:GetPositionForStructure(startPosition, direction, structureAbility, lastClickedPosition, lastClickedPositionNormal)

    PROFILE("DropStructureAbility:GetPositionForStructure")

    local validPosition = false
    local range = structureAbility:GetDropRange(lastClickedPosition)
    local origin = startPosition + direction * range
    local player = self:GetParent()

    -- Trace short distance in front
    local trace = Shared.TraceRay(player:GetEyePos(), origin, CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, FilterBabblersAndTwo(player, self))

    local displayOrigin = trace.endPoint


    -- If we hit nothing, try a slightly bigger ray
    if trace.fraction == 1 then
        local boxTrace = Shared.TraceBox(Vector(0.2,0.2,0.2), player:GetEyePos(), origin,  CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, EntityFilterTwo(player, self))
        if boxTrace.entity and boxTrace.entity:isa("Web") then
            trace = boxTrace
        end

    end

    -- If we still hit nothing, trace down to place on ground
    if trace.fraction == 1 then
        origin = startPosition + direction * range
        trace = Shared.TraceRay(origin, origin - Vector(0, range, 0), CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, FilterBabblersAndTwo(player, self))
    end

    -- If it hits something, position on this surface (must be the world or another structure)
    if trace.fraction < 1 then

        if trace.entity == nil then
            validPosition = true

        elseif trace.entity:isa("Infestation") or trace.entity:isa("Clog") then
            validPosition = true
        elseif trace.entity:isa("Web") and structureAbility.GetDropMapName() == Clog.kMapName then
            -- Allow up to 3 entites on a web
            validPosition = true
        end

        displayOrigin = trace.endPoint
    end

    -- Clog bridge assist (also works when the aim ray hit ground or nothing)
    if structureAbility.GetDropMapName() == Clog.kMapName and not trace.entity then

        local bridgeClog, bridgeTarget = GetClogBridgeTarget(player, self, startPosition, direction, trace)
        if bridgeClog then
            -- Later code only reads these fields, so a plain table is enough.
            trace = {
                fraction = 0,
                endPoint = bridgeTarget,
                normal = Vector(0, 1, 0),
                entity = bridgeClog,
                surface = ""
            }
            displayOrigin = bridgeTarget
            validPosition = true
        end

    end

    -- Can only be built on infestation
    local requiresInfestation = LookupTechData(structureAbility.GetDropStructureId(), kTechDataRequiresInfestation)
    if requiresInfestation and not GetIsPointOnInfestation(displayOrigin) then

        if self:GetActiveStructure().OverrideInfestationCheck then
            validPosition = self:GetActiveStructure():OverrideInfestationCheck(trace)
        else
            validPosition = false
        end

    end

    if not structureAbility.AllowBackfacing() and trace.normal:DotProduct(GetNormalizedVector(startPosition - trace.endPoint)) < 0 then
        validPosition = false
    end

    -- Don't allow dropped structures to go too close to techpoints and resource nozzles
    if GetPointBlocksAttachEntities(displayOrigin) then
        validPosition = false
    end

    if not structureAbility:GetIsPositionValid(displayOrigin, player, trace.normal, lastClickedPosition, lastClickedPositionNormal, trace.entity) then
        validPosition = false
    end

    if trace.surface == "nocling" then
        validPosition = false
    end

    -- Don't allow placing above or below us and don't draw either
    local structureFacing = Vector(direction)

    if math.abs(Math.DotProduct(trace.normal, structureFacing)) > 0.9 then
        structureFacing = trace.normal:GetPerpendicular()
    end

    -- Coords.GetLookIn will prioritize the direction when constructing the coords,
    -- so make sure the facing direction is perpendicular to the normal so we get
    -- the correct y-axis.
    local perp = Math.CrossProduct( trace.normal, structureFacing )
    structureFacing = Math.CrossProduct( perp, trace.normal )

    local coords = Coords.GetLookIn( displayOrigin, structureFacing, trace.normal )

    if structureAbility.ModifyCoords then
        structureAbility:ModifyCoords(coords, lastClickedPosition, trace.normal, player)
    end

    -- perform a final check to ensure the gorge isn't trying to build from inside a clog.
    if GetIsPointInsideClogs(player:GetEyePos()) then
        validPosition = false
    end

    return coords, validPosition, trace.entity, trace.normal

end

function DropStructureAbility:OnDraw(player, previousWeaponMapName)

    Ability.OnDraw(self, player, previousWeaponMapName)

    self.previousWeaponMapName = previousWeaponMapName
    self.dropping = false
    self.activeStructure = nil

end

function DropStructureAbility:OnTag(tagName)
    if tagName == "shoot" then
        self.dropping = false
    end
end

function DropStructureAbility:OnUpdateAnimationInput(modelMixin)

    PROFILE("DropStructureAbility:OnUpdateAnimationInput")

    modelMixin:SetAnimationInput("ability", "chamber")

    local activityString = "none"
    if self.dropping then
        activityString = "primary"
    end
    modelMixin:SetAnimationInput("activity", activityString)

end

function DropStructureAbility:ProcessMoveOnWeapon(input)

    -- Show ghost if we're able to create structure, and if menu is not visible
    local player = self:GetParent()
    if player and player:GetIsAlive() then

        if Server then

            local team = player:GetTeam()
            local numAllowedHydras = LookupTechData(kTechId.Hydra, kTechDataMaxAmount, -1)
            local numAllowedClogs = LookupTechData(kTechId.Clog, kTechDataMaxAmount, -1)
            local numAllowedWebs = LookupTechData(kTechId.Web, kTechDataMaxAmount, -1)
            local numAllowedBabblers = LookupTechData(kTechId.BabblerEgg, kTechDataMaxAmount, -1)

            if numAllowedHydras >= 0 then
                self.numHydrasLeft = team:GetNumDroppedGorgeStructures(player, kTechId.Hydra)
            end

            if numAllowedClogs >= 0 then
                self.numClogsLeft = team:GetNumDroppedGorgeStructures(player, kTechId.Clog)
            end

            if numAllowedWebs >= 0 then
                self.numWebsLeft = team:GetNumDroppedGorgeStructures(player, kTechId.Web)
            end

            if numAllowedBabblers >= 0 then
                self.numBabblersLeft = team:GetNumDroppedGorgeStructures(player, kTechId.BabblerEgg)
            end

        end

    end

end

function DropStructureAbility:GetShowGhostModel()
    return self.activeStructure ~= nil
end

function DropStructureAbility:GetGhostModelCoords()
    return self.ghostCoords
end

function DropStructureAbility:GetIsPlacementValid()
    return self.placementValid
end

function DropStructureAbility:GetIgnoreGhostHighlight()
    if self.activeStructure ~= nil and self:GetActiveStructure().GetIgnoreGhostHighlight then
        return self:GetActiveStructure():GetIgnoreGhostHighlight()
    end

    return false

end

function DropStructureAbility:GetGhostModelTechId()

    if self.activeStructure == nil then
        return nil
    else
        return self:GetActiveStructure():GetDropStructureId()
    end

end

function DropStructureAbility:GetGhostModelName(player)

    if self.activeStructure ~= nil and self:GetActiveStructure().GetGhostModelName then
        return self:GetActiveStructure():GetGhostModelName(self)
    end

    return nil

end

if Client then

    function DropStructureAbility:OnProcessIntermediate(input)

        if not self.activeStructure then
            return
        end

        local player = self:GetParent()
        if player then

            local viewDirection = player:GetViewCoordsZAxis()
            self.ghostCoords, self.placementValid, self.ghostEntity, self.ghostNormal = self:GetPositionForStructure(player:GetEyePos(), viewDirection, self:GetActiveStructure(), self.lastClickedPosition, self.lastClickedPositionNormal)

            if player:GetResources() < LookupTechData(self:GetActiveStructure():GetDropStructureId(), kTechDataCostKey) then
                self.placementValid = false
            end

            self.placementValidIgnoringCooldown = self.placementValid

            if self:GetHasDropCooldown() then
                self.placementValid = false
            end

        end

    end

    function DropStructureAbility:CreateBuildMenu()

        if not self.buildMenu then
            self.buildMenu = GetGUIManager():CreateGUIScript("GUIGorgeBuildMenu")
        end

    end

    function DropStructureAbility:DestroyBuildMenu()

        if self.buildMenu ~= nil then

            GetGUIManager():DestroyGUIScript(self.buildMenu)
            self.buildMenu = nil

        end

    end

    function DropStructureAbility:OnDestroy()

        self:DestroyBuildMenu()
        Ability.OnDestroy(self)

    end

    function DropStructureAbility:OnKillClient()
        self.menuActive = false
    end

    function DropStructureAbility:OnDrawClient()

        Ability.OnDrawClient(self)

        -- We need this here in case we switch to it via Prev/NextWeapon keys

        -- Do not show menu for other players or local spectators.
        local player = self:GetParent()
        if player:GetIsLocalPlayer() and self:GetActiveStructure() == nil and Client.GetIsControllingPlayer() then
            self.menuActive = true
        end

    end

    local function UpdateGUI(self, player)

        local localPlayer = Client.GetLocalPlayer()
        if localPlayer == player then
            self:CreateBuildMenu()
        end

        if self.buildMenu then
            self.buildMenu:SetIsVisible(player and localPlayer == player and player:isa("Gorge") and self.menuActive and not HelpScreen_GetHelpScreen():GetIsBeingDisplayed() and not GetMainMenu():GetVisible())
        end

    end

    function DropStructureAbility:OnHolsterClient()

        self.menuActive = false
        Ability.OnHolsterClient(self)
        self.activeStructure = nil

    end

    function DropStructureAbility:OnSetActive()
    end

    function DropStructureAbility:OverrideInput(input)

        if self.buildMenu then

            -- Build menu is up, let it handle input
            if self.buildMenu:GetIsVisible() then

                local selected = false
                input, selected = self.buildMenu:OverrideInput(input)
                self.menuActive = not selected

            else

                -- If player wants to switch to this, open build menu immediately
                local weaponSwitchCommands = { Move.Weapon1, Move.Weapon2, Move.Weapon3, Move.Weapon4, Move.Weapon5 }
                local thisCommand = weaponSwitchCommands[ self:GetHUDSlot() ]

                if bit.band( input.commands, thisCommand ) ~= 0 then
                    self.menuActive = true
                end

            end

        end

        return input

    end

    function DropStructureAbility:OnUpdateRender()
        UpdateGUI(self, self:GetParent())
    end

end

Shared.LinkClassToMap("DropStructureAbility", DropStructureAbility.kMapName, networkVars)
