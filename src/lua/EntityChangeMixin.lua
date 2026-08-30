-- ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\EntityChangeMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

--
-- EntityChangeMixin allows an entity to be notified when other entities change.
--
EntityChangeMixin = CreateMixin( EntityChangeMixin )
EntityChangeMixin.type = "EntityChange"

EntityChangeMixin.optionalCallbacks =
{
    OnEntityChange = "Called when an entity changes into another entity or is destroyed"
}

if Server then

    function EntityChangeMixin:__initmixin()
        self.replacedById = false
    end

    --
    -- Pass in Id of new Entity this Entity is turning into or nil if it's being deleted.
    --
    function EntityChangeMixin:SendEntityChanged(newId)
        PROFILE("EntityChangeMixin:SendEntityChanged")

        if self.replacedById and newId == nil then
            return -- Already called the OnEntityChange during the replace, no need to redo
        end

        -- This happens during the game shutdown process, so don't force a new game
        -- rules to be created if one doesn't already exist.
        if GetHasGameRules() then
            GetGamerules():OnEntityChange(self:GetId(), newId)
        end
        
        -- Send message to everyone that the player changed ids
        Server.SendNetworkMessage("EntityChanged", BuildEntityChangedMessage(self:GetId(), ConditionalValue(newId ~= nil, newId, -1)), true)
        if newId then
            self.replacedById = true -- We got replaced by a new entId, this is now an empty shell entity
        end
        
    end
    
    function EntityChangeMixin:OnDestroy()
        self:SendEntityChanged(nil)
    end
    
end

if Client then

    function OnCommandEntityChanged(entityChangedTable)
        PROFILE("EntityChangeMixin:OnCommandEntityChanged")
    
        local newId = ConditionalValue(entityChangedTable.newEntityId == -1, nil, entityChangedTable.newEntityId)
        
        local player = Client.GetLocalPlayer()
        
        for index, entity in ientitylist(Shared.GetEntitiesWithTag("EntityChange")) do
        
            if entity.OnEntityChange then
                entity:OnEntityChange(entityChangedTable.oldEntityId, newId)
            end
            
        end
        
    end
    
    Client.HookNetworkMessage("EntityChanged", OnCommandEntityChanged)
    
end
