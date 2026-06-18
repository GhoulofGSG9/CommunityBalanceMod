-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\PhaseGateUserMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

PhaseGateUserMixin = CreateMixin( PhaseGateUserMixin )
PhaseGateUserMixin.type = "PhaseGateUser"

PhaseGateUserMixin.networkVars =
{
    timeOfLastPhase = "compensated private time"
}

local kPhaseCheckRadius = 0.6

local function SharedUpdate(self)
    PROFILE("PhaseGateUserMixin:OnUpdate")
    if self:GetCanPhase() then

        for _, phaseGate in ipairs(GetEntitiesForTeamWithinRange("PhaseGate", self:GetTeamNumber(), self:GetOrigin(), kPhaseCheckRadius)) do
        
            if phaseGate:GetIsDeployed() and GetIsUnitActive(phaseGate) and phaseGate:Phase(self) then

                self.timeOfLastPhase = Shared.GetTime()
                
                if Client then               
                    self.timeOfLastPhaseClient = Shared.GetTime()
                    local viewAngles = self:GetViewAngles()
                    Client.SetYaw(viewAngles.yaw)
                    Client.SetPitch(viewAngles.pitch)     
                end
                --[[
                if HasMixin(self, "Controller") then
                    self:SetIgnorePlayerCollisions(1.5)
                end
                --]]
                break
                
            end
        
        end
    
    end

end

function PhaseGateUserMixin:__initmixin()
    
    PROFILE("PhaseGateUserMixin:__initmixin")
    
    self.timeOfLastPhase = 0
end

local kOnPhase =
{
    phaseGateId = "entityid",
    phasedEntityId = "entityid"
}
Shared.RegisterNetworkMessage("OnPhase", kOnPhase)

if Server then

    function PhaseGateUserMixin:OnProcessMove(input)
        PROFILE("PhaseGateUserMixin:OnProcessMove")

        local now = Shared.GetTime()
        local rangeCheckThrottleRate = 0.3 -- Low enough in case of beacon/spawn
        local rangeCheckDist = rangeCheckThrottleRate * 30 -- Safe margin
        local performCheck = not self.kLastPhaseInRangeCheck or self.kLastPhaseInRangeCheck + rangeCheckThrottleRate < Shared.GetTime()
        if performCheck and self:GetCanPhase() then

            local gatesNearby = GetEntitiesForTeamWithinRange("PhaseGate", self:GetTeamNumber(), self:GetOrigin(), rangeCheckDist)
            if #gatesNearby == 0 then
                self.kLastPhaseInRangeCheck = now -- Prevents calling this mixing for the next Xs
                return
            end

            for _, phaseGate in ipairs(gatesNearby) do
                local distToGate = self:GetOrigin():GetDistanceTo(phaseGate:GetOrigin())
                if distToGate < kPhaseCheckRadius and phaseGate:GetIsDeployed() and GetIsUnitActive(phaseGate) and phaseGate:Phase(self) then
                    -- If we can found a phasegate we can phase through, inform the server
                    self.timeOfLastPhase = Shared.GetTime()
                    local id = self:GetId()
                    Server.SendNetworkMessage(self:GetClient(), "OnPhase", { phaseGateId = phaseGate:GetId(), phasedEntityId = id or Entity.invalidId }, true)
                    return
                end
            end
        end
    end

    function PhaseGateUserMixin:OnUpdate(deltaTime)
        SharedUpdate(self)
    end
    
end

if Client then

    local function OnMessagePhase(message)
        PROFILE("PhaseGateUserMixin:OnMessagePhase")

        -- TODO: Is there a better way to do this?
        local phaseGate = Shared.GetEntity(message.phaseGateId)
        local phasedEnt = Shared.GetEntity(message.phasedEntityId)

        -- Need to keep this var updated so that client side effects work correctly
        phasedEnt.timeOfLastPhaseClient = Shared.GetTime()

        if phaseGate then
            phaseGate:Phase(phasedEnt)
        end
        local viewAngles = phasedEnt:GetViewAngles()

        -- Update view angles
        Client.SetYaw(viewAngles.yaw)
        Client.SetPitch(viewAngles.pitch)
    end

    Client.HookNetworkMessage("OnPhase", OnMessagePhase)

end

function PhaseGateUserMixin:GetCanPhase()
	
	local kPhaseDelay = 2
	local AdvGates = GetHasTech(self, kTechId.AdvancedObservatory) 
	if AdvGates then
		kPhaseDelay = 1.5
	end

    if Server then
        return self:GetIsAlive() and Shared.GetTime() > self.timeOfLastPhase + kPhaseDelay and not GetConcedeSequenceActive()
    else
        return self:GetIsAlive() and Shared.GetTime() > self.timeOfLastPhase + kPhaseDelay
    end
    
end


function PhaseGateUserMixin:OnPhaseGateEntry(destinationOrigin)
    if Server and HasMixin(self, "LOS") then
        self:MarkNearbyDirtyImmediately()
    end
end
