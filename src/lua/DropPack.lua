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

    self:SetUpdateRate(kRealTimeUpdateRate)
    
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
        if weapon == nil and self.onGroundPoint and self.onGroundPoint ~= self:GetOrigin() and self.fallSpeed then
            
            self.fallSpeed = math.min(50, self.fallSpeed + deltaTime * 9.81)
            self:SetOrigin(SlerpVector(self:GetOrigin(), self.onGroundPoint, deltaTime * self.fallSpeed))
            
        elseif weapon ~= nil and weapon.weaponWorldState == true then
            if self:GetOrigin() ~= weapon:GetOrigin() then
                self.onGroundPoint = nil
                self:SetOrigin(weapon:GetOrigin())
            end
        
        elseif not self.hitStaticGround and not (weapon ~= nil and weapon.weaponWorldState == true) then -- For med/ammo/etc

            -- This trace is only here in the event you drop it on an entity that dies, so they don't stay in the air

            local trace = Shared.TraceRay(self:GetOrigin() + kUpVector * 0.025, self:GetOrigin() - kUpVector * 20, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterOneAndIsa(self, "Player"))
            self:SetOrigin(Vector(trace.endPoint))
            if not trace.entity and trace.fraction ~= 1 then
                self.hitStaticGround = true
            end

            self.weapon = nil
        elseif not self.hitStaticGround then -- For weapons

            if not self.lastOnGroundUpdate or self.lastOnGroundUpdate + 0.1 < Shared.GetTime() then        

                self.lastOnGroundUpdate = Shared.GetTime()
                
                local trace = Shared.TraceRay(self:GetOrigin() + kUpVector * 0.025, self:GetOrigin() - kUpVector * 20, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterOneAndIsa(self, "Player"))
                if trace.fraction ~= 1 and self:GetOrigin().y - trace.endPoint.y > 0.025 then
                    
                    self.onGroundPoint = Vector(trace.endPoint)
                    self.fallSpeed = 0
                    
                else                
                    self.onGroundPoint = nil                    
                end
                
                if not trace.entity and trace.fraction ~= 1 then
                    self.hitStaticGround = true
                end
                
                if trace.fraction ~= 1 then                
                    
                    local coords = self:GetCoords()
                    coords.yAxis = trace.normal                    
                    coords.xAxis = coords.yAxis:CrossProduct(coords.zAxis)
                    coords.zAxis = coords.xAxis:CrossProduct(coords.yAxis)
                    
                    self.desiredAngles = Angles()
                    self.desiredAngles:BuildFromCoords(coords)
                    self.setAngleStartTime = Shared.GetTime()
                
                end
            
            end
        
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

        -- update pickup checks

        local playersNearby = GetEntitiesWithinXZRange( "Player", self:GetOrigin(), self.pickupRange )
        if #playersNearby > 0 then

            if self.pickupRange > 1 then -- Don't even bother if range too short, just pick first one in list
                Shared.SortEntitiesByDistance(self:GetOrigin(), playersNearby)
            end

            for _, player in ipairs(playersNearby) do
            
                local sameTeam = player:GetTeamNumber() == self:GetTeamNumber()
                if sameTeam and not player:isa("Commander") and self:GetIsValidRecipient(player) then
                
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
