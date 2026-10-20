-- Core classes must come from the live driver's engine-owned references.
-- Native GC retention is exercised in PFBuild, not simulated by this test.
local function valid(o)return type(o)=="table" and not o.destroyed end
package.loaded["pf.game"]={valid=valid,read=function(o,k)return o[k]end}
local worldTime=100
package.loaded["UEHelpers"]={GetGameplayStatics=function()return {
    GetGameState=function()return {GetServerWorldTimeSeconds=function()return worldTime end}end
}end}
package.loaded["pf.log"]={once=function()end}
function StaticFindObject()error("Transport must not dynamically load unowned actor classes")end
function LoadAsset()error("Transport must not dynamically load unowned actor classes")end
local function class()return {IsClass=function()return true end}end
local driver={PFPlayerClass=class(),PFImpactClass=class(),PFInputClass=class()}
local Transport=require("pf.transport")
local t=Transport.new({}, {Debug=true}, driver)
assert(t.driver==driver and t.playerClass==driver.PFPlayerClass
    and t.inputClass==driver.PFInputClass and t.impactClass==driver.PFImpactClass)
local actor={GetAddress=function()return 1 end,
    K2_SetActorLocation=function()end,ForceNetUpdate=function()end,K2_DestroyActor=function()end}
local session={active=true,reason="active",aim={X=1,Y=0,Z=0}}
t:publishState(actor,session,{duration=0.2,points={{X=10,Y=20,Z=100}},
    endpoint={X=110,Y=20,Z=100},hit={kind="overlap"}},0)
local last=t.states[actor].lastPath
assert(last.kind=="overlap" and last.length==100 and last.duration==0.2)
session.active=false;session.reason="released"
t:publishState(actor,session,nil,0.1)
assert(t.states[actor].lastPath==last and actor.PFHasPath==false,
    "Keep plain last-path diagnostics after stopping while clearing replicated visuals")
t:publishState(actor,session,nil,0.2)
assert(t.states[actor].lastPath==last)
t:destroy(actor)
assert(not t.states[actor],"Removed players must discard diagnostic state")
local ok,err=pcall(Transport.new,{}, {},nil)
assert(not ok and tostring(err):find("class owner is unavailable",1,true))
driver.PFImpactClass=nil
ok,err=pcall(Transport.new,{}, {},driver)
assert(not ok and tostring(err):find("Missing engine-owned PFImpactClass",1,true))
driver.PFImpactClass={IsClass=function()return false end}
ok,err=pcall(Transport.new,{}, {},driver)
assert(not ok and tostring(err):find("Missing engine-owned PFImpactClass",1,true))
print("Transport checks passed: engine-owned core classes, no dynamic asset loads, missing owner/class rejection")
