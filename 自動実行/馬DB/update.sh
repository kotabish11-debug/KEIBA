#!/usr/bin/env bash
# 馬DB(馬情報/馬DB/)を JRA公式から少しずつ集めて最新にする。PC収集の run_pc.ps1 から毎回呼ばれる(Claudeは使わない)
# 中身は update.pl。1回 BUDGET 秒(既定1500)まで。二重に動かないよう state/.lock を使う
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
ST="$ROOT/馬情報/馬DB/state"; mkdir -p "$ST"
LOCK="$ST/.lock"
if [ -e "$LOCK" ] && [ $(( $(date +%s) - $(stat -c %Y "$LOCK") )) -lt 10800 ]; then echo "馬DB: 前回の実行中のため見送り"; exit 0; fi
# git が rebase・マージの途中だと、作業フォルダーのファイルが古い版(退避の前)に戻っている。その上に足すと、あとで退避が戻されたときに消えるので動かない(2026-10-27 に起きた)
G="$ROOT/.git"
if [ -d "$G/rebase-merge" ] || [ -d "$G/rebase-apply" ] || [ -e "$G/MERGE_HEAD" ] || [ -n "$(git -C "$ROOT" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
  echo "馬DB: git が rebase・マージの途中(競合が未解決)のため見送り"; exit 1
fi
touch "$LOCK"; trap 'rm -f "$LOCK"' EXIT
perl "$HERE/update.pl" "$@"
