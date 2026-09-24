# Validation and release gates

Do not publish v1.0.0 until every required scenario below passes on the pinned
game and UE4SS builds. Record evidence per build in `validation/results.json`.
Missing checks are **unverified**, not passed.

The owner requested multiplayer testing last on 2026-09-23. Follow the
[development order](development-plan.md): remaining feature implementation and
single-player checks precede hosted/dedicated, late-join and network-fault tests.
This changes scheduling only; all release gates below remain required.

## Evidence collected

- Game log identifies Abiotic Factor 1.4.0.28206 and Unreal Engine 5.4.4.
- UE4SS 1.22.0 bundle checksum matches the upstream GitHub release digest.
- The game loaded UE4SS and the PissingFactor diagnostic mod successfully.
- A local reflection dump confirms continence fields, `ModifyStat_Continence`,
  `OnRep_CurrentContinence`, player/controller types, FPArms, and interruption
  state fields. Runtime semantics remain to be tested in a disposable world.
- Portable Lua tests pass; see CI and `python tools/test.py` for the current count.
- The read-only rig probe exported 45 first-person bones and 27 bones from the
  modular body/head mesh. The body uses `hips`; game reference transforms stay local.
- `IsAnyMenuOpen` successfully updates the Lua out-parameter table in the main menu.
- Unreal Editor 5.4.4 (CL 35576357) compiled the editor plugin with MSVC 14.38.33145
  and generated the first editable actors/materials.
- On 2026-09-11, the eight original assets cooked successfully. UnrealPak's IoStore
  inventory contains only those assets and a container header. The game mounted
  all three containers, spawned `ModActor`, loaded the prototype classes and
  registered both RPC hooks and all ten input-event hooks in the main menu.
  This proves loading only; it does not establish possessed-player or remote-client behavior.
- A user-run single-player session on 2026-09-11 established one possessed-player
  input actor and an idle authority handshake (`ready=true`, continence 75/75).
  F6 snapshots succeeded. The user reported a freeze before testing relief; the
  full loader log ended with an EngineTick `Ref was not function` error. This is
  a **failed stability test**, not a passed single-player acceptance gate.
- Actor-tick prototype 2 replaces the overlapping update/diagnostic queues.
  Its authoring commandlet compiles with zero errors/warnings, and offline
  bootstrap checks cover throttling, diagnostic edges, cleanup and old-asset
  rejection. A subsequent user-run session reached ready input and an idle
  authority session at continence 63/75 (F6, 2026-09-11 21:54:44 local). The user
  reported another freeze and identified pressing LB as the trigger. No error
  follows that snapshot in the available loader log. Prototype 2 therefore
  **failed stability**; relief and visible status are still unverified.
- Prototype 3 removes LB interception, native input-action replay and Lua hooks
  on input events. It consumes only P and D-pad Left, checked in the compiled
  Blueprint; input state is read at 10 Hz. Offline regression checks cover the
  real Lua client with mocked engine objects, including hold/release, interruption,
  stale key state and rejection of old input assets. No automated desktop/game
  testing is used.
- On 2026-09-11, the user confirmed that prototype 3 restored ordinary LB cycling
  without freezing, D-pad Left relieved bathroom need, and releasing it stopped
  the action. The local authority log records 13 relief steps from 63 to 75 at
  22:27:42-22:27:43; the 22:28:00 snapshot shows `held=false`, `active=false`,
  `reason=released` and continence 75/75. The world hooks were subsequently
  removed on return to the main menu. The 17 installed runtime/container files
  match the tested archive, excluding local configuration. Exact source commit,
  hashes, dependencies and the user's report are in the
  [prototype 3 observation record](https://github.com/ToxcGang/PissingFactor/blob/main/validation/prototype-3-2026-09-11.json).
  These individual checks passed; the broader release gates remain pending,
  including interruptions, keyboard behavior, long sessions and multiplayer.

## Required gameplay scenarios

Prototype 4 adds the original spline stream and solid-surface stains. Offline
tests cover collision ordering, conservative water exclusion, arc duration,
presentation expiry/fade, moving-surface references, allocation caps and cleanup.
Unreal generation checks the Blueprint graphs and original mesh. These checks
are not evidence of in-game visual quality or correct physical surfaces; the
owner's prototype 4 manual run is still pending. Prototype 3's recorded success
does not transfer automatically to the new build.

| ID | Scenario | Acceptance |
| --- | --- | --- |
| singleplayer | Hold P, partial relief, release, empty | Existing meter updates correctly; no relief while stopped; fresh press required |
| emergency | Start during bathroom emergency | Existing emergency behavior resolves correctly without toilet rewards |
| controller | P/D-pad Left hold, rebound keys, ordinary LB cycling, device disconnect | No unwanted drops/hotbar changes; UI fully navigable; release stops |
| interruptions | Attack, sprint, interaction, menus, focus loss, death, respawn | Action and sounds stop; equipment and animations restore; no automatic restart |
| surfaces | Floors, walls, moving doors/props, thin obstructions | First-hit collision and correctly attached fading stains |
| water | Shoreline, shallow/deep water, aiming over water | Water cloud/ripples; no erroneous submerged-floor stain |
| animations | First/third person, clothing variants, movement | Correct hands/pose, no clipping or stuck pose |
| hosted_multiplayer | Host plus remote client, simultaneous use | Both observe matching action/effects; only server updates stats |
| dedicated_multiplayer | Windows dedicated server plus two clients | Same behavior, no render/audio initialization on server |
| late_join | Join during streams and existing stains | Correct active state and remaining lifetime |
| network_faults | Latency, dropped updates, disconnect, mismatch | Timely stop, no stale restart or wrong-player changes |
| lifecycle | Save/reload, map travel, reconnect, uninstall | No persistent effects, duplicate hooks, stale actors, or broken save |
| performance | Several simultaneous emitters, long session | Caps hold; actor/component counts return to baseline after expiry |
| clean_install | New installation from release ZIP | All dependencies/files detected; no missing resources |

The owner performs in-game and physical controller testing. Arrange a second
player/client at the final multiplayer stage; this is not a prerequisite for
current feature development. Editor simulations and mocked transport tests do
not replace those final checks.
