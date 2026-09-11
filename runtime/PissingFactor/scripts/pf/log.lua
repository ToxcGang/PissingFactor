local Log = { seen = {} }
function Log.info(message) print("[PissingFactor] " .. tostring(message) .. "\n") end
function Log.once(key, message)
    if Log.seen[key] then return end
    Log.seen[key] = true
    Log.info(message)
end
return Log
