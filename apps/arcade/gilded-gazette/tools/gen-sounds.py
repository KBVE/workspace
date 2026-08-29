#!/usr/bin/env python3
"""The train's voice, synthesised rather than recorded.

    python3 tools/gen-sounds.py

Writes 16-bit mono WAVs into godot/assets/audio. Nothing here is sampled from
anywhere: every sound is a few hundred lines of arithmetic over a fixed seed, so
regenerating produces byte-identical files and the repository does not grow a new
copy of the same noise each time somebody runs it.

Why generate at all. A murder mystery on a night train needs perhaps eight sounds,
none of them heard closely: bogies under the floor, gas in the lamps, a door on its
hinge, feet on carriage board. Licensed samples for that are a folder of megabytes in
Git LFS, an attribution file, and a licence to re-check every time the game is
published. These are kilobytes, ours, and tuned by editing the number rather than by
finding another recording.

The ear is unfussy about texture down here and very fussy about envelope. What makes a
door read as a door is the creak rising and stopping dead against the jamb; what makes
a footstep read as board rather than stone is a short body resonance under the click.
So the shaping is where the detail is, and the source is almost always noise.
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
    """One-pole, which is all the shaping any of this needs.

    A steeper filter would be a better filter and a worse tool: everything here is
    heard through a carriage floor or over an engine, and the difference between six
    and twenty-four decibels an octave is not audible at that distance.
    """
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
    """Struck: up fast, then down as a power curve rather than a straight line.

    Linear decay is the sound of a fade, not of something stopping. The power is what
    makes a footstep land instead of being turned down.
    """
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
    """Folds the tail back over the head so a loop has no seam at the join.

    A loop that clicks is the one flaw nobody stops hearing, and it is heard as a fault
    in the game rather than in the file: the lamps are what seem to be ticking.
    """
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
    """Bogies under the floor: everything below the voice, and nothing above it.

    Heard for the whole run, so it has to survive being heard for the whole run. The
    beat between two near-identical low tones is what keeps it from settling into a
    hum the ear stops registering and starts resenting.
    """
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
    """The knock of the wheels over the fishplates, four to the loop.

    Rail was laid in lengths and the gap between them is what a train is heard on. Kept
    as its own loop rather than mixed into the rumble so it can be quieter in a saloon
    than in the guard's van, which is the actual difference between the two rooms.
    """
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
    """Board, not stone. The click is the heel and the ring under it is the carriage.

    Two of them, alternating, because a walk made of one sample is a limp: the ear
    picks up the repeat long before it picks up the sound.
    """
    n = int(0.22 * RATE)
    heel = envelope(high_pass(noise(n, rng), 2200.0), 0.0005, 0.045, 3.0)
    board = envelope(resonate(noise(n, rng), hz, 12.0), 0.001, 0.16, 2.4)
    return name, normalise(mix([s * 0.6 for s in heel], board), 0.7)


def door_open(rng):
    """The hinge, which is the whole sound: a rising complaint that stops.

    Swept rather than static. A creak at one pitch is a tone; what makes it a hinge is
    that it climbs as the leaf goes round and gives out before it gets anywhere.
    """
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
    """Two pulls on a handle that does not give.

    Reported rather than silent, for the same reason [SDoor] reports it: a locked door
    that says nothing is indistinguishable from one the player failed to reach.
    """
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


if __name__ == "__main__":
    main()
