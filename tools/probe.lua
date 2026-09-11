-- Opt-in development probe. Install as a separate PissingFactorProbe mod.
-- Generates local reflection metadata; never upload dumps of game content.
local UEHelpers = require("UEHelpers")
local didDump, didPlayer, didRig = false, false, false
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

local function json(value)
    if type(value) == "string" then
        return '"' .. value:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n') .. '"'
    elseif type(value) == "number" or type(value) == "boolean" then return tostring(value)
    elseif type(value) == "table" then
        local parts = {}
        if #value > 0 then
            for _,v in ipairs(value) do parts[#parts+1]=json(v) end
            return '[' .. table.concat(parts,',') .. ']'
        end
        for k,v in pairs(value) do parts[#parts+1]=json(k)..':'..json(v) end
        return '{' .. table.concat(parts,',') .. '}'
    end
    return 'null'
end

local function rig(label, component)
    if not component or not component:IsValid() then return end
    local mesh = component:GetSkinnedAsset()
    if not mesh:IsValid() then return end
    local bones = {}
    for i=0,component:GetNumBones()-1 do
        local name = component:GetBoneName(i)
        local t = component:GetRefPoseTransform(i)
        bones[#bones+1] = {name=name:ToString(),parent=component:GetParentBone(name):ToString(),
            translation={t.Translation.X,t.Translation.Y,t.Translation.Z},
            rotation={t.Rotation.X,t.Rotation.Y,t.Rotation.Z,t.Rotation.W},
            scale={t.Scale3D.X,t.Scale3D.Y,t.Scale3D.Z}}
    end
    log("PF_RIG_JSON=" .. json({label=label,mesh=mesh:GetFullName(),
        skeleton=mesh.Skeleton:GetFullName(),bones=bones}))
end

local function probe()
    local ok, err = pcall(function()
        local player = UEHelpers.GetPlayer()
        if not player or not player:IsValid() then player = FindFirstOf("Abiotic_PlayerCharacter_C") end
        if player and player:IsValid() then
            inspect("Player", player, {"CurrentContinence", "MaxContinence", "HasContinence",
                "CurrentHealth", "IsDead", "IsSprinting", "IsSwimming", "IsInWater",
                "MyPlayerController", "Mesh", "Mesh1P", "CharacterMovement"})
            inspect("Controller", UEHelpers.GetPlayerController(), {
                "MinigameActive", "bShowMouseCursor", "PlayerInput", "InputComponent"})
            didPlayer = true
            if not didRig then
                rig("hands",player.FPArms)
                rig("body",player.Mesh)
                didRig = true
                local out = {MenuOpen=false}
                local success,result = pcall(function() return player:IsAnyMenuOpen(out) end)
                log("Menu call: " .. tostring(success) .. " result=" .. tostring(result) .. " out=" .. json(out))
            end
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
