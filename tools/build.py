"""Build/cook with a locally installed Unreal Editor 5.4.4. No downloads or licenses."""
from pathlib import Path
import argparse
import json
import subprocess
from verify import ROOT, require, read_json, sha256

PROJECT = ROOT / "unreal/AbioticFactor/AbioticFactor.uproject"


def run(args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def build(engine, stage, prototype=False):
    start_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    version = read_json(engine / "Engine/Build/Build.version")
    require(tuple(version[k] for k in ("MajorVersion", "MinorVersion", "PatchVersion")) == (5, 4, 4),
            "Use Unreal Editor exactly 5.4.4")
    editor = engine / "Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
    require(editor.is_file(), "UnrealEditor-Cmd.exe is missing")
    if stage in {"generate", "all"}:
        run([engine / "Engine/Build/BatchFiles/Build.bat", "AbioticFactorEditor", "Win64",
             "Development", PROJECT, "-WaitMutex", "-NoHotReloadFromIDE"])
        run([editor, PROJECT, "-run=PFBuild", "-unattended", "-nop4", "-stdout"])
    if stage in {"cook", "all"}:
        source_content = PROJECT.parent / "Content/Mods/PissingFactor"
        packages = ["/Game/Mods/PissingFactor/" + p.relative_to(source_content).with_suffix("").as_posix()
                    for p in sorted(source_content.rglob("*.uasset"))]
        require(packages, "No original mod assets were found")
        # Single-package mode skips directory discovery together with soft
        # references, so list every original package explicitly.
        run([editor, PROJECT, "-run=Cook", "-TargetPlatform=Windows",
             "-Package=" + "+".join(packages), "-CookSinglePackage",
             "-unattended", "-nop4", "-stdout"])
        content = PROJECT.parent / "Saved/Cooked/Windows/AbioticFactor/Content/Mods/PissingFactor"
        require(content.is_dir(), "No cooked mod content was produced")
        manifest = read_json(ROOT / "assets/manifest.json")
        actual = {p.stem for p in content.glob("*.uasset")}
        required = {"ModActor", "BP_PFPlayer", "BP_PFImpact", "BP_PFInput"} if prototype else set(manifest["requiredCookedAssets"])
        require(required <= actual, "Cook is incomplete: " + ", ".join(sorted(required - actual)))
        output = ROOT / "build"
        output.mkdir(exist_ok=True)
        entries = []
        for path in sorted(content.rglob("*")):
            if path.is_file():
                require(path.suffix in {".uasset", ".uexp", ".ubulk"}, f"Unexpected cook file: {path}")
                mount = "../../../AbioticFactor/Content/Mods/PissingFactor/" + path.relative_to(content).as_posix()
                entries.append(f'"{path}" "{mount}"')
        response = output / "pak-response.txt"
        response.write_text("\n".join(entries) + "\n", encoding="utf-8")
        pak = output / "PissingFactor.pak"
        unrealpak = engine / "Engine/Binaries/Win64/UnrealPak.exe"
        run([unrealpak, pak, f"-Create={response}", "-compress"])
        run([unrealpak, pak, "-Test"])
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
        require(not dirty, "Generated editable assets changed; review and commit them, then rerun --stage cook")
        require(commit == start_commit, "Source commit changed during cooking; rerun --stage cook")
        record = {"engine": "5.4.4", "sourceCommit": commit, "pakSha256": sha256(pak),
                  "cookedAssets": sorted(actual), "kind": "prototype" if prototype else "complete"}
        pak.with_suffix(".build.json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True, help="Installed UE_5.4 directory")
    parser.add_argument("--stage", choices=("generate", "cook", "all"), default="all")
    parser.add_argument("--prototype", action="store_true", help="Only for owned-RPC/continence integration, never release")
    args = parser.parse_args()
    try:
        build(args.engine.resolve(), args.stage, args.prototype)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
