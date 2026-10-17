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

function ExoWeaponSlotMixin:__initmixin()
    PROFILE("ExoWeaponSlotMixin:__initmixin")
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
    return string.lower(EnumToString(ExoWeaponHolder.kSlotNames, self.exoWeaponSlot))
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
-- Sound emitters follow the actual arm sockets, independent of weapon entity origin.
function ExoWeaponSlotMixin:GetWeaponSoundCoords()
 local player=self:GetParent()
 if not player then return self:GetCoords() end
 local side=self:GetIsLeftSlot() and "l" or "r"
 local names
 if self:isa("Minigun") then names={"fxnode_"..side.."_minigun_muzzle"}
 elseif self:isa("Railgun") then names={"fxnode_"..side.."_railgun_muzzle"}
 elseif self:isa("PlasmaLauncher") then names={"fxnode_"..side.."_plasma_charge"}
 elseif self:isa("Claw") then
  -- Use animated fist bones, never cockpit GUI joints.
  names=Client and player==Client.GetLocalPlayer() and not player:GetIsThirdPerson()
      and {side=="l" and "bone_Claw_Hand" or "R_bone_Claw_Hand"}
      or {side=="l" and "Exosuit_LWrist" or "Exosuit_RWrist"}
 else names={"fxnode_"..side.."_claw"} end
 -- View sockets are camera-local; audio always receives world coordinates.
 local localView=Client and player==Client.GetLocalPlayer() and not player:GetIsThirdPerson()
 local source=localView and player:GetViewModelEntity() or player
 if source and source.GetAttachPointIndex then
  for _,name in ipairs(names)do
   if source:GetAttachPointIndex(name)>=0 then
    local frame=source:GetAttachPointCoords(name)
    if frame and frame:GetIsFinite() then
     if localView then return GetRenderCameraCoords()*frame end
     return frame
    end
   end
  end
 end
 local frame=player:GetViewCoords()
 -- Authored claw rigs place the left hand on +X and the right on -X.
 local sideOffset=self:isa("Claw") and (side=="l" and .55 or -.55) or (side=="l" and -.55 or .55)
 frame.origin=player:GetEyePos()+frame.xAxis*sideOffset+frame.zAxis*.6-frame.yAxis*.3
 return frame
end
function ExoWeaponSlotMixin:UpdateWeaponSound(sound,volume)
 if not Client or not sound then return end
 -- Only a live (playing) instance has an FMOD handle; touching a stopped one spams
 -- "An invalid object handle was used" every frame.
 if not sound:GetIsPlaying() then return end
 sound:SetCoords(self:GetWeaponSoundCoords())
 sound:SetPositional(true)
 -- Full authored level in the cockpit; normal spatial falloff outside it.
 sound:SetMinDistance(3)
 sound:SetMaxDistance(50)
 sound:SetVolume(volume or 1)
end
function ExoWeaponSlotMixin:PlayWeaponSound(asset,volume)
 if Predict then return end
 local player=self:GetParent();if not player then return end
 if Client and (player~=Client.GetLocalPlayer() or not Client.GetIsControllingPlayer())then return end
 -- Server event excludes the predicting owner; that owner plays it once locally.
 StartSoundEffectAtOrigin(asset,self:GetWeaponSoundCoords().origin,volume or 1,player)
end
