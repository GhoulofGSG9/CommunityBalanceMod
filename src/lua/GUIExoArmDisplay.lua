-- Claw / shield arm panel, drawn on the 800x800 claw screen.
--   Claw:   stock NS2 claw panel art, mirrored on the right arm like CBM.
--   Shield: the stock minigun heat bar, run in reverse - full while the shield is
--           healthy, draining as it absorbs damage, flashing when low.
displayHP=600;displayMaxHP=600;displayMode=0;displayHeat=0;displayFloor=0;displayStatus="READY";displaySide="left"
local kClawPanel="models/marine/exosuit/exosuit_view_panel_claw2.dds"
local kBarTexture="models/marine/exosuit/exosuit_view_panel_mini2.dds"
local kBarX,kBarY=(800-242)/2,40
local background,clawArt,bar,barFill,barMask,alertLight
local animAlert,animDir=0,1
function Initialize()
 GUI.SetSize(800,800)
 background=GUI.CreateItem();background:SetSize(Vector(800,800,0));background:SetColor(Color(0,0,0,1))
 clawArt=GUI.CreateItem();clawArt:SetSize(Vector(800,800,0));clawArt:SetTexture(kClawPanel);background:AddChild(clawArt)
 bar=GUI.CreateItem();bar:SetPosition(Vector(kBarX,kBarY,0));bar:SetSize(Vector(242,720,0))
 bar:SetTexture(kBarTexture);bar:SetTexturePixelCoordinates(0,0,242,720);background:AddChild(bar)
 barMask=GUI.CreateItem();barMask:SetPosition(Vector(0,0,0));barMask:SetSize(Vector(242,720,0))
 barMask:SetIsStencil(true);barMask:SetClearsStencilBuffer(true);bar:AddChild(barMask)
 barFill=GUI.CreateItem();barFill:SetPosition(Vector(0,0,0));barFill:SetSize(Vector(242,720,0))
 barFill:SetTexture(kBarTexture);barFill:SetTexturePixelCoordinates(330,0,572,720)
 barFill:SetStencilFunc(GUIItem.Equal);barMask:AddChild(barFill)
 alertLight=GUI.CreateItem();alertLight:SetPosition(Vector(0,0,0));alertLight:SetSize(Vector(60,720,0))
 alertLight:SetTexture(kBarTexture);alertLight:SetTexturePixelCoordinates(264,0,324,720);bar:AddChild(alertLight)
end
function Update(dt)
 local shield=displayMode==5
 clawArt:SetIsVisible(not shield);bar:SetIsVisible(shield)
 if not shield then
  if displaySide=="right" then clawArt:SetTexturePixelCoordinates(800,0,0,800) else clawArt:SetTexturePixelCoordinates(0,0,800,800) end
  return
 end
 local fraction=math.max(0,math.min(1,displayHP/math.max(1,displayMaxHP)))
 -- Same masking as the minigun heat bar, fed with shield health instead of heat.
 barMask:SetSize(Vector(242,720*(1-fraction),0))
 local depletion=1-fraction
 local alert=Color(1,1,1,1)
 if depletion>0.5 then
  animAlert=animAlert+animDir*dt*10*depletion
  if animAlert>1 then animAlert=1;animDir=-1 elseif animAlert<0 then animAlert=0;animDir=1 end
  alert=Color(depletion,animAlert*(1-(depletion-0.5)/0.5),0,1)
 end
 alertLight:SetColor(alert)
end
Initialize()
