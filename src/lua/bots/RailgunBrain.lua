
Script.Load("lua/bots/ExoBrain_Data.lua")

------------------------------------------
--
------------------------------------------
class 'RailgunBrain' (PlayerBrain)

RailgunBrain.kUseObjectiveActions = true

function RailgunBrain:Initialize()

    PlayerBrain.Initialize(self)

    self.senses = CreateExoBrainsSenses()
    self.hadGoodHealth = false

    self.isRailgun = true
    self.lastOrderId = Entity.invalidId

end

function RailgunBrain:Update( bot, move )
    
    if gBotDebug:Get("spam") then
        Print("RailgunBrain:Update")
    end

    if PlayerBrain.Update( self, bot, move ) == false then
        return false
    end

    
    local marine = bot:GetPlayer()
    if marine and marine:GetIsAlive() then

        PerformExoSupportAbility(bot, self, marine, move)
        
        -- Med kit request
        if self.hadGoodHealth then
            if self.senses:Get("healthFraction") <= 0.5 then
                if math.random() < 0.5 then
                    CreateVoiceMessage( marine, kVoiceId.RequestWeld )
                end
                self.hadGoodHealth = false
            end
        else
            if self.senses:Get("healthFraction") > 0.5 then
                self.hadGoodHealth = true
            end
        end
        
        local lightMode
        local powerPoint = GetPowerPointForLocation(marine:GetLocationName())
        if powerPoint then
            lightMode = powerPoint:GetLightMode()
        end
        
        if not lightMode or (lightMode == kLightMode.NoPower or kLightMode.LowPower )then
            if not marine:GetFlashlightOn() then
                marine:SetFlashlightOn(true)
            end
        else
            if marine:GetFlashlightOn() then
                marine:SetFlashlightOn(false)
            end
        end
    end
end


function RailgunBrain:GetExpectedPlayerClass()
    return "Exo"
end

function RailgunBrain:GetExpectedTeamNumber()
    return kMarineTeamType
end

function RailgunBrain:GetObjectiveActions()
    return kExoBrainObjectives
end

function RailgunBrain:GetActions()
    return kExoBrainActions
end

function RailgunBrain:GetSenses()
    return self.senses
end
