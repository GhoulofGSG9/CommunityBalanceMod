-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\CloakableMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
--    Outlines targets blue when SetRailgunTarget() is called for kRailgunTargetDuration seconds,
--    pink when the aiming dual rail's next slug resonates on them.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

RailgunTargetMixin = CreateMixin( RailgunTargetMixin )
RailgunTargetMixin.type = "RailgunTarget"

--PrecacheAsset("cinematics/vfx_materials/highlightmodel.surface_shader")

local kRailgunTargetDuration = 0.2
local kHighlightmodel_Material = PrecacheAsset("cinematics/vfx_materials/highlightmodel.material")

RailgunTargetMixin.expectedMixins =
{
    Model = "Required to add to shader mask."
}

function RailgunTargetMixin:__initmixin()
    
    PROFILE("RailgunTargetMixin:__initmixin")
    
    assert(Client)
    self.timeRailgunTargeted = -1
    self.timeRailgunPrimed = -1
end

function RailgunTargetMixin:SetRailgunTarget(primed)
    local now = Shared.GetTime()
    self.timeRailgunTargeted = now
    if primed then
        self.timeRailgunPrimed = now
    end
end

function RailgunTargetMixin:OnUpdate(deltaTime)
    PROFILE("RailgunTargetMixin:OnUpdate")
    local now = Shared.GetTime()
    local isTarget = self.timeRailgunTargeted + kRailgunTargetDuration > now
    local color = isTarget and (self.timeRailgunPrimed + kRailgunTargetDuration > now
            and kEquipmentOutlineColor.Fuchsia or kEquipmentOutlineColor.TSFBlue)
    local model = self:GetRenderModel()
    
    if self.railgunOutlineColor ~= color and model then
    
        if color then
            EquipmentOutline_AddModel(model, color)
        else
            EquipmentOutline_RemoveModel(model)
        end
        
        self.railgunOutlineColor = color

    end

end

--[[ disabled since it doesnt look very good and distracts too much
function RailgunTargetMixin:OnUpdateRender()

    local model = self:GetRenderModel()

    if model then
    
        local intensity = 1 - Clamp( (Shared.GetTime() - self.timeRailgunTargeted) / 0.3, 0, 1 )
        local showMaterial = intensity ~= 0
    
        if not self.railgunHighlightMaterial and showMaterial then
            self.railgunHighlightMaterial = AddMaterial(model, kHighlightmodel_Material)
        elseif not showMaterial and self.railgunHighlightMaterial then
            RemoveMaterial(model, self.railgunHighlightMaterial)
            self.railgunHighlightMaterial = nil
        end

        if self.railgunHighlightMaterial then
            self.railgunHighlightMaterial:SetParameter("intensity", intensity * 0.5)
        end
    
    end

end
--]]
