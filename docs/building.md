# Building and development

The Lua core can be tested without the game or Unreal Editor. The cooked mod
cannot. There is currently no complete asset cook or playable package. The
editor generator compiles against 5.4.4 and produces the initial network/input
actors and materials. Full presentation and gameplay acceptance remain pending.

## Portable checks

Install Python 3.12, then run from the repository root:

```powershell
python -m pip install -r requirements-dev.txt
python tools/test.py
python -m unittest discover -s tests -p "test_*.py"
python tools/verify.py
```

These validate Lua syntax and logic, configuration, repository metadata,
documentation links, and packaging rules. They do not simulate Unreal RPCs.

## Local Unreal build

1. Install and license Unreal Editor **5.4.4** through Epic Games Launcher.
2. Install Visual Studio 2022 Build Tools with MSVC **14.38.33130** (compiler
   14.38.33145 tested) and Windows SDK 10.0.26100.0. The editor target pins that
   toolset; the installed MSVC 14.51 compiler fails in UE 5.4.4 headers.
3. Run `python tools/build.py --engine "D:\Epic Games\UE_5.4" --stage generate`.
   Adjust the path to your actual installation. This compiles the editor-only
   plugin and invokes `PFBuild` to generate editable assets.
4. Review the generated assets under `Content/Mods/PissingFactor` in the editor.
   Complete and verify the input, UI, animations, and effects against the game.
   The generator currently creates the actor RPC definitions, key capture and four materials;
   the asset manifest deliberately requires the unfinished resources too.
5. Commit reviewed original assets, then run the same command with `--stage cook`.
   Only the mod's namespace is packed. No engine, editor, or game assets are copied.
   The cooker uses Unreal's single-package mode to omit default maps, unrelated
   dependencies and global shader libraries already provided by the game.
6. Run `python tools/package.py` for a development ZIP. The command refuses an
   incomplete cook, uncommitted changes, or a stale build record.

UE4SS loads the cooked `ModActor` through BPModLoaderMod. The editor plugin is
only an authoring tool; players never install a native PissingFactor DLL.

For the initial transport proof only, append `--prototype` to the cook command.
This creates a build explicitly marked as a prototype; release packaging rejects
it even if someone supplies acceptance evidence. Enable `EnablePrototype` only
in the installed development configuration of a disposable test world. This
mode has no completed animations, collision/water effects, or settings panel.

## Private compatibility probe

Install `tools/probe.lua` as `ue4ss/Mods/PissingFactorProbe/Scripts/main.lua`, with
an empty `enabled.txt` beside `Scripts`. It logs read-only bindings and writes
reflection metadata locally. F6 repeats diagnostics. Remove `enabled.txt` when
finished. Do not upload the full object dump, SDK, game saves, or extracted rigs.

```powershell
python tools/extract_probe.py "PATH\TO\ue4ss\UE4SS.log"
```

This saves reference rig data in ignored `local/rigs`. It is a private authoring
input, never redistributable content. A main-menu rig probe is not a gameplay test.

## Release

Keep acceptance evidence outside the source commit being tested, for example
`local/acceptance.json`, using `validation/results.json` as the blank template.
Record the exact commit, cooked-pack SHA-256, full dependency lock, and a tester,
date and evidence for each passed scenario. A missing gate blocks packaging:

```powershell
python tools/package.py --acceptance local/acceptance.json
python tools/verify.py --zip dist/PissingFactor-1.0.0.zip
```

Only after every real-game gate passes may a maintainer create `v1.0.0` and
upload the verified ZIP and its `.sha256` file with release notes. CI never
creates tags or publishes releases. The source archive from GitHub is not an
installable mod download.
