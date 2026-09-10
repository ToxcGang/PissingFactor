-- Edge/chord arbitration independent of engine bindings. Interception happens
-- before native action dispatch; observing keys without consuming them is unsafe.
local Input = {}
Input.__index = Input

function Input.new()
    return setmetatable({ bumper = false, down = false, keyboard = false,
        used = false, armed = false, blocked = false, held = false }, Input)
end

function Input:cancel()
    self.held = false
    self.blocked = self.bumper or self.down or self.keyboard
    self.used = true -- do not replay a queued hotbar change after a menu opens
end

function Input:update(keys, enabled)
    local bumper, down, keyboard = keys.bumper == true, keys.down == true, keys.keyboard == true
    local actions = { previousHotbar = false, drop = false, consumeBumper = false, consumeDown = false }
    local risingBumper, risingDown = bumper and not self.bumper, down and not self.down
    if enabled ~= true then
        self:cancel()
    else
        if risingBumper then
            self.armed = not down -- modifier must precede D-pad Down
            self.used = false
        end
        if risingDown and not bumper then actions.drop = true end
        if bumper and down and self.armed then self.used = true end
        if self.bumper and not bumper and not self.used and not self.blocked then
            actions.previousHotbar = true
        end
        actions.consumeBumper = bumper or self.bumper
        actions.consumeDown = (bumper and self.armed) or self.used and (down or self.down)
        self.held = not self.blocked and (keyboard or (bumper and down and self.armed))
    end
    self.bumper, self.down, self.keyboard = bumper, down, keyboard
    if not bumper then self.armed = false end
    if not bumper and not down and not keyboard then
        self.blocked, self.used = false, false
    end
    actions.held = self.held
    return actions
end

return Input
