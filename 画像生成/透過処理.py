#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Codex image_gen の出力(近白/薄いチェッカー背景・実アルファ無し)を透過PNGに変換する後処理。

縁の背景画素を種に flood fill して「外周とつながった近白領域」だけを透明化するため、
被写体内部の白いハイライトは残る。最後に被写体の外接矩形でトリミングし最大512pxへ縮小。

使い方:
  python 透過処理.py                      # assets/images の全PNGを処理(透過済みは内容で判定)
  python 透過処理.py fish_grouper.png ...  # 指定ファイルのみ
"""
import os, sys
from collections import deque
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IMGDIR = os.path.normpath(os.path.join(HERE, "..", "assets", "images"))
MAXSIZE = 512
WHITE_MIN = 232      # 近白とみなす最小チャンネル値
GRAY_SPREAD = 16     # max-min がこの範囲内なら無彩色(白/灰)


def is_bgish(px):
    r, g, b = int(px[0]), int(px[1]), int(px[2])
    return min(r, g, b) >= WHITE_MIN and (max(r, g, b) - min(r, g, b)) <= GRAY_SPREAD


def process(path):
    im = Image.open(path).convert("RGBA")
    arr = np.array(im)
    h, w = arr.shape[:2]
    rgb = arr[:, :, :3].astype(np.int16)
    mn = rgb.min(axis=2)
    mx = rgb.max(axis=2)
    bgish = (mn >= WHITE_MIN) & ((mx - mn) <= GRAY_SPREAD)

    visited = np.zeros((h, w), dtype=bool)
    q = deque()
    # 外周の背景画素を種に
    for x in range(w):
        for y in (0, h - 1):
            if bgish[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bgish[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and bgish[ny, nx]:
                visited[ny, nx] = True; q.append((ny, nx))

    arr[visited, 3] = 0  # 外周連結の近白を透明化
    # 半透明の縁取り軽減: 透明境界に隣接する薄色を少し落とす(簡易)

    out = Image.fromarray(arr, "RGBA")
    # 被写体の外接矩形でトリミング
    alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 8)
    if len(xs) and len(ys):
        pad = 8
        x0 = max(int(xs.min()) - pad, 0); x1 = min(int(xs.max()) + pad, w)
        y0 = max(int(ys.min()) - pad, 0); y1 = min(int(ys.max()) + pad, h)
        out = out.crop((x0, y0, x1, y1))
    # 縮小
    if max(out.size) > MAXSIZE:
        s = MAXSIZE / max(out.size)
        out = out.resize((max(1, int(out.size[0] * s)), max(1, int(out.size[1] * s))), Image.LANCZOS)
    out.save(path)
    return out.size


def already_transparent(path):
    try:
        im = Image.open(path)
        if im.mode != "RGBA":
            return False
        a = np.array(im)[:, :, 3]
        return bool((a == 0).any())
    except Exception:
        return False


def main():
    only = [a for a in sys.argv[1:]]
    files = only if only else sorted(f for f in os.listdir(IMGDIR) if f.lower().endswith(".png"))
    for f in files:
        p = os.path.join(IMGDIR, f)
        if not os.path.isfile(p):
            print("skip(なし):", f); continue
        if not only and already_transparent(p):
            print("skip(透過済):", f); continue
        try:
            sz = process(p)
            print("透過OK:", f, sz)
        except Exception as e:
            print("失敗:", f, e)


if __name__ == "__main__":
    main()
