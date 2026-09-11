"""Extract only rig metadata produced by our own probe into ignored local files."""
from pathlib import Path
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("log", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = root / "local/rigs"
output.mkdir(parents=True, exist_ok=True)
count = 0
for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
    marker = "[PissingFactorProbe] PF_RIG_JSON="
    if marker not in line:
        continue
    data = json.loads(line.split(marker, 1)[1])
    if data["label"] not in {"hands", "body"} or not data["bones"]:
        raise SystemExit("Unexpected or empty rig in probe output")
    (output / f'{data["label"]}.json').write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f'{data["label"]}: {len(data["bones"])} reference-pose bones')
    count += 1
if count < 2:
    raise SystemExit("Both body and hands metadata are required; run the probe in the game first")
