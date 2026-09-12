-- Either action key holds the ability. Interruptions require releasing both
-- inputs before starting again; native inventory/menu actions are never replayed.
local Input = {}
Input.__index = Input

function Input.new()
    return setmetatable({ controller = false, keyboard = false,
        blocked = false, held = false }, Input)
end

function Input:cancel()
    self.held = false
    self.blocked = self.controller or self.keyboard
end

function Input:update(keys, enabled)
    self.controller, self.keyboard = keys.controller == true, keys.keyboard == true
    local down = self.controller or self.keyboard
    if enabled ~= true then
        self.blocked = self.blocked or down
    end
    if not down then self.blocked = false end
    self.held = enabled == true and not self.blocked and down
    return { held = self.held }
end

return Input
