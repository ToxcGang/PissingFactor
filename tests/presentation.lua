-- Exercise the real presentation adapter with fake reflected engine objects.
-- GPU output, physical collision and multiplayer remain manual acceptance.
local world,players,impacts={},{},{}
local now,dedicated,loads,live,peak=0,false,0,0,0
local badMaterial=false
local materialLoadFailure=false
local spawnFailure
local requests=0
local spawned={}
local nativeClasses={}
local function valid(o)return type(o)=="table" and not o.destroyed end
local function source(id)
    return setmetatable({GetWorld=function()return world end,GetAddress=function()return id end,
        K2_GetActorLocation=function()return {X=10,Y=20,Z=0}end},
        {__index=function(o,key)if key=="PFStreamClass" then return nativeClasses[o] end end,
         __newindex=function(o,key,value)
             assert(key~="PFStreamClass","Lua must never write a cosmetic UClass property")
             rawset(o,key,value)
         end})
end
local function near(a,b)assert(math.abs(a-b)<0.000001,tostring(a).." ~= "..tostring(b))end
function world:SpawnActor()error("Lua must never spawn a cosmetic stream actor")end
local function streamActor()
    local o={K2_DestroyActor=function(self)self.destroyed=true end,
        SetActorHiddenInGame=function(self,hidden)self.hidden=hidden;self.bHidden=hidden end,hidden=true}
    o.PFStreamMesh={GetStartPosition=function()return {X=0,Y=0,Z=0}end,
        GetEndPosition=function()return {X=100,Y=0,Z=0}end,
        K2_GetComponentLocation=function()return {X=10,Y=20,Z=100}end,
        IsVisible=function()return true end}
    spawned[#spawned+1]=o
    return o
end
-- This models the asynchronous boundary only. The generated Blueprint's real
-- spawn/latch/release/EndPlay graph is executed separately by PFBuild.
local function engineTick()
    for _,actor in ipairs(players) do
        if actor.PFMaterialWanted then
            if not valid(actor.PFStainMaterial) and actor.PFMaterialStatus~=3 then
                loads=loads+1
                if materialLoadFailure then actor.PFMaterialStatus=3
                else actor.PFStainMaterial={};actor.PFMaterialStatus=2 end
            end
        else actor.PFStainMaterial=nil;actor.PFMaterialStatus=0 end
        if actor.PFStreamWanted then
            if not valid(actor.PFStreamVisual) and actor.PFStreamStatus~=3 then
                requests=requests+1
                if spawnFailure then actor.PFStreamStatus=3
                else
                    if not nativeClasses[actor] then nativeClasses[actor]={};loads=loads+1 end
                    actor.PFStreamVisual=streamActor();actor.PFStreamStatus=2
                end
            end
        else
            if valid(actor.PFStreamVisual) then actor.PFStreamVisual:K2_DestroyActor() end
            actor.PFStreamVisual=nil;actor.PFStreamStatus=0
        end
    end
end
local function decal(position,attached,life)
    live=live+1;peak=math.max(peak,live)
    local o={position=position,attached=attached,life=life}
    function o:K2_DestroyComponent(caller)
        assert(caller==self,"Only the mod-created component may be destroyed")
        if not self.destroyed then live=live-1;self.destroyed=true end
    end
    function o:SetFadeScreenSize()end
    function o:SetFadeOut(delay,duration,destroyOwner)
        assert(destroyOwner==false,"Never destroy a prop when its stain fades")
        self.delay,self.duration=delay,duration
    end
    function o:CreateDynamicMaterialInstance()
        if badMaterial then return nil end
        return {SetScalarParameterValue=function(_,name,value)
            assert(name=="Opacity");self.opacity=value
        end}
    end
    return o
end
-- Keep the helper libraries separate, as reflected in UE 5.4.4. The old mock
-- incorrectly put IsDedicatedServer on GameplayStatics and hid a startup failure.
local system={IsDedicatedServer=function(_,context)
    assert(context==world,"The dedicated-server check needs the presentation world")
    return dedicated
end}
local statics={GetGameState=function()return {GetServerWorldTimeSeconds=function()return now end}end,
    BeginDeferredActorSpawnFromClass=function()error("Deferred spawn must not run inside Lua")end,
    FinishSpawningActor=function()error("Finish spawning must not run inside Lua")end,
    SpawnDecalAttached=function(_,_,_,surface,_,position,_,mode,life)
        assert(mode==0);return decal(position,surface,life)
    end,
    SpawnDecalAtLocation=function(_,_,_,_,position,_,life)return decal(position,nil,life)end}
setmetatable(statics,{__index=function()return {}end}) -- Non-callable missing UE member.
package.loaded["pf.game"]={valid=valid,same=function(a,b)return valid(a) and a==b end}
package.loaded["pf.log"]={info=function()end,once=function()end}
package.loaded["UEHelpers"]={GetGameplayStatics=function()return statics end,
    GetKismetSystemLibrary=function()return system end,
    GetKismetMathLibrary=function()return {MakeRotFromX=function(_,v)return v end}end}
function FName(s)return s end
function StaticFindObject()error("Lua presentation must not load or look up cosmetic assets")end
function LoadAsset()error("Lua presentation must not load cosmetic assets")end
function FindAllOf(name)return name=="BP_PFPlayer_C" and players or impacts end
local Presentation=require("pf.presentation")
dedicated=true
assert(Presentation.new(world)==nil and loads==0,"Dedicated server must not load visual assets")
dedicated=false
local p=Presentation.new(world,true)
assert(p and loads==0 and p.streamClass==nil and p.stainMaterial==nil,
    "Presentation must never keep a Lua cache of cosmetic asset wrappers")
local player=source(1)
player.PFPresentationRevision,player.PFProtocol,player.PFVersion=6,1,"1.0.0"
player.PFActive,player.PFHasPath,player.PFServerTime=true,true,0
player.PFOrigin,player.PFEndpoint={X=0,Y=0,Z=100},{X=100,Y=0,Z=80}
player.PFAim,player.PFDuration={X=1,Y=0,Z=0},0.2
players={player};p:update(0)
assert(#spawned==0 and player.PFStreamWanted and player.PFMaterialWanted and not player.PFStreamClass,
    "Lua must only publish plain requests; Blueprint resolves asset references")
now=0.05;p:update(now);assert(#spawned==0 and requests==0)
engineTick();p:update(now)
local stream=p.streams["1"].visual
assert(not stream.hidden and stream.PFDisplayStart.Z==100)
assert(p.created==1 and p.lastStream.length==100 and p.lastStream.visible and not p.lastStream.hidden)
assert(requests==1,"Repeated Lua updates must not duplicate a pending request")
assert(loads==2 and player.PFStreamClass and player.PFStainMaterial,"Only the engine tick may load cosmetic assets")
near(stream.PFTargetTangentA.X,110)
player.PFDuration=0.1;player.PFEndpoint={X=50,Y=0,Z=90}
now=0.1;p:update(now)
assert(stream.PFDisplayEnd.X==50,"Closer obstruction must snap the endpoint")
player.PFAim={X=0,Y=0,Z=-1};p:update(now)
assert(stream.PFUp.Y==1,"Vertical aiming needs a nonparallel spline up vector")
player.PFOrigin={X=5000,Y=0,Z=100};p:update(now)
assert(stream.PFDisplayStart.X==5000,"Teleport must not interpolate across the world")
player.PFActive=false;now=0.2;p:update(now)
assert(not player.PFStreamWanted and not stream.destroyed,"Lua must request release without destroying actors")
engineTick()
assert(stream.destroyed and next(p.streams)==nil,"Release must remove the stream")
assert(p.lastStream.length==100 and p.lastStream.position.Z==100,
    "F6 must retain plain geometry diagnostics after the short-lived actor is gone")
stream=nil
player.PFActive=true;player.PFServerTime=-5
p:update(now);assert(next(p.streams)==nil,"Stale network state cannot leave an abandoned stream")
player.PFServerTime=now;player.PFHasPath=false
p:update(now);assert(next(p.streams)==nil,"Failed collision must not draw through walls")

-- Class ownership remains entirely with Blueprint across idle/restart cycles.
local oldClass,oldLoads=player.PFStreamClass,loads
player.PFHasPath=true
p:update(now)
assert(player.PFStreamClass==oldClass and loads==oldLoads,"Lua must not validate/reload a cached class")
engineTick();p:update(now)
local observed=p.lastStream
p.streams["1"].visual.PFStreamMesh=nil
p:update(now)
assert(p.lastStream==observed and p.lastStreamError,
    "Optional diagnostic failures must not disable presentation or replace the last good sample")
player.PFActive=false;p:update(now)
engineTick()
assert(spawned[#spawned].destroyed)
local priorRequests=requests
local ok,err
spawnFailure=true;player.PFActive=true
p:update(now);engineTick()
priorRequests=requests;engineTick();assert(requests==priorRequests,"Rejected requests must not retry every frame")
ok,err=pcall(function()p:update(now)end)
assert(not ok and tostring(err):find("Blueprint stream spawn rejected",1,true))
p:reset();engineTick();spawnFailure=nil
p:update(now) -- Queue but deliberately do not advance the engine tick.
now=now+2.1;player.PFServerTime=now
ok,err=pcall(function()p:update(now)end)
assert(not ok and tostring(err):find("request timed out",1,true))
p:reset();engineTick()
-- A release before the engine tick must cancel a pending allocation entirely.
player.PFServerTime=now;p:update(now);priorRequests=requests
player.PFActive=false;p:update(now);engineTick();assert(requests==priorRequests)

local function impact(id)
    local a=source(id)
    a.PFKind,a.PFExpires,a.PFFade="solid",60,10
    a.PFAttached=false;a.PFNormal={X=0,Y=0,Z=1}
    return a
end
local stain=impact(10)
player.PFStainMaterial=nil;oldLoads=loads
impacts={stain};now=55;p:update(now)
assert(live==0,"Wait for Blueprint material loading before allocating a decal")
engineTick();p:update(now)
assert(loads==oldLoads+1,"Only Blueprint may resolve the stain material")
local visual=p.stains["10"].visual
near(visual.opacity,0.35);near(visual.delay,0);near(visual.duration,5);near(visual.life,5)
assert(live==1,"Late-join fading must allocate one stain only")
now=55.1;p:update(now);assert(live==1 and p.stains["10"].visual==visual)
local surface={}
stain.PFAttached=true;stain.PFSurface=surface
stain.PFLocalPosition={X=1,Y=2,Z=3};stain.PFLocalNormal={X=1,Y=0,Z=0}
now=55.2;p:update(now)
assert(visual.destroyed and live==1)
visual=p.stains["10"].visual
assert(visual.attached==surface and visual.position.X==1,"Resolved prop attachment must replace world-space decal")
surface.destroyed=true;now=55.3;p:update(now)
assert(live==0,"Destroyed props must not leave a floating stain")
stain.PFAttached=false;now=60;p:update(now)
assert(live==0 and next(p.stains)==nil,"Expired records must not respawn")

impacts={}
for i=1,300 do local a=impact(100+i);a.PFExpires=100;impacts[#impacts+1]=a end
now=61;p:update(now);assert(live==256)
impacts={}
for i=1,300 do local a=impact(1000+i);a.PFExpires=100;impacts[#impacts+1]=a end
now=62;p:update(now)
assert(live==256 and peak==256,"Eviction must free decals before replacement allocations")
p:reset();assert(live==0 and next(p.stains)==nil)
impacts={impact(3000)};now=55;badMaterial=true
assert(not pcall(function()p:update(now)end))
p:reset();assert(live==0,"Partial material initialization must not leak a decal")
engineTick();badMaterial=false;materialLoadFailure=true
p:update(now);engineTick()
oldLoads=loads;engineTick();assert(loads==oldLoads,"Failed material loads must not retry each frame")
ok,err=pcall(function()p:update(now)end)
assert(not ok and tostring(err):find("Blueprint stain material load rejected",1,true))
p:reset();engineTick()
print("Presentation checks passed: no Lua cosmetic loading/UClass writes/spawning, native asset requests, cancellation, failure latch/timeout, stream stop/clipping, fade, attachment, expiry, cap")
