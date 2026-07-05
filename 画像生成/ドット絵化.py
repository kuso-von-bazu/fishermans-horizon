#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成済みの透過スプライトをドット絵化する(#26)。
縮小(長辺48px)+減色(32色)で assets/images/pixel/ に出力。
Godot側は texture_filter=NEAREST で拡大表示し、くっきりしたドット絵として描画する。"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "assets", "images"))
DST = os.path.join(SRC, "pixel")
os.makedirs(DST, exist_ok=True)
LONG = 48
# #81: 大型ボスは高精細(ドット数多め)
LONG_OVERRIDE = {"lord_leviathan.png": 128, "lord_hydra.png": 80, "lord_quetzal.png": 80}

for f in sorted(os.listdir(SRC)):
    if not f.lower().endswith(".png"):
        continue
    if f.startswith("title") or f.endswith("_source.png"):
        continue
    p = os.path.join(SRC, f)
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    s = LONG_OVERRIDE.get(f, LONG) / max(w, h)
    small = im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    # 減色(アルファ保持): RGBを32色にパレット化
    rgb = small.convert("RGB").quantize(colors=32, dither=Image.Dither.NONE).convert("RGB")
    out = Image.merge("RGBA", (*rgb.split(), small.split()[3]))
    # 半端なアルファを2値化(ドット絵らしく)
    a = out.split()[3].point(lambda v: 255 if v > 96 else 0)
    out.putalpha(a)
    out.save(os.path.join(DST, f))
    print("pixel:", f, out.size)
print("done")
