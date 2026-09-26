local Game=require("pf.game")
local Version=require("pf.version")
local Trajectory=require("pf.trajectory")
local UE=require("UEHelpers")
local Presentation={}
Presentation.__index=Presentation
local zero={X=0,Y=0,Z=0}
local rotation={Pitch=0,Yaw=0,Roll=0}
local function vector(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function stringValue(v) return type(v)=="string" and v or v:ToString() end
local function asset(name,class)
    local registry=StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    assert(Game.valid(registry),"AssetRegistryHelpers unavailable")
    local object=registry:GetAsset({PackageName=FName("/Game/Mods/PissingFactor/"..name),
        AssetName=FName(name..(class and "_C" or ""))})
    assert(Game.valid(object),"Missing presentation asset "..name.."; install all prototype 4 cooked files")
    return object
end
local function destroyActor(o) if Game.valid(o) then o:K2_DestroyActor() end end
local function destroyDecal(o) if Game.valid(o) then o:K2_DestroyComponent(o) end end

function Presentation.new(world)
    -- No cosmetic asset loads, actors, materials or discovery on a dedicated server.
    -- IsDedicatedServer belongs to KismetSystemLibrary in the pinned game dump.
    -- GameplayStatics returns a non-callable TrivialObject for this missing member.
    if UE.GetKismetSystemLibrary():IsDedicatedServer(world) then return nil end
    return setmetatable({world=world,streams={},stains={},players={},impacts={},
        streamClass=asset("BP_PFStream",true),stainMaterial=asset("M_Stain",false)},Presentation)
end

function Presentation:reset()
    for _,e in pairs(self.streams) do destroyActor(e.visual) end
    for _,e in pairs(self.stains) do destroyDecal(e.visual) end
    self.streams,self.stains,self.players,self.impacts={},{},{},{}
    self.discovered=nil
end

function Presentation:stream(actor,entry)
    local start,finish=vector(actor.PFOrigin),vector(actor.PFEndpoint)
    local duration=actor.PFDuration
    assert(type(duration)=="number" and duration>0 and duration<=2.56,"Invalid replicated arc duration")
    local tangentA,tangentB=Trajectory.tangents(vector(actor.PFAim),duration)
    if not entry or not Game.valid(entry.visual) then
        local visual=self.world:SpawnActor(self.streamClass,zero,rotation)
        assert(Game.valid(visual),"Stream actor spawn failed")
        entry={source=actor,visual=visual}
        self.streams[tostring(actor:GetAddress())]=entry
    end
    local visual=entry.visual
    visual.PFUp=math.abs(actor.PFAim.Z)>0.9 and {X=0,Y=1,Z=0} or {X=0,Y=0,Z=1}
    -- On first visibility or a newly closer obstruction, snap the curve instead
    -- of interpolating its previous endpoint through the blocking surface.
    local jumped=entry.origin and ((start.X-entry.origin.X)^2+(start.Y-entry.origin.Y)^2+
        (start.Z-entry.origin.Z)^2>10000)
    if not entry.duration or duration<entry.duration-0.001 or jumped then
        visual.PFDisplayStart=start;visual.PFDisplayEnd=finish
        visual.PFDisplayTangentA=tangentA;visual.PFDisplayTangentB=tangentB
    end
    visual.PFTargetStart=start;visual.PFTargetEnd=finish
    visual.PFTargetTangentA=tangentA;visual.PFTargetTangentB=tangentB
    visual:SetActorHiddenInGame(false)
    entry.duration=duration
    entry.origin=start
    return entry
end

function Presentation:stain(actor,remaining)
    local surface=actor.PFSurface
    -- Wait for a replicated component reference. Falling back to world-space
    -- prematurely would leave stains floating when a prop moves.
    if actor.PFAttached and not Game.valid(surface) then return nil end
    local attached=actor.PFAttached
    local normal=vector(attached and actor.PFLocalNormal or actor.PFNormal)
    local position=vector(attached and actor.PFLocalPosition or actor:K2_GetActorLocation())
    local rot=UE.GetKismetMathLibrary():MakeRotFromX(normal)
    local size={X=2,Y=10,Z=8}
    local visual
    if attached then
        visual=UE.GetGameplayStatics():SpawnDecalAttached(self.stainMaterial,size,surface,
            FName("None"),position,rot,0,remaining)
    else
        visual=UE.GetGameplayStatics():SpawnDecalAtLocation(self.world,self.stainMaterial,
            size,position,rot,remaining)
    end
    local entry={source=actor,visual=visual,surface=attached and surface or nil,attached=attached}
    self.stains[tostring(actor:GetAddress())]=entry
    if Game.valid(visual) then
        visual:SetFadeScreenSize(0.001)
        local fade=math.max(0,actor.PFFade)
        local opacity=fade>0 and math.min(1,remaining/fade) or 1
        local material=visual:CreateDynamicMaterialInstance()
        if not Game.valid(material) then destroyDecal(visual);error("Stain material instance unavailable") end
        material:SetScalarParameterValue(FName("Opacity"),0.7*opacity)
        if fade>0 then visual:SetFadeOut(math.max(0,remaining-fade),math.min(fade,remaining),false) end
    end
    -- Non-decal-receiving surfaces legitimately produce no component. Remember
    -- that attempt rather than allocating repeatedly until the record expires.
    return entry
end

function Presentation:update(now)
    local state=UE.GetGameplayStatics():GetGameState(self.world)
    if not Game.valid(state) then return end
    if not self.discovered or now<self.discovered or now-self.discovered>=0.2 then
        self.discovered=now
        self.players=FindAllOf("BP_PFPlayer_C") or {}
        self.impacts=FindAllOf("BP_PFImpact_C") or {}
    end
    local worldTime=state:GetServerWorldTimeSeconds()
    local streams={}
    for _,actor in ipairs(self.players) do
        if Game.valid(actor) and Game.same(actor:GetWorld(),self.world)
            and actor.PFPresentationRevision==4 and actor.PFProtocol==Version.protocol
            and stringValue(actor.PFVersion)==Version.mod and actor.PFActive and actor.PFHasPath
            and worldTime-actor.PFServerTime<=1.1 then
            local id=tostring(actor:GetAddress())
            -- Cache entries immediately so a later error can clean up allocations.
            self.streams[id]=self:stream(actor,self.streams[id])
            streams[id]=true
        end
    end
    for id,entry in pairs(self.streams) do
        if not streams[id] then destroyActor(entry.visual);self.streams[id]=nil end
    end
    local count,desired=0,{}
    for _,actor in ipairs(self.impacts) do
        if count<256 and Game.valid(actor) and Game.same(actor:GetWorld(),self.world)
            and stringValue(actor.PFKind)=="solid" and actor.PFExpires>worldTime then
            local id=tostring(actor:GetAddress())
            desired[id]=actor;count=count+1
        end
    end
    -- Free expired/evicted records before allocating replacements, so even
    -- transient local allocations stay within the world cap.
    for id,entry in pairs(self.stains) do
        local actor=desired[id]
        if not actor or entry.attached~=actor.PFAttached
            or (entry.attached and not Game.same(entry.surface,actor.PFSurface)) then
            destroyDecal(entry.visual);self.stains[id]=nil
        end
    end
    for id,actor in pairs(desired) do
        if not self.stains[id] then self:stain(actor,actor.PFExpires-worldTime) end
    end
end
return Presentation
