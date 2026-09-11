# Original assets

The editor generator under `unreal/AbioticFactor/Plugins/PissingFactorEditor`
creates editable Blueprints and analytic materials. Those generated assets live
under `/Game/Mods/PissingFactor`; they reference ordinary engine classes and do
not contain extracted game assets.

`audio/S_Stream.wav` and `audio/S_Splash.wav` are original deterministic sound
synthesis from `tools/synth_audio.py`, authored for this project. Regenerate them
with `python tools/synth_audio.py`. Both are mono 48 kHz, 16-bit PCM. Stream is a
four-second loop; splash is a short one-shot. Spatial attenuation, in-game mix,
import and playback remain to be integrated and listening-tested.

The raw game skeleton metadata used privately for animation compatibility stays
in ignored `local/rigs`. It is not a redistributable asset. No character mesh,
texture, animation or sound from Abiotic Factor or Postal 2 is included here.

All original assets and their generating source are MIT licensed to ToxcGang.
`manifest.json` lists the resources required before a complete pack can be cooked.
