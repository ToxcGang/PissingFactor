-- Exercise the real bootstrap with fake engine objects. This checks scheduling
-- and lifecycle only; it cannot establish Unreal or multiplayer compatibility.
local logs,messages,hooks={},{},{}
local now,updates,cleans,closes,nextId=0,0,0,0,0
local world,controller,player,network,driver={},{},{},{},{}
local beginPlay,endPlay
local function valid(v) return type(v)=="table" and not v.invalid end
local function wrap(v) return {get=function()return v end} end
function controller:IsLocalController() return true end
function controller:IsA() return true end
function controller:IsInputKeyDown() return self.f6==true end
controller.Pawn=player
function player:GetWorld() return world end
function player:GetController() return controller end
function player:GetAddress() return 7 end
function player:HasAuthority() return true end
player.CurrentContinence,player.MaxContinence=75,75
function driver:GetWorld() return world end
function driver:GetClass()
    return {GetFullName=function()return "BlueprintGeneratedClass /Game/Mods/PissingFactor/ModActor.ModActor_C" end}
end
driver.PFHeartbeatSeen=false
network.PFReason="released"
local transport={inputClass={DynamicBindingObjects={ForEach=function()end}}}
function transport:now() return now end
function transport:spawnPlayer() return network end
function transport:ownedBy(a,p) return a==network and p==player end
package.loaded["pf.log"]={info=function(s)logs[#logs+1]=s end,once=function(_,s)logs[#logs+1]=s end}
package.loaded["UEHelpers"]={GetGameInstance=function()return {PlayerVersionString="1.4.0.28206"}end}
package.loaded["pf.game"]={playerClass="test_player",valid=valid,same=function(a,b)return a~=nil and a==b end,
    read=function(o,n)return o[n]end,inspect=function()return true end,
    localController=function()return controller end,
    showStatus=function(_,s)messages[#messages+1]=s;return true end}
package.loaded["pf.transport"]={new=function()return transport end}
package.loaded["pf.server"]={new=function()
    return {sessions={},add=function(self,id,p,a)
        self.sessions[id]={player=p,actor=a,simulation={ready=true,held=false,active=false,sequence=1,reason="released"}}
    end,remove=function(self,id)self.sessions[id]=nil end,
    tick=function()updates=updates+1 end,
    reset=function(self)self.sessions={};cleans=cleans+1 end}
end}
package.loaded["pf.client"]={new=function(_,p,c,a)
    return {player=p,actor=a,enabled=true,update=function()return true end,
        close=function()closes=closes+1 end}
end}
function FName(s)return s end
function FindAllOf(name)return name=="test_player" and {player} or {network} end
function RegisterHook(path,callback)nextId=nextId+1;hooks[path]=callback;return nextId,nextId end
function UnregisterHook(path)hooks[path]=nil end
function RegisterBeginPlayPostHook(callback)beginPlay=callback end
function RegisterEndPlayPreHook(callback)endPlay=callback end
function ExecuteInGameThread()error("Bootstrap must not enqueue game-thread actions")end
function ExecuteWithDelay()error("Bootstrap must not enqueue async actions")end
function RegisterKeyBind()error("Diagnostics must not allocate callbacks on the input thread")end
local originalDofile=dofile
function dofile(path)
    if path:match("config%.lua$") then return {EnablePrototype=true} end
    return originalDofile(path)
end
assert(loadfile("runtime/PissingFactor/scripts/main.lua"))()
assert(beginPlay and endPlay and next(hooks)==nil,"Must wait for BPModLoaderMod")
beginPlay(wrap(driver))
local path="/Game/Mods/PissingFactor/ModActor.ModActor_C:ReceiveTick"
assert(hooks[path],"Engine heartbeat hook missing")
for i=0,100 do now=i/100;hooks[path](wrap(driver)) end
assert(updates==11,"Expected 10 Hz simulation, including initial tick")
assert(#messages==1,"Input attachment message should appear once")
controller.f6=true
for i=101,200 do now=i/100;hooks[path](wrap(driver)) end
assert(#messages==2,"Holding F6 must not repeat diagnostics")
assert(messages[2]:find("No bathroom need yet",1,true),"Empty state must be explained")
controller.f6=false;now=2.01;hooks[path](wrap(driver))
controller.f6=true;now=2.02;hooks[path](wrap(driver))
assert(#messages==3,"A new press should work after cooldown")
local oldHeartbeat=hooks[path]
endPlay(wrap(driver))
assert(next(hooks)==nil and cleans==1 and closes==1,"EndPlay must release actors and hooks")
now=5;oldHeartbeat(wrap(driver))
assert(#messages==3,"Stale heartbeat must be ignored")
driver.PFHeartbeatSeen=nil
beginPlay(wrap(driver))
assert(next(hooks)==nil,"Old cooked assets must not start the runtime")
assert(logs[#logs]:find("Old ModActor assets",1,true),"Old assets need an actionable diagnostic")
print("Bootstrap checks passed: engine-only pump, 10 Hz, F6 edges, empty status, teardown, stale tick, old assets")
