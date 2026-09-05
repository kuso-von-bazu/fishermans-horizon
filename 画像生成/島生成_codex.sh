#!/usr/bin/env bash
# #278(提案2): 島のドット絵化。上空から見た島の全景を島ごとに1枚生成する。
#
# 敵スプライトの 画像生成_codex.sh と作りは同じだが、
#   ・視点が「真上から」なので STYLE を別に持つ
#   ・雪の島(果ての島・北の孤島)があるため背景を近白ではなく**マゼンタ**にする
#     (透過処理.py は近白を抜くので、白い雪原だと島まで抜けてしまう)
# 生成後は 島透過.py でマゼンタを抜き、ドット絵化.py でドット絵にする。
#
# 使い方:
#   bash 島生成_codex.sh              # 未生成の島だけ
#   bash 島生成_codex.sh -f           # 全部作り直し
#   bash 島生成_codex.sh island_4.png # 指定の島だけ

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$(cd "$HERE/.." && pwd)/assets/images"
mkdir -p "$OUTDIR"

CODEX="$(ls -t /c/Users/aoe10/AppData/Local/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1)"
if [ -z "$CODEX" ] || [ ! -f "$CODEX" ]; then
  echo "ERROR: codex.exe が見つかりません。" >&2; exit 1
fi
echo "codex: $CODEX"

STYLE='ゲーム用の2Dマップ素材を作ってください。真上(トップダウン・俯瞰)から見下ろした小さな孤島の全景を、画面中央に1つだけ描く。海は描かず、背景は一様な純マゼンタ(RGB 255,0,255)で塗りつぶす。島の輪郭は不規則で、外周から順に砂浜・草地・内陸・小さな山という層になっている。真上からの見下ろしなので、木や建物は上から見た形(樹冠の丸/屋根)で小さく描く。ややデフォルメの効いたドット絵向けのデジタルペイント調。世界観は終末的で海面上昇により陸地が水没した未来、旧文明の遺産が眠る海。文字・枠・地図記号・方位磁針・船・波・海面の反射は描かない。島の姿:'

FORCE=0
declare -a ONLY=()
for a in "$@"; do
  if [ "$a" = "-f" ]; then FORCE=1; else ONLY+=("$a"); fi
done
want() {
  [ ${#ONLY[@]} -eq 0 ] && return 0
  for o in "${ONLY[@]}"; do [ "$o" = "$1" ] && return 0; done
  return 1
}

# 島index:内容(Island2D.PALETTES と Database.islands の設定に合わせている)
ISLANDS=(
"island_0.png|南国の島。白い砂浜が広く、内陸は明るい緑の草地。中央にごく低い岩山。ヤシの木が5本ほど海岸ぞいに立ち、片側の入り江に木の桟橋と数軒の赤い屋根の小屋が並ぶ小さな漁村がある。"
"island_1.png|涼しい岩場の島。砂浜は灰白色で、内陸は深い緑の草地。灰青色の岩山が中央にあり、風に耐える低い木が7本ほど。片側に木の桟橋と灰色の屋根の小屋。"
"island_2.png|砂漠の島。島のほとんどが黄褐色の砂丘で、中央に小さな泉(オアシス)があり、そのまわりだけ緑がわずかにある。ヤシの木は2本だけ。片側に石造りの桟橋と土壁の小屋。"
"island_3.png|火山の島。黒っぽい砂浜と褐色の荒地。中央に赤黒い火口があり、うっすら赤く光っている。枯れた木が3本ほど。片側に黒い石の桟橋と鉄板の小屋。"
"island_4.png|寒冷の島。雪に覆われた白い海岸と、灰色の岩肌。中央に白い峰の山。濃緑の針葉樹が3本ほど。片側に凍った木の桟橋と、雪の積もった小屋。"
"island_5.png|星霜の島。明るい緑の草地が大部分を占め、片側にこぢんまりとした落葉樹の森がある。淡い砂浜。中央に低いなだらかな丘。片側に木の桟橋と小屋。"
"island_6.png|常闇の島。島の大部分が深く暗い針葉樹の森で、草地はわずか。砂浜はくすんだ灰色。中央に暗い岩山。片側に古びた木の桟橋と苔むした小屋。"
"island_7.png|海嘯の島。明るい緑の草地が中心で、片側に広めの砂地がある。砂浜は明るいクリーム色。低い丘と3本ほどの木。片側に頑丈な石積みの桟橋と小屋。"
"island_8.png|北の小さな孤島。ごく小さく、地面はすべて雪原。灰色の岩がいくつか露出し、濃緑の針葉樹が2本だけ。人の住居はなく、朽ちた小屋がひとつ。"
"island_9.png|南の小さな孤島。ごく小さく、地面はすべて明るい草原。砂浜は細い。木は2本だけ。人の住居はなく、石積みの跡がひとつ。"
"island_10.png|雪夜の島。緑豊かな草地が大部分を占め、山頂と針葉樹の梢にだけうっすらと雪が積もる。砂浜は白っぽい灰色。中央になだらかな低い山があり山頂だけ白い雪化粧。針葉樹が5本ほど。片側に木の桟橋と、屋根にうっすら雪の積もった小屋。"
)

for row in "${ISLANDS[@]}"; do
  fname="${row%%|*}"
  content="${row#*|}"
  want "$fname" || continue
  target="$OUTDIR/$fname"
  if [ -f "$target" ] && [ "$FORCE" -eq 0 ]; then echo "[skip] $fname (既存)"; continue; fi
  echo "[gen ] $fname : $content"
  stamp="$(mktemp)"
  # 重要(#290): config.toml のデフォルトモデル(gpt-6-astra)はこのCLIバージョンでは
  # 使えない(「requires a newer version of Codex」で全滅する)ため、-m で明示指定する。
  "$CODEX" exec -m "gpt-5.6-sol" --dangerously-bypass-approvals-and-sandbox --cd "$OUTDIR" \
    "${STYLE}${content} 生成した画像を $target に保存してください。" </dev/null >/dev/null 2>&1
  fresh=0
  if [ -f "$target" ] && [ "$target" -nt "$stamp" ]; then
    echo "       -> OK"; fresh=1
  else
    latest="$(find ~/.codex/generated_images -name 'ig_*.png' -newer "$stamp" 2>/dev/null | head -1)"
    if [ -n "$latest" ]; then cp "$latest" "$target" && echo "       -> OK(fallback)" && fresh=1
    else echo "       -> FAILED(今回の生成画像なし)"; fi
  fi
  rm -f "$stamp"
  if [ "$fresh" = "1" ]; then python "$HERE/島透過.py" "$fname" </dev/null && echo "       -> 透過処理済"; fi
done
echo "完了"
