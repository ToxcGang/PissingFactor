local world,player={},{}
local traceCount,mode=0,"solid"
local time=0.1
local function valid(o)return type(o)=="table" and not o.destroyed end
local function weak(o)return {Get=function()return o end}end
local component={K2_GetComponentToWorld=function()return {offset=10}end}
local wall={IsA=function()return false end}
local water={GetWorld=function()return world end,GetActorBounds=function(_,_,center,extent)
    center.X,center.Y,center.Z=7,0,0;extent.X,extent.Y,extent.Z=1,1,1
end}
package.loaded["pf.game"]={valid=valid,same=function(a,b)return valid(a) and a==b end,
    read=function(o,k)return o[k]end}
package.loaded["pf.log"]={once=function()end}
package.loaded["UEHelpers"]={GetKismetSystemLibrary=function()return {
    LineTraceSingle=function(_,context,_,_,channel,complex,ignore,debug,hit,ignoreSelf)
        traceCount=traceCount+1
        assert(context==player and channel==0 and complex and debug==0 and ignoreSelf and ignore[1]==player)
        if mode=="error" then error("binding unavailable") end
        if mode=="miss" then return false end
        hit.Time=time;hit.ImpactPoint={X=time*10,Y=0,Z=0};hit.ImpactNormal={X=-1,Y=0,Z=0}
        hit.Component=weak(component);hit.HitObjectHandle={ReferenceObject=weak(wall)}
        return true
    end}end,
    GetKismetMathLibrary=function()return {
        InverseTransformLocation=function(_,t,v)return {X=v.X-t.offset,Y=v.Y,Z=v.Z}end,
        InverseTransformDirection=function(_,_,v)return v end}end}
function FindAllOf(name)return name=="InteractableLiquidVolume_C" and {water} or {}end
local Collision=require("pf.collision")
local c=Collision.new(world)
local a,b={X=0,Y=0,Z=0},{X=10,Y=0,Z=0}
local hit=c:trace(player,a,b,0)
assert(hit.kind=="solid" and hit.position.X==1 and hit.component==component and hit.localPosition.X==-9)
time=0.8;hit=c:trace(player,a,b,0.1)
assert(hit.kind=="unverified_water" and hit.position.X==6,"Water exclusion must beat a submerged solid hit")
mode="miss";hit=c:trace(player,a,b,0.2)
assert(hit.kind=="unverified_water" and hit.position.X==6)
assert(c:trace(player,{X=0,Y=5,Z=0},{X=10,Y=5,Z=0},0.3)==nil)
mode="error"
assert(not pcall(function()c:trace(player,a,b,0.4)end))
local count=traceCount
assert(not pcall(function()c:trace(player,a,b,0.5)end))
assert(traceCount==count,"Failed bindings must stay disabled without repeated engine calls")
print("Collision checks passed: trace exclusions, first obstruction, local attachment data, water guard, fail-closed binding")
