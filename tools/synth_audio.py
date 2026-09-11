"""Recreate original liquid sounds from deterministic synthesis; no recordings."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000


def liquid(seconds, seed, splash=False):
    rng = random.Random(seed)
    count = int(seconds * RATE)
    samples = [0.0] * count
    low = 0.0
    for i in range(count):
        noise = rng.uniform(-1, 1)
        low += 0.22 * (noise - low)
        t = i / RATE
        envelope = math.exp(-5 * t) if splash else 0.6 + 0.15 * math.sin(2 * math.pi * t * 3)
        samples[i] = (low * 0.2 + noise * 0.028) * envelope
    # Overlapping short descending resonances evoke irregular droplets.
    for _ in range(int(seconds * (80 if splash else 38))):
        start = rng.randrange(count)
        frequency = rng.uniform(550, 2200)
        length = int(RATE * rng.uniform(0.012, 0.048))
        amplitude = rng.uniform(0.012, 0.06)
        for offset in range(length):
            index = start + offset
            if index >= count:
                break
            t = offset / RATE
            envelope = math.exp(-t * 130) * min(1, offset / 30)
            if splash:
                envelope *= math.exp(-start / RATE * 5)
            phase = 2 * math.pi * (frequency * t - frequency * 4 * t * t)
            samples[index] += amplitude * envelope * math.sin(phase)
    if splash:
        for i in range(count):
            samples[i] *= min(1, i / 160) * min(1, (count - 1 - i) / 300)
    else:
        # Crossfade a cyclic overlap, preserving a continuous loop boundary.
        overlap = RATE // 10
        for i in range(overlap):
            alpha = i / overlap
            samples[count - overlap + i] = samples[count - overlap + i] * (1 - alpha) + samples[i] * alpha
        samples = samples[overlap:]
    pcm = array("h", (round(max(-0.95, min(0.95, value)) * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def main():
    output = ROOT / "assets/audio"
    output.mkdir(parents=True, exist_ok=True)
    for name, data in [("S_Stream.wav", liquid(4.1, 1000)), ("S_Splash.wav", liquid(0.8, 1001, True))]:
        with wave.open(str(output / name), "wb") as sound:
            sound.setnchannels(1)
            sound.setsampwidth(2)
            sound.setframerate(RATE)
            sound.writeframes(data)
        print(f"Generated {name}: original mono 48 kHz PCM")


if __name__ == "__main__":
    main()
