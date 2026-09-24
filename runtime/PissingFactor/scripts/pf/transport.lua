-- Unreal RPC ownership is enforced by the engine; this adapter also checks the
-- pawn/controller association before delivering an input envelope to simulation.
local Game = require("pf.game")
local Version = require("pf.version")
local Log = require("pf.log")
local UE = require("UEHelpers")
local Collision = require("pf.collision")
local Transport = {}
Transport.__index = Transport
local root = "/Game/Mods/PissingFactor/"
local zero = {X=0,Y=0,Z=0}
local rotation = {Pitch=0,Yaw=0,Roll=0}

local function asset(name)
    -- Use the same reflected loader as AF's BPModLoaderMod. LoadAsset does
    -- not provide a dependable returned UClass in the pinned UE4SS build.
    local registry = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    assert(Game.valid(registry), "AssetRegistryHelpers unavailable")
    local object = registry:GetAsset({PackageName=FName(root .. name),AssetName=FName(name .. "_C")})
    assert(Game.valid(object), "Missing cooked " .. name .. "; install the matching PissingFactor.pak")
    return object
end

function Transport.new(world, config)
    return setmetatable({world=world,config=config,impacts={},states={},
        collision=Collision.new(world),
        playerClass=asset("BP_PFPlayer"),impactClass=asset("BP_PFImpact"),
        inputClass=asset("BP_PFInput")},Transport)
end

function Transport:now()
    return UE.GetGameplayStatics():GetRealTimeSeconds(self.world)
end

function Transport:worldTime()
    local state = UE.GetGameplayStatics():GetGameState(self.world)
    assert(Game.valid(state), "GameState unavailable")
    return state:GetServerWorldTimeSeconds()
end

function Transport:spawnPlayer(player)
    assert(player:HasAuthority(), "Only authority may create a player network actor")
    local controller=player:GetController()
    assert(Game.valid(controller), "Player has no controller")
    local actor=self.world:SpawnActor(self.playerClass,player:K2_GetActorLocation(),rotation)
    assert(Game.valid(actor), "Cannot spawn BP_PFPlayer")
    if Game.read(actor,"PFPresentationRevision")~=4 then
        actor:K2_DestroyActor()
        error("Old network assets: install all three cooked files from prototype 4")
    end
    actor:SetOwner(controller)
    actor.PFPawn=player
    actor.PFVersion=Version.mod
    actor.PFProtocol=Version.protocol
    actor.PFRange=self.config.RangeCm
    actor:ForceNetUpdate()
    assert(self:ownedBy(actor,player), "RPC actor ownership was not established")
    return actor
end

function Transport:ownedBy(actor,player)
    return Game.valid(actor) and Game.valid(player)
        and Game.same(actor.PFPawn,player) and Game.same(actor:GetOwner(),player:GetController())
end

function Transport:destroy(actor)
    if actor then self.states[actor]=nil end
    if Game.valid(actor) then actor:K2_DestroyActor() end
end

function Transport:publishState(actor,session,path,now)
    local previous=self.states[actor]
    if not session.active and previous and not previous.active and previous.reason==session.reason then return end
    actor.PFActive=session.active
    actor.PFHasPath=path~=nil and path.duration>0.0001
    actor.PFReason=session.reason
    actor.PFAim=session.aim
    actor.PFServerTime=self:worldTime()
    if path then
        actor.PFDuration=path.duration
        actor.PFOrigin=path.points[1]
        actor.PFEndpoint=path.endpoint
        actor:K2_SetActorLocation(path.points[1],false,{},true)
    end
    actor:ForceNetUpdate()
    self.states[actor]={active=session.active,reason=session.reason}
end

function Transport:stop(actor,reason)
    Log.once("transport:" .. reason,reason)
    if Game.valid(actor) then
        actor.PFActive=false; actor.PFReason="compatibility_error"; actor:ForceNetUpdate()
    end
end

function Transport:trace(player,a,b,now)
    return self.collision:trace(player,a,b,now)
end

function Transport:publishImpact(record)
    local actor=self.world:SpawnActor(self.impactClass,record.position,rotation)
    if not Game.valid(actor) then return end
    actor.PFKind=record.kind
    actor.PFNormal=record.normal or {X=0,Y=0,Z=1}
    local age=self:now()-record.created
    local remaining=record.expires-self:now()
    actor.PFCreated=self:worldTime()-age
    actor.PFExpires=self:worldTime()+remaining
    actor.PFFade=record.fade
    actor.PFLocalPosition=record.localPosition or zero
    actor.PFLocalNormal=record.localNormal or record.normal or {X=0,Y=0,Z=1}
    actor.PFAttached=Game.valid(record.component)
    if Game.valid(record.component) then actor.PFSurface=record.component end
    actor:SetLifeSpan(math.max(0.01,remaining))
    actor:ForceNetUpdate()
    self.impacts[record.id]=actor
end

function Transport:pruneImpacts(records)
    local keep={}
    for _,r in ipairs(records) do keep[r.id]=true end
    for id,actor in pairs(self.impacts) do
        if not keep[id] then self:destroy(actor); self.impacts[id]=nil end
    end
end

function Transport:request(actor,sequence,held,aim,reliable)
    if reliable then
        actor:ServerSetInput(sequence,held,aim,Version.mod,Version.protocol)
    else
        actor:ServerUpdateAim(sequence,held,aim,Version.mod,Version.protocol)
    end
end

return Transport
