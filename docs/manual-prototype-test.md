# Manual prototype test

This development build tests input, owned network actors and the existing
bathroom stat. It has no rendered stream, stains, water effects, animations,
in-game audio or settings/rebinding panel yet. Those are unfinished features,
not the expected result of this first test. No multiplayer acceptance has passed.

## Prepare

1. Close Abiotic Factor before updating files. Extract `PissingFactor-1.0.0-dev.zip`
   into `steamapps/common/AbioticFactor`, following [installation](installation.md).
   Keep the `.pak`, `.utoc` and `.ucas` files together.
2. Open the installed `AbioticFactor/Binaries/Win64/ue4ss/Mods/PissingFactor/config.lua`.
   Set `EnablePrototype = true` and `Debug = true`. The ZIP ships with both false.
   These settings take effect after restarting the game.
3. Keep `PissingFactorProbe` disabled. Its separate F6 diagnostic conflicts with
   this prototype's F6 key. Its `enabled.txt` was renamed to `disabled.txt` during
   local setup.
4. Launch the game yourself and use a disposable world. `PissingFactor_Prototype`
   was created for this purpose. Finish job/trait selection if needed, then enter
   normal gameplay. Leave your established worlds out of this test.

## First test: keyboard and bathroom meter

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

Expected initial diagnostics in single-player are `Local input actor: true`,
`enabled: true`, one authority session, and `ready=true`. If these are missing,
or the first hold has no effect despite available need, stop at this point and
report the logs before running the rest of the checklist.

## Interruptions and controller

After the first keyboard test succeeds:

- While holding P, open a menu, sprint, attack, or interact. Each should stop
  relief. Closing the menu or ending the other action while P remains held
  should not resume it. Release P and press it again to restart.
- Switch focus away from the game during a hold. Relief should stop; returning
  to the game should require a fresh press.
- With a controller, hold **LB/L1 first**, then **D-pad Down**. Releasing either
  should stop relief. Using this chord must not drop an item or change hotbar slots.
- Tap LB/L1 alone: its ordinary hotbar action should happen once on release.
  D-pad Down alone retains the ordinary drop action, so use an expendable item
  if testing that separately. Disconnect the controller during the pee chord
  and verify that relief stops.

Record your controller model and whether Steam Input is enabled. Rebinding and
settings-panel navigation are deferred until that UI is implemented.

## Send back

Use `AbioticFactor/Binaries/Win64/ue4ss/UE4SS.log` in your game installation.
Copy just the `[PissingFactor]` lines covering startup and your F6 snapshots,
including the first `Integration stopped` or other error if present. Include:

- Keyboard or controller, plus the controller model/Steam Input setting.
- What the bathroom meter did during the hold and after release.
- Which step failed, or which steps behaved as expected.
- `sourceCommit` from the ZIP's `package-manifest.json` if you updated the package.

Avoid posting a complete game dump, save, or unredacted log publicly. The
[multiplayer procedure](multiplayer.md) is the next stage when another client
is available; a successful single-player test does not prove remote RPC delivery.

## After testing

Close the game and set `EnablePrototype = false` to disable the prototype for
ordinary play, or follow the removal instructions. Applied bathroom relief is
ordinary character state; disabling the mod does not roll back that relief.
Keep the test results separate from release acceptance until the complete
feature set is implemented and validated.
