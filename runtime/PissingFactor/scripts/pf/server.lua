local Session = require("pf.session")
local Effects = require("pf.effects")
local Trajectory = require("pf.trajectory")
local Config = require("pf.config")
local Log = require("pf.log")
local Server = {}
Server.__index = Server

-- Dependency injection keeps authoritative orchestration testable separately
-- from UE4SS and the cooked Blueprint transport.
function Server.new(config, game, transport)
    return setmetatable({ config=config, game=game, transport=transport,
        sessions={}, effects=Effects.new(config), lastTick=nil }, Server)
end

function Server:add(id, player, actor)
    if self.sessions[id] then self:remove(id) end
    self.sessions[id] = { player=player, actor=actor, simulation=Session.new(self.config) }
end

function Server:remove(id)
    local entry = self.sessions[id]
    if entry then self.transport:destroy(entry.actor) end
    self.sessions[id] = nil
    self.effects:removePlayer(id)
end

function Server:receive(id, actor, message, now)
    if type(message) ~= "table" or not Config.finite(now) then return false end
    local entry = self.sessions[id]
    if not entry or not self.game.same(entry.actor, actor) then return false end
    if not self.transport:ownedBy(actor, entry.player) then return false end
    if not entry.simulation:handshake(message.mod, message.protocol) then return false end
    return entry.simulation:input(message.sequence, message.held, message.aim, now)
end

function Server:tick(now, dt)
    if not Config.finite(now) or not Config.finite(dt) or dt < 0 then return end
    if self.lastTick then
        if now <= self.lastTick then return end
        dt = math.min(dt, now - self.lastTick)
    end
    self.lastTick = now
    local departed = {}
    for id, entry in pairs(self.sessions) do
        local player, session = entry.player, entry.simulation
        if not self.game.valid(player) or not self.game.valid(entry.actor) then
            departed[#departed+1] = id
        else
            local ok, err = pcall(function()
                local state = self.game.state(player)
                local target = session:tick(now, dt, state)
                if target then
                    self.game.applyRelief(player, target)
                    if self.config.Debug then
                        Log.info(string.format("Authority relief %.4f -> %.4f",state.current,target))
                    end
                end
                local path
                if session.active then
                    path = Trajectory.trace(self.game.origin(player), session.aim,
                        self.config.RangeCm, function(a,b)
                            return self.transport:trace(player,a,b)
                        end)
                    local stamp = self.effects:stamp(id,path.hit,now)
                    if stamp then self.transport:publishImpact(stamp) end
                end
                self.transport:publishState(entry.actor, session, path, now)
            end)
            if not ok then
                session:stop("compatibility_error",true)
                self.transport:stop(entry.actor,tostring(err))
            end
        end
    end
    for _, id in ipairs(departed) do self:remove(id) end
    self.effects:expire(now)
    self.transport:pruneImpacts(self.effects.records,now)
end

function Server:reset()
    local ids = {}
    for id in pairs(self.sessions) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do self:remove(id) end
    self.effects=Effects.new(self.config)
    self.lastTick=nil
    self.transport:pruneImpacts({},0)
end

return Server
