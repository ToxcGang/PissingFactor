local M = {}
M.schema = {
    ReliefSeconds = { 8, 1, 60 },
    RangeCm = { 400, 50, 600 },
    StainSeconds = { 60, 1, 300 },
    StainFadeSeconds = { 10, 0, 60 },
    WaterSeconds = { 4, 0.5, 15 },
    MaxStains = { 256, 1, 256, integer = true },
    StampsPerSecond = { 5, 1, 5, integer = true },
    InputTimeoutSeconds = { 1, 0.5, 2 },
    TickSeconds = { 0.1, 0.1, 0.1 },
}

function M.finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.validate(source)
    source = type(source) == "table" and source or {}
    local result, warnings = {}, {}
    for name, rule in pairs(M.schema) do
        local value = source[name]
        if value == nil then value = rule[1] end
        if not M.finite(value) or value < rule[2] or value > rule[3]
            or (rule.integer and value % 1 ~= 0) then
            warnings[#warnings + 1] = name .. " is invalid; using " .. rule[1]
            value = rule[1]
        end
        result[name] = value
    end
    result.StainFadeSeconds = math.min(result.StainFadeSeconds, result.StainSeconds)
    result.Debug = source.Debug == true
    return result, warnings
end

return M
