# Validation and release gates

Do not publish v1.0.0 until every required scenario below passes on the pinned
game and UE4SS builds. Record evidence per build in `validation/results.json`.
Missing checks are **unverified**, not passed.

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
  rejection. Its in-game stability, local message display and relief remain
  pending the user's manual retest. No automated desktop/game testing is used.

## Required gameplay scenarios

| ID | Scenario | Acceptance |
| --- | --- | --- |
| singleplayer | Hold P, partial relief, release, empty | Existing meter updates correctly; no relief while stopped; fresh press required |
| emergency | Start during bathroom emergency | Existing emergency behavior resolves correctly without toilet rewards |
| controller | Keyboard/controller hold, rebound keys, chord, device disconnect | No unwanted drops/hotbar changes; UI fully navigable; release stops |
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

The owner can provide physical controller testing. A second player/client still
needs to be arranged for real co-op acceptance. Editor simulations and mocked
transport tests do not replace those checks.
