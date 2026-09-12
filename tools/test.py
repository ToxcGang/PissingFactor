"""Run the same portable Lua 5.4 core locally and in GitHub Actions."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools/python"))
try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    raise SystemExit("Install test dependencies: python -m pip install -r requirements-dev.txt")

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().package.path = str(ROOT / "runtime/PissingFactor/scripts/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
compile_lua = lua.eval("function(source,name) local f,e=load(source,name); assert(f,e); return true end")
for path in (ROOT / "runtime").rglob("*.lua"):
    compile_lua(path.read_text(encoding="utf-8"), "@" + str(path))
compile_lua((ROOT / "tools/probe.lua").read_text(encoding="utf-8"), "@probe.lua")
lua.execute((ROOT / "tests/run.lua").read_text(encoding="utf-8"))
for scenario in ("bootstrap", "client"):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().package.path = str(ROOT / "runtime/PissingFactor/scripts/?.lua").replace("\\", "/") + ";" + runtime.globals().package.path
    runtime.execute((ROOT / f"tests/{scenario}.lua").read_text(encoding="utf-8"))
