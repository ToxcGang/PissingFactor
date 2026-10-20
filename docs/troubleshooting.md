# Troubleshooting

## Earlier prototype freezes / F6 seems to do nothing

The first prototype's F6 wrote only to the log. A reported run showed one ready
authority session and `continence=75/75`, followed by a UE4SS EngineTick error
`[Lua::Registry::get_function_ref] Ref was not function` and removal of the hook.
This resembles the overlapping-action failure in
[UE4SS issue 1180](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180).
The exact cause of the game freeze has not been reproduced under a debugger.

Actor-tick prototype 2 removes PissingFactor's repeating async/game-thread queues
and its external-thread F6 callback. A cooked `ModActor:ReceiveTick` hook drives
the simulation; F6 is read on that same thread, limited to one snapshot per press.
It also attempts a local in-game status message. Idle input RPCs and redundant
idle actor updates are suppressed. This does not repair other mods or UE4SS itself.

The user subsequently reported prototype 2 freezing when pressing LB. Its last
F6 snapshot showed ready input and continence 63/75; the latest loader log has
no exception after that snapshot. Prototype 3 removes the LB interception and
native action replay, binds D-pad Left alone, and removes the Lua input-event
hooks. The subsequent manual test confirmed normal LB cycling without a freeze
and D-pad Left relief that stopped on release. This resolves the reported LB
symptom in that test; the root cause and longer-session stability remain unproven.

Install all files from the new prototype and follow the
[stability-first manual test](manual-prototype-test.md). Preserve the final
unfiltered log lines if it freezes: the loader error is outside the PissingFactor
prefix. Game and loader versions remain pinned while this mitigation is evaluated.

## Nothing happens

Confirm that both the Lua folder and cooked asset pack are installed. Source
downloads are not playable release packages. Look for `[PissingFactor]` in
`Binaries/Win64/ue4ss/UE4SS.log` and record the first compatibility failure.
Do not work around a failed compatibility check by guessing property names.

## No relief or remote effects

The server must run the same complete mod and protocol version as all clients.
Check server logs as well as the affected client's logs. A local visual alone
does not demonstrate successful authoritative relief.

## Relief works but the stream or stains are missing

In prototype 4d, `EnableEffects = false` intentionally runs relief-only mode.
F6 reports `Effects off`; missing visuals are expected. Keep that setting for
the first stability test after the 4b freeze. The separate effects test requires
closing the game, enabling the switch, and restarting.

Prototype 4's reported startup error was `attempt to call a TrivialObject value
(method 'IsDedicatedServer')`. It called a function on the wrong helper library;
this disabled all presentation before any cosmetic assets were loaded. Prototype
4a corrects the call to `KismetSystemLibrary`, verified against the pinned game's
reflection dump. This was a mod defect, not an effect-setting or input problem.

The 2026-10-19 prototype 4a run initialized presentation but reported `Stream
actor spawn failed` on first use. The engine log did not establish the cause.
Prototype 4b uses reflected deferred spawning at the stream origin with explicit
collision/scale settings, initializes the curve before finishing construction,
and revalidates class/material references before allocation. It reports the
class, failing phase and begin-spawn location if creation is still rejected.
The subsequent owner-run 4b test froze on first use. The final mod log line is
the first relief update, without a completed spawn or caught Lua exception; it
does not identify the exact native hang. 4c removes both Lua deferred-spawn calls.
The player Blueprint's own tick creates/releases streams and EndPlay cleans them
up; Lua only writes request/class fields and consumes the resulting reference.
The generated graph passes a headless Unreal lifecycle test, which does not
prove stability inside the game/UE4SS combination. The 4c relief-only test passed,
but its effects-enabled run froze after `arc trace complete` and `state publish
complete`, before `Stream creation requested`. There was no Lua error. This
narrows the boundary to subsequent presentation setup, without proving a native
cause. Prototype 4d removes all cosmetic asset loading/caching and UClass writes
from Lua; Blueprint resolves soft paths and holds strong references on its own
tick. Fresh-process authoring checks validate native loading, spawn and GC
retention. In-game stability still requires the owner's retest.

Install the entire prototype 4d package, including all three cooked containers.
Confirm startup says `prototype 4d (Blueprint asset ownership)`. When continence is already
at maximum, no stream or fresh stain is expected. Look down toward a nearby wall
or floor in a dry room while holding P or D-pad Left with need available.

F6 shows `Effects ready` and counts locally, or `Effects unavailable` with a short
reason. It records `Presentation enabled`, local visual counts and the full stored
`Presentation error` in the log on every press. Report that error or the first
`Presentation unavailable`, `Presentation disabled` or `Environmental effects
disabled` message. Cosmetic failures are isolated from bathroom relief.
Surfaces can have decal reception disabled by the game. Known liquid-volume
bounds suppress stains; water clouds/ripples are not implemented in this build.
For a new spawn failure, also copy nearby `LogSpawn` messages from
`%LOCALAPPDATA%/AbioticFactor/Saved/Logs/AbioticFactor.log`. A successful first
stream logs `First local stream actor created`; F6 while held records its count.

## Shortcut drops items or changes hotbar slots

Stop testing the ability and report the input bindings and controller model.
The controller interception check is a release requirement. Use D-pad Left
alone. The mod must leave LB/L1 inventory cycling with the game. Confirm startup
logs say `prototype 4d (Blueprint asset ownership)` and replace all three cooked files as well
as Lua when updating. When using Steam Input, check whether the controller is
being translated into keyboard presses and avoid mapping the same button twice.

## Game update or loader instability

Compare exact versions with `dependencies.lock.json`. Disable PissingFactor,
restart, and check whether the issue persists with UE4SS alone. Report the
smallest reproducible combination of mods and the relevant log excerpt.

## Logs and probes

`tools/probe.lua` is for development only and should not be installed with a
normal player release. It writes potentially large reflection dumps locally.
Do not upload complete game dumps or saves to public issues. Remove the probe's
`enabled.txt` when finished, then restart the game.
