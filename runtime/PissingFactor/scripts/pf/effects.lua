local Effects = {}
Effects.__index = Effects

function Effects.new(config)
    return setmetatable({ config = config, records = {}, nextId = 1, lastStamp = {} }, Effects)
end

function Effects:expire(now)
    local remaining = {}
    for _, record in ipairs(self.records) do
        if record.expires > now then remaining[#remaining + 1] = record end
    end
    self.records = remaining
end

function Effects:stamp(playerId, hit, now)
    self:expire(now)
    if not hit or (hit.kind ~= "solid" and hit.kind ~= "water") then return nil end
    local previous = self.lastStamp[playerId] or -math.huge
    if now - previous < 1 / self.config.StampsPerSecond - 0.000001 then return nil end
    self.lastStamp[playerId] = now
    local water = hit.kind == "water"
    local lifetime = water and self.config.WaterSeconds or self.config.StainSeconds
    local record = { id = self.nextId, kind = hit.kind, position = hit.position,
        normal = hit.normal, component = hit.component, localPosition = hit.localPosition,
        localNormal = hit.localNormal, created = now, expires = now + lifetime,
        fade = water and lifetime or self.config.StainFadeSeconds }
    self.nextId = self.nextId + 1
    if #self.records >= self.config.MaxStains then table.remove(self.records, 1) end
    self.records[#self.records + 1] = record
    return record
end

function Effects:removePlayer(playerId)
    self.lastStamp[playerId] = nil
end

function Effects:snapshot(now)
    self:expire(now)
    local result = {}
    for _, record in ipairs(self.records) do
        local copy = {}
        for key, value in pairs(record) do copy[key] = value end
        copy.remaining = record.expires - now
        result[#result + 1] = copy
    end
    return result
end

function Effects.opacity(record, now)
    if now >= record.expires then return 0 end
    if record.fade <= 0 then return 1 end
    return math.min(1, math.max(0, (record.expires - now) / record.fade))
end

return Effects
