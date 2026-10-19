# Architecture

The portable Lua core owns gameplay decisions. A game compatibility adapter
reads player state and calls the verified continence update function. Unreal
Blueprint assets provide networked actors and presentation resources. No chat
messages, item-use RPCs, or external network service carry mod traffic.

## Authority

The host creates one replicated PissingFactor actor per player, owned by that
player's controller. Its server RPC accepts the owning player's version,
protocol, monotonic input sequence, held state, and aim vector. Receipt time is
measured by the server. The server never accepts client-supplied relief, hit
positions, affected player identity, or effect expiration times.

Reliable start/stop transitions and bounded aim updates feed `pf.session`.
The session rejects incompatible versions, stale sequences, non-finite input,
and invalid player states. A one-second timeout cancels input. Emptying or any
interruption latches the action until a release; it cannot restart when the
continence meter subsequently decays while the button is still held.

Simulation runs at 10 Hz, caps each relief step at 0.1 seconds, and checks
eligibility every step. The game continues to own its normal needs system.
Respawns and world transitions discard old sessions.

## Collision and presentation

The server traces successive segments of a gravity-driven arc from the
character's waist. The first water or solid hit wins. Solid impacts attach
decals in the hit component's local coordinates where possible. Water produces
short-lived clouds and ripples instead of stains on the floor beneath it.

Prototype 4 implements solid tracing and stream/stain presentation. Until exact
water surfaces are verified, bounds from known liquid interaction actors and
water physics volumes act as conservative exclusions: they clip streams and
prevent stamps rather than rendering water effects. This does not prove that
every game water surface is covered.

Clients deform an original tube mesh using spline tangents derived from the
replicated aim, duration and clipped endpoint. A local Blueprint interpolates
presentation each frame; simulation remains at 10 Hz. Shorter obstruction hits
and large origin jumps snap to the new path. Decals use replicated component-local
positions/normals and remaining server time; their material multiplies opacity
by Unreal's decal lifetime fade. Late-discovered decals start at their remaining
opacity. Rendering asset loads and cosmetic actors are skipped on dedicated
servers. Cosmetic binding failures are isolated from continence updates.

Prototype 4b attempted stream creation through the reflected `BeginDeferredActorSpawnFromClass`
and `FinishSpawningActor` signatures verified in the pinned game dump. It supplied
the stream-origin transform, AlwaysSpawn collision handling and unit scale, and
set curve state before finishing construction and registered partial actors for
cleanup. Class types are checked on load; cached stream classes and
stain materials are revalidated before use so an idle Lua wrapper is not treated
as an Unreal lifetime guarantee. The pinned loader's native
[UWorld spawn wrapper](https://github.com/UE4SS-RE/RE-UE4SS/blob/c838a8ac/UE4SS/src/LuaType/LuaUWorld.cpp)
does not expose collision handling or deferred initialization. The actual cause
of the reported 4a rejection remains unproven pending in-game evidence.

That 4b implementation was withdrawn after a first-use freeze. In prototype 4c,
Lua publishes `PFStreamClass` and `PFStreamWanted` on the player network actor;
these local fields are transient and not replicated. Its separate, unhooked
Blueprint tick creates a local stream, retaining `PFStreamVisual` and status.
Class/actor references are owned by Unreal. Lua observes the result on a later
10 Hz update and supplies the curve; it never allocates or destroys a stream
inside the driver hook. Release clears the request, the Blueprint destroys the
stream, and its EndPlay also handles owner/world teardown. Failed spawns latch
until release; a pending request times out after two seconds. Dedicated servers
skip this graph and receive no cosmetic class assignment.

`EnableEffects = false` gates environmental tracing/publishing on the host and
all presentation initialization locally. It is the default for the prototype's
relief-only baseline. Debug checkpoints identify the first trace/publish stages
and the request/completion boundary when effects are explicitly enabled.

Replicated action/impact state carries server time and expiration, so late
joiners see only the remaining lifetime. Each client creates cosmetic visuals
locally; the dedicated server performs no rendering or audio work. Limit
new impact stamps to five per player per second and retain at most 256 records
per world, evicting the oldest first. Effects never enter game saves.

## Input

Hold P or D-pad Left alone. The input Blueprint consumes just those two keys in
gameplay and stores their pressed/released state. Lua reads that state together
with the engine's current key state on the 10 Hz actor tick, so focus flushing
can stop a stale Blueprint hold. No Lua hooks run inside the input events.

LB/L1, D-pad Down, F8 and the controller menu button are not captured. No native
inventory, drop or menu action is deferred or replayed. Opening a menu disables
capture and cancels the hold; an interruption requires release before restarting.
Menus retain native navigation. Input asset revision 3 is checked before input
is enabled, preventing an older cooked Blueprint from consuming the old chord.

## Compatibility boundary

`tools/probe.lua` is an opt-in diagnostic mod. It generates local reflection
metadata without changing player stats. Reflection presence proves a binding
exists; it does not prove its gameplay semantics or replication. Those require
the acceptance tests in `validation.md`.
