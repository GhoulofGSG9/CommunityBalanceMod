-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\AlienActionFinderMixin.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

local kIconUpdateRate = 0.25

AlienActionFinderMixin = CreateMixin( AlienActionFinderMixin )
AlienActionFinderMixin.type = "AlienActionFinder"

AlienActionFinderMixin.expectedCallbacks =
{
    GetIsAlive = "Bool whether alive or not",
    PerformUseTrace = "Called to use",
    GetIsUsing = "Returns bool if using something"
}

function AlienActionFinderMixin:__initmixin()
    
    PROFILE("AlienActionFinderMixin:__initmixin")
    
    if Client and Client.GetLocalPlayer() == self then
    
        self.actionIconGUI = GetGUIManager():CreateGUIScript("GUIActionIcon")
        self.actionIconGUI:SetColor(kAlienFontColor)
        self.lastAlienActionFindTime = 0
        
    end

end

function AlienActionFinderMixin:OnDestroy()

    if Client and self.actionIconGUI then
    
        GetGUIManager():DestroyGUIScript(self.actionIconGUI)
        self.actionIconGUI = nil
        
    end

end

if Client then

    function AlienActionFinderMixin:OnProcessMove(input)
        PROFILE("AlienActionFinderMixin:OnProcessMove")
        
        local prediction = Shared.GetIsRunningPrediction()
        if prediction then
            return
        end

        local now = Shared.GetTime()
        local enoughTimePassed = (now - self.lastAlienActionFindTime) >= kIconUpdateRate
         -- If pressing use, keep updating (for smooth dissolve progress bars)
        if not enoughTimePassed and bit_band(input.commands, Move.Use) == 0 then
            return
        end
        
        self.lastAlienActionFindTime = now

        local ent = self:PerformUseTrace()
        local usageAllowed = ent ~= nil -- check for entity
        usageAllowed = usageAllowed and (self:GetGameStarted() or (ent.GetUseAllowedBeforeGameStart and ent:GetUseAllowedBeforeGameStart())) -- check if entity can be used before game start
        usageAllowed = usageAllowed and (not GetWarmupActive() or not ent.GetCanBeUsedDuringWarmup or ent:GetCanBeUsedDuringWarmup()) -- check if entity can be used during warmup
        if usageAllowed then
        
            if GetPlayerCanUseEntity(self, ent) and not self:GetIsUsing() then
            
                if ent:isa("Hive") and ent:GetIsBuilt() then
                    local text = self:GetGameStarted() and "START_COMMANDING" or "START_GAME"
                    self.actionIconGUI:ShowIcon(BindingsUI_GetInputValue("Use"), nil, text, nil)
                elseif ent:isa("Egg") then
                    self.actionIconGUI:ShowIcon(BindingsUI_GetInputValue("Use"), nil, "EVOLVE", nil)
                elseif ent:isa("BabblerEgg") then
                    self.actionIconGUI:ShowIcon(BindingsUI_GetInputValue("Use"), nil, "HATCH", nil)
                elseif HasMixin(ent, "Digest") and ent:GetIsAlive() then
                
                    local digestFraction = DigestMixin.GetDigestFraction(ent)
                    -- avoid the slight flicker at the end, caused by the digest effect for Clogs..
                    if digestFraction <= 1.0 then
                        self.actionIconGUI:ShowIcon(BindingsUI_GetInputValue("Use"), nil, "DESTROY", digestFraction)
                     else
                        self.actionIconGUI:Hide()
                     end
                     
                else
                    self.actionIconGUI:ShowIcon(BindingsUI_GetInputValue("Use"), nil, nil, nil)
                end
                
            else
                self.actionIconGUI:Hide()
            end
            
        else
            self.actionIconGUI:Hide()
        end
        
    end
    
end
