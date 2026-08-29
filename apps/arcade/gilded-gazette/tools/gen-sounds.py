#!/usr/bin/env python3
"""The train's voice, synthesised rather than recorded.

    python3 tools/gen-sounds.py

Writes 16-bit mono WAVs into godot/assets/audio, off a fixed seed, so regenerating
produces byte-identical files and the repository does not grow a new copy of the same
noise every time somebody runs it.

A night train needs a dozen sounds, none of them heard closely. Licensed samples for
that are a folder of megabytes in LFS, an attribution file and a licence to re-check
at every publish; these are kilobytes, ours, and tuned by editing the number.

The ear is unfussy about texture down here and very fussy about envelope -- a door
reads as a door because the creak stops dead against the jamb -- so the shaping is
where the detail is and the source is almost always noise.
"""

import math
import os
import random
import struct
import wave

RATE = 22050

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "audio")

# Written down rather than randomised, so two runs of this file produce the same
# bytes. A generator that regenerated differently every time would be a diff on every
# checkout and a re-import of every sound.
SEED = 0x5EED_50


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def low_pass(samples, cutoff_hz):
    """One-pole. Everything here is heard through a carriage floor, where the
    difference between six and twenty-four decibels an octave is not audible."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / RATE)
    out = []
    held = 0.0
    for s in samples:
        held += a * (s - held)
        out.append(held)
    return out


def high_pass(samples, cutoff_hz):
    return [s - h for s, h in zip(samples, low_pass(samples, cutoff_hz))]


def resonate(samples, hz, q):
    """A two-pole ring at [hz]. What turns a noise burst into a thing with a body."""
    w = 2.0 * math.pi * hz / RATE
    r = math.exp(-w / (2.0 * q))
    a1 = 2.0 * r * math.cos(w)
    a2 = -r * r
    out = []
    y1 = y2 = 0.0
    for s in samples:
        y = s + a1 * y1 + a2 * y2
        out.append(y)
        y2, y1 = y1, y
    return out


def envelope(samples, attack_s, decay_s, curve=2.0):
    """Struck: up fast, then down a power curve. Linear decay is the sound of a fade
    rather than of something stopping."""
    n = len(samples)
    attack = max(1, int(attack_s * RATE))
    decay = max(1, int(decay_s * RATE))
    out = []
    for i, s in enumerate(samples):
        if i < attack:
            gain = i / attack
        else:
            through = min(1.0, (i - attack) / decay)
            gain = (1.0 - through) ** curve
        out.append(s * gain)
    return out


def seamless(samples, blend_s=0.25):
    """Folds the tail over the head so the join has no seam. A loop that clicks is
    heard as a fault in the game rather than in the file: the lamps seem to tick."""
    blend = min(int(blend_s * RATE), len(samples) // 2)
    out = list(samples[:-blend])
    for i in range(blend):
        through = i / blend
        head = samples[i]
        tail = samples[len(samples) - blend + i]
        out[i] = head * through + tail * (1.0 - through)
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def normalise(samples, peak=0.85):
    loudest = max(abs(s) for s in samples) or 1.0
    return [s * peak / loudest for s in samples]


def write(name, samples):
    path = os.path.join(OUT, name + ".wav")
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)
    print("%-14s %5.2fs  %6d bytes" % (name, len(samples) / RATE, len(frames)))


# --- the sounds -------------------------------------------------------------

def carriage_rumble(rng):
    """Bogies under the floor. Heard for the whole run, so two near-identical low tones
    beat against each other rather than settling into a hum."""
    n = int(3.0 * RATE)
    body = low_pass(noise(n, rng), 90.0)
    body = low_pass(body, 140.0)
    rail = [
        0.35 * math.sin(2.0 * math.pi * 41.0 * i / RATE)
        + 0.28 * math.sin(2.0 * math.pi * 43.5 * i / RATE)
        for i in range(n)
    ]
    return seamless(normalise(mix([s * 3.0 for s in body], rail), 0.7), 0.5)


def rail_joints(rng):
    """The knock of the wheels over the fishplates, four to the loop. Its own loop
    rather than mixed into the rumble, so a saloon can ride quieter than a service
    car -- which is the actual difference between the two rooms."""
    n = int(2.4 * RATE)
    out = [0.0] * n
    for knock in range(4):
        at = int((knock + 0.12) * n / 4)
        hit = envelope(noise(int(0.09 * RATE), rng), 0.001, 0.085, 3.0)
        hit = resonate(hit, 120.0 + knock * 7.0, 9.0)
        for i, s in enumerate(hit):
            if at + i < n:
                out[at + i] += s * (0.8 if knock % 2 else 1.0)
    return seamless(normalise(low_pass(out, 900.0), 0.8), 0.3)


def gas_hiss(rng):
    """A lamp burning. Almost nothing, and its absence is loud."""
    n = int(2.0 * RATE)
    breath = high_pass(noise(n, rng), 1800.0)
    breath = low_pass(breath, 6000.0)
    flame = resonate(noise(n, rng), 430.0, 4.0)
    return seamless(normalise(mix(breath, [s * 0.08 for s in flame]), 0.45), 0.4)


def footstep(rng, hz, name):
    """Board, not stone: the click is the heel and the ring under it is the carriage.
    Two of them, because the ear picks up a repeat long before it picks up a sound."""
    n = int(0.22 * RATE)
    heel = envelope(high_pass(noise(n, rng), 2200.0), 0.0005, 0.045, 3.0)
    board = envelope(resonate(noise(n, rng), hz, 12.0), 0.001, 0.16, 2.4)
    return name, normalise(mix([s * 0.6 for s in heel], board), 0.7)


def door_open(rng):
    """The hinge, which is the whole sound. A creak at one pitch is a tone; what makes
    it a hinge is that it climbs as the leaf goes round and gives out."""
    n = int(0.62 * RATE)
    source = noise(n, rng)
    out = []
    y1 = y2 = 0.0
    for i, s in enumerate(source):
        through = i / n
        hz = 300.0 + 520.0 * through
        w = 2.0 * math.pi * hz / RATE
        r = math.exp(-w / (2.0 * 26.0))
        y = s + 2.0 * r * math.cos(w) * y1 - r * r * y2
        y2, y1 = y1, y
        out.append(y)
    creak = envelope(out, 0.06, 0.5, 1.6)
    latch = [0.0] * n
    click = envelope(high_pass(noise(int(0.03 * RATE), rng), 3000.0), 0.0004, 0.026, 3.0)
    for i, s in enumerate(click):
        latch[i] += s
    return normalise(mix(creak, [s * 0.5 for s in latch]), 0.6)


def door_shut(rng):
    """Wood against the jamb, and the catch a moment behind it."""
    n = int(0.34 * RATE)
    thud = envelope(resonate(noise(n, rng), 155.0, 7.0), 0.001, 0.2, 2.6)
    catch = [0.0] * n
    click = envelope(high_pass(noise(int(0.04 * RATE), rng), 2600.0), 0.0004, 0.03, 3.0)
    at = int(0.05 * RATE)
    for i, s in enumerate(click):
        catch[at + i] += s
    return normalise(mix(thud, [s * 0.45 for s in catch]), 0.8)


def door_locked(rng):
    """Two pulls on a handle that does not give. Heard rather than silent, because a
    locked door that says nothing is one the player thinks they failed to reach."""
    n = int(0.44 * RATE)
    out = [0.0] * n
    for i, at_s in enumerate((0.0, 0.17)):
        at = int(at_s * RATE)
        rattle = envelope(noise(int(0.08 * RATE), rng), 0.001, 0.07, 3.0)
        rattle = resonate(rattle, 620.0 + i * 90.0, 14.0)
        for j, s in enumerate(rattle):
            if at + j < n:
                out[at + j] += s
    return normalise(high_pass(out, 300.0), 0.7)


def paper(rng):
    """A sheet taken off the wall and turned over."""
    n = int(0.5 * RATE)
    out = [0.0] * n
    for at_s, length in ((0.0, 0.2), (0.16, 0.16), (0.3, 0.18)):
        at = int(at_s * RATE)
        crackle = envelope(high_pass(noise(int(length * RATE), rng), 2400.0), 0.01, length, 1.4)
        for j, s in enumerate(crackle):
            if at + j < n:
                out[at + j] += s * rng.uniform(0.6, 1.0)
    return normalise(out, 0.55)


def cushion(rng):
    """Getting down onto a bench: fabric giving, then the frame taking the weight."""
    n = int(0.5 * RATE)
    fabric = envelope(high_pass(noise(n, rng), 1400.0), 0.02, 0.34, 1.5)
    frame = envelope(resonate(noise(n, rng), 118.0, 8.0), 0.03, 0.3, 2.0)
    return normalise(mix([s * 0.5 for s in fabric], frame), 0.5)


def rising(rng):
    """And off it again: the frame lets go before the fabric does."""
    n = int(0.42 * RATE)
    frame = envelope(resonate(noise(n, rng), 132.0, 9.0), 0.005, 0.16, 2.6)
    fabric = envelope(high_pass(noise(n, rng), 1600.0), 0.05, 0.3, 1.3)
    return normalise(mix(frame, [s * 0.45 for s in fabric]), 0.5)


def verdict(rng, hz, decay, detune, name):
    """A struck bell, for the moment the envelope is opened. The same strike twice:
    right is in tune with itself, wrong has a crack in it -- partials beating slowly
    against each other, which nobody has to be told the meaning of."""
    n = int(decay * 1.2 * RATE)
    struck = noise(int(0.006 * RATE), rng) + [0.0] * (n - int(0.006 * RATE))
    body = []
    for partial, weight in ((1.0, 1.0), (2.01, 0.5), (2.98, 0.28), (4.16, 0.14)):
        rung = resonate(struck, hz * partial * detune ** partial, 340.0 * partial)
        body.append([s * weight for s in rung])
    return name, normalise(envelope(mix(*body), 0.001, decay, 1.4), 0.7)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(SEED)
    write("carriage_rumble", carriage_rumble(rng))
    write("rail_joints", rail_joints(rng))
    write("gas_hiss", gas_hiss(rng))
    for hz, name in ((196.0, "footstep_a"), (233.0, "footstep_b")):
        step_name, samples = footstep(rng, hz, name)
        write(step_name, samples)
    write("door_open", door_open(rng))
    write("door_shut", door_shut(rng))
    write("door_locked", door_locked(rng))
    write("paper", paper(rng))
    write("sit", cushion(rng))
    write("rise", rising(rng))
    for hz, decay, detune, name in (
        (392.0, 2.4, 1.0, "verdict_right"),
        (233.0, 2.0, 1.006, "verdict_wrong"),
    ):
        bell_name, samples = verdict(rng, hz, decay, detune, name)
        write(bell_name, samples)


if __name__ == "__main__":
    main()
