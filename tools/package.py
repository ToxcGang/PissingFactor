"""Build a reproducible mod ZIP from an inspected local cook; never uploads."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import zipfile
from verify import ROOT, PAK_PATH, LUA_PREFIX, require, read_json, sha256, validate_acceptance, validate_zip


def package(pak, output, acceptance=None):
    require(pak.is_file() and pak.stat().st_size > 1024, "Missing or empty Unreal cooked pack")
    build = read_json(pak.with_suffix(".build.json"))
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    require(not dirty, "Commit source changes before building a test/release package")
    require(build["sourceCommit"] == commit, "Cook is stale; rebuild this source commit")
    require(build["pakSha256"] == sha256(pak), "Cooked pack hash differs from build record")
    require(build["engine"] == "5.4.4", "Wrong cooking engine")
    cooked_files = {pak.with_suffix(s).name: sha256(pak.with_suffix(s)) for s in (".pak", ".utoc", ".ucas")}
    require(build.get("cookedFiles") == cooked_files, "Cooked container hashes differ from build record")
    if acceptance:
        require(build.get("kind") == "complete", "A transport prototype cannot be released")
        required = set(read_json(ROOT / "assets/manifest.json")["requiredCookedAssets"])
        require(required <= set(build.get("cookedAssets", [])), "Build is missing required assets")
        validate_acceptance(read_json(acceptance), commit, sha256(pak), cooked_files)
    files = {str(Path(PAK_PATH).with_suffix(s)).replace("\\", "/"): pak.with_suffix(s).read_bytes()
             for s in (".pak", ".utoc", ".ucas")}
    runtime = ROOT / "runtime/PissingFactor"
    for path in runtime.rglob("*"):
        if path.is_file() and path.name != "user_settings.json":
            files[LUA_PREFIX + path.relative_to(runtime).as_posix()] = path.read_bytes()
    for name in ("LICENSE", "README.md", "CHANGELOG.md", "dependencies.lock.json"):
        files[name] = (ROOT / name).read_bytes()
    for path in (ROOT / "docs").glob("*.md"):
        files["docs/" + path.name] = path.read_bytes()
    manifest = {"version": "1.0.0", "protocol": 1, "sourceCommit": commit,
                "kind": build.get("kind", "unknown"),
                "releaseValidated": acceptance is not None,
                "files": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}
    files["package-manifest.json"] = json.dumps(manifest, indent=2, sort_keys=True).encode() + b"\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    validate_zip(output)
    output.with_suffix(output.suffix + ".sha256").write_text(f"{sha256(output)}  {output.name}\n")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pak", type=Path, default=ROOT / "build/PissingFactor.pak")
    parser.add_argument("--acceptance", type=Path, help="Required only for a release package")
    args = parser.parse_args()
    suffix = "" if args.acceptance else "-dev"
    try:
        print(package(args.pak, ROOT / f"dist/PissingFactor-1.0.0{suffix}.zip", args.acceptance))
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit(str(error))
