local Game=require("pf.game")
local Version=require("pf.version")
local Trajectory=require("pf.trajectory")
local Log=require("pf.log")
local UE=require("UEHelpers")
local Presentation={}
Presentation.__index=Presentation
local function vector(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function stringValue(v) return type(v)=="string" and v or v:ToString() end
local function releaseStream(entry)
    -- The unhooked player Blueprint tick/EndPlay owns allocation and destruction.
    if Game.valid(entry.source) then
        entry.source.PFStreamWanted=false
    end
end
local function destroyDecal(o) if Game.valid(o) then o:K2_DestroyComponent(o) end end

function Presentation.new(world,debug)
    -- No cosmetic asset loads, actors, materials or discovery on a dedicated server.
    -- IsDedicatedServer belongs to KismetSystemLibrary in the pinned game dump.
    -- GameplayStatics returns a non-callable TrivialObject for this missing member.
    if UE.GetKismetSystemLibrary():IsDedicatedServer(world) then return nil end
    return setmetatable({world=world,debug=debug==true,created=0,
        streams={},stains={},players={},impacts={}},Presentation)
end

function Presentation:observeStream(entry)
    if not self.debug or not Game.valid(entry.visual) then return end
    -- Read the live component only while its actor is owned by Blueprint.
    -- Store plain values so F6 can show the last result after it is destroyed.
    local ok,sample=pcall(function()
        local mesh=entry.visual.PFStreamMesh
        assert(Game.valid(mesh),"stream mesh component unavailable")
        local a,b=mesh:GetStartPosition(),mesh:GetEndPosition()
        local position=mesh:K2_GetComponentLocation()
        local hidden=entry.visual.bHidden
        if type(hidden)~="boolean" then hidden="unavailable" end
        return {visible=mesh:IsVisible(),hidden=hidden,
            length=math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2),
            position=vector(position)}
    end)
    if ok then self.lastStream=sample;self.lastStreamError=nil else self.lastStreamError=tostring(sample) end
end

function Presentation:reset()
    for _,e in pairs(self.streams) do releaseStream(e) end
    for _,e in pairs(self.stains) do destroyDecal(e.visual) end
    if Game.valid(self.materialSource) then self.materialSource.PFMaterialWanted=false end
    self.streams,self.stains,self.players,self.impacts={},{},{},{}
    self.discovered=nil
    self.materialSource=nil
end

function Presentation:stream(actor,entry,now)
    Log.once("stream_state:"..tostring(self),"Presentation checkpoint: stream state accepted")
    local start,finish=vector(actor.PFOrigin),vector(actor.PFEndpoint)
    local duration=actor.PFDuration
    assert(type(duration)=="number" and duration>0 and duration<=2.56,"Invalid replicated arc duration")
    local tangentA,tangentB=Trajectory.tangents(vector(actor.PFAim),duration)
    if not entry then
        assert(Game.valid(self.world),"Stream world is no longer valid")
        Log.once("stream_queue:"..tostring(self),"Presentation checkpoint: stream queue begin")
        -- Blueprint resolves its soft class path and owns the class reference.
        -- No cosmetic asset loading, cached UClass validation or UClass writes in Lua.
        actor.PFStreamStatus=0
        actor.PFStreamWanted=true
        entry={source=actor,requestedAt=now}
        self.streams[tostring(actor:GetAddress())]=entry
        Log.once("stream_requested:"..tostring(self),"Stream creation requested; waiting for Blueprint tick")
    end
    if entry.visual and not Game.valid(entry.visual) then entry.visual=nil;entry.requestedAt=now end
    if not Game.valid(entry.visual) then
        assert(actor.PFStreamStatus~=3,"Blueprint stream spawn rejected; see game LogSpawn")
        if not Game.valid(actor.PFStreamVisual) then
            assert(now-entry.requestedAt<=2,"Blueprint stream request timed out; status="..tostring(actor.PFStreamStatus))
            return entry
        end
        entry.visual=actor.PFStreamVisual
        self.created=self.created+1
        Log.once("stream_created:"..tostring(self),"First local stream actor created by Blueprint")
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
    self:observeStream(entry)
    entry.duration=duration
    entry.origin=start
    return entry
end

function Presentation:stain(actor,remaining)
    local surface=actor.PFSurface
    -- Wait for a replicated component reference. Falling back to world-space
    -- prematurely would leave stains floating when a prop moves.
    if actor.PFAttached and not Game.valid(surface) then return nil end
    local source=self.materialSource
    if not Game.valid(source) then return nil end
    assert(source.PFMaterialStatus~=3,"Blueprint stain material load rejected; install all prototype 4e cooked files")
    local stainMaterial=source.PFStainMaterial
    if not Game.valid(stainMaterial) then return nil end
    local attached=actor.PFAttached
    local normal=vector(attached and actor.PFLocalNormal or actor.PFNormal)
    local position=vector(attached and actor.PFLocalPosition or actor:K2_GetActorLocation())
    local rot=UE.GetKismetMathLibrary():MakeRotFromX(normal)
    local size={X=2,Y=10,Z=8}
    local visual
    if attached then
        visual=UE.GetGameplayStatics():SpawnDecalAttached(stainMaterial,size,surface,
            FName("None"),position,rot,0,remaining)
    else
        visual=UE.GetGameplayStatics():SpawnDecalAtLocation(self.world,stainMaterial,
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
    local streams,materialSource={}
    for _,actor in ipairs(self.players) do
        if Game.valid(actor) and Game.same(actor:GetWorld(),self.world)
            and actor.PFPresentationRevision==6 and actor.PFProtocol==Version.protocol
            and stringValue(actor.PFVersion)==Version.mod then
            if not materialSource then
                materialSource=actor
                actor.PFMaterialWanted=true
            end
            if actor.PFActive and actor.PFHasPath and worldTime-actor.PFServerTime<=1.1 then
                local id=tostring(actor:GetAddress())
                self.streams[id]=self:stream(actor,self.streams[id],now)
                streams[id]=true
            end
        end
    end
    if Game.valid(self.materialSource) and not Game.same(self.materialSource,materialSource) then
        self.materialSource.PFMaterialWanted=false
    end
    self.materialSource=materialSource
    if materialSource then
        assert(materialSource.PFMaterialStatus~=3,"Blueprint stain material load rejected; install all prototype 4e cooked files")
    end
    for id,entry in pairs(self.streams) do
        if not streams[id] then
            self:observeStream(entry)
            releaseStream(entry);self.streams[id]=nil
        end
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
