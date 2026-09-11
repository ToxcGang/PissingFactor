# Installation and removal

**Development status:** do not install GitHub's source ZIP as a playable mod.
The full runtime requires cooked PissingFactor assets. Use a verified release
ZIP when one is available, or follow the developer build instructions.

## Prerequisites

Use Windows Steam Abiotic Factor and the
[pinned UE4SS bundle](https://github.com/igromanru/AF-UE4SS/releases/tag/1.22.0).
Check `dependencies.lock.json` for the complete versions and download checksum.
Close the game before installing files.

UE4SS belongs beside the game's shipping executable:

```text
AbioticFactor/AbioticFactor/Binaries/Win64/
  dwmapi.dll
  ue4ss/UE4SS.dll
```

Preserve an existing UE4SS installation and its other mods. Do not overwrite
the entire `Mods` folder or `mods.txt` with PissingFactor's files.

## Mod files

Extract the verified mod ZIP into Steam's game installation directory
(`steamapps/common/AbioticFactor`), which contains the inner `AbioticFactor`
directory. Inside that inner directory, the resulting layout is:

```text
Binaries/Win64/ue4ss/Mods/PissingFactor/
  enabled.txt
  config.lua
  scripts/main.lua
  scripts/pf/...
Content/Paks/LogicMods/
  PissingFactor.pak
  PissingFactor.utoc
  PissingFactor.ucas
```

All three cooked files are required. A `.pak` alone mounts but does not load
the Blueprint actors in the target game's IoStore loader. The package verifier
checks the presence and hashes of all three files.

The server and every client need the same complete package. A dedicated server
uses the corresponding folders beside its own executable/content directory.
An editor installation is not required to play a cooked release.

## Controls and tuning

Hold P on keyboard. On controller, hold LB/L1 **before** pressing D-pad Down;
release either to stop. A bumper tap keeps its ordinary hotbar action on release.
The shortcut must never drop an item. Controls and audiovisual preferences are
local; the host's `config.lua` controls relief rate, range, and effect lifetimes.

## Removal

Close the game/server. Remove only the `PissingFactor` mod folder and its
named cooked files. Keep UE4SS when other mods use it. Effects are transient;
normal bathroom relief already applied to the character remains normal game
state. Restart the game after removal.
