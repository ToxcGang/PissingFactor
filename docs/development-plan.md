# Development order

Updated 2026-09-23 at the owner's request: finish the remaining features and
single-player checks first, then perform multiplayer acceptance last. This
replaces the earlier requirement to prove remote-client RPC delivery before
building the full animation and effects package.

## Established baseline

Prototype 3 has a recorded manual test of normal LB inventory cycling without
freezing, D-pad Left bathroom relief and stopping on release. Hold P remains
the keyboard binding. See [validation](validation.md) for the exact evidence;
other scenarios remain unverified until tested.

## Implementation and testing sequence

1. Build visible presentation and environmental effects: the arcing stream,
   solid-surface collision, temporary fading stains, and water ripples/clouds.
   Verify the game's water bindings before enabling water-specific effects.
2. Complete original first-person and clothed third-person animations, spatial
   stream/splash audio, and the controller-accessible settings/rebinding panel.
3. Finish single-player acceptance with the owner: partial/full relief, empty
   state, interruptions, emergencies, focus loss, controller disconnect,
   respawn, save/reload, effects, resource limits, clean installation and removal.
4. Run [multiplayer acceptance](multiplayer.md) last on the complete candidate:
   hosted co-op and Windows dedicated server with two clients, followed by
   simultaneous use, late joining, latency, disconnection and version mismatch.
   Resolve failures and repeat affected checks before publishing v1.0.0.

The next development milestone is a visible arcing stream and temporary solid
surface impacts. A second client is needed for step 4, not as a prerequisite
for the remaining implementation.

## Constraints throughout development

Keep server-authoritative relief and collision, controller-owned RPC actors,
version checks, replicated state, bounded transient effects and dedicated-server
rendering guards while implementing features. Deferring multiplayer tests does
not remove multiplayer support or mark its acceptance gates passed.

The owner performs all in-game and physical controller testing. Do not launch
or control their game for testing. Offline checks and command-line asset builds
can support development. Every distributed prototype must identify its source
commit and cooked-file hashes. Release 1.0.0 remains unpublished until the full
feature set and all required acceptance gates pass.
