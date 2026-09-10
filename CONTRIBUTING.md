# Contributing

Open a bug report or feature request using the repository's issue forms. For
bugs, include exact game, mod, and UE4SS versions, whether you are a host/client
or dedicated server, the input device, reproduction steps, and a relevant log
excerpt. Remove personal information before attaching logs.

Develop against the environment pinned in `dependencies.lock.json`. Make a
focused branch, run the checks in the README, and describe the behavior changed
and validation performed in your pull request.

Keep game-specific bindings in the compatibility adapter. Do not guess function
names or ship a client-only stat edit as multiplayer support. Preserve server
authority, bounded effects, correct actor ownership, and clean lifecycle teardown.

Do not commit downloaded tools, extracted game assets, private test worlds,
credentials, crash dumps, or reflection dumps. New original assets must include
editable source or a reproducible generation script and an entry in the asset
manifest. All contributions must be compatible with this project's MIT license.

Only mark a validation scenario passed after running it, including exact builds
and evidence. Unit-test success cannot replace a multiplayer gameplay test.
