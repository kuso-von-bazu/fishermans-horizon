#!/usr/bin/env bash
# Fisherman's Horizon — Codex image_gen による魚/モンスター/海賊船の画像自動生成。
# サウンドブックと同様、API不要でデスクトップ版 codex.exe の組み込み image_gen を使う。
#
# 使い方:
#   bash 画像生成_codex.sh            # プロンプト.csv 全件を生成(既存はスキップ)
#   bash 画像生成_codex.sh -f         # 既存も上書き再生成
#   bash 画像生成_codex.sh fish_grouper.png lord_hydra.png   # 指定ファイルのみ
#
# 落とし穴対策: while-read ループ内で codex が stdin(CSV) を食って2件目で止まるため
#   codex 呼び出しに必ず </dev/null を付ける。

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CSV="$HERE/プロンプト.csv"
OUTDIR="$(cd "$HERE/.." && pwd)/assets/images"
mkdir -p "$OUTDIR"

# 最新の codex.exe を自動検出(更新でハッシュ名が変わるため固定しない)
CODEX="$(ls -t /c/Users/aoe10/AppData/Local/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1)"
if [ -z "$CODEX" ] || [ ! -f "$CODEX" ]; then
  echo "ERROR: codex.exe が見つかりません。Codexデスクトップ版のインストールを確認してください。" >&2
  exit 1
fi
echo "codex: $CODEX"
echo "out  : $OUTDIR"

FORCE=0
declare -a ONLY=()
for a in "$@"; do
  if [ "$a" = "-f" ]; then FORCE=1; else ONLY+=("$a"); fi
done

STYLE='ゲーム用の2Dスプライト素材を作ってください。被写体を画面中央に1体だけ、横向きの全身像で描く。背景は完全な透明(アルファチャンネル/PNG透過)。ややリアル寄りだがデフォルメの効いたデジタルペイント調。世界観は終末的で海面上昇により陸地が水没した未来、旧文明の遺産が眠る海。文字・枠・地面の影・水しぶきの装飾は入れない。被写体:'

want() { # ファイル名が ONLY 指定に含まれるか(未指定なら全部)
  [ ${#ONLY[@]} -eq 0 ] && return 0
  for o in "${ONLY[@]}"; do [ "$o" = "$1" ] && return 0; done
  return 1
}

n=0; ok=0; skip=0
# CSV(ヘッダ1行スキップ)
tail -n +2 "$CSV" | while IFS=, read -r fname content; do
  fname="$(echo "$fname" | tr -d '\r' | xargs)"
  [ -z "$fname" ] && continue
  want "$fname" || continue
  n=$((n+1))
  target="$OUTDIR/$fname"
  if [ -f "$target" ] && [ "$FORCE" -eq 0 ]; then
    echo "[skip] $fname (既存)"; skip=$((skip+1)); continue
  fi
  prompt="${STYLE}${content} 生成した画像を $target に保存してください。"
  echo "[gen ] $fname : $content"
  # 重要(#234再): フォールバックで「今回生成された画像」だけを拾うため、
  # 呼び出し直前の時刻を基準ファイルとして持っておく。これが無いと、
  # 生成に失敗したときに前回の画像を黙ってコピーしてしまい、
  # 複数のファイルが同一画像になる事故が起きる(実際に7枚が重複した)。
  # 重要(#234再2): 既存ファイルは消さない。生成に失敗したときに元の画像まで
  # 失われるため(実際に4枚を消してしまった)。代わりに、
  #   ・呼び出し直前の時刻(stamp)より新しいか
  #   ・元ファイルより新しいか
  # で「今回生成されたもの」だけを採用し、失敗時は元のまま据え置く。
  # 重要(#290): config.toml のデフォルトモデル(gpt-6-astra)はこのCLIバージョンでは
  # 使えない(「requires a newer version of Codex」で全滅する)ため、-m で明示指定する。
  stamp="$(mktemp)"
  "$CODEX" exec -m "gpt-5.6-sol" --dangerously-bypass-approvals-and-sandbox --cd "$OUTDIR" "$prompt" </dev/null >/dev/null 2>&1
  if [ -f "$target" ] && [ "$target" -nt "$stamp" ]; then
    echo "       -> OK"; ok=$((ok+1)); fresh=1
  else
    # フォールバック: codex が指定パスへ保存しなかった場合、
    # 「この呼び出しより後に作られた」生成画像だけを拾う(古い画像は使わない)
    latest="$(find ~/.codex/generated_images -name 'ig_*.png' -newer "$stamp" 2>/dev/null | head -1)"
    if [ -n "$latest" ]; then
      cp "$latest" "$target" && echo "       -> OK(fallback)"; ok=$((ok+1)); fresh=1
    else
      echo "       -> FAILED(今回の生成画像なし: 既存ファイルは据え置き)"; fresh=0
    fi
  fi
  rm -f "$stamp"
  # 生成直後に背景透過処理(近白背景を抜いてトリミング)
  # 今回生成できたものだけ透過処理する(失敗時に既存画像を再処理しない)
  if [ "$fresh" = "1" ] && [ -f "$target" ]; then python "$HERE/透過処理.py" "$fname" </dev/null >/dev/null 2>&1 && echo "       -> 透過処理済"; fi
done
echo "完了"
