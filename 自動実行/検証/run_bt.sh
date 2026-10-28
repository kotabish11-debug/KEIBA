#!/usr/bin/env bash
# 過去レースでシミュレーターと同じ計算を動かし、レースごとの勝率・馬券の候補・今の買い目を作る(Node で bt.js を動かす)
# 使い方: bash 自動実行/検証/run_bt.sh <作業フォルダー>  → <作業フォルダー>/bt.jsonl(1行1レース)
set -uo pipefail
B="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
NODE="$(command -v node || echo "/c/Program Files/nodejs/node.exe")"
mkdir -p "$B"
perl "$HERE/extract.pl" "$ROOT/シミュレーター/simulator.html" > "$B/sim_core.js" || exit 1
perl "$HERE/make_data.pl" "$B/data.js" "$ROOT"/馬情報/過去レースデータ/平場_*.jsonl.gz
"$NODE" "$(cygpath -w "$HERE/bt.js")" "$(cygpath -w "$B/sim_core.js")" "$(cygpath -w "$B/data.js")" "$(cygpath -w "$B/bt.jsonl")" || exit 1
echo "bt: $(wc -l < "$B/bt.jsonl") races, errors $(grep -c '"error"' "$B/bt.jsonl")"
