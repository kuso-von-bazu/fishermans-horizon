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
# #173: ケツァルコアトルもドット数・色数を増やして精細に(front/backも)
# #81再: ヒュドラ(80→180)とケツァル(140→180)をさらに高精細化(front/backも揃える)
LONG_OVERRIDE = {"lord_leviathan.png": 200, "lord_leviathan_front.png": 200, "lord_leviathan_back.png": 200, "lord_hydra.png": 180, "lord_hydra_front.png": 180, "lord_hydra_back.png": 180, "lord_quetzal.png": 180, "lord_quetzal_front.png": 180, "lord_quetzal_back.png": 180,
                 # #187: 幽霊船(帆船は細部が多いので高精細)
                 "lord_ghost.png": 180, "lord_ghost_front.png": 180, "lord_ghost_back.png": 180,
                 # #190: 月下の島の主。レギオンは小魚の粒立ちを残したいので高精細
                 "lord_aspidochelone.png": 180,
                 "lord_legion.png": 180, "lord_legion_front.png": 180, "lord_legion_back.png": 180,
                 # #239再3: ウンディーネ・セイレーンを高精細化(人型は細部が潰れやすい)
                 "lord_undine.png": 180, "lord_undine_front.png": 180, "lord_undine_back.png": 180,
                 "lord_siren.png": 180, "lord_siren_front.png": 180, "lord_siren_back.png": 180,
                 # #239再6: オクトパス(触腕が細かいので高精細。48pxだと足が潰れて塊に見える)
                 "lord_kraken_lord.png": 180, "lord_kraken_lord_front.png": 180, "lord_kraken_lord_back.png": 180,
                 # #270/#271/#272: 序盤の主も高精細に(ドット絵が粗いという指摘)
                 "lord_sawshark.png": 180, "lord_sawshark_front.png": 180, "lord_sawshark_back.png": 180,
                 "lord_walrus.png": 180, "lord_walrus_front.png": 180, "lord_walrus_back.png": 180,
                 "lord_dumbo.png": 180, "lord_dumbo_front.png": 180, "lord_dumbo_back.png": 180,
                 # #265再: ムーンジェリー・海賊王・夜の帝王(横向きだけ粗かった)
                 "mob_moon_jelly.png": 180, "pirate_king.png": 180, "lord_night_emperor.png": 180,
                 # #239再7: レイス(ぼろ布のほつれが細かい)
                 "lord_wraith.png": 180, "lord_wraith_front.png": 180, "lord_wraith_back.png": 180}
# #81: レヴィアタンは色数も増やしてより詳細に。#173: ケツァルも増色。#81再: ヒュドラ増色・ケツァル64色
COLORS_OVERRIDE = {"lord_leviathan.png": 64, "lord_leviathan_front.png": 64, "lord_leviathan_back.png": 64, "lord_hydra.png": 64, "lord_hydra_front.png": 64, "lord_hydra_back.png": 64, "lord_quetzal.png": 64, "lord_quetzal_front.png": 64, "lord_quetzal_back.png": 64,
                   # #187: 幽霊船
                   "lord_ghost.png": 64, "lord_ghost_front.png": 64, "lord_ghost_back.png": 64,
                   # #190: 月下の島の主
                   "lord_aspidochelone.png": 64,
                   "lord_legion.png": 64, "lord_legion_front.png": 64, "lord_legion_back.png": 64,
                   # #239再3: 人型2体は色数も増やす
                   "lord_undine.png": 64, "lord_undine_front.png": 64, "lord_undine_back.png": 64,
                   "lord_siren.png": 64, "lord_siren_front.png": 64, "lord_siren_back.png": 64,
                   # #239再6: オクトパス
                   "lord_kraken_lord.png": 64, "lord_kraken_lord_front.png": 64, "lord_kraken_lord_back.png": 64,
                   # #270/#271/#272 と #265再
                   "lord_sawshark.png": 64, "lord_walrus.png": 64, "lord_dumbo.png": 64,
                   "mob_moon_jelly.png": 64, "pirate_king.png": 64, "lord_night_emperor.png": 64,
                   # #239再7: レイス
                   "lord_wraith.png": 64, "lord_wraith_front.png": 64, "lord_wraith_back.png": 64}

for f in sorted(os.listdir(SRC)):
    if not f.lower().endswith(".png"):
        continue
    if f.startswith("title") or f.startswith("logo") or f.endswith("_source.png"):
        continue   # #175: タイトルロゴはドット絵化しない(オープニングは高精細表示)
    p = os.path.join(SRC, f)
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    s = LONG_OVERRIDE.get(f, LONG) / max(w, h)
    small = im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
    # 減色(アルファ保持): RGBを32色にパレット化
    rgb = small.convert("RGB").quantize(colors=COLORS_OVERRIDE.get(f, 32), dither=Image.Dither.NONE).convert("RGB")
    out = Image.merge("RGBA", (*rgb.split(), small.split()[3]))
    # 半端なアルファを2値化(ドット絵らしく)
    a = out.split()[3].point(lambda v: 255 if v > 96 else 0)
    out.putalpha(a)
    out.save(os.path.join(DST, f))
    print("pixel:", f, out.size)
print("done")
