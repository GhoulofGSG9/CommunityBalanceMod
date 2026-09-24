-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\Weapons\Marine\ExoWeaponSlotMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

ExoWeaponSlotMixin = CreateMixin(ExoWeaponSlotMixin)
ExoWeaponSlotMixin.type = "ExoWeaponSlot"

ExoWeaponSlotMixin.networkVars =
{
    exoWeaponSlot = "enum ExoWeaponHolder.kSlotNames"
}

ExoWeaponSlotMixin.optionalCallbacks =
{
    OnWeaponSlotAssigned = "Call after SetExoWeaponSlot() is called"
}

-- Per-slot key strings, built once instead of per frame.
-- string.lower() is not compiled by LuaJIT, so rebuilding "activity_left" (and
-- the material/GUI parameter names) inside OnUpdateAnimationInput/OnUpdateRender
-- aborted the trace and got every exo weapon update blacklisted for good.
-- The tables are created at file load so callers can cache a local reference to
-- them, and filled on the first __initmixin, by which point ExoWeaponHolder is
-- loaded. Indexing them with a bad slot yields nil and fails loudly rather than
-- silently driving the wrong side.
local gSlotKeyTables = {}
local gSlotKeysBuilt = false

local function FillSlotKeyTable(prefix, keys)

    for value, name in pairs(ExoWeaponHolder.kSlotNames) do
        if type(value) == "number" then
            keys[value] = prefix .. string.lower(name)
        end
    end

end

-- On the mixin rather than a bare global so the name cannot collide with a
-- mod. Mixin function fields are copied onto every class that takes the
-- mixin, so each exo weapon class gains a dead GetSlotKeyTable method; that
-- is the cost of keeping it out of the global namespace.
function ExoWeaponSlotMixin.GetSlotKeyTable(prefix)

    local keys = gSlotKeyTables[prefix]
    if not keys then

        keys = {}
        gSlotKeyTables[prefix] = keys
        if gSlotKeysBuilt then
            FillSlotKeyTable(prefix, keys)
        end

    end

    return keys

end

local function BuildSlotKeys()

    for prefix, keys in pairs(gSlotKeyTables) do
        FillSlotKeyTable(prefix, keys)
    end
    gSlotKeysBuilt = true

end

ExoWeaponSlotMixin.kSlotName = ExoWeaponSlotMixin.GetSlotKeyTable("")
ExoWeaponSlotMixin.kActivityInput = ExoWeaponSlotMixin.GetSlotKeyTable("activity_")

function ExoWeaponSlotMixin:__initmixin()
    PROFILE("ExoWeaponSlotMixin:__initmixin")
    if not gSlotKeysBuilt then
        BuildSlotKeys()
    end
    self.exoWeaponSlot = ExoWeaponHolder.kSlotNames.Left
end

function ExoWeaponSlotMixin:SetExoWeaponSlot(slot)

    assert(Server)
    
    self.exoWeaponSlot = slot
    
    if self.OnWeaponSlotAssigned then
        self:OnWeaponSlotAssigned(slot)
    end
    
end

function ExoWeaponSlotMixin:GetExoWeaponSlotName()
    return ExoWeaponSlotMixin.kSlotName[self.exoWeaponSlot]
end

function ExoWeaponSlotMixin:GetIsLeftSlot()
    return self.exoWeaponSlot == ExoWeaponHolder.kSlotNames.Left
end

function ExoWeaponSlotMixin:GetIsRightSlot()
    return self.exoWeaponSlot == ExoWeaponHolder.kSlotNames.Right
end

function ExoWeaponSlotMixin:GetExoWeaponSlot()
    return self.exoWeaponSlot
end