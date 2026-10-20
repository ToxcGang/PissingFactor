-- Core classes must come from the live driver's engine-owned references.
-- Native GC retention is exercised in PFBuild, not simulated by this test.
local function valid(o)return type(o)=="table" and not o.destroyed end
package.loaded["pf.game"]={valid=valid,read=function(o,k)return o[k]end}
package.loaded["UEHelpers"]={}
function StaticFindObject()error("Transport must not dynamically load unowned actor classes")end
function LoadAsset()error("Transport must not dynamically load unowned actor classes")end
local function class()return {IsClass=function()return true end}end
local driver={PFPlayerClass=class(),PFImpactClass=class(),PFInputClass=class()}
local Transport=require("pf.transport")
local t=Transport.new({}, {}, driver)
assert(t.driver==driver and t.playerClass==driver.PFPlayerClass
    and t.inputClass==driver.PFInputClass and t.impactClass==driver.PFImpactClass)
local ok,err=pcall(Transport.new,{}, {},nil)
assert(not ok and tostring(err):find("class owner is unavailable",1,true))
driver.PFImpactClass=nil
ok,err=pcall(Transport.new,{}, {},driver)
assert(not ok and tostring(err):find("Missing engine-owned PFImpactClass",1,true))
driver.PFImpactClass={IsClass=function()return false end}
ok,err=pcall(Transport.new,{}, {},driver)
assert(not ok and tostring(err):find("Missing engine-owned PFImpactClass",1,true))
print("Transport checks passed: engine-owned core classes, no dynamic asset loads, missing owner/class rejection")
