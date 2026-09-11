# Changelog

Development progress includes a compiled UE 5.4.4 editor generator, editable
network/input Blueprints and materials, an opt-in Lua transport integration,
ownership and lifecycle tests, configuration checks, and guarded packaging.
This does not constitute a playable 1.0.0 release.

## 1.0.0 — In development

Initial release target. No stable release has been published.

- Implement hold/release and controller shortcut state machines.
- Implement gradual continence relief with server-side eligibility, version
  checks, input timeouts, and protection against stale input.
- Implement bounded ballistic tracing and temporary impact lifetimes.
- Add reproducible tests, compatibility diagnostics, build/release tooling,
  and GitHub contribution templates.

In-game integration, visuals, animations, and multiplayer acceptance are tracked
in [validation](docs/validation.md). A feature listed here is not a compatibility
claim until its corresponding acceptance check passes.
