-- Exercise the real presentation adapter with fake reflected engine objects.
-- GPU output, physical collision and multiplayer remain manual acceptance.
local world,players,impacts={},{},{}
local now,dedicated,loads,live,peak=0,false,0,0,0
local badMaterial=false
local badClass=false
local spawnFailure
local begins,finishes=0,0
local spawned={}
local function valid(o)return type(o)=="table" and not o.destroyed end
local function source(id)
    return {GetWorld=function()return world end,GetAddress=function()return id end,
        K2_GetActorLocation=function()return {X=10,Y=20,Z=0}end}
end
local function near(a,b)assert(math.abs(a-b)<0.000001,tostring(a).." ~= "..tostring(b))end
function world:SpawnActor()error("Stream must use the explicit reflected deferred spawn API")end
local function streamActor()
    local o={K2_DestroyActor=function(self)self.destroyed=true end,
        SetActorHiddenInGame=function(self,hidden)self.hidden=hidden end,hidden=true}
    spawned[#spawned+1]=o
    return o
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
    BeginDeferredActorSpawnFromClass=function(_,context,class,transform,collision,owner,scale)
        begins=begins+1
        assert(context==world and valid(class) and class:IsClass())
        assert(collision==1 and owner==nil and scale==0,"Explicit AlwaysSpawn and unit root scale required")
        assert(transform.Translation.Z==100,"Spawn at the stream origin instead of world zero")
        if spawnFailure=="begin" then return nil end
        local o=streamActor();o.spawnTransform=transform;return o
    end,
    FinishSpawningActor=function(_,o,transform,scale)
        finishes=finishes+1
        assert(o.hidden and o.spawnTransform==transform and scale==0)
        assert(o.PFDisplayStart==transform.Translation and o.PFTargetStart==transform.Translation,
            "Set presentation state before construction/BeginPlay")
        assert(o.PFDisplayEnd and o.PFTargetEnd and o.PFDisplayTangentA and o.PFDisplayTangentB and o.PFUp)
        if spawnFailure=="finish" then return nil end
        if spawnFailure=="construction" then error("mock construction failure") end
        return o
    end,
    SpawnDecalAttached=function(_,_,_,surface,_,position,_,mode,life)
        assert(mode==0);return decal(position,surface,life)
    end,
    SpawnDecalAtLocation=function(_,_,_,_,position,_,life)return decal(position,nil,life)end}
setmetatable(statics,{__index=function()return {}end}) -- Non-callable missing UE member.
package.loaded["pf.game"]={valid=valid,same=function(a,b)return valid(a) and a==b end}
package.loaded["pf.log"]={info=function()end,once=function()end}
package.loaded["UEHelpers"]={GetGameplayStatics=function()return statics end,
    GetKismetSystemLibrary=function()return system end,
    GetKismetMathLibrary=function()return {MakeRotFromX=function(_,v)return v end,
        MakeTransform=function(_,position,rotation,scale)
            assert(rotation.Pitch==0 and rotation.Yaw==0 and rotation.Roll==0)
            assert(scale.X==1 and scale.Y==1 and scale.Z==1)
            return {Translation=position,Rotation={X=0,Y=0,Z=0,W=1},Scale3D=scale}
        end}end}
function FName(s)return s end
function StaticFindObject()return {GetAsset=function(_,data)
    loads=loads+1
    return {IsClass=function()return not badClass and data.AssetName=="BP_PFStream_C"end,
        GetFullName=function()return "BlueprintGeneratedClass "..data.PackageName.."."..data.AssetName end}
end}end
function FindAllOf(name)return name=="BP_PFPlayer_C" and players or impacts end
local Presentation=require("pf.presentation")
dedicated=true
assert(Presentation.new(world)==nil and loads==0,"Dedicated server must not load visual assets")
dedicated=false
local p=Presentation.new(world)
assert(p and loads==2,"Non-dedicated worlds must initialize both presentation assets")
local player=source(1)
player.PFPresentationRevision,player.PFProtocol,player.PFVersion=4,1,"1.0.0"
player.PFActive,player.PFHasPath,player.PFServerTime=true,true,0
player.PFOrigin,player.PFEndpoint={X=0,Y=0,Z=100},{X=100,Y=0,Z=80}
player.PFAim,player.PFDuration={X=1,Y=0,Z=0},0.2
players={player};p:update(0)
local stream=p.streams["1"].visual
assert(not stream.hidden and stream.PFDisplayStart.Z==100)
assert(begins==1 and finishes==1,"Each stream allocation must finish spawning exactly once")
near(stream.PFTargetTangentA.X,110)
player.PFDuration=0.1;player.PFEndpoint={X=50,Y=0,Z=90}
now=0.1;p:update(now)
assert(stream.PFDisplayEnd.X==50,"Closer obstruction must snap the endpoint")
player.PFAim={X=0,Y=0,Z=-1};p:update(now)
assert(stream.PFUp.Y==1,"Vertical aiming needs a nonparallel spline up vector")
player.PFOrigin={X=5000,Y=0,Z=100};p:update(now)
assert(stream.PFDisplayStart.X==5000,"Teleport must not interpolate across the world")
player.PFActive=false;now=0.2;p:update(now)
assert(stream.destroyed and next(p.streams)==nil,"Release must remove the stream")
player.PFActive=true;player.PFServerTime=-5
p:update(now);assert(next(p.streams)==nil,"Stale network state cannot leave an abandoned stream")
player.PFServerTime=now;player.PFHasPath=false
p:update(now);assert(next(p.streams)==nil,"Failed collision must not draw through walls")

-- Simulate Unreal collecting an idle class while Lua still holds its wrapper.
local oldClass,oldLoads=p.streamClass,loads
oldClass.destroyed=true;player.PFHasPath=true
p:update(now)
assert(p.streamClass~=oldClass and loads==oldLoads+1,"Reload a stale stream class immediately before use")
player.PFActive=false;p:update(now)
assert(spawned[#spawned].destroyed)
badClass=true
local priorBegins=begins
local ok,err=pcall(Presentation.new,world)
assert(not ok and tostring(err):find("not a class",1,true) and begins==priorBegins,
    "Do not pass a non-class asset to Unreal's spawn API")
badClass=false
for _,phase in ipairs({"begin","finish","construction"}) do
    spawnFailure=phase;player.PFActive=true
    local allocations=#spawned
    ok,err=pcall(function()p:update(now)end)
    assert(not ok,"A failed spawn must produce a presentation diagnostic")
    if phase~="construction" then
        assert(tostring(err):find("Stream spawn "..phase.." failed",1,true))
        assert(tostring(err):find("BP_PFStream_C",1,true),"Include the exact class in spawn diagnostics")
    end
    p:reset()
    if #spawned>allocations then assert(spawned[#spawned].destroyed,"Clean up a partial deferred spawn") end
end
spawnFailure=nil;player.PFActive=false

local function impact(id)
    local a=source(id)
    a.PFKind,a.PFExpires,a.PFFade="solid",60,10
    a.PFAttached=false;a.PFNormal={X=0,Y=0,Z=1}
    return a
end
local stain=impact(10)
p.stainMaterial.destroyed=true;oldLoads=loads
impacts={stain};now=55;p:update(now)
assert(loads==oldLoads+1,"Reload a stale stain material before creating a decal")
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
print("Presentation checks passed: server guard, deferred spawn/init/cleanup, class/material revalidation, stream stop/clipping, stale state, late fade, prop attachment, expiry, cap")
