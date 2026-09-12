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
local Pump=require("pf.pump")
local configSource=dofile(directory.."../config.lua")
local config,warnings=Config.validate(configSource)
for _,warning in ipairs(warnings) do Log.info(warning) end
Log.info("Loading "..Version.mod..", protocol "..Version.protocol..", actor-tick prototype 2")

if configSource.EnablePrototype~=true then
    Log.info("Development build: gameplay disabled. EnablePrototype is only for disposable-world integration testing.")
    return
end

local driver,world,transport,server,client,pump,localController,lastRoster
local failed,busy=false,false
local hooks={}
local driverPath="/Game/Mods/PissingFactor/ModActor.ModActor_C"
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
    if failed or not server or not Game.valid(actor) or not actor:HasAuthority() then return end
    local pawn=actor.PFPawn
    if not Game.valid(pawn) then return end
    local v=actor.PFInputAim
    server:receive(tostring(pawn:GetAddress()),actor,{sequence=actor.PFInputSequence,
        held=actor.PFInputHeld,aim={X=v.X,Y=v.Y,Z=v.Z},
        mod=stringValue(actor.PFInputVersion),protocol=actor.PFInputProtocol},transport:now())
end
local function reset()
    if client then pcall(function()client:close()end); client=nil end
    if server then pcall(function()server:reset()end) end
    for path,ids in pairs(hooks) do pcall(UnregisterHook,path,ids[1],ids[2]) end
    hooks={}
    driver,world,transport,server,pump,localController,lastRoster=nil,nil,nil,nil,nil,nil,nil
    failed,busy=false,false
end

local function diagnostics()
    Log.info("Diagnostic snapshot "..Version.mod.." / protocol "..Version.protocol.." / actor-tick prototype 2")
    Log.info("Local input actor: "..tostring(client~=nil).."; enabled: "..tostring(client and client.enabled))
    local count=0
    if server then
        for _,entry in pairs(server.sessions) do
            if Game.valid(entry.player) then
                count=count+1
                local s=entry.simulation
                Log.info(string.format("Session %d: ready=%s held=%s active=%s sequence=%d reason=%s continence=%.4f/%.4f",
                    count,tostring(s.ready),tostring(s.held),tostring(s.active),s.sequence,s.reason,
                    entry.player.CurrentContinence,entry.player.MaxContinence))
            end
        end
    end
    Log.info("Authority sessions: "..count)
    local message="Input is not ready. See UE4SS.log."
    if client and Game.valid(client.player) and Game.valid(client.actor) then
        local current,maximum=client.player.CurrentContinence,client.player.MaxContinence
        local reason=stringValue(client.actor.PFReason)
        local empty=current>=maximum and " No bathroom need yet." or " Hold P to test relief."
        message=string.format("Continence %.1f/%.1f; input %s; %s.%s",current,maximum,
            client.enabled and "enabled" or "blocked",reason,empty)
    end
    if not Game.showStatus(localController,message) then
        Log.once("status_ui","Local status message unavailable; F6 results are in UE4SS.log")
    end
end

local function refreshRoster(now)
    -- Object discovery is comparatively expensive; simulation still runs at 10 Hz.
    if lastRoster and now>=lastRoster and now-lastRoster<1 then return end
    lastRoster=now
    local present={}
    for _,player in ipairs(FindAllOf(Game.playerClass) or {}) do
        if Game.valid(player) and Game.same(player:GetWorld(),world) then
            local controller=player:GetController()
            if Game.valid(controller) and controller:IsA("/Script/Engine.PlayerController")
                and Game.same(controller.Pawn,player) then
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
    localController=Game.localController(world)
end

local function tick(now,dt)
    refreshRoster(now)
    local controller=localController
    local player=Game.valid(controller) and controller.Pawn or nil
    if client and (not Game.same(client.player,player) or not Game.valid(client.actor)) then
        client:close();client=nil
    end
    if not client and Game.valid(player) and controller:IsLocalController() then
        for _,actor in ipairs(FindAllOf("BP_PFPlayer_C") or {}) do
            if transport:ownedBy(actor,player) then
                client=Client.new(transport,player,controller,actor)
                Log.info("Local input attached. Tap F6 for status; hold P for relief when needed.")
                Game.showStatus(controller,"Prototype input attached. Tap F6 for status (local message and log).")
                break
            end
        end
    end
    if client and not client:update(true) then client=nil end
    server:tick(now,dt)
end

local function heartbeat(context)
    if failed or busy or not Game.same(context:get(),driver) then return end
    busy=true
    local ok,err=pcall(function()
        local now=transport:now()
        local down=Game.valid(localController) and localController:IsInputKeyDown({KeyName=FName("F6")})
        local due,diagnostic,dt=pump:step(now,down)
        if due then tick(now,dt) end
        if diagnostic then diagnostics() end
    end)
    busy=false
    if not ok then
        failed=true
        Log.info("Integration stopped: "..tostring(err))
        if client then pcall(function()client:close()end);client=nil end
        if server then pcall(function()server:reset()end) end
        Game.showStatus(localController,"Prototype stopped after an error. See UE4SS.log.")
        -- Do not unregister the currently executing hook or retry every frame.
        -- EndPlay performs cleanup; a fresh world creates a fresh driver.
    end
end

local function initialize(actor)
    reset()
    local instance=UE.GetGameInstance()
    assert(Game.valid(instance),"Game instance unavailable")
    local installed=stringValue(instance.PlayerVersionString)
    assert(installed==Version.game,"Unsupported game version: "..installed.."; expected "..Version.game)
    assert(Game.read(actor,"PFHeartbeatSeen")~=nil,
        "Old ModActor assets: install all three cooked files from actor-tick prototype 2")
    world=actor:GetWorld()
    transport=Transport.new(world,config)
    driver=actor
    server=Server.new(config,Game,transport)
    pump=Pump.new(config.TickSeconds)
    local path="/Game/Mods/PissingFactor/BP_PFPlayer.BP_PFPlayer_C:"
    register(path.."ServerSetInput",rpc)
    register(path.."ServerUpdateAim",rpc)
    transport.inputClass.DynamicBindingObjects:ForEach(function(_,binding)
        local object=binding:get()
        if object:IsA("/Script/Engine.InputKeyDelegateBinding") then
            object.InputKeyDelegateBindings:ForEach(function(_,entry)
                local name=entry:get().FunctionNameToBind:ToString()
                register("/Game/Mods/PissingFactor/BP_PFInput.BP_PFInput_C:"..name,function(context)
                    if not failed and client and Game.same(client.capture,context:get()) then
                        local ok,err=pcall(function()client:update(false)end)
                        if not ok then
                            Log.once("input_error",err)
                            pcall(function()client:close()end);client=nil
                        end
                    end
                end)
            end)
        end
    end)
    register(driverPath..":ReceiveTick",heartbeat)
    Log.info("Actor-tick prototype 2 ready; no async update/F6 queues. Tap F6 for local status.")
end

-- BPModLoaderMod creates ModActor in each world. Both callbacks below already
-- execute on the game thread. Do not add ExecuteInGameThread/ExecuteWithDelay
-- chains here: overlapping queues triggered a loader registry failure in testing.
RegisterBeginPlayPostHook(function(context)
    local actor=context:get()
    if Game.valid(actor) and actor:GetClass():GetFullName()=="BlueprintGeneratedClass "..driverPath then
        local ok,err=pcall(function()initialize(actor)end)
        if not ok then Log.info("Driver initialization stopped: "..tostring(err)); reset() end
    end
end)
RegisterEndPlayPreHook(function(context)
    if Game.same(context:get(),driver) then reset() end
end)
Log.info("Waiting for BPModLoaderMod to spawn the actor-tick driver")
