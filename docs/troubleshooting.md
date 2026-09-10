# Troubleshooting

## Nothing happens

Confirm that both the Lua folder and cooked asset pack are installed. Source
downloads are not playable release packages. Look for `[PissingFactor]` in
`Binaries/Win64/ue4ss/UE4SS.log` and record the first compatibility failure.
Do not work around a failed compatibility check by guessing property names.

## No relief or remote effects

The server must run the same complete mod and protocol version as all clients.
Check server logs as well as the affected client's logs. A local visual alone
does not demonstrate successful authoritative relief.

## Shortcut drops items or changes hotbar slots

Stop testing the ability and report the input bindings and controller model.
The controller interception check is a release requirement. Press the modifier
before D-pad Down. When using Steam Input, check whether the controller is
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
