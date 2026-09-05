# -*- coding: utf-8 -*-
# #289: Steamストアページの試作PDFを生成する(使い捨てスクリプト)。
import os
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Image,
    Table, TableStyle, NextPageTemplate, PageBreak, FrameBreak, KeepTogether
)
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER

FONT_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts", "NotoSansJP.ttf")
pdfmetrics.registerFont(TTFont("NotoSansJP", FONT_PATH))

SHOTS = os.path.join("C:/tmp/steam_shots")
OUT = os.path.join(os.path.dirname(__file__), "..", "Steamストアページ試作_2026-09-05.pdf")

PAGE = landscape(A4)
W, H = PAGE
MARGIN = 14 * mm

DARK = colors.HexColor("#0e1b2a")
GOLD = colors.HexColor("#c9a24b")
LIGHT = colors.HexColor("#e8ecf1")
SUBTLE = colors.HexColor("#9fb0c3")

styles = {
    "title": ParagraphStyle("title", fontName="NotoSansJP", fontSize=26, leading=30,
                             textColor=GOLD, alignment=TA_LEFT),
    "tagline": ParagraphStyle("tagline", fontName="NotoSansJP", fontSize=12.5, leading=17,
                               textColor=LIGHT, alignment=TA_LEFT),
    "h2": ParagraphStyle("h2", fontName="NotoSansJP", fontSize=13, leading=17,
                          textColor=GOLD, alignment=TA_LEFT, spaceBefore=4, spaceAfter=4),
    "body": ParagraphStyle("body", fontName="NotoSansJP", fontSize=9.7, leading=14.5,
                            textColor=LIGHT, alignment=TA_LEFT),
    "bullet": ParagraphStyle("bullet", fontName="NotoSansJP", fontSize=9.5, leading=14,
                              textColor=LIGHT, alignment=TA_LEFT, leftIndent=10,
                              bulletIndent=0, spaceAfter=3),
    "caption": ParagraphStyle("caption", fontName="NotoSansJP", fontSize=8.7, leading=11.5,
                               textColor=SUBTLE, alignment=TA_CENTER),
    "footer": ParagraphStyle("footer", fontName="NotoSansJP", fontSize=7.5, leading=10,
                              textColor=SUBTLE, alignment=TA_CENTER),
}


def bg(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(DARK)
    canvas.rect(0, 0, W, H, fill=1, stroke=0)
    canvas.setStrokeColor(GOLD)
    canvas.setLineWidth(0.6)
    canvas.line(MARGIN, H - 12 * mm, W - MARGIN, H - 12 * mm)
    canvas.setFont("NotoSansJP", 7.5)
    canvas.setFillColor(SUBTLE)
    canvas.drawRightString(W - MARGIN, 7 * mm, f"{doc.page}")
    canvas.drawString(MARGIN, 7 * mm, "Fisherman's Horizon — Steam ストアページ試作 (PDF / #289)")
    canvas.restoreState()


doc = BaseDocTemplate(OUT, pagesize=PAGE,
                       leftMargin=MARGIN, rightMargin=MARGIN,
                       topMargin=16 * mm, bottomMargin=12 * mm)

frame_full = Frame(MARGIN, 12 * mm, W - 2 * MARGIN, H - 28 * mm, id="full")
doc.addPageTemplates([PageTemplate(id="page", frames=[frame_full], onPage=bg)])

story = []

# ---- ページ1: ヘッダー + ヒーロー画像 + 概要 + 特徴 ----
story.append(Paragraph("Fisherman's Horizon", styles["title"]))
story.append(Paragraph(
    "海面上昇に沈んだ世界を、粗末な蒸気漁船で漕ぎ出す — 見下ろし2Dの拡大再生産×漁業アクション",
    styles["tagline"]))
story.append(Spacer(1, 4 * mm))

hero = Image(os.path.join(SHOTS, "01_title.png"), width=148 * mm, height=148 * mm * (1017 / 1920))
hero.hAlign = "CENTER"
story.append(hero)
story.append(Spacer(1, 3 * mm))

overview = (
    "粗末な蒸気漁船から始め、漁と狩りで資金と名声を稼ぎ、近海の主(ヌシ)や海賊を討ち、"
    "より強い船と武器を得て島々を進む。そして人類種の天敵レヴィアタンを討伐し、"
    "伝説の漁場「Fisherman's Horizon」を目指す —— 出港のたびに魚倉を満たしながら襲い来る敵を"
    "迎え撃つ、漁業と一斉射撃サバイバルが一体化した拡大再生産ゲームです。"
)
story.append(Paragraph("ゲーム概要", styles["h2"]))
story.append(Paragraph(overview, styles["body"]))
story.append(Spacer(1, 4 * mm))

features = [
    "<b>漁 × 戦闘の航海ループ</b> — 燃料と食料が尽きる前に、漁で魚倉を満たしつつ襲い来る海賊・怪物を迎撃して帰港する",
    "<b>拡大再生産</b> — 漁獲・討伐で得た資金と名声で船体・武器・クルーを強化し、より遠くの海域へ",
    "<b>10の島・個性豊かな「近海の主」</b> — 島ごとに固有の強敵(ヌシ)が待ち受け、天候や地形も変化",
    "<b>船団編成(最大5隻)</b> — 僚艦を加えて陣形を組み、艦隊戦術で戦況を変える",
    "<b>ボスラッシュ・実績システム</b> — 討伐済みの主を連戦できるやり込みモードと、達成でバフが得られる実績要素",
    "<b>ブラウザですぐ遊べる</b> — インストール不要のWeb版を公開中",
]
story.append(Paragraph("特徴", styles["h2"]))
for f in features:
    story.append(Paragraph("・" + f, styles["bullet"]))

story.append(NextPageTemplate("page"))
story.append(PageBreak())

# ---- ページ2: スクリーンショットギャラリー ----
story.append(Paragraph("スクリーンショット", styles["title"]))
story.append(Spacer(1, 4 * mm))

gallery = [
    ("02_sea.png", "近海の航海。ソナー・燃料・魚倉・装甲を見ながら漁と戦闘をこなす"),
    ("03_boss.png", "多彩な怪物たち。島ごとに固有の「近海の主」や海の魔物が立ちはだかる"),
    ("04_charge.png", "船団を率いての突撃スキル。陣形を組んで艦隊戦術を活かす"),
    ("05_yard.png", "造船所で船体・武器を強化し、より過酷な海域へ挑む拡大再生産"),
    ("06_lords.png", "酒場で仕入れる「主の情報」。狙う相手の強さと所在を事前に知れる"),
    ("07_ach.png", "実績システム。達成するとステータスバフとして永続的に積み上がる"),
]

cell_w = (W - 2 * MARGIN - 8 * mm) / 2
img_w = cell_w
img_h = img_w * (1017 / 1920)

rows = []
row = []
for i, (fname, cap) in enumerate(gallery):
    img = Image(os.path.join(SHOTS, fname), width=img_w, height=img_h)
    cell = [img, Spacer(1, 1.5 * mm), Paragraph(cap, styles["caption"])]
    row.append(cell)
    if len(row) == 2:
        rows.append(row)
        row = []
if row:
    row.append([Spacer(1, 1, )])
    rows.append(row)

table = Table(rows, colWidths=[cell_w, cell_w], hAlign="CENTER")
table.setStyle(TableStyle([
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("TOPPADDING", (0, 0), (-1, -1), 6),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
    ("LEFTPADDING", (0, 0), (-1, -1), 4),
    ("RIGHTPADDING", (0, 0), (-1, -1), 4),
]))
story.append(table)

story.append(Spacer(1, 3 * mm))
story.append(Paragraph(
    "※ 試作版のため動画は未制作。スクリーンショットは開発中ビルドの実機画面です。",
    styles["footer"]))

doc.build(story)
print("PDF_SAVED:", OUT)
