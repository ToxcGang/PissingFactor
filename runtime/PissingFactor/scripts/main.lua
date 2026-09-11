local source=debug.getinfo(1,"S").source:gsub("^@","")
local directory=source:match("^(.*[/\\])") or ""
package.path=directory.."?.lua;"..package.path
local Log=require("pf.log")
local Version=require("pf.version")
local Game=require("pf.game")
local Config=require("pf.config")
local UE=require("UEHelpers")
local Server=require("pf.server")
local Transport=require("pf.transport")
local Client=require("pf.client")
local configSource=dofile(directory.."../config.lua")
local config,warnings=Config.validate(configSource)
for _,warning in ipairs(warnings) do Log.info(warning) end
Log.info("Loading "..Version.mod..", protocol "..Version.protocol)

-- The prototype exercises owned RPCs and existing bathroom stats. It stays
-- opt-in until the unfinished collision, UI and presentation work is complete.
if configSource.EnablePrototype~=true then
    Log.info("Development build: gameplay disabled. EnablePrototype is only for disposable-world integration testing.")
    return
end

local world,transport,server,client,lastTime
local hooks={}
local function stringValue(v)
    if type(v)=="string" then return v end
    return v:ToString()
end
local function register(path,callback)
    if hooks[path] then return end
    local pre,post=RegisterHook(path,callback)
    hooks[path]={pre,post}
end
local function rpc(context)
    local actor=context:get()
    if not server or not Game.valid(actor) or not actor:HasAuthority() then return end
    local pawn=actor.PFPawn
    if not Game.valid(pawn) then return end
    local v=actor.PFInputAim
    server:receive(tostring(pawn:GetAddress()),actor,{sequence=actor.PFInputSequence,
        held=actor.PFInputHeld,aim={X=v.X,Y=v.Y,Z=v.Z},
        mod=stringValue(actor.PFInputVersion),protocol=actor.PFInputProtocol},transport:now())
end
local function reset()
    if client then client:close(); client=nil end
    if server then server:reset() end
    for path,ids in pairs(hooks) do
        pcall(UnregisterHook,path,ids[1],ids[2])
    end
    hooks={}
    server,transport,world,lastTime=nil,nil,nil,nil
end

local function initialize(current)
    reset()
    transport=Transport.new(current,config)
    world=current
    server=Server.new(config,Game,transport)
    local path="/Game/Mods/PissingFactor/BP_PFPlayer.BP_PFPlayer_C:"
    register(path.."ServerSetInput",rpc)
    register(path.."ServerUpdateAim",rpc)
    -- These are normal generated UFunctions, not unsupported delegate hooks.
    transport.inputClass.DynamicBindingObjects:ForEach(function(_,binding)
        local object=binding:get()
        if object:IsA("/Script/Engine.InputKeyDelegateBinding") then
            object.InputKeyDelegateBindings:ForEach(function(_,entry)
                local name=entry:get().FunctionNameToBind:ToString()
                register("/Game/Mods/PissingFactor/BP_PFInput.BP_PFInput_C:"..name,function(context)
                    if client and Game.same(client.capture,context:get()) then
                        local ok,err=pcall(function()client:update(false)end)
                        if not ok then Log.once("input_error",err); client:close(); client=nil end
                    end
                end)
            end)
        end
    end)
    Log.info("Transport prototype ready; collision, animation and settings acceptance are pending")
end

local function tick()
    local current=UE.GetWorld()
    if not Game.valid(current) then if world then reset() end; return end
    local instance=UE.GetGameInstance()
    if not Game.valid(instance) then return end
    local installed=stringValue(instance.PlayerVersionString)
    if installed~=Version.game then
        Log.once("game_version:"..installed,"Unsupported game version: "..installed.."; expected "..Version.game)
        if world then reset() end
        return
    end
    if not Game.same(current,world) then initialize(current) end
    local now=transport:now()
    local dt=lastTime and now-lastTime or config.TickSeconds
    lastTime=now
    local present={}
    for _,player in ipairs(FindAllOf(Game.playerClass) or {}) do
        if Game.valid(player) and Game.same(player:GetWorld(),world) then
            local controller=player:GetController()
            if Game.valid(controller) and controller:IsA("/Script/Engine.PlayerController") then
                local id=tostring(player:GetAddress())
                present[id]=true
                if player:HasAuthority() and not server.sessions[id] then
                    local supported,reason=Game.inspect(player)
                    if supported then server:add(id,player,transport:spawnPlayer(player))
                    else Log.once("adapter:"..reason,reason) end
                end
            end
        end
    end
    local departed={}
    for id in pairs(server.sessions) do if not present[id] then departed[#departed+1]=id end end
    for _,id in ipairs(departed) do server:remove(id) end
    local controller=UE.GetPlayerController()
    local player=Game.valid(controller) and controller.Pawn or nil
    if client and (not Game.same(client.player,player) or not Game.valid(client.actor)) then
        client:close();client=nil
    end
    if not client and Game.valid(player) and controller:IsLocalController() then
        for _,actor in ipairs(FindAllOf("BP_PFPlayer_C") or {}) do
            if transport:ownedBy(actor,player) then
                client=Client.new(transport,player,controller,actor);break
            end
        end
    end
    if client and not client:update(true) then client=nil end
    server:tick(now,dt)
end

local function poll()
    ExecuteInGameThread(function()
        local ok,err=pcall(tick)
        if not ok then
            Log.once("runtime:"..tostring(err),"Integration stopped: "..tostring(err))
            pcall(reset)
        end
        ExecuteWithDelay(100,poll)
    end)
end
ExecuteWithDelay(1000,poll)
