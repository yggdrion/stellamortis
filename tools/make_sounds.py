"""Synthesizes the sounds no CC0 pack had (PLAN §6 M14): sword swooshes, a crossbow twang, the
telegraph cue, embers, the portal hum and travel shimmer, the gravity well rumble, a jump pad
whoom, and ambience loops (wind for the keep and the Barrows, torch crackle). Standard library
only; the output is checked in, so run this only to change a sound:

    python tools/make_sounds.py

Writes 22.05 kHz mono 16-bit WAV files to game/assets/sounds/synth/. Fixed seeds, so the result
is the same on every run.
"""

import math
import random
import struct
import wave
from pathlib import Path

from _common import GAME

RATE = 22050
OUT = GAME / "assets" / "sounds" / "synth"


def write(name: str, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.9 / peak
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * gain * 32767)) for s in samples))
    print(path.relative_to(GAME.parent), f"{len(samples) / RATE:.2f} s")


def envelope(t: float, length: float, attack: float, release: float) -> float:
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


class Filter:
    """A state-variable filter: low, band and high pass from one cutoff and resonance."""

    def __init__(self) -> None:
        self.low = 0.0
        self.band = 0.0

    def step(self, x: float, cutoff: float, q: float = 0.7) -> tuple[float, float, float]:
        f = 2.0 * math.sin(math.pi * min(cutoff, RATE / 6) / RATE)
        self.low += f * self.band
        high = x - self.low - self.band / q
        self.band += f * high
        return self.low, self.band, high


def swoosh(seed: int, length: float, low: float, high: float) -> list[float]:
    """Noise through a band pass sweeping up then down: a blade cutting air."""
    rng = random.Random(seed)
    band = Filter()
    n = int(length * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        p = t / length
        cutoff = low + (high - low) * math.sin(math.pi * p) ** 1.5
        _, b, _ = band.step(rng.uniform(-1, 1), cutoff, 2.5)
        out.append(b * math.sin(math.pi * p) ** 2)
    return out


def twang(seed: int) -> list[float]:
    """Karplus-Strong string with a wooden knock: the crossbow's release."""
    rng = random.Random(seed)
    period = int(RATE / 110)
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(int(0.45 * RATE)):
        s = buf[i % period]
        buf[i % period] = 0.5 * (s + buf[(i + 1) % period]) * 0.996
        knock = math.exp(-i / 200) * rng.uniform(-1, 1) * 0.6
        out.append(s * math.exp(-i / (0.2 * RATE)) + knock)
    return out


def telegraph(seed: int, length: float, base: float) -> list[float]:
    """A low rising growl with breath: an enemy winding up."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    phase = 0.0
    for i in range(int(length * RATE)):
        t = i / RATE
        p = t / length
        freq = base * (1.0 + 0.6 * p)
        phase += 2 * math.pi * freq / RATE
        tone = math.sin(phase) * 0.6 + math.sin(phase * 2.01) * 0.25 + math.sin(phase * 0.5) * 0.3
        _, breath, _ = band.step(rng.uniform(-1, 1), 300 + 900 * p, 1.5)
        out.append((tone * 0.7 + breath * 0.8) * envelope(t, length, 0.08, 0.12) * (0.4 + 0.6 * p))
    return out


def ember(seed: int) -> list[float]:
    """A short fiery hiss with a crackle: an ember leaving the dead's hand."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    length = 0.35
    for i in range(int(length * RATE)):
        t = i / RATE
        _, _, high = band.step(rng.uniform(-1, 1), 2500 - 1500 * t / length, 0.8)
        crack = rng.uniform(-1, 1) if rng.random() < 0.004 else 0.0
        out.append((high * 0.6 + crack) * envelope(t, length, 0.01, 0.25))
    return out


def hum(seed: int, length: float, base: float, shimmer: float) -> list[float]:
    """A loopable low hum with a slow beat and airy shimmer: portals. Whole cycles, so it loops."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    for i in range(int(length * RATE)):
        t = i / RATE
        beat = 0.75 + 0.25 * math.sin(2 * math.pi * t * 2 / length)
        tone = math.sin(2 * math.pi * base * t) + 0.5 * math.sin(2 * math.pi * base * 1.5 * t)
        _, air, _ = band.step(rng.uniform(-1, 1), 1800, 3.0)
        out.append(tone * beat * 0.5 + air * shimmer)
    return crossfade_loop(out, 0.3)


def travel(seed: int) -> list[float]:
    """A rising shimmer with a low thump: stepping through a portal."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    length = 1.1
    for i in range(int(length * RATE)):
        t = i / RATE
        p = t / length
        _, b, _ = band.step(rng.uniform(-1, 1), 400 + 3500 * p, 4.0)
        thump = math.sin(2 * math.pi * 55 * t) * math.exp(-t * 6)
        out.append(b * envelope(t, length, 0.2, 0.4) + thump)
    return out


def rumble(seed: int, length: float) -> list[float]:
    """Deep filtered noise with a slow swell, loopable: the gravity well and the Warden rising."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    for i in range(int(length * RATE)):
        t = i / RATE
        low, _, _ = band.step(rng.uniform(-1, 1), 90, 1.2)
        swell = 0.7 + 0.3 * math.sin(2 * math.pi * t * 3 / length)
        out.append(low * swell + 0.3 * math.sin(2 * math.pi * 41 * t) * swell)
    return crossfade_loop(out, 0.4)


def whoom(seed: int) -> list[float]:
    """A falling-then-rising air rush: the jump pad's launch."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    length = 0.8
    for i in range(int(length * RATE)):
        t = i / RATE
        p = t / length
        _, b, _ = band.step(rng.uniform(-1, 1), 200 + 1400 * p * p, 1.8)
        out.append(b * envelope(t, length, 0.05, 0.4))
    return out


def wind(seed: int, length: float, cutoff: float, gusts: float) -> list[float]:
    """Loopable wind: low passed noise with slow gusts (whole cycles over the loop)."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    for i in range(int(length * RATE)):
        t = i / RATE
        gust = 0.55 + 0.45 * (
            0.6 * math.sin(2 * math.pi * t * 2 / length) + 0.4 * math.sin(2 * math.pi * t * 5 / length + 1)
        )
        _, b, _ = band.step(rng.uniform(-1, 1), cutoff * (0.6 + 0.8 * gust), 1.0 + gusts * gust)
        out.append(b * gust)
    return crossfade_loop(out, 0.5)


def crackle(seed: int, length: float) -> list[float]:
    """Loopable torch fire: a soft roar with random pops."""
    rng = random.Random(seed)
    band = Filter()
    out = []
    pops: list[tuple[int, float]] = []
    for i in range(int(length * RATE)):
        if rng.random() < 0.0009:
            pops.append((i, rng.uniform(0.3, 1.0)))
        low, _, _ = band.step(rng.uniform(-1, 1), 500, 0.8)
        pop = 0.0
        for start, size in pops[-6:]:
            age = i - start
            if age < 400:
                pop += rng.uniform(-1, 1) * size * math.exp(-age / 60)
        out.append(low * 0.5 + pop)
    return crossfade_loop(out, 0.2)


def crossfade_loop(samples: list[float], seconds: float) -> list[float]:
    """Fades the tail into the head, so the loop point doesn't click."""
    n = int(seconds * RATE)
    body = samples[: len(samples) - n]
    for i in range(n):
        w = i / n
        body[i] = body[i] * w + samples[len(samples) - n + i] * (1 - w)
    return body


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        write(f"swing_{i}", swoosh(10 + i, 0.32 + 0.04 * i, 500 + 80 * i, 2600 + 300 * i))
    write("swing_heavy", swoosh(20, 0.55, 250, 1500))
    write("swing_giant", swoosh(21, 0.8, 120, 900))
    write("twang", twang(30))
    write("telegraph", telegraph(40, 0.6, 70))
    write("telegraph_giant", telegraph(41, 0.9, 42))
    write("ember", ember(50))
    write("portal_hum", hum(60, 4.0, 82.5, 0.35))
    write("travel", travel(61))
    write("well", rumble(70, 4.0))
    write("whoom", whoom(80))
    write("wind_keep", wind(90, 12.0, 500, 1.0))
    write("wind_barrows", wind(91, 12.0, 320, 2.5))
    write("torch", crackle(100, 5.0))


if __name__ == "__main__":
    main()
