#!/usr/bin/env bash
# 過去レースでシミュレーターと同じ計算を動かし、レースごとの勝率・馬券の候補・今の買い目を作る(PCのEdgeをヘッドレスで使う。PCにNodeが無いため)
# 使い方: bash 自動実行/検証/run_bt.sh <作業フォルダー>  → <作業フォルダー>/bt.jsonl(1行1レース)
set -uo pipefail
B="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
mkdir -p "$B"; cp "$HERE/harness.html" "$B/"
perl "$HERE/extract.pl" "$ROOT/シミュレーター/simulator.html" > "$B/sim_core.js" || exit 1
perl "$HERE/make_data.pl" "$B/data.js" "$ROOT"/馬情報/過去レースデータ/平場_*.jsonl.gz
N=$(grep -o '"id":"[0-9]\{12\}"' "$B/data.js" | wc -l); WB=$(cygpath -m "$B"); : > "$B/bt.jsonl"
for ((s = 0; s < N; s += 250)); do
  "$EDGE" --headless=new --disable-gpu --no-first-run --user-data-dir="$(cygpath -w "$B/prof")" --dump-dom "file:///$WB/harness.html#$s,$((s + 250))" 2>/dev/null |
    perl -MHTML::Entities -ne 'if (s/.*<pre id="out">//) { $on = 1 } if ($on) { my $e = s/<\/pre>.*//s; decode_entities($_); print; $on = 0 if $e }' >> "$B/bt.jsonl"
  echo >> "$B/bt.jsonl"
done
sed -i '/^$/d' "$B/bt.jsonl"
echo "bt: $(wc -l < "$B/bt.jsonl") races, errors $(grep -c '"error"' "$B/bt.jsonl")"
