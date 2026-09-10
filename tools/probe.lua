-- Opt-in development probe. Install as a separate PissingFactorProbe mod.
-- Generates local reflection metadata; never upload dumps of game content.
local UEHelpers = require("UEHelpers")
local didDump, didPlayer = false, false
local function log(message) print("[PissingFactorProbe] " .. tostring(message) .. "\n") end

local function inspect(label, object, names)
    if not object or not object:IsValid() then log(label .. " unavailable"); return end
    log(label .. " " .. object:GetFullName())
    for _, name in ipairs(names) do
        local ok, value = pcall(function() return object[name] end)
        if ok then
            local textOk, valueText = pcall(function()
                if type(value) == "userdata" then return value:GetFullName() end
                return tostring(value)
            end)
            log(name .. " = " .. (textOk and valueText or type(value)))
        else log(name .. " unavailable") end
    end
end

local function probe()
    local ok, err = pcall(function()
        local player = UEHelpers.GetPlayer()
        if player and player:IsValid() then
            inspect("Player", player, {"CurrentContinence", "MaxContinence", "HasContinence",
                "CurrentHealth", "IsDead", "IsSprinting", "IsSwimming", "IsInWater",
                "MyPlayerController", "Mesh", "Mesh1P", "CharacterMovement"})
            inspect("Controller", UEHelpers.GetPlayerController(), {
                "MinigameActive", "bShowMouseCursor", "PlayerInput", "InputComponent"})
            didPlayer = true
        end
        if not didDump then
            LoadAsset("/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C")
            log("Generating local object and C++ reflection dumps")
            DumpAllObjects()
            GenerateSDK()
            didDump = true
            log("Reflection dump complete")
        end
    end)
    if not ok then log(err) end
end

RegisterKeyBind(Key.F6, function() ExecuteInGameThread(probe) end)
local function poll()
    ExecuteInGameThread(function()
        if not didDump or not didPlayer then probe() end
    end)
    if not didPlayer then ExecuteWithDelay(15000, poll) end
end
ExecuteWithDelay(15000, poll)
log("Loaded. F6 writes local diagnostics; player stats are never changed.")
