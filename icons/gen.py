#!/usr/bin/env python3
"""Generate launcher icons: dark blue rounded square with an orange temperature
curve dipping below a zero line (blue part) and small blue precipitation bars."""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SIZES = [86, 108, 128, 172]
SS = 4  # supersampling


def make(size):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(s * 0.22)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=(26, 46, 74, 255))

    # zero line
    zero = s * 0.60
    d.line([(s * 0.10, zero), (s * 0.90, zero)], fill=(255, 255, 255, 90), width=max(2, int(s * 0.012)))

    # precipitation bars
    bw = s * 0.045
    for i, h in enumerate([0.06, 0.12, 0.09, 0.04, 0.0, 0.0, 0.07, 0.13, 0.05]):
        x = s * 0.14 + i * s * 0.085
        if h > 0:
            d.rectangle([x, s * 0.86 - h * s, x + bw, s * 0.86], fill=(80, 150, 255, 255))

    # temperature curve: points (x, y) in unit coords
    pts = [(0.10, 0.42), (0.22, 0.36), (0.34, 0.44), (0.46, 0.56), (0.56, 0.68),
           (0.66, 0.70), (0.76, 0.58), (0.90, 0.48)]
    pts = [(x * s, y * s) for x, y in pts]
    # filled area under curve: above zero orange, below zero blue
    poly_top = pts + [(s * 0.90, zero), (s * 0.10, zero)]
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon(poly_top, fill=255)
    orange = Image.new("RGBA", (s, s), (255, 170, 60, 170))
    blue = Image.new("RGBA", (s, s), (90, 170, 255, 190))
    above = Image.new("L", (s, s), 0)
    ImageDraw.Draw(above).rectangle([0, 0, s, zero], fill=255)
    below = Image.new("L", (s, s), 0)
    ImageDraw.Draw(below).rectangle([0, zero, s, s], fill=255)
    m1 = Image.new("L", (s, s), 0)
    m1.paste(mask, (0, 0), above)
    m2 = Image.new("L", (s, s), 0)
    m2.paste(mask, (0, 0), below)
    img.paste(orange, (0, 0), m1)
    img.paste(blue, (0, 0), m2)
    w = max(3, int(s * 0.03))
    for a, b in zip(pts, pts[1:]):
        col = (255, 190, 80, 255) if (a[1] + b[1]) / 2 < zero else (120, 190, 255, 255)
        d.line([a, b], fill=col, width=w)
    return img.resize((size, size), Image.LANCZOS)


for sz in SIZES:
    out = os.path.join(HERE, f"{sz}x{sz}")
    os.makedirs(out, exist_ok=True)
    img = make(sz).quantize(colors=64, method=Image.Quantize.FASTOCTREE)
    img.save(os.path.join(out, "harbour-weatherchart.png"), optimize=True)
    print("wrote", sz)
