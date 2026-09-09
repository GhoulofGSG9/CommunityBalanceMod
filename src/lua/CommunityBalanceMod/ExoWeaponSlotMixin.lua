-- ====**** CommunityBalanceMod\ExoWeaponSlotMixin.lua ****====
--
-- Post hook on lua/Weapons/Marine/ExoWeaponSlotMixin.lua.
--
-- string.lower() is not compiled by LuaJIT, so rebuilding "activity_left" and the
-- material parameter names inside OnUpdateAnimationInput / OnUpdateRender aborted the
-- trace and got every exo weapon update blacklisted for good. The tables are created at
-- load so callers can cache a local reference, and filled on the first __initmixin, by
-- which point ExoWeaponHolder is loaded.

local gSlotKeyTables = {}
local gSlotKeysBuilt = false

local function FillSlotKeyTable(prefix, keys)

    for value, name in pairs(ExoWeaponHolder.kSlotNames) do
        if type(value) == "number" then
            keys[value] = prefix .. string.lower(name)
        end
    end

end

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

local kOriginalInitMixin = ExoWeaponSlotMixin.__initmixin

function ExoWeaponSlotMixin:__initmixin()

    if not gSlotKeysBuilt then
        BuildSlotKeys()
    end

    kOriginalInitMixin(self)

end

function ExoWeaponSlotMixin:GetExoWeaponSlotName()
    return ExoWeaponSlotMixin.kSlotName[self.exoWeaponSlot]
end
