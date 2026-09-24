# Manual prototype test

**Current build: prototype 4 (stream and stains).** Replace the earlier prototype before
retesting. Both the Lua files and all three cooked files changed; updating only
Lua leaves incompatible network/driver assets, which the new code rejects.
P and D-pad Left retain the prototype 3 controls. You perform all game/controller
tests yourself; this is not a stable release.

This build adds a visible arcing stream and fading solid-surface stains to the
existing bathroom relief. Water effects, animations, in-game audio and settings/
rebinding are unfinished. Test walls and floors away from water first. Known
liquid-volume bounds suppress stains conservatively, but do not establish exact
water surfaces. Multiplayer acceptance remains scheduled last.

## Prepare

1. Close Abiotic Factor before updating files. Extract `PissingFactor-1.0.0-prototype-4.zip`
   into `steamapps/common/AbioticFactor`, following [installation](installation.md).
   Replace the Lua files and keep the `.pak`, `.utoc` and `.ucas` files together.
   The build tool's `PissingFactor-1.0.0-dev.zip` is also valid when its startup
   message and source commit match this revision.
2. Open the installed `AbioticFactor/Binaries/Win64/ue4ss/Mods/PissingFactor/config.lua`.
   Set `EnablePrototype = true` and `Debug = true`. The ZIP ships with both false.
   These settings take effect after restarting the game.
3. Keep `PissingFactorProbe` disabled. Its separate F6 diagnostic conflicts with
   this prototype's F6 key. Its `enabled.txt` was renamed to `disabled.txt` during
   local setup.
4. Launch the game yourself and use a disposable world. `PissingFactor_Prototype`
   was created for this purpose. Finish job/trait selection if needed, then enter
   normal gameplay. Leave your established worlds out of this test.

## First test: stability and visible status

1. Enter normal gameplay in the disposable world. The startup log should include
   `prototype 4 (stream and stains)` and `Prototype 4 ready`. If it only says
   `Waiting for BPModLoaderMod`, send that log before testing the ability.
2. **Tap and release F6 once.** The mod should show a local status message in the
   game's text-message area, and write one diagnostic snapshot to `UE4SS.log`.
   Holding F6 should produce only one snapshot. The message is local only.
3. `Continence 75/75` (or any equal current/maximum pair) means there is no
   bathroom need yet. This is a valid diagnostic result; you do not need to wait
   for need to build for this stability test.
4. Tap **LB/L1 alone**, then release, several times. Inventory cycling should
   work normally without a freeze. No modifier is needed for the mod anymore.
   If this freezes, stop here and preserve the log before restarting.
5. Hold **D-pad Left alone** briefly, then release it. With bathroom need available,
   continence should rise during the hold and stop on release. At maximum continence
   there is no bathroom need, so no stream or new stain should appear. With need
   available, the visual stream should accompany relief. D-pad Left's ordinary
   gameplay action is consumed by the mod.
6. Play normally for five minutes, then tap F6 once more.
   Report whether both status messages appeared and whether the game stayed
   responsive. Only continue with relief tests after this passes.

If the game freezes again, note the time and preserve the **last 40 lines of the
whole UE4SS.log**, not just `[PissingFactor]` entries. The first failure included
`[UE4SS.EngineTick.LuaModImpl] ... Ref was not function`, which the mod-only
filter omitted. Send any `Driver initialization stopped` message too. If needed,
close the game yourself, set `EnablePrototype = false`, and report whether the
same world stays responsive with gameplay disabled.

## Next: keyboard and bathroom meter

1. Stand still on solid ground, with menus and chat closed. Press **F6**.
2. Let the bathroom need build until continence is below maximum. F6 records the
   exact `continence=current/maximum` values. At maximum, relief should do nothing.
3. Hold **P** briefly, press **F6 while still holding P**, then release P. Press
   F6 again after two seconds. Watch the bathroom meter during this sequence.
4. Expected: continence increases during the hold and stops increasing after
   release. With enough need remaining, the held snapshot says `held=true` and
   `active=true`; the released snapshot says both false. Debug log lines beginning
   `Authority relief` show the actual before/after values. Natural game decay
   can still reduce the stat independently.
5. Hold P until fully relieved, then keep holding briefly. It should stop at
   maximum and require release before another press can start it. Eight seconds
   is the default for the entire maximum need, so partial need takes less time.
   Your previous snapshot was 63/75, which would take about 1.3 seconds to fill;
   use a short hold for a partial-relief test at that level.

Expected initial diagnostics in single-player are `Local input actor: true`,
`enabled: true`, one authority session, and `ready=true`. If these are missing,
or the first hold has no effect despite available need, stop at this point and
report the logs before running the rest of the checklist.

## Stream and surface stains

1. With bathroom need available, stand about one metre from a plain wall in a
   dry room. Hold P or D-pad Left and aim at the wall, then slightly down toward
   the floor. Expect a narrow yellow curved stream that stops at the first solid
   surface. Walking and aiming should move it. Look down enough to see the
   waist-height origin; custom hand/body animations are not present yet.
2. Release the button. The stream should disappear promptly; the yellow impact
   stain should remain. Tap F6: the log includes presentation status and local
   stream/stain counts. Releasing should leave zero active stream visuals.
3. Time one isolated group of stains from the last impact. It should stay visible
   for roughly 50 seconds, fade during the final ten seconds, and be gone at
   about 60 seconds. Additional impacts at the same spot create younger stains.
4. If available, hit a movable door or prop, then move it. The stain should follow
   the surface. It must not destroy the prop when fading. Some surfaces may have
   decal reception disabled by the game; report those separately.
5. Check a nearby obstruction and straight-down aiming. The stream should not
   continue behind the obstruction or stay visible after the action ends.
6. Return to the main menu, then reload the disposable world. Old streams and
   stains should be gone. Check for duplicate effects on the next use.

Send the first `Environmental effects disabled`, `Presentation unavailable` or
`Presentation disabled` log line if relief works but visuals do not. These paths
disable affected cosmetics without intentionally disabling bathroom relief.
Exact water boundaries and water effects are deferred; do not treat dry-surface
success as passing the water acceptance gate.

## Interruptions and controller

After the first keyboard test succeeds:

- While holding P, open a menu, sprint, attack, or interact. Each should stop
  relief. Closing the menu or ending the other action while P remains held
  should not resume it. Release P and press it again to restart.
- Switch focus away from the game during a hold. Relief should stop; returning
  to the game should require a fresh press.
- Repeat the relief and interruption tests with **D-pad Left alone**. Release
  should stop relief, without dropping an item or changing hotbar slots.
- Open a menu and check D-pad navigation. Close it and verify that a held action
  does not resume until released and pressed again.
- Disconnect the controller while holding D-pad Left and verify that relief stops.
  LB/L1 and D-pad Down now remain entirely with the game's native input handling.

Record your controller model and whether Steam Input is enabled. Rebinding and
settings-panel navigation are deferred until that UI is implemented.

## Send back

Use `AbioticFactor/Binaries/Win64/ue4ss/UE4SS.log` in your game installation.
For normal results, copy the `[PissingFactor]` startup and F6 snapshot lines.
For a freeze or crash, include the last 40 lines regardless of prefix, including
the first error if present. Include:

- Keyboard or controller, plus the controller model/Steam Input setting.
- What the bathroom meter did during the hold and after release.
- Whether the stream appeared, stopped at surfaces and vanished on release;
  whether stains attached, faded and disappeared, including the approximate times.
- Which step failed, or which steps behaved as expected.
- `sourceCommit` from the ZIP's `package-manifest.json` if you updated the package.

Avoid posting a complete game dump, save, or unredacted log publicly. Continue
with the remaining features and single-player checks in the
[development order](development-plan.md). The [multiplayer procedure](multiplayer.md)
is reserved for the final acceptance stage; a successful single-player test
does not prove remote RPC delivery.

## After testing

Close the game and set `EnablePrototype = false` to disable the prototype for
ordinary play, or follow the removal instructions. Applied bathroom relief is
ordinary character state; disabling the mod does not roll back that relief.
Keep the test results separate from release acceptance until the complete
feature set is implemented and validated.
