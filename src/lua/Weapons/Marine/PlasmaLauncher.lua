Script.Load("lua/Weapons/BulletsMixin.lua")
Script.Load("lua/Weapons/Marine/ExoWeaponSlotMixin.lua")
Script.Load("lua/TechMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/AchievementGiverMixin.lua")
Script.Load("lua/EffectsMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/Weapons/PlasmaBallT3.lua")
class 'PlasmaLauncher'(Entity)
PlasmaLauncher.kMapName="PlasmaLauncher"
PlasmaLauncher.kChargeDuration=1.5
PlasmaLauncher.kShotCooldown=.35
local ballModel=PrecacheAsset("models/marine/exosuit/purpla.model")
local plasmaFireSound=PrecacheAsset("sound/NS2.fev/marine/heavy/railgun_fire")
local chargeSound=PrecacheAsset("sound/NS2.fev/marine/heavy/railgun_charge")
local networkVars={timeChargeStarted="time",plasmalauncherAttacking="boolean",timeOfLastShot="time",
 energyWAmount="float (0 to 1 by 0.01)",lastShotCharge="float (0 to 1 by 0.01)"}
AddMixinNetworkVars(TechMixin,networkVars)
AddMixinNetworkVars(TeamMixin,networkVars)
AddMixinNetworkVars(ExoWeaponSlotMixin,networkVars)
local function clamp(v)return math.max(0,math.min(1,v))end
local function scaledCoords(frame,scale)
 local c=Coords.GetIdentity();c.origin=frame.origin
 c.xAxis=frame.xAxis:GetUnit()*scale;c.yAxis=frame.yAxis:GetUnit()*scale;c.zAxis=frame.zAxis:GetUnit()*scale
 return c
end
local function chargeEffectWorldCoords(frame,isView)
 if not isView then return frame end
 local camera=GetRenderCameraCoords()
 local vf=Client.GetZoneFov(RenderScene.Zone_ViewModel);local wf=Client.GetZoneFov(RenderScene.Zone_Default)
 local factor=math.tan(wf/2)/math.tan(vf/2)
 local function project(v)return Vector(v.x*factor,v.y*factor,v.z)end
 local c=Coords.GetIdentity();c.origin=camera:TransformPoint(project(frame.origin))
 c.xAxis=camera:TransformVector(project(frame.xAxis));c.yAxis=camera:TransformVector(project(frame.yAxis));c.zAxis=camera:TransformVector(project(frame.zAxis))
 return c
end
function PlasmaLauncher:OnCreate()
 Entity.OnCreate(self)
 for _,mixin in ipairs({TechMixin,TeamMixin,DamageMixin,BulletsMixin,ExoWeaponSlotMixin,PointGiverMixin,AchievementGiverMixin,EffectsMixin})do InitMixin(self,mixin)end
 self.timeChargeStarted=0;self.plasmalauncherAttacking=false;self.timeOfLastShot=0;self.energyWAmount=.5;self.lastShotCharge=0
 if Client then
  InitMixin(self,ClientWeaponEffectsMixin)
  self.chargeSound=Client.CreateSoundEffect(Shared.GetSoundIndex(chargeSound));self:UpdateWeaponSound(self.chargeSound,.8)
 end
end
-- One sound start per charge attempt; no replay when the finite ARC clip ends.
function PlasmaLauncher:UpdateChargeAudio(fraction)
 if not Client or not self.chargeSound then return end
 if fraction>0 then
  self:UpdateWeaponSound(self.chargeSound,.8)
  self.chargeSound:SetParameter("charge",fraction,0) -- Original railgun event, driven directly by actual charge.
  if self.chargeAudioStartedAt~=self.timeChargeStarted then
   if self.chargeSound:GetIsPlaying()then self.chargeSound:Stop()end
   self.chargeAudioStartedAt=self.timeChargeStarted
   self.chargeSound:Start()
   self:UpdateWeaponSound(self.chargeSound,.8)
  end
 else
  if self.chargeSound:GetIsPlaying()then self.chargeSound:Stop()end
  self.chargeAudioStartedAt=nil
 end
end
function PlasmaLauncher:ClearChargeVisuals()
 if not Client then return end
 self.chargeAudioStartedAt=nil
 for _,key in ipairs({"launchWorldEffect","launchViewEffect"})do
  if self[key] then Client.DestroyCinematic(self[key]);self[key]=nil end
 end
 if self.chargeSound and self.chargeSound:GetIsPlaying() then self.chargeSound:Stop()end
 for _,key in ipairs({"chargeWorld","chargeView"})do
  if self[key.."Effect"] then Client.DestroyCinematic(self[key.."Effect"]);self[key.."Effect"]=nil end
  if self[key] then Client.DestroyRenderModel(self[key]);self[key]=nil end
 end
end
function PlasmaLauncher:OnDestroy()
 self:ClearChargeVisuals()
 if self.chargeSound then Client.DestroySoundEffect(self.chargeSound);self.chargeSound=nil end
 if self.chargeDisplayUI then Client.DestroyGUIView(self.chargeDisplayUI);self.chargeDisplayUI=nil end
 Entity.OnDestroy(self)
end
function PlasmaLauncher:GetIsThrusterAllowed()return true end
function PlasmaLauncher:GetWeight()return kPlasmaLauncherWeight end
function PlasmaLauncher:GetMode()return "Bomb" end
function PlasmaLauncher:GetDeathIconIndex()return kDeathMessageIcon.Railgun end
function PlasmaLauncher:AddEnergyW(amount)self.energyWAmount=clamp(self.energyWAmount+amount)end
function PlasmaLauncher:GetChargeAmount()return self.energyWAmount end
function PlasmaLauncher:GetChargeFraction()
 if not self.plasmalauncherAttacking then return 0 end
 return math.min(clamp((Shared.GetTime()-self.timeChargeStarted)/self.kChargeDuration),clamp(self.energyWAmount/kPlasmaBombEnergyCost))
end
function PlasmaLauncher:GetDisplayCharge()
 if self.plasmalauncherAttacking then return self:GetChargeFraction() end
 return self.lastShotCharge*clamp(1-(Shared.GetTime()-self.timeOfLastShot)/.2)
end
function PlasmaLauncher:GetPlasmaCoords(isView,launch,charge)
 local player=self:GetParent();if not player then return nil end
 local source=isView and player:GetViewModelEntity() or player
 if not source or not source.GetAttachPointIndex then return nil end
 local side=self:GetIsLeftSlot() and "l" or "r"
 local function attachment(name)
  local index=source:GetAttachPointIndex(name)
  if index<0 then return nil end
  local c=source:GetAttachPointCoords(name)
  if Client and not isView and source.GetRenderModel and source.boneCoords then
   local render=source:GetRenderModel();local model=Shared.GetModel(source.modelIndex)
   if render and model and source.boneCoords:GetSize()>0 then c=render:GetCoords()*model:GetAttachPointCoords(index,source.boneCoords)end
  end
  return c and c:GetIsFinite() and c or nil
 end
 local tip=attachment(isView and ("fxnode_"..side.."_railgun_muzzle") or ("fxnode_"..side.."railgunmuzzle"))
 local stump=attachment("fxnode_"..side.."_plasma_charge")
 if not tip or not stump then return nil end
 -- The actual barrel line runs from stump face to original muzzle tip.
 local barrel=tip.origin-stump.origin
 if barrel:GetLengthSquared()<.000001 then return nil end
 local fraction=charge
 if fraction==nil then fraction=self:GetChargeFraction()end
 local result=scaledCoords(tip,1)
 result.origin=tip.origin-barrel:GetUnit()*PlasmaT3.GetVisualRadius(fraction)
 return result
end
function PlasmaLauncher:ProcessMoveOnWeapon(player,input)
 self:AddEnergyW(input.time*kPlasmaLauncherEnergyUpRate)
 if self.plasmalauncherAttacking and not player:GetIsAlive() then self.plasmalauncherAttacking=false end
end
function PlasmaLauncher:OnPrimaryAttack(player)
 if not self.plasmalauncherAttacking and player:GetIsAlive() and self.energyWAmount>0 and Shared.GetTime()-self.timeOfLastShot>=self.kShotCooldown then
  self.timeChargeStarted=Shared.GetTime();self.plasmalauncherAttacking=true
 end
end
function PlasmaLauncher:MoveSpawnPastOwnShield(player, startPoint, direction, shotRadius)
    local holder = player:GetActiveWeapon()
    local shield
    for _, w in ipairs({ holder and holder.GetLeftSlotWeapon and holder:GetLeftSlotWeapon() or false,
                         holder and holder.GetRightSlotWeapon and holder:GetRightSlotWeapon() or false }) do
        if w and w:isa("ExoShield") and w:GetIsShieldActive() then shield = w; break end
    end
    if not shield then return startPoint end
    -- The barrier spans both halves, centred on the seam.
    local coords = shield:GetBarrierCentreCoords()
    if not coords then return startPoint end
    local denominator = direction:DotProduct(coords.zAxis)
    if denominator <= 0.001 then return startPoint end
    local radius = shotRadius or 0.095
    local signedDistance = (startPoint - coords.origin):DotProduct(coords.zAxis)
    local required = ExoShield.kDepth / 2 + radius + 0.03 - signedDistance
    if required <= 0 then return startPoint end
    local planePoint = startPoint - direction * (signedDistance / denominator)
    local offset = planePoint - coords.origin
    if math.abs(offset:DotProduct(coords.xAxis)) > ExoShield.kWidth + radius
        or math.abs(offset:DotProduct(coords.yAxis)) > ExoShield.kHeight / 2 + radius then
        return startPoint
    end
    return startPoint + direction * (required / denominator)
end
function PlasmaLauncher:FireChargedBall(player,charge)
 if Predict then return end
 local frame=self:GetPlasmaCoords(false,true,charge)
 local start=frame and frame.origin or player:GetEyePos()+player:GetViewCoords().zAxis
 local eye=player:GetEyePos()
 local filter=EntityFilterOne(player)
 if ExoShieldFilterFriendlyTrace then filter=ExoShieldFilterFriendlyTrace(filter,player)end
 -- Parallel launch direction: no convergence toward a crosshair trace hit.
 local direction=player:GetViewCoords().zAxis:GetUnit()
 local shotRadius=PlasmaT3.GetVisualRadius(charge)
 start=self:MoveSpawnPastOwnShield(player,start,direction,shotRadius)
 local clearance=Shared.TraceCapsule(eye,start,shotRadius,0,CollisionRep.Damage,PhysicsMask.Bullets,filter)
 if clearance.fraction and clearance.fraction<1 then
  start=eye
  direction=player:GetViewCoords().zAxis
 end
 -- View-zone particle simulations cannot travel with a world collision object.
 if Client then
  for _,key in ipairs({"chargeView","chargeWorld"})do
   if self[key.."Effect"]then Client.DestroyCinematic(self[key.."Effect"]);self[key.."Effect"]=nil end
   self[key.."EffectCoords"]=nil;self[key.."EffectAsset"]=nil
   if self[key]then self[key]:SetIsVisible(false)end
  end
 end
 local projectile=player:CreatePierceProjectile("PlasmaT3",start,direction*kPlasmaBombSpeed,0,0,9.81,nil,
  kPlasmaBombDamage*charge,kPlasmaBombDOTDamage*charge,shotRadius,kPlasmaBombDamageRadius*(.35+.65*charge),charge,player,nil)
 if Server and projectile then projectile.chargeFraction=charge end
end
function PlasmaLauncher:OnPrimaryAttackEnd(player)
 if not self.plasmalauncherAttacking then return end
 local charge=self:GetChargeFraction();self.plasmalauncherAttacking=false
 if not player or not player:GetIsAlive() or charge<.05 then return end
 self.lastShotCharge=charge;self.timeOfLastShot=Shared.GetTime()
 self.energyWAmount=clamp(self.energyWAmount-kPlasmaBombEnergyCost*charge)
 if Server or (Client and Client.GetIsControllingPlayer()) then self:FireChargedBall(player,charge)end
 self:PlayWeaponSound(plasmaFireSound,.85)
end
-- Firing is owned by release, never by a repeating legacy railgun shoot tag.
function PlasmaLauncher:OnTag(tagName)end
function PlasmaLauncher:OnUpdateAnimationInput(modelMixin)
 modelMixin:SetAnimationInput("activity_"..self:GetExoWeaponSlotName(),self.plasmalauncherAttacking and "primary" or "none")
 self:UpdateViewModelPoseParameters(modelMixin)
end
function PlasmaLauncher:UpdateViewModelPoseParameters(model)
 model:SetPoseParam("plasma_charge_"..(self:GetIsLeftSlot() and "l" or "r"),self:GetDisplayCharge())
 -- Raise the exposed arm to its native ready/aim pose instead of leaving it down.
 model:SetPoseParam("charge_"..(self:GetIsLeftSlot() and "l" or "r"),self.plasmalauncherAttacking and 1 or 0)
end
if Client then
 function PlasmaLauncher:GetIsActive()return true end
 function PlasmaLauncher:GetSecondaryAttacking()return false end
 function PlasmaLauncher:GetPrimaryAttacking()return self.lastShotCharge>0 and Shared.GetTime()-self.timeOfLastShot<.15 end
 function PlasmaLauncher:GetTriggerPrimaryEffects()return self:GetPrimaryAttacking()end
 function PlasmaLauncher:OnClientPrimaryAttacking()
  -- The charge sphere and launched projectile already show the shot. The
  -- legacy test-room muzzle cinematic obscures the cockpit with a huge flash.
  self.lastMuzzleShot=self.timeOfLastShot
 end
 function PlasmaLauncher:OnUpdateRender()
  local player=self:GetParent()
  if not player or not player:GetIsAlive() then self:ClearChargeVisuals();return end
  if self.lastShotCharge>0 and Shared.GetTime()-self.timeOfLastShot<.3 then self:OnClientPrimaryAttacking()end
  local fraction=self:GetChargeFraction();local localPlayer=player==Client.GetLocalPlayer()
  local view=localPlayer and not player:GetIsThirdPerson()
  for _,kind in ipairs({"World","View"})do
   local isView=kind=="View";local visible=fraction>.005 and (isView and view or not isView and not view)
   local key="charge"..kind;local effectVisible=false
   if visible then
    local frame=self:GetPlasmaCoords(isView,false,fraction)
    if frame then
     if not self[key] then
      self[key]=Client.CreateRenderModel(isView and RenderScene.Zone_ViewModel or RenderScene.Zone_Default)
      self[key]:SetModel(Shared.GetModelIndex(ballModel));self[key]:SetCastsShadows(false)
     end
     local chargedCoords=scaledCoords(frame,PlasmaT3.GetVisualRadius(fraction)/.17776726)
     self[key]:SetCoords(chargedCoords);self[key]:SetIsVisible(true) -- Explicit sphere uses the same radius as collision.
     -- Keep the accepted charge socket and its original render zone.
     local effectCoords=scaledCoords(frame,PlasmaT3.GetEffectVisualScale(fraction))
     local asset=PlasmaT3.GetChargeCinematic(fraction)
     if not self[key.."Effect"] then
      local effect=Client.CreateCinematic(isView and RenderScene.Zone_ViewModel or RenderScene.Zone_Default)
      effect:SetIsVisible(false)
      effect:SetCoords(effectCoords)
      effect:SetCinematic(asset)
      effect:SetRepeatStyle(Cinematic.Repeat_Endless)
      self[key.."Effect"]=effect;self[key.."EffectAsset"]=asset
     end
     self[key.."Effect"]:SetCoords(effectCoords)
     if self[key.."EffectAsset"]~=asset then self[key.."Effect"]:SetCinematic(asset);self[key.."EffectAsset"]=asset end
     self[key.."EffectCoords"]=effectCoords;effectVisible=true
    elseif self[key] then self[key]:SetIsVisible(false)end
   elseif self[key] then self[key]:SetIsVisible(false)end
   if self[key.."Effect"] then
    if effectVisible then self[key.."Effect"]:SetIsVisible(true)
    else Client.DestroyCinematic(self[key.."Effect"]);self[key.."Effect"]=nil;self[key.."EffectAsset"]=nil;self[key.."EffectCoords"]=nil end
   end
  end
  self:UpdateChargeAudio(fraction)
  if localPlayer then
   if not self.chargeDisplayUI then
    self.chargeDisplayUI=Client.CreateGUIView(246,256)
    self.chargeDisplayUI:Load("lua/GUI"..self:GetExoWeaponSlotName():gsub("^%l",string.upper).."PlasmaDisplay.lua")
    self.chargeDisplayUI:SetTargetTexture("*exo_railgun_"..self:GetExoWeaponSlotName())
   end
   self.chargeDisplayUI:SetGlobal("chargeAmount"..self:GetExoWeaponSlotName(),fraction)
   self.chargeDisplayUI:SetGlobal("Mode"..self:GetExoWeaponSlotName(),"Bomb")
   self.chargeDisplayUI:SetGlobal("minEnergy"..self:GetExoWeaponSlotName(),.05)
  elseif self.chargeDisplayUI then Client.DestroyGUIView(self.chargeDisplayUI);self.chargeDisplayUI=nil end
 end
end
if Server then
 function PlasmaLauncher:OnParentKilled()self.plasmalauncherAttacking=false end
 function PlasmaLauncher:OnDamageDone(doer,target)
  if doer==self and HasMixin(target,"Ragdoll") and target:isa("Player") and not target:GetIsAlive() then target:SetBypassRagdoll(true)end
 end
end
Shared.LinkClassToMap("PlasmaLauncher",PlasmaLauncher.kMapName,networkVars)
