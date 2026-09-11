-- Bindings confirmed in the 1.4.0.28206 reflection dump. Gameplay semantics
-- must additionally pass the recorded in-game acceptance tests.
local Config = require("pf.config")
local Game = {}
Game.playerClass = "Abiotic_PlayerCharacter_C"
Game.playerPath = "/Game/Blueprints/Characters/Abiotic_PlayerCharacter.Abiotic_PlayerCharacter_C"
Game.parentPath = "/Game/Blueprints/Characters/Abiotic_Character_ParentBP.Abiotic_Character_ParentBP_C"

function Game.valid(object)
    if not object then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

function Game.same(a, b)
    return Game.valid(a) and Game.valid(b) and a:GetAddress() == b:GetAddress()
end

function Game.read(object, name)
    local ok, value = pcall(function() return object[name] end)
    if not ok then return nil end
    return value
end

function Game.inspect(player)
    if not Game.valid(player) then return false, "player unavailable" end
    for _, name in ipairs({"CurrentContinence", "MaxContinence"}) do
        if not Config.finite(Game.read(player, name)) then return false, "missing numeric " .. name end
    end
    for _, name in ipairs({"HasContinence", "IsDead", "IsDBNO", "IsSittingInSeat",
        "ClimbingLadder", "PerformingMeleeAttack", "PerformingInteraction", "SprintKeyHeld"}) do
        if type(Game.read(player, name)) ~= "boolean" then return false, "missing boolean " .. name end
    end
    if not Game.valid(Game.read(player, "ModifyStat_Continence")) then
        return false, "ModifyStat_Continence unavailable"
    end
    return true
end

function Game.state(player)
    local valid, reason = Game.inspect(player)
    if not valid then return { eligible = false, reason = reason } end
    local p = { current = player.CurrentContinence, maximum = player.MaxContinence, eligible = true }
    local blockers = {
        {"IsDead", "dead"}, {"IsDBNO", "downed"}, {"IsSittingInSeat", "seated"},
        {"ClimbingLadder", "climbing"}, {"PerformingMeleeAttack", "attacking"},
        {"PerformingInteraction", "interacting"}, {"SprintKeyHeld", "sprinting"},
    }
    if not player.HasContinence then p.eligible = false; p.reason = "needs_disabled"; return p end
    for _, blocker in ipairs(blockers) do
        if player[blocker[1]] then p.eligible = false; p.reason = blocker[2]; return p end
    end
    local movement = player.CharacterMovement
    if not Game.valid(movement) then p.eligible = false; p.reason = "movement_unavailable"; return p end
    if movement:IsSwimming() or movement:IsFalling() then
        p.eligible = false; p.reason = "unsupported_movement"; return p
    end
    return p
end

function Game.localEligible(player, controller)
    if not Game.valid(player) or not Game.valid(controller) then return false end
    local settings=StaticFindObject("/Script/Engine.Default__InputSettings")
    if Game.read(settings,"bShouldFlushPressedKeysOnViewportFocusLost") ~= true then return false end
    if Game.read(controller, "IsTextChatOpen") ~= false
        or Game.read(controller, "MinigameActive") ~= false then return false end
    -- Unknown menu/focus state is deliberately not treated as playable input.
    local menu = { MenuOpen = true }
    local ok = pcall(function() player:IsAnyMenuOpen(menu) end)
    if not ok or menu.MenuOpen ~= false then return false end
    if controller.bShowMouseCursor then return false end
    for _, key in ipairs({"Local_KeyHeld_Fire", "Local_KeyHeld_AltFire", "Local_KeyHeld_Interact"}) do
        if Game.read(player, key) ~= false then return false end
    end
    return Game.state(player).eligible
end

function Game.applyRelief(player, target)
    if not player:HasAuthority() then error("Refusing client-side continence mutation") end
    local before, maximum = player.CurrentContinence, player.MaxContinence
    if not Config.finite(before) or not Config.finite(target) or not Config.finite(maximum)
        or target < before or target > maximum then error("Invalid continence update") end
    local delta = target - before
    if delta > 0 then player:ModifyStat_Continence(delta) end
    local after = player.CurrentContinence
    if not Config.finite(after) or math.abs(after - target) > 0.001 then
        error("ModifyStat_Continence did not apply the expected positive relief")
    end
    -- Emergency and RepNotify semantics still require an in-game acceptance run.
    -- ForceNetUpdate requests delivery of replicated fields, not a client RPC.
    player:ForceNetUpdate()
    return after
end

function Game.origin(player)
    local mesh = player.Mesh
    if Game.valid(mesh) and mesh:DoesSocketExist(FName("hips")) then
        local location = mesh:GetSocketLocation(FName("hips"))
        if location then return {X=location.X,Y=location.Y,Z=location.Z} end
    end
    local location = player:K2_GetActorLocation()
    return { X=location.X, Y=location.Y, Z=location.Z - 10 }
end

return Game
