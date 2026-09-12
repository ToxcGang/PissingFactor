local Input=require("pf.input")
local Game=require("pf.game")
local Version=require("pf.version")
local Log=require("pf.log")
local UE=require("UEHelpers")
local Client={}
Client.__index=Client
local function key(name) return {KeyName=FName(name)} end

function Client.new(transport,player,controller,actor)
    local capture=transport.world:SpawnActor(transport.inputClass,{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0})
    assert(Game.valid(capture),"Input actor spawn failed")
    if Game.read(capture,"PFInputRevision")~=3 then
        transport:destroy(capture)
        error("Old input assets: install all three cooked files from prototype 3 before enabling input")
    end
    capture:SetOwner(controller)
    return setmetatable({transport=transport,player=player,controller=controller,actor=actor,
        capture=capture,input=Input.new(),sequence=0,lastHeld=nil,enabled=false},Client)
end

function Client:send(held,reliable)
    local camera=self.controller.PlayerCameraManager
    if not Game.valid(camera) then held=false end
    local aim={X=1,Y=0,Z=0}
    if held then
        local vector=UE.GetKismetMathLibrary():GetForwardVector(camera:GetCameraRotation())
        aim={X=vector.X,Y=vector.Y,Z=vector.Z}
    end
    self.sequence=self.sequence+1
    self.transport:request(self.actor,self.sequence,held,aim,reliable)
    self.lastHeld=held
end

function Client:update()
    if not Game.valid(self.capture) or not Game.valid(self.actor) then return false end
    local version=self.actor.PFVersion:ToString()
    if version~=Version.mod or self.actor.PFProtocol~=Version.protocol then
        Log.once("client_version","Host uses a different PissingFactor version/protocol; input disabled")
        self:close(); return false
    end
    local enabled=Game.localEligible(self.player,self.controller)
    if enabled~=self.enabled then
        if enabled then self.capture:EnableInput(self.controller)
        else self.capture:DisableInput(self.controller) end
        self.enabled=enabled
    end
    -- Engine key state complements event state: focus-loss flushing can clear
    -- held keys without executing a Blueprint key-release event.
    local function held(field,name)
        return self.capture[field] and self.controller:IsInputKeyDown(key(name))
    end
    local keys={keyboard=held("PFKeyboard","P"),controller=held("PFLeft","Gamepad_DPad_Left")}
    local actions=self.input:update(keys,enabled)
    if actions.held~=self.lastHeld then self:send(actions.held,true)
    elseif actions.held then self:send(true,false) end
    return true
end

function Client:close()
    if Game.valid(self.actor) then pcall(function() self:send(false,true) end) end
    self.transport:destroy(self.capture)
end

return Client
