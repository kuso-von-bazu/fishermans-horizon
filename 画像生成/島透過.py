#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""#278(提案2): 島の生成画像(マゼンタ背景)を透過PNGにする。

透過処理.py は「近白の背景」を抜くが、島には雪原の島(果ての島・北の孤島)があり、
白を抜くと島そのものが消える。そのため島だけは背景をマゼンタで生成し、
ここでマゼンタを抜く。にじみ(縁のマゼンタ寄りの画素)も色かぶりを取り除く。

使い方: python 島透過.py island_4.png [...]   (無指定なら island_*.png 全部)
"""
import os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IMGDIR = os.path.normpath(os.path.join(HERE, "..", "assets", "images"))
MAXSIZE = 512


def trim(im, path):
    """すでに透過済みの絵を、被写体の外接矩形で切り抜いて最大512pxへ縮める。"""
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)
    if max(im.size) > MAXSIZE:
        s = MAXSIZE / max(im.size)
        im = im.resize((max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s))), Image.LANCZOS)
    im.save(path)
    print("切り抜き(透過済み):", os.path.basename(path), im.size)


def process(path):
    im = Image.open(path).convert("RGBA")
    arr = np.array(im).astype(np.int16)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    # マゼンタ = 赤と青が高く緑が低い。純色から多少ずれても拾えるようにゆるく判定する
    mag = (r > 120) & (b > 120) & (g + 60 < np.minimum(r, b))
    if mag.mean() < 0.02:
        # マゼンタで描いてくれなかった場合。すでにアルファが入っている絵なら
        # (四隅が透明なら)切り抜き・縮小だけ行う。そうでなければ手を付けない。
        a0 = arr[:, :, 3]
        corners = [a0[0, 0], a0[0, -1], a0[-1, 0], a0[-1, -1]]
        if max(corners) == 0 and (a0 == 0).mean() > 0.15:
            trim(im, path)
        else:
            print("skip(マゼンタ背景が見つからない):", os.path.basename(path))
        return
    a = np.where(mag, 0, 255).astype(np.uint8)
    # 縁のにじみ: 残った画素のうち緑が極端に低いものは緑を持ち上げて色かぶりを消す
    edge = (~mag) & (g + 30 < np.minimum(r, b))
    g2 = g.copy()
    g2[edge] = np.minimum(r, b)[edge] - 30
    out = np.dstack([r, g2, b, a]).astype(np.uint8)
    im2 = Image.fromarray(out, "RGBA")
    bbox = im2.split()[3].getbbox()
    if bbox:
        im2 = im2.crop(bbox)
    if max(im2.size) > MAXSIZE:
        s = MAXSIZE / max(im2.size)
        im2 = im2.resize((max(1, int(im2.size[0] * s)), max(1, int(im2.size[1] * s))), Image.LANCZOS)
    im2.save(path)
    print("透過:", os.path.basename(path), im2.size)


only = [a for a in sys.argv[1:] if a.lower().endswith(".png")]
files = only if only else sorted(f for f in os.listdir(IMGDIR) if f.startswith("island_") and f.endswith(".png"))
for f in files:
    process(os.path.join(IMGDIR, f))
print("done")
