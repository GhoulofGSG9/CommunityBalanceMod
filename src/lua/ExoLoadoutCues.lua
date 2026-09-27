-- ======= Copyright (c) 2003-2026, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\ExoLoadoutCues.lua
--
-- World-view cues that let other players read an exosuit's loadout. The flamethrower and
-- plasma arms reuse the railgun model and the core modules change nothing on the suit, so
-- without these an alien cannot tell what it is about to fight.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

-- The arms' own muzzle effects, so the tell looks like the weapon and shows in both views.
local kFlameMuzzleViewCinematic = PrecacheAsset("cinematics/marine/flamethrower/flame_1p.cinematic")
local kFlameMuzzleCinematic = PrecacheAsset("cinematics/marine/flamethrower/flame.cinematic")
local kPlasmaMuzzleCinematic = PrecacheAsset("models/plasma/muzzle_flash_plasma.cinematic")
local kBeaconCinematic = PrecacheAsset("cinematics/marine/mac/siren.cinematic")
local kPlatingMaterial = PrecacheAsset("cinematics/vfx_materials/exo_plating.material")
local kPlatingViewMaterial = PrecacheAsset("cinematics/vfx_materials/exo_plating_view.material")
-- The Battle MAC field decal with its extents set to kExoSupportRadius.
local kSupportFieldCinematic = PrecacheAsset("cinematics/healing_field/exo_support_field.cinematic")

if Client then

    -- Every arm pair that can hold a flamethrower or plasma launcher uses a railgun model
    -- (exosuit_rr, exosuit_cr, exosuit_pr), and all three carry both muzzle nodes. Skins only
    -- override materials, so the nodes are the same on every variant. The view models name
    -- the same nodes differently.
    local kArmAttachPoints =
    {
        left = { view = "fxnode_l_railgun_muzzle", world = "fxnode_lrailgunmuzzle",
                 flameTime = "loadoutCueLeftFlameTime", nextCue = "loadoutCueLeftNext" },
        right = { view = "fxnode_r_railgun_muzzle", world = "fxnode_rrailgunmuzzle",
                  flameTime = "loadoutCueRightFlameTime", nextCue = "loadoutCueRightNext" },
    }

    -- An arm that fired a moment ago has already told everyone what it is.
    local kArmCueQuietTime = 8
    local kArmCueIntervalMin = 2.5
    local kArmCueIntervalMax = 4.5

    local kBeaconBlinkPeriod = 1.6
    local kBeaconBlinkOnTime = 0.4

    -- In the suit's own space: no bone sits in the same place on the claw and dual models.
    local kBeaconOffset = Vector(0, 2, 0.6)

    local function DestroyCue(exo, slot)

        local cue = exo.loadoutCues[slot]
        if cue then
            Client.DestroyCinematic(cue.cinematic)
            exo.loadoutCues[slot] = nil
        end

    end

    local function UpdateCue(exo, slot, cinematicName, attachPoint, visible, offset)

        local cue = exo.loadoutCues[slot]

        if cue and (cue.name ~= cinematicName or cue.offset ~= offset) then
            DestroyCue(exo, slot)
            cue = nil
        end

        if cinematicName and not cue then

            -- Negative until the model has streamed in; try again next frame.
            local attachPointIndex = attachPoint and exo:GetAttachPointIndex(attachPoint)
            if attachPointIndex and attachPointIndex < 0 then
                return
            end

            local coords = Coords.GetIdentity()
            if offset then
                coords.origin = offset
            end

            local cinematic = Client.CreateCinematic(RenderScene.Zone_Default)
            cinematic:SetCinematic(cinematicName)
            cinematic:SetRepeatStyle(Cinematic.Repeat_Endless)
            cinematic:SetParent(exo)
            cinematic:SetCoords(coords)
            if attachPointIndex then
                cinematic:SetAttachPoint(attachPointIndex)
            end

            cue = { cinematic = cinematic, name = cinematicName, offset = offset }
            exo.loadoutCues[slot] = cue

        end

        if cue then
            cue.cinematic:SetIsVisible(visible)
        end

    end

    local function GetArmFiredRecently(exo, weapon, flameTimeField, now)

        if not weapon then
            return false
        end

        if weapon:isa("PlasmaLauncher") then
            return now - (weapon.timeOfLastShot or 0) < kArmCueQuietTime
        end

        if weapon:isa("ExoFlamer") then

            if weapon.isShooting then
                exo[flameTimeField] = now
            end

            return now - (exo[flameTimeField] or -kArmCueQuietTime) < kArmCueQuietTime

        end

        return false

    end

    local function GetNextArmCueTime(now)
        return now + kArmCueIntervalMin + math.random() * (kArmCueIntervalMax - kArmCueIntervalMin)
    end

    -- One muzzle puff every few seconds from an arm that has been quiet.
    local function UpdateArmCue(exo, weapon, side, now)

        local fields = kArmAttachPoints[side]

        if not weapon or GetArmFiredRecently(exo, weapon, fields.flameTime, now) then
            exo[fields.nextCue] = GetNextArmCueTime(now)
            return
        end

        if now < (exo[fields.nextCue] or 0) then
            return
        end
        exo[fields.nextCue] = GetNextArmCueTime(now)

        local viewName, worldName
        if weapon:isa("ExoFlamer") then
            viewName, worldName = kFlameMuzzleViewCinematic, kFlameMuzzleCinematic
        elseif weapon:isa("PlasmaLauncher") then
            viewName, worldName = kPlasmaMuzzleCinematic, kPlasmaMuzzleCinematic
        else
            return
        end

        local isFirstPerson = exo:GetIsLocalPlayer() and not exo:GetIsThirdPerson()
        CreateMuzzleCinematic(weapon, viewName, worldName, isFirstPerson and fields.view or fields.world, exo)

    end

    local kPlatingWorld = { material = "platingMaterial", model = "platingModel", name = kPlatingMaterial }
    local kPlatingView = { material = "platingViewMaterial", model = "platingViewModel", name = kPlatingViewMaterial }

    local function UpdatePlating(exo, fields, model, wanted)

        local material = exo[fields.material]

        if wanted and model then

            if not material then
                material = Client.CreateRenderMaterial()
                material:SetMaterial(fields.name)
                exo[fields.material] = material
            end

            -- A model swap destroys the old render model together with its additive materials.
            if exo[fields.model] ~= model then
                model:AddMaterial(material)
                exo[fields.model] = model
            end

        elseif material then

            if model and exo[fields.model] == model then
                model:RemoveMaterial(material)
            end

            Client.DestroyRenderMaterial(material)
            exo[fields.material] = nil
            exo[fields.model] = nil

        end

    end

    local function GetViewRenderModel(exo)
        local viewModel = exo:GetViewModelEntity()
        return viewModel and viewModel:GetRenderModel()
    end

    function ExoLoadoutCues_Update(exo)

        if not exo.loadoutCues then
            exo.loadoutCues = { }
        end

        local isLocalFirstPerson = exo:GetIsLocalPlayer() and not exo:GetIsThirdPerson()
        local visible = exo:GetIsAlive() and exo:GetIsVisible() and not isLocalFirstPerson

        local now = Shared.GetTime()
        local holder = exo:GetActiveWeapon()
        local hasSlots = holder and holder:isa("ExoWeaponHolder")

        if exo:GetIsAlive() and hasSlots then
            UpdateArmCue(exo, holder:GetLeftSlotWeapon(), "left", now)
            UpdateArmCue(exo, holder:GetRightSlotWeapon(), "right", now)
        end

        local hasSeat = exo.utilityModuleType == kExoModuleTypes.EjectionSeat
        local beaconLit = (now % kBeaconBlinkPeriod) < kBeaconBlinkOnTime
        UpdateCue(exo, "beacon", hasSeat and kBeaconCinematic or nil, nil, visible and beaconLit, kBeaconOffset)

        local ownField = exo:GetIsLocalPlayer() and exo:GetHasSupportAbility()
        local abilityReady = exo:GetIsAlive() and exo:GetSupportAbilityTimeRemaining() == 0
        UpdateCue(exo, "supportField", ownField and kSupportFieldCinematic or nil, nil, abilityReady)

        local hasPlating = exo.utilityModuleType == kExoModuleTypes.Armor
        UpdatePlating(exo, kPlatingWorld, exo._renderModel, visible and hasPlating)
        UpdatePlating(exo, kPlatingView, GetViewRenderModel(exo), isLocalFirstPerson and hasPlating and exo:GetIsAlive())

    end

    function ExoLoadoutCues_Destroy(exo)

        if exo.loadoutCues then
            DestroyCue(exo, "beacon")
            DestroyCue(exo, "supportField")
        end

        UpdatePlating(exo, kPlatingWorld, exo._renderModel, false)
        UpdatePlating(exo, kPlatingView, GetViewRenderModel(exo), false)

    end

end
