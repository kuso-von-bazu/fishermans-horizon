#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""#287: 酒場の討伐済みの近海の主に重ねる「Defeated」の赤スタンプ画像。

英字の綴りをAI画像生成に任せると誤字・崩れが起きやすいため(UIアイコン生成.py と同じ理由で)、
Pillow でテキストと枠を直接描いてスタンプ風に加工する。

出力: assets/images/ui_defeated_stamp.png (透過PNG)
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "images"))
FONT_PATH = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts", "NotoSansJP.ttf"))

SS = 4  # スーパーサンプリング倍率
W, H = 420, 200
RED = (196, 28, 28, 255)

random.seed(287)


def _canvas():
    return Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))


def _distress(mask: Image.Image, text_box) -> Image.Image:
    """かすれたゴム印っぽく見えるよう、枠線と文字の両方に小さな穴を開ける(文字は密度を抑えて可読性を保つ)。"""
    d = ImageDraw.Draw(mask)
    w, h = mask.size
    tx0, ty0, tx1, ty1 = text_box
    for _ in range(int(w * h * 0.0015)):
        x = random.randint(0, w - 1)
        y = random.randint(0, h - 1)
        in_text = tx0 <= x <= tx1 and ty0 <= y <= ty1
        if in_text and random.random() > 0.25:
            continue  # 文字部分は穴あけ頻度を下げて可読性を優先
        r = random.randint(1, 2) * SS // 2 + 1
        d.ellipse([x - r, y - r, x + r, y + r], fill=0)
    return mask


def build() -> None:
    img = _canvas()
    d = ImageDraw.Draw(img)
    cx, cy = W * SS / 2.0, H * SS / 2.0

    # 二重の角丸枠(ゴム印っぽく)
    pad1 = 10 * SS
    pad2 = 22 * SS
    d.rounded_rectangle([pad1, pad1, W * SS - pad1, H * SS - pad1], radius=18 * SS, outline=RED, width=int(4.5 * SS))
    d.rounded_rectangle([pad2, pad2, W * SS - pad2, H * SS - pad2], radius=12 * SS, outline=RED, width=int(2.2 * SS))

    # 中央のテキスト。stroke_width で太らせて視認性を確保する。
    # #287再3: 「もう少し大きく」とのご要望で 70 -> 78pt。これ以上大きくすると
    #   14度傾けたときに D と d の端が内枠の線に触れてしまう。
    font = ImageFont.truetype(FONT_PATH, int(78 * SS))
    text = "Defeated"
    bbox = d.textbbox((0, 0), text, font=font, stroke_width=int(3 * SS))
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    text_x = cx - tw / 2.0 - bbox[0]
    text_y = cy - th / 2.0 - bbox[1]
    d.text((text_x, text_y), text, font=font, fill=RED, stroke_width=int(3 * SS), stroke_fill=RED)
    text_box = (text_x + bbox[0] - 6 * SS, text_y + bbox[1] - 6 * SS,
                text_x + bbox[2] + 6 * SS, text_y + bbox[3] + 6 * SS)

    # アルファチャンネルの枠線部分だけを荒らして、ハンコのかすれ感を出す(文字は避ける)
    r, g, b, a = img.split()
    a = _distress(a, text_box)
    img = Image.merge("RGBA", (r, g, b, a))

    # 右斜め上に傾ける(反時計回りに回転。expand=Trueで欠けを防ぎ、後で元サイズにトリミング)
    img = img.rotate(14, resample=Image.BICUBIC, expand=True)
    ew, eh = img.size
    left = (ew - W * SS) // 2
    top = (eh - H * SS) // 2
    img = img.crop((left, top, left + W * SS, top + H * SS))

    img = img.resize((W, H), Image.LANCZOS)
    out_path = os.path.join(OUT, "ui_defeated_stamp.png")
    img.save(out_path)
    print("wrote", out_path, img.size)


if __name__ == "__main__":
    build()
