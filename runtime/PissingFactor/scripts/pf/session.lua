-- Pure server simulation. All times are monotonic world seconds supplied by
-- the engine adapter, never os.clock() or client-supplied timestamps.
local Config = require("pf.config")
local Version = require("pf.version")
local Session = {}
Session.__index = Session

function Session.new(config)
    return setmetatable({
        config = config, active = false, held = false, latched = false,
        sequence = -1, lastInput = -math.huge, ready = false,
        reason = "not_connected", aim = { X = 1, Y = 0, Z = 0 },
    }, Session)
end

function Session:handshake(mod, protocol)
    self.ready = mod == Version.mod and protocol == Version.protocol
    if not self.ready then self:stop("version_mismatch", true) end
    return self.ready
end

function Session:stop(reason, latch)
    self.active = false
    self.reason = reason
    if latch then self.latched = true end
end

function Session:input(sequence, held, aim, now)
    if not self.ready then return false, "not_connected" end
    if not Config.finite(sequence) or sequence < 0 or sequence % 1 ~= 0
        or sequence > 2147483646 or sequence <= self.sequence
        or type(held) ~= "boolean" or not Config.finite(now) then
        return false, "invalid_input"
    end
    if held then
        if type(aim) ~= "table" or not Config.finite(aim.X)
            or not Config.finite(aim.Y) or not Config.finite(aim.Z) then
            return false, "invalid_aim"
        end
        local length = math.sqrt(aim.X ^ 2 + aim.Y ^ 2 + aim.Z ^ 2)
        if not Config.finite(length) or length < 0.001 then return false, "invalid_aim" end
        self.aim = { X = aim.X / length, Y = aim.Y / length, Z = aim.Z / length }
    end
    self.sequence = sequence
    self.lastInput = now
    self.held = held
    if not held then
        self.latched = false
        self:stop("released", false)
    end
    return true
end

function Session:tick(now, dt, player)
    if not Config.finite(now) or not Config.finite(dt) or dt < 0 then
        self:stop("invalid_clock", true)
        return nil
    end
    if not self.ready or not self.held then self.active = false; return nil end
    if now - self.lastInput >= self.config.InputTimeoutSeconds or now < self.lastInput then
        self:stop("input_timeout", true)
        return nil
    end
    if not player or player.eligible ~= true then
        self:stop(player and player.reason or "unavailable", true)
        return nil
    end
    if not Config.finite(player.current) or not Config.finite(player.maximum)
        or player.maximum <= 0 or player.current < 0 or player.current > player.maximum then
        self:stop("incompatible_continence", true)
        return nil
    end
    if player.current >= player.maximum then
        self:stop("empty", true)
        return nil
    end
    if self.latched then return nil end
    self.active = true
    self.reason = "active"
    -- Never award relief for a long stall or time after an input timeout.
    local step = math.min(dt, self.config.TickSeconds)
    local nextValue = math.min(player.maximum,
        player.current + player.maximum * step / self.config.ReliefSeconds)
    if nextValue >= player.maximum then self:stop("empty", true) end
    return nextValue
end

return Session
