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

Install the entire prototype 4 package, including all three cooked containers.
Confirm startup says `prototype 4 (stream and stains)`. When continence is already
at maximum, no stream or fresh stain is expected. Look down toward a nearby wall
or floor in a dry room while holding P or D-pad Left with need available.

F6 records `Presentation enabled` and local visual counts. Report the first
`Presentation unavailable`, `Presentation disabled` or `Environmental effects
disabled` message. Cosmetic failures are isolated from bathroom relief.
Surfaces can have decal reception disabled by the game. Known liquid-volume
bounds suppress stains; water clouds/ripples are not implemented in this build.

## Shortcut drops items or changes hotbar slots

Stop testing the ability and report the input bindings and controller model.
The controller interception check is a release requirement. Use D-pad Left
alone. The mod must leave LB/L1 inventory cycling with the game. Confirm startup
logs say `prototype 4 (stream and stains)` and replace all three cooked files as well
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
