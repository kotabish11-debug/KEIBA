#!/usr/bin/env bash
# 馬DB(馬情報/馬DB/)を JRA公式から少しずつ集めて最新にする。PC収集の run_pc.ps1 から毎回呼ばれる(Claudeは使わない)
# 中身は update.pl。1回 BUDGET 秒(既定1500)まで。二重に動かないよう state/.lock を使う
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
ST="$ROOT/馬情報/馬DB/state"; mkdir -p "$ST"
LOCK="$ST/.lock"
if [ -e "$LOCK" ] && [ $(( $(date +%s) - $(stat -c %Y "$LOCK") )) -lt 10800 ]; then echo "馬DB: 前回の実行中のため見送り"; exit 0; fi
touch "$LOCK"; trap 'rm -f "$LOCK"' EXIT
perl "$HERE/update.pl" "$@"
