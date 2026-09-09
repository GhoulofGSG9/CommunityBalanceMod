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

PlasmaLauncher.kMapName = "PlasmaLauncher"

local kPlasmaRange = kRelevancyRangeCap
local kPlasmaSpread = 0 --Math.Radians(3)

local kChargeSound = PrecacheAsset("sound/NS2.fev/marine/heavy/railgun_charge")

local networkVars =
{
    timeChargeStarted = "time",
    plasmalauncherAttacking = "boolean",
    timeOfLastShot = "time",
	energyWAmount = "float (0 to 1 by 0.01)",
	energyAnimation = "float (0 to 1 by 0.01)",
}

AddMixinNetworkVars(TechMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(ExoWeaponSlotMixin, networkVars)

function PlasmaLauncher:OnCreate()

    Entity.OnCreate(self)
    
    InitMixin(self, TechMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, DamageMixin)
    InitMixin(self, BulletsMixin)
    InitMixin(self, ExoWeaponSlotMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, AchievementGiverMixin)
    InitMixin(self, EffectsMixin)
		
    self.timeChargeStarted = 0
    self.plasmalauncherAttacking = false
    self.timeOfLastShot = 0
	self.energyWAmount = 0.5
	self.energyAnimation = 0
	self.fireMode = "Bomb"
	self.energyCost = kPlasmaBombEnergyCost
    
    if Client then
    
        InitMixin(self, ClientWeaponEffectsMixin)
        self.chargeSound = Client.CreateSoundEffect(Shared.GetSoundIndex(kChargeSound))
        self.chargeSound:SetParent(self:GetId())
        
    end
end

function PlasmaLauncher:OnDestroy()

    Entity.OnDestroy(self)
    
    if self.chargeSound then
    
        Client.DestroySoundEffect(self.chargeSound)
        self.chargeSound = nil
        
    end
    
    if self.chargeDisplayUI then
    
        Client.DestroyGUIView(self.chargeDisplayUI)
        self.chargeDisplayUI = nil
        
    end

end

function PlasmaLauncher:GetIsThrusterAllowed()
    return true
end

function PlasmaLauncher:GetWeight()
    return kPlasmaLauncherWeight
end

function PlasmaLauncher:GetChargeAmount()
    return self.energyWAmount
end

function PlasmaLauncher:GetMode()
	return self.fireMode
end

function PlasmaLauncher:AddEnergyW(amount)
    self.energyWAmount = self.energyWAmount + amount
end

function PlasmaLauncher:ProcessMoveOnWeapon(player, input)

	local dt = input.time
    local addAmount = dt * kPlasmaLauncherEnergyUpRate
    self.energyWAmount = math.min(1, math.max(0, self.energyWAmount + addAmount))

end

function PlasmaLauncher:OnPrimaryAttack(player)
	self.plasmalauncherAttacking = true
end

function PlasmaLauncher:OnPrimaryAttackEnd(player)
    self.plasmalauncherAttacking = false
end

local function TriggerSteamEffect(self, player)

    if self:GetIsLeftSlot() then
        player:TriggerEffects("railgun_steam_left")
    elseif self:GetIsRightSlot() then
        player:TriggerEffects("railgun_steam_right")
    end
    
end

function PlasmaLauncher:GetDeathIconIndex()
    return kDeathMessageIcon.Railgun
end

local function PlasmaBallProjectile(self, player)

	if not Predict then
		
		local viewAngles = player:GetViewAngles()
		local shootCoords = viewAngles:GetCoords()

		local eyePos = player:GetEyePos()
		local viewCoords = player:GetViewCoords()

		local startPoint

		if self:GetIsLeftSlot() then
			startPoint = eyePos + viewCoords.zAxis * 1.75 + viewCoords.xAxis * 0.65 + viewCoords.yAxis * -0.19
		else
			startPoint = eyePos + viewCoords.zAxis * 1.75 + viewCoords.xAxis * -0.65 + viewCoords.yAxis * -0.19
		end

		local spreadDirection = CalculateSpread(shootCoords, kPlasmaSpread, NetworkRandom)

		local endPoint = eyePos + spreadDirection * kPlasmaRange		
		local trace = Shared.TraceRay(eyePos, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterAllButIsa("Tunnel"))
		local direction = (trace.endPoint - startPoint):GetUnit()
				
		local exoWeaponHolder = player:GetActiveWeapon()
		local LeftWeapon = exoWeaponHolder:GetLeftSlotWeapon()
		local RightWeapon = exoWeaponHolder:GetRightSlotWeapon()	
		
		player:CreatePierceProjectile("PlasmaT3", startPoint, direction * kPlasmaBombSpeed, 0, 0, 9.81, nil, kPlasmaBombDamage, kPlasmaBombDOTDamage, kPlasmaHitBoxRadiusT3, kPlasmaBombDamageRadius, nil, player)
    end
end

function PlasmaLauncher:LockGun()
    self.timeOfLastShot = Shared.GetTime()
end

local function Shoot(self, leftSide)

    local player = self:GetParent()
	
    -- We can get a shoot tag even when the clip is empty if the frame rate is low
    -- and the animation loops before we have time to change the state.
	
    if player then
    	
		
        player:TriggerEffects("railgun_attack")
			
		if Server or (Client and Client.GetIsControllingPlayer()) then
			PlasmaBallProjectile(self, player)
		end
		
		--if Client then
		--	TriggerSteamEffect(self, player)
		--end
				
		--self:LockGun()
		--self.lockCharging = true
        
    end
    
end

local kActivityInput = ExoWeaponSlotMixin.kActivityInput
local kChargeAmountKey = ExoWeaponSlotMixin.GetSlotKeyTable("chargeAmount")
local kTimeSinceLastShotKey = ExoWeaponSlotMixin.GetSlotKeyTable("timeSinceLastShot")
local kRailgunTextureKey = ExoWeaponSlotMixin.GetSlotKeyTable("*exo_railgun_")
local kModeKey = ExoWeaponSlotMixin.GetSlotKeyTable("Mode")
local kMinEnergyKey = ExoWeaponSlotMixin.GetSlotKeyTable("minEnergy")

function PlasmaLauncher:OnUpdateRender()

    PROFILE("PlasmaLauncher:OnUpdateRender")
    	
	local parent = self:GetParent()
	local chargeAmount, Mode, minEnergy

	local exoWeaponHolder = parent:GetActiveWeapon()
	local LeftWeapon = exoWeaponHolder:GetLeftSlotWeapon()
	local RightWeapon = exoWeaponHolder:GetRightSlotWeapon()
	local otherSlotWeapon = self:GetExoWeaponSlot() == ExoWeaponHolder.kSlotNames.Left and exoWeaponHolder:GetRightSlotWeapon() or exoWeaponHolder:GetLeftSlotWeapon()

	chargeAmount = self.energyWAmount --self:GetChargeAmount()
	UIchargeAmount = self.energyWAmount --self:GetChargeAmount()
	Mode = self.fireMode
	minEnergy = self.energyCost
	
    if parent and parent:GetIsLocalPlayer() then
    
        local viewModel = parent:GetViewModelEntity()
        if viewModel and viewModel:GetRenderModel() then
        
            viewModel:InstanceMaterials()
            local renderModel = viewModel:GetRenderModel()
            local slot = self.exoWeaponSlot
            renderModel:SetMaterialParameter(kChargeAmountKey[slot], chargeAmount)
            renderModel:SetMaterialParameter(kTimeSinceLastShotKey[slot], Shared.GetTime() - self.timeOfLastShot)
            
        end
        
        local chargeDisplayUI = self.chargeDisplayUI
        if not chargeDisplayUI then
        
            chargeDisplayUI = Client.CreateGUIView(246, 256)
            chargeDisplayUI:Load("lua/GUI" .. self:GetExoWeaponSlotName():gsub("^%l", string.upper) .. "PlasmaDisplay.lua")
            chargeDisplayUI:SetTargetTexture(kRailgunTextureKey[self.exoWeaponSlot])
            self.chargeDisplayUI = chargeDisplayUI
			
        end
        
        local slot = self.exoWeaponSlot
        chargeDisplayUI:SetGlobal(kChargeAmountKey[slot], UIchargeAmount)
        chargeDisplayUI:SetGlobal(kModeKey[slot], Mode)
		chargeDisplayUI:SetGlobal(kMinEnergyKey[slot], minEnergy)
        		
    else
    
        if self.chargeDisplayUI then
        
            Client.DestroyGUIView(self.chargeDisplayUI)
            self.chargeDisplayUI = nil
            
        end
        
    end
    	
    --[[if self.chargeSound then
    
        local playing = self.chargeSound:GetIsPlaying()
        if not playing and UIchargeAmount > 0 then
            self.chargeSound:Start()
        elseif playing and UIchargeAmount <= 0 then
            self.chargeSound:Stop()
        end
        
        self.chargeSound:SetParameter("charge", UIchargeAmount, 1)
        
    end]]
    
end

function PlasmaLauncher:OnTag(tagName)

    PROFILE("PlasmaLauncher:OnTag")
	
    if self:GetIsLeftSlot() then
    	self.energyAnimation = self.energyWAmount	
        if tagName == "l_shoot" and self.energyWAmount >= self.energyCost then
            Shoot(self, true)
			if Server then	
				self.energyWAmount = math.max(0,self.energyWAmount - self.energyCost)
			end
        end
        
    elseif not self:GetIsLeftSlot() then
		self.energyAnimation = self.energyWAmount
        if tagName == "r_shoot" and self.energyWAmount >= self.energyCost then
			Shoot(self, false)
			if Server then
				self.energyWAmount = math.max(0,self.energyWAmount - self.energyCost)
			end
        end
    end
end

function PlasmaLauncher:OnResolutionChanged()
    self:UpdateItemsGUIScale()
end

function PlasmaLauncher:OnUpdateAnimationInput(modelMixin)

    local activity = "none"
    
	if self.plasmalauncherAttacking and self.energyWAmount >= self.energyCost then
        activity = "primary"
    end
    
	modelMixin:SetAnimationInput(kActivityInput[self.exoWeaponSlot], activity)
end

function PlasmaLauncher:UpdateViewModelPoseParameters(viewModel)

    local chargeParam = "charge_" .. (self:GetIsLeftSlot() and "l" or "r")
    local chargeAmount = self:GetChargeAmount()
    viewModel:SetPoseParam(chargeParam, chargeAmount)
    
end

if Client then

    -- NOTE(Salads): The railgun exo has different attach point names for both viewmodel and the regular model. FIXME
    local kFirstPersonAttachPoints = { [ExoWeaponHolder.kSlotNames.Left] = "fxnode_l_railgun_muzzle", [ExoWeaponHolder.kSlotNames.Right] = "fxnode_r_railgun_muzzle" }
    local kThirdPersonAttachPoints = { [ExoWeaponHolder.kSlotNames.Left] = "fxnode_lrailgunmuzzle", [ExoWeaponHolder.kSlotNames.Right] = "fxnode_rrailgunmuzzle" }
    local kMuzzleEffectName = PrecacheAsset("models/plasma/muzzle_flash_plasma.cinematic")

    function PlasmaLauncher:OnClientPrimaryAttacking()
    
        local parent = self:GetParent()
        
        if parent then

            local attachPoint
            if parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
                attachPoint = kFirstPersonAttachPoints[self:GetExoWeaponSlot()]
            else
                attachPoint = kThirdPersonAttachPoints[self:GetExoWeaponSlot()]
            end

            CreateMuzzleCinematic(self, kMuzzleEffectName, kMuzzleEffectName, attachPoint, parent, nil, true)
        end
        
    end
    
    function PlasmaLauncher:GetSecondaryAttacking()
        return false
    end
    
    function PlasmaLauncher:GetIsActive()
        return true
    end    
    
    function PlasmaLauncher:GetPrimaryAttacking()
        return self.plasmalauncherAttacking
    end
    
    function PlasmaLauncher:GetTriggerPrimaryEffects()
        return self.energyWAmount >= self.energyCost
    end
    
end

if Server then

    function PlasmaLauncher:OnParentKilled(attacker, doer, point, direction)
    end
    
    -- 
    -- The Railgun explodes players. We must bypass the ragdoll here.
    -- 
    function PlasmaLauncher:OnDamageDone(doer, target)
    
        if doer == self then
        
            if HasMixin(target, "Ragdoll") and target:isa("Player") and not target:GetIsAlive() then
                target:SetBypassRagdoll(true)
            end
            
        end
        
    end
    
end

Shared.LinkClassToMap("PlasmaLauncher", PlasmaLauncher.kMapName, networkVars)
