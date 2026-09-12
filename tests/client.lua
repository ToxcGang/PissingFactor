-- Real client adapter with strict fake engine objects. These are regression
-- checks for input handling, not proof of controller or engine compatibility.
local requests,raw,eligible={},{},true
local function valid(o) return type(o)=="table" and not o.destroyed end
local capture={PFInputRevision=3,PFKeyboard=false,PFLeft=false}
function capture:SetOwner(owner) self.owner=owner end
function capture:EnableInput() self.enabled=true end
function capture:DisableInput() self.enabled=false end
local controller={PlayerCameraManager={GetCameraRotation=function()return {}end}}
function controller:IsInputKeyDown(key)
    assert(key.KeyName=="P" or key.KeyName=="Gamepad_DPad_Left","Unexpected key polling")
    return raw[key.KeyName]==true
end
-- Any attempt to replay a native hotbar/drop/menu action fails immediately.
local player=setmetatable({},{__index=function(_,key)error("Unexpected player call: "..key)end})
local actor={PFVersion={ToString=function()return "1.0.0"end},PFProtocol=1}
local transport={world={SpawnActor=function()return capture end},inputClass={}}
function transport:destroy(o) o.destroyed=true end
function transport:request(a,sequence,held,aim,reliable)
    assert(a==actor)
    assert(sequence==#requests+1)
    requests[#requests+1]={held=held,reliable=reliable,aim=aim}
end
package.loaded["pf.game"]={valid=valid,read=function(o,k)return o[k]end,
    localEligible=function()return eligible end}
package.loaded["pf.log"]={once=function()end}
package.loaded["UEHelpers"]={GetKismetMathLibrary=function()
    return {GetForwardVector=function()return {X=1,Y=0,Z=0}end}
end}
function FName(s)return s end
local Client=require("pf.client")
local client=Client.new(transport,player,controller,actor)
assert(not capture.enabled,"Capture must stay disabled until eligibility is checked")
assert(client:update() and capture.enabled)
assert(#requests==1 and not requests[1].held)
raw.Gamepad_LeftShoulder=true
client:update()
raw.Gamepad_LeftShoulder=false
client:update()
assert(#requests==1,"LB must not send input or replay actions")
capture.PFLeft,raw.Gamepad_DPad_Left=true,true
client:update()
assert(requests[2].held and requests[2].reliable,"D-pad Left alone starts reliably")
client:update()
assert(requests[3].held and not requests[3].reliable,"Held aim uses the tick heartbeat")
capture.PFLeft,raw.Gamepad_DPad_Left=false,false
client:update()
assert(not requests[4].held and requests[4].reliable,"Release stops reliably")
capture.PFKeyboard,raw.P=true,true
client:update()
assert(requests[5].held,"Keyboard P is preserved")
eligible=false
client:update()
assert(not capture.enabled and not requests[6].held,"Menu/interrupt disables capture and stops")
eligible=true
client:update()
assert(#requests==6,"Closing a menu with P held must not restart")
raw.P=false
client:update()
raw.P=true
client:update()
assert(requests[7].held,"A fresh press rearms after interruption")
raw.P=false -- focus loss/disconnect can flush engine state without a BP release
client:update()
assert(not requests[8].held,"Flushed engine key state must stop a stale BP hold")
capture.PFLeft=true
client:update()
assert(#requests==8,"A stale controller BP flag cannot start without physical input")
client:close()
assert(capture.destroyed,"Closing destroys the input capture")
for _,revision in ipairs({false,2}) do
    capture={PFInputRevision=revision or nil}
    local ok,err=pcall(Client.new,transport,player,controller,actor)
    assert(not ok and tostring(err):find("Old input assets",1,true))
    assert(capture.destroyed and not capture.enabled,"Old LB bindings must never become enabled")
end
local Preferences=require("pf.preferences")
local defaults=Preferences.validate({})
assert(defaults.Keyboard=="P" and defaults.Action=="Gamepad_DPad_Left" and defaults.Modifier==nil)
local duplicate,warnings=Preferences.validate({Action="P"})
assert(duplicate.Action=="Gamepad_DPad_Left" and #warnings>0)
print("Client checks passed: Left-only hold/release, untouched LB, keyboard, interruption, focus/disconnect, old assets, defaults")
