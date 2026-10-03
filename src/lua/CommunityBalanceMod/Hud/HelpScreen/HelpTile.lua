local oldUpdateBinding = HelpTile.UpdateBinding
function HelpTile:UpdateBinding()

    local actions = self.actions
    if type(actions) ~= "function" then
        return oldUpdateBinding(self)
    end

    self.actions = actions()
    oldUpdateBinding(self)
    self.actions = actions

end

local oldSetIsVisible = HelpTile.SetIsVisible
function HelpTile:SetIsVisible(state)

    if state and type(self.actions) == "function" then
        self:UpdateBinding()
        self:UpdateBindingPosition()
        if self.unlocked == false then
            self:UnlockStateChanged()
        end
    end

    oldSetIsVisible(self, state)

end
