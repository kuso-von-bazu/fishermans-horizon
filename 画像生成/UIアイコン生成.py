#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""#235/#236: UIの小アイコンを Pillow で幾何的に描いて生成する。

「⚙」「?」などの記号はフォントに字形が無い環境で豆腐(文字化け)になるため、
ボタンの中身をテキストではなく画像にする。クリーチャー等の絵とは違い
単純な図形なので、画像生成AIは使わずここで直接描く。

出力: assets/images/ui_gear.png / ui_help.png (128x128 RGBA)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "images")
OUT = os.path.normpath(OUT)
SS = 4          # スーパーサンプリング倍率(縁を滑らかにする)
SIZE = 128
FG = (222, 238, 250, 255)


def _canvas():
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))


def _finish(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def gear():
    """歯車。外周に台形の歯を並べ、中央を丸く抜く。"""
    img = _canvas()
    d = ImageDraw.Draw(img)
    c = SIZE * SS / 2.0
    teeth = 8
    r_out = SIZE * SS * 0.46      # 歯の先端
    r_root = SIZE * SS * 0.36     # 歯の付け根(=本体の円)
    half = math.pi / teeth * 0.36  # 歯の半幅(ラジアン)

    for i in range(teeth):
        a = i * 2.0 * math.pi / teeth
        pts = []
        # 付け根(広い)→先端(狭い)の台形にすると歯車らしくなる
        for sign, r, w in ((-1, r_root, half * 1.7), (-1, r_out, half),
                           (1, r_out, half), (1, r_root, half * 1.7)):
            ang = a + sign * w
            pts.append((c + math.cos(ang) * r, c + math.sin(ang) * r))
        d.polygon(pts, fill=FG)

    d.ellipse([c - r_root, c - r_root, c + r_root, c + r_root], fill=FG)
    # 中央の穴(完全な透明で抜く)
    r_in = SIZE * SS * 0.155
    d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=(0, 0, 0, 0))
    _finish(img, "ui_gear.png")


def help_mark():
    """はてなマーク。円弧+縦棒+点で描く(フォント非依存)。"""
    img = _canvas()
    d = ImageDraw.Draw(img)
    c = SIZE * SS / 2.0
    w = int(SIZE * SS * 0.115)          # 線の太さ
    r = SIZE * SS * 0.215               # 上部の円弧の半径
    cy = c - SIZE * SS * 0.20           # 円弧の中心
    # 上のフック(左下から時計回りに約220度)。PILの角度は3時方向から時計回り
    # 終端を円の真下(90度)にすると、そのまま縦棒へ継ぎ目なく繋がる
    end_deg = 90.0
    d.arc([c - r, cy - r, c + r, cy + r], start=160, end=360 + end_deg, fill=FG, width=w)
    ey = cy + r
    d.line([(c, ey), (c, c + SIZE * SS * 0.17)], fill=FG, width=w)
    # 下の点
    dot = SIZE * SS * 0.072
    dy = c + SIZE * SS * 0.30
    d.ellipse([c - dot, dy - dot, c + dot, dy + dot], fill=FG)
    _finish(img, "ui_help.png")


if __name__ == "__main__":
    gear()
    help_mark()
    print("done")
