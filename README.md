# PissingFactor

A hold-to-pee mod for **Abiotic Factor**, inspired by Postal 2.

**Version: 1.0.0 · In development · Not yet a verified playable release.**

PissingFactor is being built for Windows Steam, hosted co-op, and Windows
dedicated servers. All players and the host need the same mod version and
UE4SS. Controller support means controllers on PC, not installation on consoles.

## Intended gameplay

- Hold **P**, or hold **LB/L1** followed by **D-pad Down**. Release to stop.
- Walk and aim while peeing. Attacks, sprinting, interactions, menus, death,
  and lost input focus interrupt the action.
- Relieve the existing bathroom need gradually; stop when empty. The default
  time for complete relief is eight seconds.
- A clothed first-person hand animation and third-person pose accompany an
  arcing stream, spatial sound, and splashes.
- Surfaces receive temporary stains; water receives a dispersing yellow cloud
  and ripples. Effects are cosmetic, bounded, and never saved into the world.
- Rebind controls and adjust sound/effects in a controller-accessible panel.

## Development status

The repository contains the implementation in progress, tests, and build tools.
The current milestone is an opt-in transport/continence prototype: the editor
plugin generates replicated actors, consumed key bindings, and material assets.
Animations, water collision, presentation, rebinding UI and multiplayer acceptance
are unfinished. `EnablePrototype` defaults to false so a source installation
does not change gameplay silently.
Unit tests do **not** establish in-game or multiplayer compatibility. See
[validation](docs/validation.md) for the evidence and remaining release gates.
There is no `v1.0.0` release until all required acceptance checks pass.

Target environment:

| Component | Target |
| --- | --- |
| Abiotic Factor | 1.4.0.28206, Steam build 24343447 |
| Unreal Editor | 5.4.4 |
| Abiotic Factor UE4SS bundle | 1.22.0 |
| Underlying UE4SS | 3.0.1-1012-gc838a8ac |
| Mod / network protocol | 1.0.0 / 1 |

## Documentation

- [Installation and removal](docs/installation.md)
- [Building and development](docs/building.md)
- [Architecture and networking](docs/architecture.md)
- [Validation and multiplayer checklist](docs/validation.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) · [Credits](CREDITS.md)

## Tests

With Python 3.12 or later:

```shell
python -m pip install -r requirements-dev.txt
python tools/test.py
python -m unittest discover -s tests -p "test_*.py"
python tools/verify.py
```

## License

Original PissingFactor code and assets are [MIT licensed](LICENSE), copyright
2026 ToxcGang. Abiotic Factor, Postal 2, Unreal Engine, and UE4SS belong to their
respective owners. This is an unofficial project, not endorsed by those owners.
The repository and release packages must not contain extracted game assets.
