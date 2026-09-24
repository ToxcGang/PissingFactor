"""Build/cook with a locally installed Unreal Editor 5.4.4. No downloads or licenses."""
from pathlib import Path
import argparse
import csv
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
        required = set(manifest["prototypeCookedAssets"] if prototype else manifest["requiredCookedAssets"])
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
        # Abiotic Factor uses the IoStore loader. A legacy pak alone mounts
        # successfully but cannot supply these Blueprint packages to it.
        io_response = output / "io-response.txt"
        io_response.write_text("\n".join(e for e in entries if '.uexp"' not in e) + "\n", encoding="utf-8")
        commands = output / "io-commands.txt"
        commands.write_text(f'-Output="{pak.with_suffix(".utoc")}" -ContainerName=PissingFactor '
                            f'-ResponseFile="{io_response}"\n', encoding="utf-8")
        cooked = PROJECT.parent / "Saved/Cooked/Windows"
        metadata = cooked / "AbioticFactor/Metadata"
        run([unrealpak, "IoStore", f"-CreateGlobalContainer={output / 'authoring-global.utoc'}",
             f"-CookedDirectory={cooked}", f"-PackageStoreManifest={metadata / 'packagestore.manifest'}",
             f"-ScriptObjects={metadata / 'scriptobjects.bin'}", f"-Commands={commands}"])
        inventory = output / "iostore-list.csv"
        run([unrealpak, "IoStore", f"-List={pak.with_suffix('.utoc')}", f"-CSV={inventory}"])
        with inventory.open(encoding="utf-8-sig", newline="") as stream:
            rows = list(csv.DictReader(stream, skipinitialspace=True))
        filenames = {r["Filename"].strip() for r in rows if r["ChunkType"].strip() != "ContainerHeader"}
        expected_files = {"../../../AbioticFactor/Content/Mods/PissingFactor/" +
                          p.relative_to(content).as_posix() for p in content.rglob("*")
                          if p.is_file() and p.suffix != ".uexp"}
        require(filenames == expected_files, "IoStore inventory differs from the original mod assets")
        # authoring-global is private build metadata, never an installation file.
        containers = {pak.with_suffix(s).name: sha256(pak.with_suffix(s))
                      for s in (".pak", ".utoc", ".ucas")}
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
        require(not dirty, "Generated editable assets changed; review and commit them, then rerun --stage cook")
        require(commit == start_commit, "Source commit changed during cooking; rerun --stage cook")
        record = {"engine": "5.4.4", "sourceCommit": commit, "pakSha256": sha256(pak),
                  "cookedFiles": containers,
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
