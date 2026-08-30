#!/usr/bin/env bash
# 共有者が GitHub Issue に書いた意見(feedback)を取得する読み取り専用スクリプト。
# 事前準備:
#   - 同フォルダに .gh_token (GitHub Personal Access Token, repoスコープ) を置く
#   - 同フォルダに .gh_repo (例: kuso-von-bazu/fishermans-horizon) を置く
# どちらも .gitignore 済み。Claude が /loop でこれを実行して意見を拾い、改良する。

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GH="/c/Program Files/GitHub CLI/gh.exe"

if [ ! -x "$GH" ] && ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI(gh) が見つかりません。" >&2; exit 1
fi
[ -x "$GH" ] || GH="gh"

if [ -f "$HERE/.gh_token" ]; then
  export GH_TOKEN="$(cat "$HERE/.gh_token" | tr -d '\r\n')"
fi
REPO="$(cat "$HERE/.gh_repo" 2>/dev/null | tr -d '\r\n')"
if [ -z "$REPO" ]; then
  echo "ERROR: .gh_repo にリポジトリ(owner/name)を書いてください。" >&2; exit 1
fi

# コンサル希望(コンサルラベル)と製作依頼(製作依頼ラベル)は、開発者が別のタイミングで
# Fable に切り替えて手動対応するため、ここでは拾わない。件数だけ知らせる。
CONSULT="$("$GH" issue list --repo "$REPO" --state open --limit 50 --label コンサル --json number --jq 'length' 2>/dev/null || echo 0)"
BUILDREQ="$("$GH" issue list --repo "$REPO" --state open --limit 50 --label 製作依頼 --json number --jq 'length' 2>/dev/null || echo 0)"

echo "== オープン中の意見 ($REPO) 古い順 / コンサル希望・製作依頼は除く =="
"$GH" issue list --repo "$REPO" --state open --limit 50 \
  --json number,title,labels,body,createdAt,author \
  --jq 'map(select((([.labels[].name] | index("コンサル")) | not) and (([.labels[].name] | index("製作依頼")) | not))) | sort_by(.createdAt) | .[] | "──────────\n#\(.number)  [\(.author.login)]  \(.title)\n  ラベル: \([.labels[].name] | join(","))\n\(.body)\n"'
echo "──────────"
if [ "${CONSULT:-0}" != "0" ]; then
  echo "※ コンサル希望が ${CONSULT} 件あります(このスクリプトでは表示しません)。"
  echo "   開発者が別途 Fable で対応するため、/loop では触らないこと。"
  echo "   見る場合: gh issue list --repo \"$REPO\" --state open --label コンサル"
fi
if [ "${BUILDREQ:-0}" != "0" ]; then
  echo "※ 製作依頼(エディタ等)が ${BUILDREQ} 件あります(このスクリプトでは表示しません)。"
  echo "   開発者が別途 Fable で対応するため、/loop では触らないこと。"
  echo "   見る場合: gh issue list --repo \"$REPO\" --state open --label 製作依頼"
fi
echo "(反映後: gh issue comment <番号> -b \"✅反映: ...\" ; gh issue close <番号>)"
