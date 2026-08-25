#!/usr/bin/env python3
"""Verify visual quality of Phase 2 screenshots.

Reads 3 verification PNGs, reports per-image statistics:
  - Average RGB, Std Dev RGB, Overall brightness std dev
  - Unique color count (sampled), near-gray pixel percentage
  - Brightness distribution (dark/mid/bright)

Usage:
    python3 verify_visuals.py [--label BEFORE|AFTER]
"""
import sys
import os
import statistics
from PIL import Image


SCREENSHOTS = [
    ("01_spawn_facing_room.png", "Spawn facing room"),
    ("02_platform_looking_back.png", "Platform looking back"),
    ("03_wallrun_approach.png", "Wall-run approach"),
]

# Default search paths: repo root, then screenshots dir
SEARCH_DIRS = [
    os.path.join(os.path.dirname(__file__), "..", ".."),
    os.path.join(os.path.dirname(__file__), ".."),
    ".",
]


def find_screenshot(name: str) -> str:
    for d in SEARCH_DIRS:
        path = os.path.join(d, name)
        if os.path.isfile(path):
            return os.path.abspath(path)
    return ""


def analyze(path: str) -> dict:
    img = Image.open(path).convert("RGB")
    w, h = img.size
    total = w * h
    pixels = list(img.getdata())

    r_vals = [p[0] for p in pixels]
    g_vals = [p[1] for p in pixels]
    b_vals = [p[2] for p in pixels]
    brightness = [(p[0] + p[1] + p[2]) / 3.0 for p in pixels]

    r_avg = statistics.mean(r_vals)
    g_avg = statistics.mean(g_vals)
    b_avg = statistics.mean(b_vals)
    r_std = statistics.stdev(r_vals) if len(r_vals) > 1 else 0
    g_std = statistics.stdev(g_vals) if len(g_vals) > 1 else 0
    b_std = statistics.stdev(b_vals) if len(b_vals) > 1 else 0
    br_std = statistics.stdev(brightness) if len(brightness) > 1 else 0

    gray_count = sum(1 for p in pixels if max(p) - min(p) < 15)
    gray_pct = gray_count / total * 100

    step = max(1, total // 5000)
    sampled = pixels[::step]
    unique = len(set(sampled))

    dark = sum(1 for b in brightness if b < 50) / total * 100
    mid = sum(1 for b in brightness if 50 <= b < 150) / total * 100
    bright = sum(1 for b in brightness if b >= 150) / total * 100

    mn = (min(r_vals), min(g_vals), min(b_vals))
    mx = (max(r_vals), max(g_vals), max(b_vals))

    return {
        "w": w, "h": h, "total": total,
        "r_avg": r_avg, "g_avg": g_avg, "b_avg": b_avg,
        "r_std": r_std, "g_std": g_std, "b_std": b_std,
        "br_std": br_std,
        "gray_pct": gray_pct, "unique": unique,
        "dark": dark, "mid": mid, "bright": bright,
        "min": mn, "max": mx,
    }


def print_report(label: str, results: list):
    print(f"\n{'=' * 72}")
    print(f"  {label}")
    print(f"{'=' * 72}")

    for fname, desc, stats in results:
        print(f"\n  [{desc}] {fname}")
        print(f"    Size:             {stats['w']}x{stats['h']} ({stats['total']} px)")
        print(f"    Avg RGB:          ({stats['r_avg']:.1f}, {stats['g_avg']:.1f}, {stats['b_avg']:.1f})")
        print(f"    Std RGB:          ({stats['r_std']:.1f}, {stats['g_std']:.1f}, {stats['b_std']:.1f})")
        print(f"    Brightness std:   {stats['br_std']:.1f}")
        print(f"    Min/Max RGB:      {stats['min']} / {stats['max']}")
        print(f"    Unique (5k):      {stats['unique']}")
        print(f"    Near-gray %:      {stats['gray_pct']:.1f}%")
        print(f"    Brightness:       dark={stats['dark']:.1f}%  mid={stats['mid']:.1f}%  bright={stats['bright']:.1f}%")


def print_comparison(before: list, after: list):
    print(f"\n{'=' * 72}")
    print(f"  SIDE-BY-SIDE COMPARISON")
    print(f"{'=' * 72}")
    print(f"  {'':30s} {'BEFORE':>16s}   {'AFTER':>16s}   {'Delta':>12s}")
    print(f"  {'-'*30} {'-'*16}   {'-'*16}   {'-'*12}")

    for i, (bname, bdesc, bs) in enumerate(before):
        _, _, af = after[i]
        print(f"\n  {bdesc}")
        for metric, bval, aval in [
            ("Avg R", bs["r_avg"], af["r_avg"]),
            ("Avg G", bs["g_avg"], af["g_avg"]),
            ("Avg B", bs["b_avg"], af["b_avg"]),
            ("Std (all)", bs["br_std"], af["br_std"]),
            ("Unique colors", bs["unique"], af["unique"]),
            ("Near-gray %", bs["gray_pct"], af["gray_pct"]),
        ]:
            delta = aval - bval
            sign = "+" if delta >= 0 else ""
            print(f"    {metric:28s} {bval:>15.1f}   {aval:>15.1f}   {sign}{delta:>10.1f}")


def main():
    label = "SCREENSHOT ANALYSIS"
    if len(sys.argv) > 2 and sys.argv[1] == "--label":
        label = sys.argv[2]

    results = []
    for fname, desc in SCREENSHOTS:
        path = find_screenshot(fname)
        if not path:
            print(f"  ERROR: {fname} not found")
            sys.exit(1)
        stats = analyze(path)
        results.append((fname, desc, stats))

    print_report(label, results)
    return results


if __name__ == "__main__":
    main()
