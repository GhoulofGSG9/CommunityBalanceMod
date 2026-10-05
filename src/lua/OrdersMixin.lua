-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\OrdersMixin.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/TechTreeConstants.lua")
Script.Load("lua/PhysicsGroups.lua")

OrdersMixin = CreateMixin(OrdersMixin)
OrdersMixin.type = "Orders"

OrdersMixin.expectedCallbacks =
{
    -- GetExtents() is required by GetGroundAt().
    GetExtents = "Returns a Vector describing the extents of this Entity."
}

OrdersMixin.expectedConstants =
{
    kMoveOrderCompleteDistance = "How close to the move location we must be until the order is complete."
}

local kTimeSinceDamageDefendComplete = 10
local kDefendCompleteDistance = 5

OrdersMixin.kMaxOrdersPerUnit = 10
OrdersMixin.kOrderDelay = 0.2

OrdersMixin.networkVars =
{
    -- The currentOrderId is needed on the Client for displaying
    -- to other players such as the Commander.
    currentOrderId  = "entityid"
}

local function UpdateOrderIndizes(self)

    for i = 1, #self.orders do
    
        local order = Shared.GetEntity(self.orders[i])
        if order then
            order:SetIndex(i)
        end
    
    end

end

function OrdersMixin:__initmixin()
    
    PROFILE("OrdersMixin:__initmixin")
    
    self.ignoreOrders = false

    -- Current orders. List of order entity ids.
    self.orders = { }

    -- Current order index. Especially useful for when we are looping through orders without "completing" them. (Patrol, for example)
    self.currentOrderIndex = 1
    self.currentOrderId = Entity.invalidId
    
end

local function OrderChanged(self)
    
    UpdateOrderIndizes(self)

    if self:GetHasOrder() then
        -- Since this is called whenever an order changes and when orders are transferred ( from a drifter egg to a drifter for example ),
        -- we need to specifically update the current order entity id.
        if self.currentOrderIndex > self:GetMaxOrderIndex() then
            self.currentOrderIndex = 1
        end
        self.currentOrderId = self.orders[self:GetCorrectedOrderIndex()] or Entity.invalidId
    else
        self.currentOrderIndex = 1
        self.currentOrderId = Entity.invalidId
    end

    
    if self.OnOrderChanged then
        self:OnOrderChanged()
    end
    
end

function OrdersMixin:GetIsLoopingOrders()

    if self:GetNumOrders() <= 0 then
        return false
    end

    local order = self:GetCurrentOrder()
    if order then
        return (GetIsOrderLoopingType(order))
    end

    return false
end

function OrdersMixin:TransferOrders(dest)
    
    table.copy(self.orders, dest.orders)

    -- The orders now belong to dest. Leaving the old owner would make them irrelevant to the
    -- commander (and unreachable through GetOrdersClient) once the old entity is gone.
    for _, orderId in ipairs(dest.orders) do
        local order = Shared.GetEntity(orderId)
        if order then
            order:SetOwner(dest)
        end
    end
    OrderChanged(dest)
    
    table.clear(self.orders)
    OrderChanged(self)
    
end

function OrdersMixin:CopyOrdersTo(dest)
    
    for index, orderId in ipairs(self.orders) do

        local sourceOrder = Shared.GetEntity(orderId)
        local orderCopy = sourceOrder and GetCopyFromOrder(sourceOrder)
        if orderCopy then
            orderCopy:SetOwner(dest)
        
            table.insert(dest.orders, orderCopy:GetId())
        end
        
    end

    OrderChanged(dest)
    
end

function OrdersMixin:GetHasOrder()
    return self:GetNumOrders() > 0
end

function OrdersMixin:GetNumOrders()
    return table.icount(self.orders)
end

function OrdersMixin:SetIgnoreOrders(setIgnoreOrders)
    self.ignoreOrders = setIgnoreOrders
end

function OrdersMixin:GetIgnoreOrders()
    return self.ignoreOrders
end

local function SetOrder(self, order, clearExisting, insertFirst, giver)

    if self.ignoreOrders or order:GetType() == kTechId.Default then
        return false
    end
    
    if clearExisting then
        self:ClearOrders()
    end
    
    -- Always snap the location of the order to the ground.
    local location = order:GetLocation()
    if location then
    
        location = GetGroundAt(self, location, PhysicsMask.AIMovement)
        order:SetLocation(location)
        
    end
    
    order:SetOwner(self)
    
    if insertFirst then
        table.insert(self.orders, 1, order:GetId())
    else
        table.insert(self.orders, order:GetId())
    end
    
    self.timeLastOrder = Shared.GetTime()
    OrderChanged(self)
    
    return true
    
end

--
-- Children can provide a OnOverrideOrder function to issue build, construct, etc. orders on right-click.
--
local function OverrideOrder(self, order)

    if self.OnOverrideOrder then
        self:OnOverrideOrder(order)
    elseif order:GetType() == kTechId.Default then
        order:SetType(kTechId.Move)
    end
    
end

local function OrderTargetInvalid(self, targetId)

    local invalid = false
    
    if targetId and targetId ~= Entity.invalidId  then
    
        local target = Shared.GetEntity(targetId)
        
        invalid = not target or
                  (target:isa("PowerPoint") and target:GetPowerState() == PowerPoint.kPowerState.unsocketed) or
                  target:isa("ResourcePoint") or target:isa("TechPoint")
    
    end

    return invalid

end

local kFriendlyTargetsOnlyOrderTypes = set
{
    kTechId.Defend,
    kTechId.Construct
}

local kNoTargetOrderTypes = set
{
    kTechId.Move
}

function OrdersMixin:GiveOrder(orderType, targetId, targetOrigin, orientation, clearExisting, insertFirst, giver)

    ASSERT(type(orderType) == "number")

    if self.ignoreOrders or OrderTargetInvalid(self, targetId) or (self.timeLastOrder and self.timeLastOrder + OrdersMixin.kOrderDelay > Shared.GetTime()) or
            (self:GetNumOrders() + 1 > OrdersMixin.kMaxOrdersPerUnit and not clearExisting) then

        return kTechId.None
    end

    -- prevent AI units from attack friendly players
    if orderType == kTechId.Attack then

        local target = Shared.GetEntity(targetId)
        if target and target:isa("Player") and target:GetTeamNumber() == self:GetTeamNumber() and not GetGamerules():GetFriendlyFire() then
            return kTechId.None
        end

    elseif kFriendlyTargetsOnlyOrderTypes[orderType] then

        local target = Shared.GetEntity(targetId)
        if target and target:GetTeamNumber() ~= self:GetTeamNumber() then
            return kTechId.None
        end

    end

    if clearExisting == nil then
        clearExisting = true
    end

    if insertFirst == nil then
        insertFirst = true
    end

    local order = CreateOrder(orderType, targetId, targetOrigin, orientation)

    if self.OnValidateOrder and not self:OnValidateOrder(order) then
        return kTechId.None
    end
    
    OverrideOrder(self, order)

    if kNoTargetOrderTypes[order:GetType()] then
        order.orderParam = Entity.invalidId
    end

    if self:GetHasOrder() then

        local currentOrder = self:GetCurrentOrder()

        if GetIsOrderLoopingType(order) and self:GetIsLoopingOrders() then

            -- Clear existing if com is not holding down "Shift" or order types are different or new order should repeat itself indefinitely.
            clearExisting = clearExisting or order:GetType() ~= currentOrder:GetType() or GetIsOrderRepeatingType(order)

        -- Clear existing if we are adding a order type that clears itself after completion.
        elseif GetIsOrderLoopingType(order) ~= self:GetIsLoopingOrders() then
            clearExisting = clearExisting or GetIsOrderLoopingType(currentOrder)
        end
    end

    -- We have not added this order to the entity's list of orders yet, so num orders will be one less.
    if self:GetHasOrder() and not clearExisting and not insertFirst then
        local lastOrder = self:GetLastOrder()
        order:SetOrigin(lastOrder:GetLocation())
    else
        order:SetOrigin(self:GetOrigin())
    end
    
    local success = SetOrder(self, order, clearExisting, insertFirst, giver)

    if success then

        if success and self.OnOrderGiven then
            self:OnOrderGiven(order)
        end
    end
    
    return ConditionalValue(success, order:GetType(), kTechId.None)
    
end

local function DestroyOrders(self)
    
    -- Allow ents to hook destruction of current order.
    local first = true
    
    -- Delete all order entities.
    for index, orderEntId in ipairs(self.orders) do
    
        local orderEnt = Shared.GetEntity(orderEntId)
        ASSERT(orderEnt ~= nil)
        
        if first then
        
            if self.OnDestroyCurrentOrder and orderEnt ~= nil then
                self:OnDestroyCurrentOrder(orderEnt)
            end
            first = false
            
        end
        
        if orderEnt then
            if orderEnt:isa("SharedOrder") then
                orderEnt:Unregister(self)
            else
                DestroyEntity(orderEnt)  
            end
        end    
        
    end
    
    table.clear(self.orders)

end

function OrdersMixin:ClearOrders()

    if table.icount(self.orders) > 0 then
    
        DestroyOrders(self)
        OrderChanged(self)
        
    end
    
end

function OrdersMixin:Reset()
    self:ClearOrders()
end

function OrdersMixin:OnKill()
    self:ClearOrders()
end

function OrdersMixin:GetHasSpecifiedOrder(orderEnt)

    ASSERT(orderEnt ~= nil and orderEnt.GetId ~= nil)
    
    for index, orderEntId in ipairs(self.orders) do
        if orderEntId == orderEnt:GetId() then
            return true
        end
    end
    
    return false

end

function OrdersMixin:GetMaxOrderIndex()
    return (self:GetNumOrders() * 2)
end

function OrdersMixin:GetCorrectedOrderIndex()

    local isReturning = (self.currentOrderIndex > self:GetNumOrders())
    local orderIndex = ConditionalValue(isReturning, self.currentOrderIndex - 2*(self.currentOrderIndex - self:GetNumOrders()) + 1, self.currentOrderIndex)

    return orderIndex
end

function OrdersMixin:GetCurrentOrder()

    if self.currentOrderId ~= Entity.invalidId then
        return (Shared.GetEntity(self.currentOrderId))
    end

    return nil
end

function OrdersMixin:GetLastOrder()
    local lastOrderId = self.orders[#self.orders]
    return lastOrderId and Shared.GetEntity(lastOrderId) or nil
end

function OrdersMixin:ClearCurrentOrder()

    --Print("%s:ClearCurrentOrder", self:GetClassName())

    local currentOrder = self:GetCurrentOrder()
    if currentOrder then
    
        if currentOrder:isa("SharedOrder") then
            currentOrder:Unregister(self)
        else
            if Server then
                DestroyEntity(currentOrder)
            end
        end
        
        table.remove(self.orders, self:GetCorrectedOrderIndex())
    end
    
    OrderChanged(self)
    
end

function OrdersMixin:GetCurrentOrderTarget()

    local isLooping = self:GetIsLoopingOrders()
    local order = self:GetCurrentOrder()

    if order then
        if isLooping then

            local isReturning = (self.currentOrderIndex > self:GetNumOrders())
            return ConditionalValue(isReturning, order:GetOrigin(), order:GetLocation())

        else
            return order:GetLocation()
        end
    end

    return nil

end

function OrdersMixin:CompletedCurrentOrder()

    --[[
        NOTE(Salads): Looping type orders currently include both "repeat one order indefinitely" and "cycle through orders without removing them" types.
        So, CompletedCurrentOrder should only be called for non-looping and the latter looping order type.
    ]]--

    local currentOrder = self:GetCurrentOrder()
    local isLooping = self:GetIsLoopingOrders()
    if currentOrder then

        if self.OnOrderComplete then
            self:OnOrderComplete(currentOrder)
        end

        if not isLooping then -- For orders that should be removed after completion.
            self:ClearCurrentOrder()
        else

            if self.currentOrderIndex >= self:GetMaxOrderIndex() then
                self.currentOrderIndex = 1
            else
                self.currentOrderIndex = self.currentOrderIndex + 1
            end

            self.currentOrderId = self.orders[self:GetCorrectedOrderIndex()] or Entity.invalidId
        end

    end
end

-- Convert rally orders to move and we're done.
function OrdersMixin:ProcessRallyOrder(originatingEntity)

    if self.ignoreOrders then
        return
    end
    
    originatingEntity:CopyOrdersTo(self)
    
    for _, orderId in ipairs(self.orders) do
    
        local order = Shared.GetEntity(orderId)
        ASSERT(order ~= nil)
        
        if order:GetType() == kTechId.SetRally then
            order:SetType(kTechId.Move)
        end
        
    end
    
end

if Server then

    local function TriggerOrderCompletedAlert(self)
    
        if HasMixin(self, "Team") then
            
            local team = self:GetTeam()
            local teamType
            if team then
                teamType = team:GetTeamType()
            end
            
            if teamType then
                if teamType == kMarineTeamType then
                    self:GetTeam():TriggerAlert(kTechId.MarineAlertOrderComplete, self)
                else
                    self:GetTeam():TriggerAlert(kTechId.AlienAlertOrderComplete, self)
                end
            end

        end
    
    end

    local function SharedUpdate(self)

        local currentOrder = self:GetCurrentOrder()
        
        if currentOrder ~= nil then
            
            local orderType = currentOrder:GetType()

            if orderType == kTechId.Move then
            
                if (currentOrder:GetLocation() - self:GetOrigin()):GetLength() < self:GetMixinConstants().kMoveOrderCompleteDistance then
                
                    TriggerOrderCompletedAlert(self)
                    self:CompletedCurrentOrder()
                    
                end
                
            elseif orderType == kTechId.Patrol then

                -- Patrol orders do not get "completed", so we do nothing here.
            
            elseif orderType == kTechId.Construct or orderType == kTechId.AutoConstruct then
            
                local orderTarget = Shared.GetEntity(currentOrder:GetParam())
                
                if orderTarget == nil or (not orderTarget:GetIsAlive() and not orderTarget:isa("PowerPoint")) or orderTarget.GetIsBuilt == nil then
                    self:ClearCurrentOrder()                    
                elseif orderTarget:GetIsBuilt() or ( orderTarget:isa("PowerPoint") and not orderTarget:GetCanConstruct( self ) ) then
                    self:CompletedCurrentOrder()
                    TriggerOrderCompletedAlert(self)
                end
                
            elseif orderType == kTechId.Weld or orderType == kTechId.Heal or orderType == kTechId.AutoWeld or orderType == kTechId.AutoHeal then

                local orderTarget = Shared.GetEntity(currentOrder:GetParam())
                
                if orderTarget then
                    currentOrder:SetLocation(orderTarget:GetOrigin())
                end
                
                -- clear weld targets which are too far away for players
                local tooFarAway = (orderType == kTechId.AutoWeld or orderType == kTechId.AutoHeal) and orderTarget and self:isa("Player") and (orderTarget:GetOrigin() - self:GetOrigin()):GetLength() > 20
                
                if orderTarget == nil or (not orderTarget:isa("PowerPoint") and not orderTarget:GetIsAlive()) or tooFarAway then
                    self:ClearCurrentOrder()
                elseif orderTarget:GetHealthScalar() >= 1 or (orderTarget:isa("Marine") and orderTarget:GetArmor() / orderTarget:GetMaxArmor() >= 1) then
                    self:CompletedCurrentOrder()
                    TriggerOrderCompletedAlert(self)
                end
            
            elseif orderType == kTechId.Attack then
            
                local orderTarget = Shared.GetEntity(currentOrder:GetParam())

                if orderTarget then

                    currentOrder:SetLocation(orderTarget:GetOrigin())

                    if HasMixin(orderTarget, "LOS") then

                        if (not orderTarget:GetIsSighted()) and orderTarget:isa("Player") then

                            -- NOTE(Salads): Remove the waypoint once the enemy player is out of relevancy range.
                            local attackOrderNonSightedDistance = kMaxRelevancyDistance
                            local distanceSquared = attackOrderNonSightedDistance * attackOrderNonSightedDistance
                            if (orderTarget:GetOrigin() - self:GetOrigin()):GetLengthSquared() >= distanceSquared then

                                self:ClearCurrentOrder()
                                return

                            end

                        end
                    end

                end

                if not orderTarget or orderTarget:GetId() == Entity.invalidId then
                
                    -- AI units needs to be able to attack locations
                    if not currentOrder.allowLocationAttack or not currentOrder:GetLocation() then
                    
                         self:ClearCurrentOrder()
                        
                    end
                    
                -- If given an order to a Live entity, clear the order when that entity is dead.
                -- Do not clear the order for non-live entities as there are cases we need to
                -- attack non-live entities.
                elseif HasMixin(orderTarget, "Live") and not orderTarget:GetIsAlive() then
                
                    TriggerOrderCompletedAlert(self)
                    self:CompletedCurrentOrder()
                    
                end
                
            elseif orderType == kTechId.Defend then
            
                local orderTarget = Shared.GetEntity(currentOrder:GetParam())
                local orderTargetIsLive = orderTarget ~= nil and HasMixin(orderTarget, "Live")
                
                -- If the orderTarget hasn't taken damage yet, GetTimeOfLastDamage() will return nil.
                -- In this case, just use the time the order was issued to decide when to destroy it below.
                local lastDamageTime = (orderTargetIsLive and orderTarget:GetTimeOfLastDamage()) or 0
                if lastDamageTime < currentOrder:GetOrderTime() then
                    lastDamageTime = currentOrder:GetOrderTime()
                end
                
                if not orderTarget or orderTarget:GetId() == Entity.invalidId or
                   not orderTargetIsLive or not orderTarget:GetIsAlive() then
                
                    self:ClearCurrentOrder()
                    
                elseif orderTargetIsLive and (Shared.GetTime() - lastDamageTime) > kTimeSinceDamageDefendComplete then
                
                    -- Only complete if self is close enough to the target.
                    if (self:GetOrigin() - orderTarget:GetOrigin()):GetLengthSquared() < (kDefendCompleteDistance * kDefendCompleteDistance) then
                    
                        TriggerOrderCompletedAlert(self)
                        self:CompletedCurrentOrder()
                        
                    else
                        self:ClearCurrentOrder()
                    end
                    
                end
                
            end
            
        end
        
    end
    
    function OrdersMixin:OnUpdate(deltaTime)

        PROFILE("OrdersMixin:OnUpdate")

        SharedUpdate(self)
        
    end
    
    function OrdersMixin:OnProcessMove(input)

        PROFILE("OrdersMixin:OnProcessMove")

        SharedUpdate(self)
        
    end
    
end

-- Note: This needs to be tested.
-- Get target of attack order, if any.
function OrdersMixin:GetTarget()

    local target

    local order = self:GetCurrentOrder()
    if order ~= nil and (order:GetType() == kTechId.Attack or order:GetType() == kTechId.SetTarget) then
        target = Shared.GetEntity(order:GetParam())
    end
    
    return target
    
end

-- Note: This needs to be tested.
function OrdersMixin:PerformAction(techNode, position)
    self:OnPerformAction(techNode, position)
end

--
-- Other mixins can implement this function to handle more specific actions.
-- Called when tech tree action is performed on the entity.
-- Return true if legal and action handled. Position passed if applicable.
--
function OrdersMixin:OnPerformAction(techNode, position)

    if not self.ignoreOrders and techNode:GetTechId() == kTechId.Stop then
        self:ClearOrders()
    end
    
end

function OrdersMixin:CopyPlayerDataFrom(player)

    if HasMixin(player, "Orders") then
        player:TransferOrders(self)
    end
    
end

if Client then

    local function ResetOrders(self)
    
        if self.lastClientOrderUpdate ~= Shared.GetTime() then
            
            self.ordersClient = {}
            self.lastClientOrderUpdate = Shared.GetTime()
            
        end
    
    end

    function OrdersMixin:AddClientOrder(order)
    
        ResetOrders(self)
        
        assert(order:GetIndex())
        assert(order:GetIndex() > 0)
        self.ordersClient[order:GetIndex()] = order
    
    end

    local gLastOrdersUpdate
    local function UpdateOrdersClient()
        
        -- update all orders for all entities once per frame
        if gLastOrdersUpdate ~= Shared.GetTime() then
            
            local orderEnts = Shared.GetEntitiesWithClassname("Order")
            local numOrders = orderEnts:GetSize()
            for i=1, numOrders do
                local order = orderEnts:GetEntityAtIndex(i-1)
                
                if not order:GetIsDestroyed() then
                    
                    local orderOwner = order:GetOwner()
                    if orderOwner and orderOwner.AddClientOrder then
                        orderOwner:AddClientOrder(order)
                    end
                    
                end
                
            end
            
            gLastOrdersUpdate = Shared.GetTime()
            
        end
        
    end

    function OrdersMixin:GetOrdersClient()
    
        ResetOrders(self)
        UpdateOrdersClient()
        
        -- Sometimes, if an order has JUST been completed, we won't see an order at index 1, but we will
        -- see orders at index 2 and onwards.  In this case, just shift everything down by one.  This
        -- prevents the order lines from briefly disappearing from commander view.
        local index = 1
        while self.ordersClient[index] == nil and self.ordersClient[index+1] ~= nil do
            self.ordersClient[index] = self.ordersClient[index+1]
            self.ordersClient[index+1] = nil
            index = index + 1
        end
        
        local orders = {}
        
        table.copy(self.ordersClient, orders, true)
        
        return orders
    
    end


end
