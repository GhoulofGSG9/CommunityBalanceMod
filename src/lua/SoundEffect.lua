-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\SoundEffect.lua
--
--    Created by:   Brain Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Mixins/SignalListenerMixin.lua")

-- Utility functions below.
if Server then

    local function GetMatchingSoundEffectOnEntity(soundName, onEntity)
        if not onEntity then return end
        if not soundName then return end
        
        local matchingSoundEffect

        -- Since map sounds and looping sounds (asset len == -1) don't get destroyed when stopped, check for 
        -- existing sound effects, assuming we only need 1 copy of a repeating effect on an entity
        local newAssetLength = GetSoundEffectLength(soundName)
        if onEntity:GetIsMapEntity() or newAssetLength < 0 then
            local numChildren = onEntity:GetNumChildren()
            for i = 0, numChildren - 1 do
                local child = onEntity:GetChildAtIndex(i)
                if child:isa("SoundEffect") and child:GetSoundName() == soundName then
                    matchingSoundEffect = child
                end
            end
        end
        
        return matchingSoundEffect
    end

    function StartSoundEffectAtOrigin(soundEffectName, atOrigin, volume, predictor)
    
        local soundEffectEntity = Server.CreateEntity(SoundEffect.kMapName)
        soundEffectEntity:SetOrigin(atOrigin)
        soundEffectEntity:SetAsset(soundEffectName)
        soundEffectEntity:SetVolume(volume)
        soundEffectEntity:SetPredictor(predictor)
        soundEffectEntity:Start()
        
        return soundEffectEntity
        
    end
    
    function StartSoundEffectOnEntity(soundEffectName, onEntity, volume, predictor)
      
        if onEntity and not onEntity:GetIsDestroyed() then

            local matchingSoundEffect = GetMatchingSoundEffectOnEntity(soundEffectName, onEntity)
            if matchingSoundEffect then
                matchingSoundEffect:SetVolume(volume)
                matchingSoundEffect:SetPredictor(predictor)
                matchingSoundEffect:Start()
                return matchingSoundEffect 
            end

            local soundEffectEntity = Server.CreateEntity(SoundEffect.kMapName)
            soundEffectEntity:SetParent(onEntity)
            soundEffectEntity:SetAsset(soundEffectName)
            soundEffectEntity:SetVolume(volume)
            soundEffectEntity:SetPredictor(predictor)
            soundEffectEntity:Start()
          
            return soundEffectEntity
            
        end
          
        return None
        
    end
    
    --
    -- Starts a sound effect which only 1 player will hear.
    --
    function StartSoundEffectForPlayer(soundEffectName, forPlayer, volume)
    
        if forPlayer and not forPlayer:GetIsDestroyed() then

            local matchingSoundEffect = GetMatchingSoundEffectOnEntity(soundEffectName, forPlayer)
            if matchingSoundEffect then
                matchingSoundEffect:SetPropagate(Entity.Propagate_PlayerOwner)
                matchingSoundEffect:SetVolume(volume)
                matchingSoundEffect:Start()
                return matchingSoundEffect
            end
            
            local soundEffectEntity = Server.CreateEntity(SoundEffect.kMapName)
            soundEffectEntity:SetParent(forPlayer)
            soundEffectEntity:SetAsset(soundEffectName)
            soundEffectEntity:SetPropagate(Entity.Propagate_PlayerOwner)
            soundEffectEntity:SetVolume(volume)
            soundEffectEntity:Start()
        
            return soundEffectEntity
        
      end
      
      return None
       
        
    end
    
    function StartSoundEffect2D(soundEffectName, volume)
    
        local soundEffectEntity = Server.CreateEntity(SoundEffect.kMapName)
        soundEffectEntity:SetAsset(soundEffectName)
        soundEffectEntity:SetVolume(volume)
        soundEffectEntity:SetPositional(false)
        soundEffectEntity:Start()
        
        return soundEffectEntity
        
    end
    
end

if Client then

    function StartSoundEffectAtOrigin(soundEffectName, atOrigin, volume, predictor)
        Shared.PlayWorldSound(nil, soundEffectName, nil, atOrigin, volume or 1)
    end
    
    function StartSoundEffectOnEntity(soundEffectName, onEntity, volume, predictor)
		if Client.GetIsControllingPlayer() then
			Shared.PlaySound(onEntity, soundEffectName, volume or 1)
		end
    end
    
    function StartSoundEffect(soundEffectName, volume, pitch)

        if pitch ~= nil then
            Shared.PlaySound(nil, soundEffectName, volume or 1, pitch or 0.0)
        else
            Shared.PlaySound(nil, soundEffectName, volume or 1)
        end

    end

    function StartSoundEffectForPlayer(soundEffectName, forPlayer, volume)
        Shared.PlayPrivateSound(forPlayer, soundEffectName, forPlayer, volume or 1, forPlayer:GetOrigin())
    end
    
end


if Predict then

    function StartSoundEffectAtOrigin(soundEffectName, atOrigin)
    end
    
    function StartSoundEffectOnEntity(soundEffectName, onEntity)
    end

    function StartSoundEffectForPlayer(soundEffectName, forPlayer)
    end
    
end

local kDefaultMaxAudibleDistance = 50
local kSoundEndBufferTime = 0.5

class 'SoundEffect' (Entity)

SoundEffect.kMapName = "sound_effect"

local networkVars =
{
    playing = "boolean",
    positional = "boolean",
    assetIndex = "resource",
    startTime = "time",
    predictorId  = "entityid",
    volume = "float (0 to 1 by 0.01)"
}

function SoundEffect:OnCreate()

    Entity.OnCreate(self)
    
    InitMixin(self, SignalListenerMixin)
    
    self.playing = false
    self.positional = true
    self.assetIndex = 0
    self.volume = 1
    self.predictorId = Entity.invalidId
    
    self:SetRelevancyDistance(kDefaultMaxAudibleDistance)
    self:SetUpdates(true, kRealTimeUpdateRate)
    
    if Server then
    
        self.assetLength = 0
        self.startTime = 0
        
    end
    
    if Client then
    
        self.clientPlaying = false
        self.clientAssetIndex = 0
        self.soundEffectInstance = nil
        
    end    
end

function SoundEffect:GetIsPlaying()
    return self.playing
end

function SoundEffect:GetSoundIndex()
    return self.assetIndex
end

function SoundEffect:GetSoundName()
    return Shared.GetSoundName(self.assetIndex)
end

function GetSoundEffectLength(soundName)

    local fixedAssetPath = ""
    local _, extEnd = string.find(soundName, ".fev")
    if extEnd then
        fixedAssetPath = string.sub(soundName, extEnd + 1)
    else
    
        local extStart = string.find(soundName, ".wav")
        if extStart then
            fixedAssetPath = string.sub(soundName, 0, extStart - 1)
        end
        
        local _, soundPathEnd = string.find(fixedAssetPath, "sound/")
        fixedAssetPath = string.sub(fixedAssetPath, soundPathEnd + 1)
        
    end
    
    return Server.GetSoundLength(fixedAssetPath)
    
end

if Server then

    function SoundEffect:SetVolume(volume)
        self.volume = volume or 1
    end
    
    function SoundEffect:SetPositional(positional)
        self.positional = positional
    end
    
    function SoundEffect:SetPredictor(predictor)
        self.predictorId = predictor and predictor:GetId() or Entity.invalidId
    end

    function SoundEffect:SetAsset(assetPath)
    
        if string.len(assetPath) == 0 then
            return
        end
        
        local assetIndex = Shared.GetSoundIndex(assetPath)
        if assetIndex == 0 then
        
            Shared.Message("Effect " .. assetPath .. " wasn't precached")
            return
            
        end
        
        self.assetIndex = assetIndex
        self.assetLength = GetSoundEffectLength(assetPath)
        --[[
        if not self:GetParent() and self:GetOrigin() == Vector(0,0,0) then
            Print("Warning: %s is being player at (0,0,0)", assetPath)
        end
        --]]
        
    end
    
    function SoundEffect:Start()
    
        -- Asset must be assigned before playing.
        assert(self.assetIndex ~= 0)
        
        self.playing = true
        self.startTime = Shared.GetTime()
        
    end
    
    function SoundEffect:Stop()
    
        self.playing = false
        self.startTime = 0
        
        -- Destroy when stopped if this is not a map entity and not set to loop.
        if not self:GetIsMapEntity() and self.assetLength >= 0 then
            DestroyEntity(self)
        end
        
    end
    
    function SoundEffect:GetIsPlaying()
        return self.playing
    end
    
    local function SharedUpdate(self)
    
        --PROFILE("SoundEffect:SharedUpdate")
        
        -- If the assetLength is < 0, it is a looping sound and needs to be manually destroyed.
        if self.playing and self.assetLength >= 0 and not self:GetIsMapEntity() then
        
            -- Add in a bit of time to make sure the Client has had enough time to fully play.
            local endTime = self.startTime + self.assetLength + kSoundEndBufferTime
            if Shared.GetTime() > endTime then
                DestroyEntity(self)
            end
            
        end
        
    end
    
    function SoundEffect:OnProcessMove()
        SharedUpdate(self)
    end
    
    function SoundEffect:OnUpdate(deltaTime)
        SharedUpdate(self)
    end
    
end

if Client then

    local function DestroySoundEffect(self)
    
        if self.soundEffectInstance then
        
            Client.DestroySoundEffect(self.soundEffectInstance)
            self.soundEffectInstance = nil
            
        end
        
    end
    
    function SoundEffect:OnDestroy()
        DestroySoundEffect(self)
    end
    
    --[[
    XXX Must be fixable ... the predictorId does what?
    XXX fieldwatcher on assetIndex and positional? Is it really required for positional? Or assetIndex for that matter...
    XXX should we not do this in Initialize?
    XXX ensure fieldwatcher works / gets called whenever an entity is created on client?
    --]]
    local function SharedUpdate(self)
    
        --PROFILE("SoundEffect:SharedUpdate")
        
        if self.predictorId ~= Entity.invalidId then
        
            local predictor = Shared.GetEntity(self.predictorId)
            if Client.GetLocalPlayer() == predictor and Client.GetIsControllingPlayer() then
                return
            end
            
        end
       
        if self.clientAssetIndex ~= self.assetIndex then
        
            DestroySoundEffect(self)
            
            self.clientAssetIndex = self.assetIndex
            
            if self.assetIndex ~= 0 then
            
                self.soundEffectInstance = Client.CreateSoundEffect(self.assetIndex)
                self.soundEffectInstance:SetParent(self:GetId())
                
            end
        
        end
        
        -- Only attempt to play if the index seems valid.
        if self.assetIndex ~= 0 then
        
            if self.clientPlaying ~= self.playing or self.clientStartTime ~= self.startTime then
            
                self.clientPlaying = self.playing
                self.clientStartTime = self.startTime
                
                if self.playing then
                
                    self.soundEffectInstance:Start()
                    self.soundEffectInstance:SetVolume(self.volume)
                    if self.clientSetParameters then
                    
                        for c = 1, #self.clientSetParameters do
                        
                            local param = self.clientSetParameters[c]
                            self.soundEffectInstance:SetParameter(param.name, param.value, param.speed)
                            
                        end
                        self.clientSetParameters = nil
                        
                    end
                    
                else
                    self.soundEffectInstance:Stop()
                end
                
            end
            
        end
        
        -- Update 3D positional setting.
        if self.soundEffectInstance and self.clientPositional ~= self.positional then
        
            self.soundEffectInstance:SetPositional(self.positional)
            self.clientPositional = self.positional
            
        end
        
    end
    
    function SoundEffect:OnUpdate(deltaTime)
        SharedUpdate(self)
    end
    
    function SoundEffect:OnProcessMove()
        SharedUpdate(self)
    end
    
    function SoundEffect:OnProcessSpectate()
        SharedUpdate(self)
    end
    
    -- XXX trigger a timed callback if we are not playing? Or just make sure we are actually playing?
    
    function SoundEffect:SetParameter(paramName, paramValue, paramSpeed)
    
        ASSERT(type(paramName) == "string")
        ASSERT(type(paramValue) == "number")
        ASSERT(type(paramSpeed) == "number")
        
        local success = false
        
        if self.soundEffectInstance and self.playing then
        
            if self.clientPlaying then
                success = self.soundEffectInstance:SetParameter(paramName, paramValue, paramSpeed)
            else
            
                -- SharedUpdate() has not been called yet, save the parameters until it has.
                self.clientSetParameters = self.clientSetParameters or { }
                table.insert(self.clientSetParameters, { name = paramName, value = paramValue, speed = paramSpeed })
                success = true
                
            end
            
        end
        
        return success
        
    end
    
    -- will create a sound effect instance
    function CreateLoopingSoundForEntity(entity, localSoundName, worldSoundName)
    
        local soundEffectInstance

        if entity then
        
            if entity == Client.GetLocalPlayer() and localSoundName then
                soundName = localSoundName
            else
                soundName = worldSoundName
            end
            
            if soundName then
            
                soundEffectInstance = Client.CreateSoundEffect(Shared.GetSoundIndex(soundName))
                soundEffectInstance:SetParent(entity:GetId())
        
            end
        
        end
        
        return soundEffectInstance
    
    end

end

Shared.LinkClassToMap("SoundEffect", SoundEffect.kMapName, networkVars)
