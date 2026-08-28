#!/usr/bin/env python3
"""Stripe-density verification for the green wallrun walls.

Counts how many distinct stripe-width transitions occur across the striped wall
surface in a verification screenshot:

  - green mask sampled every 2 px: g > r+25 and g > b+10
  - the 12 columns with the most green pixels are taken as the near/visible
    wall face; for each, transitions are counted across its green vertical
    span (that strip crosses the horizontal caution stripes)
  - reported: median and max transition count, plus implied stripe-band count
    (transitions / 2)

A second mode (--ab) counts the same metric on the controlled close-up pair
(same camera, stripe_freq 12 vs 34).

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
N_COLS = 12


def near_wall_metric(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    wl = w // STEP
    hl = h // STEP
    m = []
    for x in range(wl):
        col = []
        for y in range(hl):
            r, g, b = px[x * STEP, y * STEP]
            col.append(1 if (g > r + THR and g > b + 10) else 0)
        m.append(col)
    totals = [sum(c) for c in m]
    best_cols = sorted(range(wl), key=lambda x: -totals[x])[:N_COLS]
    trans = []
    for x in best_cols:
        col = m[x]
        ys = [y for y in range(hl) if col[y]]
        if not ys:
            continue
        sub = col[min(ys):max(ys) + 1]
        t = 0
        prev = 0
        for v in sub:
            if v != prev:
                t += 1
            prev = v
        trans.append(t)
    if not trans:
        return (0, 0)
    med = statistics.median(trans)
    return (int(med), (int(med) + 1) // 2)


def main():
    shots = ["01_spawn_facing_room", "02_platform_looking_back", "03_wallrun_approach"]
    if sys.argv[1] == "--ab":
        a = near_wall_metric(sys.argv[2])
        b = near_wall_metric(sys.argv[3])
        print("close-up A/B (transitions, stripe-bands):")
        print("  freq12 (before):  %d / %d" % (a[0], a[1]))
        print("  freq34 (fixed):   %d / %d" % (b[0], b[1]))
        return
    before_dir, after_dir = sys.argv[1], sys.argv[2]
    print("%-24s %-20s %s" % ("screenshot", "BEFORE trans/bands", "AFTER trans/bands"))
    for shot in shots:
        b = near_wall_metric(os.path.join(before_dir, shot + ".png"))
        a = near_wall_metric(os.path.join(after_dir, shot + ".png"))
        print("%-24s %10d / %-5d %10d / %d" % (shot, b[0], b[1], a[0], a[1]))


if __name__ == "__main__":
    main()