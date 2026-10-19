# Changelog

Development progress includes a compiled UE 5.4.4 editor generator, editable
network/input Blueprints and materials, an opt-in Lua transport integration,
ownership and lifecycle tests, configuration checks, and guarded packaging.
This does not constitute a playable 1.0.0 release.

## 1.0.0 — In development

Initial release target. No stable release has been published.

- Prototype 4c: withdraw the 4b Lua deferred-spawn path after a reported freeze.
  Lua now posts stream requests to transient, nonreplicated fields; an unhooked
  player Blueprint tick creates/releases local actors and EndPlay cleans them up.
  The class reference is held by Unreal, and rejected requests latch until release.
  Execute the generated lifecycle graph in a disposable headless Unreal world as
  part of authoring validation. Bump driver/presentation asset revision to 5.
  Add `EnableEffects = false` by default: relief-only mode skips arc traces,
  impact publishing, cosmetic asset loads and rendering. Add first-use debug
  checkpoints to locate hangs when effects are later enabled. The exact 4b hang
  location remains unproven; the new build still needs manual stability checks.

- Prototype 4b: address the first-stream spawn failure reported on 2026-10-19.
  Use UE 5.4.4's reflected deferred spawn functions at the emitting player's
  position, with explicit collision handling and scale. Initialize the curve
  before finishing construction and retain partial allocations for cleanup.
  Validate loaded class types, reload stale stream/material references before
  use, and report the spawn phase, class and location on failure. The original
  engine rejection cause remains unproven; in-game retesting is required.

- Prototype 4a: fix the presentation startup failure reported on 2026-09-25.
  Call `IsDedicatedServer` on `KismetSystemLibrary`, its verified UE 5.4.4 owner,
  instead of `GameplayStatics`. Correct the engine mock that masked this error.
  F6 now shows visual readiness/counts or a short failure reason locally and
  repeats the full presentation error in the log. In-game effects need retesting.

- Prototype 4: add an original spline-deformed stream mesh with per-frame
  interpolation, server-side arc collision and locally rendered surface decals.
  Decals retain surface-local attachment data, expire after 60 seconds and fade
  over the last ten; late discovery preserves remaining lifetime and opacity.
  Enforce the 256-record cap before allocating replacements. Known water-volume
  bounds suppress stains pending exact water-surface integration. Cosmetic
  binding failures leave continence relief running. New visuals are unverified
  in-game; multiplayer testing remains last.

- Prototype 3: replace the controller chord with hold D-pad Left alone; preserve
  keyboard P. Remove LB, D-pad Down, menu-button and unused F8 capture, plus all
  native inventory/drop/menu action replay. Read Blueprint key state on the
  existing 10 Hz tick instead of hooking input events into Lua. Reject old input
  assets before enabling capture. A subsequent manual test confirmed normal LB
  cycling without freezing, D-pad Left relief and stopping on release. The
  earlier freeze's root cause and longer-session stability remain unproven.

- Actor-tick prototype 2: replace recurring UE4SS async/game-thread queues with
  the cooked mod actor's tick; handle F6 edges on that same thread and display
  local status. Suppress idle RPCs/actor updates and reduce player discovery to
  once per second. Addresses the observed loader callback failure pattern;
  game stability and relief are pending a manual retest.

- Implement keyboard/controller hold/release and interruption state machines.
- Implement gradual continence relief with server-side eligibility, version
  checks, input timeouts, and protection against stale input.
- Implement bounded ballistic tracing and temporary impact lifetimes.
- Add reproducible tests, compatibility diagnostics, build/release tooling,
  and GitHub contribution templates.

In-game integration, visuals, animations, and multiplayer acceptance are tracked
in [validation](docs/validation.md). A feature listed here is not a compatibility
claim until its corresponding acceptance check passes.
