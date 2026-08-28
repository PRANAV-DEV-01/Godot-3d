#!/usr/bin/env python3
"""Striped-wall orientation + density verification.

Counts distinct stripe-width transitions across the striped wall surface by
detecting the green stripe LINES along a strip down the wall:

  - near-wall columns are chosen as the columns with the most strong-green
    samples (g > r+25 and g > b+10) OR the most green-channel local maxima
  - for each chosen column, stripe lines are detected as local maxima of the
    green channel along y (peaks separated by >= MIN_SEP samples, prominence
    >= PROMINENCE above the surrounding troughs), which survives antialiasing
    of thin stripes at distance
  - the number of stripe lines crossed by the strip = distinct stripe-width
    transitions (each line has an entering and leaving edge)
  - reported: median and max line counts across the chosen columns

Usage:
  python3 scripts/tools/stripe_check.py <before_dir> <after_dir>
  python3 scripts/tools/stripe_check.py --ab <freq12.png> <freq34.png>
"""
import os
import statistics
import sys

from PIL import Image

STEP = 2
THR = 25
PROMINENCE = 18
MIN_SEP = 5
N_COLS = 12


def green_samples(px, x, y0, y1):
    out = []
    for y in range(y0, y1):
        r, g, b = px[x * STEP, y * STEP]
        out.append(g if (g > r + THR and g > b + 10) else 0)
    return out


def count_peaks(vals):
    """Count stripe lines = local maxima of the green channel.

    A peak is a sample that is the max of its +-2 window, is >= PROMINENCE
    above the min in its +-6 window (so troughs are dark), and is separated
    from the previous peak by >= MIN_SEP samples.
    """
    n = len(vals)
    peaks = 0
    last = -1
    for i in range(n):
        if vals[i] == 0:
            continue
        lo = max(0, i - 2)
        hi = min(n, i + 3)
        if vals[i] != max(vals[lo:hi]):
            continue
        wlo = max(0, i - 6)
        whi = min(n, i + 7)
        if vals[i] - min(vals[wlo:whi]) < PROMINENCE:
            continue
        if last >= 0 and i - last < MIN_SEP:
            last = i
            continue
        peaks += 1
        last = i
    return peaks


def near_wall_metric(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    wl = w // STEP
    hl = h // STEP
    scores = []
    for x in range(wl):
        y0 = 0
        y1 = hl
        # roughly limit to the column's likely wall span later; for now full column
        g = px[x * STEP, hl // 2]
        r = g[0]
        base = g[1]
        strong = 0
        for y in range(hl):
            rr, gg, bb = px[x * STEP, y * STEP]
            if gg > rr + THR and gg > bb + 10:
                strong += 1
        scores.append(strong)
    best_cols = sorted(range(wl), key=lambda x: -scores[x])[:N_COLS]
    counts = []
    for x in best_cols:
        vals = green_samples(px, x, 0, hl)
        c = count_peaks(vals)
        counts.append(c)
    if not counts:
        return (0, 0)
    med = statistics.median(counts)
    return (int(med), int(max(counts)))


def main():
    shots = ["01_spawn_facing_room", "02_platform_looking_back", "03_wallrun_approach", "04_corridor_down_length"]
    if sys.argv[1] == "--ab":
        a = near_wall_metric(sys.argv[2])
        b = near_wall_metric(sys.argv[3])
        print("close-up A/B (median stripe-lines, max):")
        print("  freq12 (before):  %d / %d" % (a[0], a[1]))
        print("  freq34 (fixed):   %d / %d" % (b[0], b[1]))
        return
    before_dir, after_dir = sys.argv[1], sys.argv[2]
    print("%-26s %-22s %s" % ("screenshot", "BEFORE lines(med/max)", "AFTER lines(med/max)"))
    for shot in shots:
        bpath = os.path.join(before_dir, shot + ".png")
        a = near_wall_metric(os.path.join(after_dir, shot + ".png"))
        if os.path.exists(bpath):
            b = near_wall_metric(bpath)
            print("%-26s %11d / %-5d %9d / %d" % (shot, b[0], b[1], a[0], a[1]))
        else:
            print("%-26s   (new shot)                %9d / %d" % (shot, a[0], a[1]))


if __name__ == "__main__":
    main()