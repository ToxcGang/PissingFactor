"""Repository and release checks. Missing evidence is never an implicit pass."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GATES = (
    "singleplayer", "emergency", "controller", "interruptions", "surfaces",
    "water", "animations", "hosted_multiplayer", "dedicated_multiplayer",
    "late_join", "network_faults", "lifecycle", "performance", "clean_install",
)
PREFIX = "AbioticFactor/"
PAK_PATH = PREFIX + "Content/Paks/LogicMods/PissingFactor.pak"
LUA_PREFIX = PREFIX + "Binaries/Win64/ue4ss/Mods/PissingFactor/"


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_acceptance(data, commit, pak_hash):
    require(data.get("version") == "1.0.0", "Evidence mod version does not match")
    require(data.get("protocol") == 1, "Evidence protocol does not match")
    require(data.get("sourceCommit") == commit, "Acceptance must cover this exact source commit")
    require(data.get("pakSha256") == pak_hash, "Acceptance must cover this exact cooked pack")
    require(data.get("dependencies") == read_json(ROOT / "dependencies.lock.json"),
            "Acceptance dependencies do not match the lock file")
    checks = data.get("checks", {})
    for gate in GATES:
        check = checks.get(gate, {})
        require(check.get("status") == "passed", f"Release gate not passed: {gate}")
        for key in ("tester", "date", "evidence"):
            require(isinstance(check.get(key), str) and check[key].strip(),
                    f"Missing {key} for {gate}")
        require(re.fullmatch(r"\d{4}-\d{2}-\d{2}", check["date"]), f"Invalid test date: {gate}")


def validate_zip(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == len(set(n.casefold() for n in names)), "Duplicate ZIP entries")
        for name in names:
            p = PurePosixPath(name)
            require(not p.is_absolute() and ".." not in p.parts and "\\" not in name
                    and ":" not in name, f"Unsafe ZIP path: {name}")
            require(name in {PAK_PATH, "README.md", "LICENSE", "CHANGELOG.md",
                             "dependencies.lock.json", "package-manifest.json"}
                    or name.startswith(LUA_PREFIX) or name.startswith("docs/"),
                    f"Unexpected packaged file: {name}")
            require(not name.lower().endswith((".dll", ".exe", ".hpp", ".uproject")),
                    f"Dependency or game/editor content in package: {name}")
        required = {PAK_PATH, LUA_PREFIX + "scripts/main.lua", LUA_PREFIX + "enabled.txt",
                    LUA_PREFIX + "config.lua", "LICENSE", "README.md", "dependencies.lock.json"}
        require(required <= set(names), "ZIP is missing required installation files")
        manifest = json.loads(z.read("package-manifest.json"))
        require(manifest.get("version") == "1.0.0", "Wrong package version")
        expected = manifest.get("files", {})
        require(set(expected) == set(names) - {"package-manifest.json"}, "Manifest file inventory mismatch")
        for name, digest in expected.items():
            require(hashlib.sha256(z.read(name)).hexdigest() == digest, f"Hash mismatch: {name}")


def verify_source():
    version = (ROOT / "VERSION").read_text().strip()
    require(version == "1.0.0", "Unexpected initial version")
    lua = (ROOT / "runtime/PissingFactor/scripts/pf/version.lua").read_text()
    require(f'mod = "{version}"' in lua or f'mod="{version}"' in lua, "Lua version differs")
    lock = read_json(ROOT / "dependencies.lock.json")
    require(lock["unreal"]["version"] == "5.4.4", "Editor version changed")
    require(re.fullmatch(r"[a-f0-9]{64}", lock["ue4ss"]["sha256"]), "Invalid loader checksum")
    for path in ROOT.glob("**/*.json"):
        if any(part in {".git", ".tools", "local", "build", "dist", "Intermediate", "Saved"}
               for part in path.relative_to(ROOT).parts):
            continue
        read_json(path)
    import yaml
    for path in (ROOT / ".github").rglob("*.yml"):
        require(isinstance(yaml.safe_load(path.read_text()), dict), f"Invalid YAML: {path}")
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                                    cwd=ROOT, text=True).splitlines()
    for name in files:
        lower = name.lower()
        require(not any(term in lower for term in ("objectdump", "cxxheaderdump", "crashcontext")),
                f"Private game dump must not be committed: {name}")
        if lower.endswith((".uasset", ".umap")):
            require(name.startswith("unreal/AbioticFactor/Content/Mods/PissingFactor/"),
                    f"Unreal asset outside original mod namespace: {name}")
    for doc in [ROOT / "README.md", *ROOT.glob("docs/*.md"), ROOT / "CREDITS.md"]:
        for link in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", doc.read_text()):
            if "://" not in link and not link.startswith("#"):
                require((doc.parent / link).exists(), f"Broken documentation link: {doc.name}: {link}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", type=Path)
    args = parser.parse_args()
    try:
        verify_source()
        if args.zip:
            validate_zip(args.zip)
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        raise SystemExit(str(error))
    print("Source/configuration checks passed" + ("; ZIP verified" if args.zip else ""))
