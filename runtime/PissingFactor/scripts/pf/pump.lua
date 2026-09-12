-- One engine-owned tick drives all work. No async callbacks or deferred Lua
-- registry references, including for diagnostic key presses.
local Config = require("pf.config")
local Pump = {}
Pump.__index = Pump

function Pump.new(interval)
    return setmetatable({interval=interval, keyDown=false}, Pump)
end

function Pump:step(now, diagnosticDown)
    if not Config.finite(now) then return false, false, 0 end
    if self.lastNow and now < self.lastNow then
        self.lastTick, self.lastDiagnostic = nil, nil
    end
    self.lastNow = now
    local rising = diagnosticDown == true and not self.keyDown
    self.keyDown = diagnosticDown == true
    local diagnostic = rising and (not self.lastDiagnostic or now-self.lastDiagnostic >= 1)
    if diagnostic then self.lastDiagnostic = now end
    local dt = self.lastTick and now-self.lastTick or self.interval
    local due = not self.lastTick or dt+0.000001 >= self.interval
    if due then self.lastTick = now end
    -- Never catch up a frame stall with a burst of callbacks or extra relief.
    return due, diagnostic, math.min(dt, self.interval)
end

return Pump
