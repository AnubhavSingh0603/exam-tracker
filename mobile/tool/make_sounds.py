"""Synthesises JobSummit's sound effects (no samples, so no licences) into
android/app/src/main/res/raw. Short, soft, with fades so nothing clicks.

Run from mobile/:  python tool/make_sounds.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / "android/app/src/main/res/raw"


def tone(freq, dur, *, start=0.0, vol=0.35, decay=6.0, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)), glide=None):
    """A bell-ish note: a few harmonics with an exponential decay. glide = end freq."""
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if glide is None else freq + (glide - freq) * (t / dur)
        phase += 2 * math.pi * f / RATE
        env = math.exp(-decay * t) * min(1.0, t / 0.004)  # 4 ms attack: no click
        s = sum(a * math.sin(phase * h) for h, a in harmonics)
        out.append(vol * env * s)
    return start, out


def noise(dur, *, vol=0.2, lowpass_from=0.15, lowpass_to=0.02):
    """Soft filtered noise (a swoosh): one-pole low-pass sweeping its cutoff."""
    n = int(dur * RATE)
    out, y = [], 0.0
    rnd = random.Random(7)
    for i in range(n):
        t = i / n
        a = lowpass_from + (lowpass_to - lowpass_from) * t
        y += a * (rnd.uniform(-1, 1) - y)
        env = math.sin(math.pi * t) ** 1.5
        out.append(vol * 4 * env * y)
    return 0.0, out


def mix(parts, total):
    buf = [0.0] * int(total * RATE)
    for start, samples in parts:
        off = int(start * RATE)
        for i, s in enumerate(samples):
            if off + i < len(buf):
                buf[off + i] += s
    # fade the last 15 ms, normalise to a gentle peak
    fade = int(0.015 * RATE)
    for i in range(fade):
        buf[-1 - i] *= i / fade
    peak = max(1e-9, max(abs(s) for s in buf))
    return [s * (0.55 / peak) for s in buf]


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
    print(f"{name}.wav {len(samples) / RATE * 1000:.0f} ms")


def at(start, part):
    return (start, part[1])


C5, E5, G5, C6, E6, G6, C7 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0

# +XP: a quick rising "pop" with a sparkle on top.
write("fx_pop", mix([tone(620, 0.12, glide=1240, decay=18, vol=0.4), at(0.05, tone(C7, 0.12, decay=25, vol=0.12))], 0.2))

# Applied: a bright rising major arpeggio.
write("fx_success", mix([at(0.0, tone(C6, 0.35, decay=7)), at(0.08, tone(E6, 0.35, decay=7)),
                         at(0.16, tone(G6, 0.45, decay=6)), at(0.16, tone(C7, 0.45, decay=8, vol=0.12))], 0.62))

# Level up: arpeggio climbing into a held chord.
write("fx_levelup", mix([at(0.00, tone(C5, 0.25, decay=8)), at(0.10, tone(E5, 0.25, decay=8)),
                         at(0.20, tone(G5, 0.25, decay=8)), at(0.30, tone(C6, 0.9, decay=3.2)),
                         at(0.30, tone(E6, 0.9, decay=3.5, vol=0.25)), at(0.30, tone(G6, 0.9, decay=3.8, vol=0.2)),
                         at(0.30, tone(C7, 0.6, decay=6, vol=0.08))], 1.25))

# Tap / copy / stage change: a tiny wooden click.
write("fx_tap", mix([tone(1800, 0.03, decay=140, vol=0.5, harmonics=((1, 1.0), (2.7, 0.3)))], 0.05))

# Not for me / archive: a soft swoosh.
write("fx_swoosh", mix([noise(0.24)], 0.26))

# Something failed: a gentle falling two-tone (not an alarm).
write("fx_soft_error", mix([at(0.0, tone(392.0, 0.18, decay=9, vol=0.35)), at(0.13, tone(311.1, 0.25, decay=8, vol=0.35))], 0.42))

# Notification ping: two bell tones, clear but friendly.
write("fx_ping", mix([at(0.0, tone(1318.5, 0.5, decay=6)), at(0.11, tone(1975.5, 0.6, decay=5, vol=0.3))], 0.75))
