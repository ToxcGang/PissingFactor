# Multiplayer testing

Use a disposable world and matching source commit, cooked-pack SHA-256, mod
version, protocol, game version and UE4SS bundle on every machine. Install the
Lua mod and cooked pack on the host/dedicated server as well as each client.
Record exact builds in an acceptance file described in [building](building.md).

## Transport prototype first

The current opt-in prototype is intended to establish ownership and continence
integration before the complete visual package. It has no verified water
collision, animations, effect rendering or settings panel. Enable
`EnablePrototype = true` in each installed `config.lua` for this test only.
The source default remains false. A prototype build cannot be released as 1.0.0.

F6 writes a compact, read-only session snapshot to `UE4SS.log` while the prototype
is enabled. Set `Debug = true` to log each authoritative continence change.
Disable the separate `PissingFactorProbe` mod first to avoid sharing its F6 key.

1. Start a host and a remote client, then possess a normal living character on
   each. Confirm both logs report the prototype ready with the expected versions.
2. Allow the remote character's existing bathroom meter to fall below maximum.
   Hold P for one second. Release, then wait two seconds. Check that relief
   occurred only during the hold and only for that character.
3. Inspect the server's owned `BP_PFPlayer` actor. Its Owner must be that player's
   controller and PFPawn must be the currently possessed character. Inspect
   ServerSetInput receipt on authority, not just a locally changed held variable.
4. Repeat from the host, then simultaneously. Verify rate is maximum/8 per second
   before the game's own natural decay, capped at maximum. Test full relief and
   holding after empty; a fresh release must be required to restart.
5. Disconnect the active remote client and repeat across death/respawn. Check
   that its old actor is destroyed and old input cannot affect a new pawn.
6. Repeat with Windows dedicated server plus **two separate clients**. A local
   host-only run and mocked transport tests do not satisfy this requirement.

Capture short, redacted UE4SS log excerpts, a meter recording and observed
server ownership. Do not upload full game dumps, saves, credentials or session
passwords. Record failures as failures; do not fill a release gate from a source
review or editor compile alone.

## Complete-package acceptance

After presentation and collision are implemented, run every scenario in
[validation](validation.md). In addition to simultaneous streams, inspect:

- A late join during a stream and at 40 seconds into a 60-second stain.
- Moving props, water boundaries, first obstruction, fading and expiry on both
  observers, with their cosmetic preferences independently enabled/disabled.
- Controlled latency/loss on a private test session; no input beyond the
  one-second timeout, no stale restart after a reliable release.
- A deliberately mismatched mod/protocol; input refused with a useful diagnostic.
- Save/reload, map travel, reconnect and clean removal. No mod effects in saves.
- Actor/component counts during sustained use, after expiry and after leaving
  the world; maximum 256 stains/clouds and five new stamps per second per player.

Physical controller testing must cover modifier-first input, release of either
button, bumper-only action replay, no accidental drop, menu navigation,
rebinding and device disconnection. Verify equipment presentation after every
interruption, including focus loss.
