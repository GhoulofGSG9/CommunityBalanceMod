-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\DropPack.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Mixins/ClientModelMixin.lua")
Script.Load("lua/TeamMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/LOSMixin.lua")

class 'DropPack' (ScriptActor)

DropPack.kMapName = "droppack"

local kPickupRange = 1

local networkVars =
{
    expireTime = "time (by 0.1)"
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ClientModelMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(LOSMixin, networkVars)

local function TimeUp(self)
    DestroyEntity(self)
end

function AlignDroppack( coords, techId, targetEntityId )
    
    local targetEntity = Shared.GetEntity( targetEntityId )
    if targetEntity and targetEntity:isa("Marine") then
        coords.origin = targetEntity:GetOrigin()
    end

    return coords
    
end

function DropPack:OnCreate()

    ScriptActor.OnCreate(self)
    
    InitMixin(self, BaseModelMixin)
    InitMixin(self, ClientModelMixin)
    InitMixin(self, TeamMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LOSMixin)

    self:SetUpdateRate(kUpdateIntervalMedium)

    self:SetRelevancyDistance(25)
    
end

function DropPack:SetExpireTime(func, time)
    self:AddTimedCallback(func, time)
    self.expireTime = Shared.GetTime() + time
end

function DropPack:OnInitialized()

    ScriptActor.OnInitialized(self)

    if Server then
    
        self:SetExpireTime(TimeUp, kItemStayTime)
        self.pickupRange = kPickupRange
        self:SetAngles(Angles(0, math.random() * math.pi * 2, 0))
        
        self:OnUpdate(0)


        -- Handle Stats (Misses will be subtracted from when a derived Pack type is picked up.
        local mapName = self:GetMapName()

        local commanderStats = StatsUI_GetStatForCommander(StatsUI_GetMarineCommmaderSteamID())
        if mapName and commanderStats and commanderStats[mapName] then
            commanderStats[mapName].misses = commanderStats[mapName].misses + 1
        end
    
    end
    
    if Client then
        -- Make this show as a pickupable item in the HUD
        Shared.AddTagToEntity(self:GetId(), "Pickupable")
    end

end

function DropPack:OverrideCheckVision()
    return false
end

function DropPack:GetCanBeUsed(player, useSuccessTable)
    useSuccessTable.useSuccess = false    
end

if Server then

    function DropPack:OnUpdate(deltaTime)
    
        PROFILE("DropPack:OnUpdate")
    
        ScriptActor.OnUpdate(self, deltaTime)    
        
        -- update fall
        
        local weapon = self.weapon and Shared.GetEntity(self.weapon)
        local origin = self:GetOrigin()

        if weapon == nil and self.onGroundPoint and self.onGroundPoint ~= origin and self.fallSpeed then
            
            self.fallSpeed = math.min(50, self.fallSpeed + deltaTime * 9.81)
            self:SetOrigin(SlerpVector(origin, self.onGroundPoint, deltaTime * self.fallSpeed))
            
        elseif weapon ~= nil and weapon.weaponWorldState == true then

            local weaponOrigin = weapon:GetOrigin()
            if origin ~= weaponOrigin then
                self.onGroundPoint = nil
                self:SetOrigin(weaponOrigin)
            end
        
        elseif not self.hitStaticGround and not (weapon ~= nil and weapon.weaponWorldState == true) then -- For med/ammo/etc

            -- This trace is only here in the event you drop it on an entity that dies, so they don't stay in the air

            local trace = Shared.TraceRay(origin + kUpVector * 0.025, origin - kUpVector * 20, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterOneAndIsa(self, "Player"))

            if trace.endPoint ~= origin then
                self:SetOrigin(trace.endPoint)
            end

            if not trace.entity and trace.fraction ~= 1 then
                self.hitStaticGround = true
            end

            self.weapon = nil

        end
        
        -- set angles when on ground, then disable

        if self.desiredAngles then
        
            if self.onGroundPoint == nil or self.onGroundPoint == self:GetOrigin() then

                self:SetAngles(SlerpAngles(self:GetAngles(), self.desiredAngles, deltaTime * 5))
                
                if self.setAngleStartTime + 4 < Shared.GetTime() then
                    self.desiredAngles = nil
                end
                
            end
        
        end

        -- update pickup checks (team filtered query, no table full of enemy players)

        origin = self:GetOrigin()
        local playersNearby = GetEntitiesForTeamWithinXZRange( "Player", self:GetTeamNumber(), origin, self.pickupRange )
        if #playersNearby > 0 then

            if self.pickupRange > 1 then -- Don't even bother if range too short, just pick first one in list
                Shared.SortEntitiesByDistance(origin, playersNearby)
            end

            for _, player in ipairs(playersNearby) do
            
                if not player:isa("Commander") and self:GetIsValidRecipient(player) then
                
                    self:OnTouch(player)
                    DestroyEntity(self)
                    break
                    
                end
            
            end
        end
        
    end

end

if Client then
    
    function DropPack:OnUpdate(deltaTime)
        EquipmentOutline_UpdateModel(self)   
    end 
    
end

function DropPack:GetPhysicsModelAllowedOverride()
    return false
end

function DropPack:GetExpireTimeFraction()
    if self.expireTime then
        return Clamp((self.expireTime - Shared.GetTime()) / kItemStayTime, 0, 1)
    else
        return 0
    end
end

Shared.LinkClassToMap("DropPack", DropPack.kMapName, networkVars, false)
