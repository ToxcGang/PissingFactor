-- Trace API/out-parameter layout follows the pinned AF-UE4SS LineTraceMod and
-- the local UE 5.4 reflection dump. Water exclusions remain conservative until
-- the actual surface bindings have been validated in-game.
local Game=require("pf.game")
local Bounds=require("pf.bounds")
local Log=require("pf.log")
local UE=require("UEHelpers")
local Collision={}
Collision.__index=Collision
local clear={R=0,G=0,B=0,A=0}
local function vector(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function unwrap(v) return v and v:Get() end

function Collision.new(world)
    return setmetatable({world=world,water={},refreshed=nil,failed=false},Collision)
end

function Collision:refresh(now)
    if self.failed then error("Environmental presentation disabled after a collision binding failure",0) end
    if self.refreshed and now>=self.refreshed and now-self.refreshed<1 then return end
    self.refreshed=now
    self.water={}
    for _,class in ipairs({"InteractableLiquidVolume_C","PhysicsVolume"}) do
        for _,actor in ipairs(FindAllOf(class) or {}) do
            if Game.valid(actor) and Game.same(actor:GetWorld(),self.world)
                and (class~="PhysicsVolume" or Game.read(actor,"bWaterVolume")==true) then
                local center,extent={},{}
                actor:GetActorBounds(false,center,extent,false)
                assert(type(center.X)=="number" and type(extent.X)=="number","Water exclusion bounds unavailable")
                self.water[#self.water+1]={center=vector(center),extent=vector(extent)}
            end
        end
    end
end

function Collision:segment(player,a,b)
    local nearest
    for _,box in ipairs(self.water) do
        local fraction=Bounds.entry(a,b,box.center,box.extent)
        if fraction and (not nearest or fraction<nearest) then nearest=fraction end
    end
    local hit={}
    local blocked=UE.GetKismetSystemLibrary():LineTraceSingle(player,a,b,0,true,{player},0,hit,true,clear,clear,0)
    if blocked then
        assert(type(hit.Time)=="number" and hit.ImpactPoint and hit.ImpactNormal,"Unsupported trace result")
        if nearest and nearest<=hit.Time then blocked=false end
    end
    if not blocked then
        if not nearest then return nil end
        Log.once("water_exclusion","Water region encountered: stream clipped, stains suppressed; water effects pending")
        return {kind="unverified_water",position={X=a.X+(b.X-a.X)*nearest,
            Y=a.Y+(b.Y-a.Y)*nearest,Z=a.Z+(b.Z-a.Z)*nearest}}
    end
    local position,normal=vector(hit.ImpactPoint),vector(hit.ImpactNormal)
    local component=unwrap(hit.Component)
    local actor=hit.HitObjectHandle and unwrap(hit.HitObjectHandle.ReferenceObject)
    local record={kind="solid",position=position,normal=normal}
    -- Clip against characters but do not put environmental decals on their rigs.
    if Game.valid(actor) and actor:IsA("/Script/Engine.Pawn") then record.kind="character";return record end
    if hit.bStartPenetrating then record.kind="overlap";return record end
    if Game.valid(component) then
        local transform=component:K2_GetComponentToWorld()
        local mathlib=UE.GetKismetMathLibrary()
        record.component=component
        record.localPosition=vector(mathlib:InverseTransformLocation(transform,position))
        record.localNormal=vector(mathlib:InverseTransformDirection(transform,normal))
    end
    return record
end

function Collision:trace(player,a,b,now)
    local ok,result=pcall(function()self:refresh(now);return self:segment(player,a,b)end)
    if not ok then self.failed=true;error(result,0) end
    return result
end
return Collision
