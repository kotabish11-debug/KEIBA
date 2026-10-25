#!/usr/bin/env bash
# 学習データ(平場_*.jsonl.gz)のレースの確定のワイドオッズ(下限・上限)をスポーツナビから集めて、1つのファイルに足す(fuku_odds_all.sh のワイド版)
# 競馬ラボのオッズAPIには過去のワイドが残っていないが、スポーツナビの race/odds/wide には終わったレースの確定オッズが残っている
# 使い方: bash 自動実行/全レース/wide_odds_all.sh [学習データ.jsonl.gz ...]
# 出力: 馬情報/過去レースデータ/確定オッズ_ワイド.jsonl.gz(1行1レース {"id","wide":{"<馬番>-<馬番>":[下限,上限]}})。取得済みは飛ばす
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; D="$ROOT/馬情報/過去レースデータ"
OUTGZ="$D/確定オッズ_ワイド.jsonl.gz"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
[ $# -eq 0 ] && set -- "$D"/平場_*.jsonl.gz
[ -s "$OUTGZ" ] && zcat "$OUTGZ" > "$W/new.jsonl" || : > "$W/new.jsonl"
grep -o '"id":"[0-9]\{12\}"' "$W/new.jsonl" | grep -o '[0-9]\{12\}' | sort -u > "$W/have.txt"
for g in "$@"; do zcat "$g" | grep -o '"id":"[0-9]\{12\}"' | grep -o '[0-9]\{12\}'; done | sort -u | comm -23 - "$W/have.txt" > "$W/todo.txt"
echo "ワイドオッズ: $(wc -l < "$W/todo.txt") レースを取得"
# 競馬ラボ形式のID(年月日8+場2+R2) → スポーツナビのID(開催ID8+R2)。開催IDは月の日程ページから引く
: > "$W/map.txt"
while read -r ID; do
  Y=${ID:0:4} M=${ID:4:2} DD=${ID:6:2} V=${ID:8:2}; SF="$W/sch_$Y$M.html"
  [ -s "$SF" ] || { curl -sSL -m 30 -A "$UA" -o "$SF" "https://sports.yahoo.co.jp/keiba/schedule/monthly/?year=$Y&month=$((10#$M))"; sleep 0.3; }
  K="$Y$M$DD$V"; YK=$(grep -m1 "^$K " "$W/kai.txt" 2>/dev/null | cut -d' ' -f2)
  if [ -z "$YK" ]; then YK=$(perl "$HERE/yahoo.pl" list "$SF" "$Y-$M-$DD" "$V" 2>/dev/null) || YK=-; echo "$K $YK" >> "$W/kai.txt"; fi
  [ "$YK" != - ] && echo "$ID $YK${ID:10:2}" >> "$W/map.txt"
done < "$W/todo.txt"
echo "ワイドオッズ: スポーツナビのIDが分かったのは $(wc -l < "$W/map.txt") レース"
mkdir -p "$W/h"; split -l 90 "$W/map.txt" "$W/part_"; export UA WH="$W/h"
for part in "$W"/part_*; do
  [ -e "$part" ] || continue
  xargs -P 3 -L 1 sh -c 'curl -sSL -m 30 -A "$UA" -o "$WH/$1.html" "https://sports.yahoo.co.jp/keiba/race/odds/wide/$2?ninki=0"; sleep 0.3' _ < "$part"
  while read -r ID YID; do
    J=$(perl "$HERE/yahoo.pl" wide "$W/h/$ID.html" 2>/dev/null) && printf '{"id":"%s","wide":%s}\n' "$ID" "$J" >> "$W/new.jsonl"
    rm -f "$W/h/$ID.html"
  done < "$part"
  gzip -c "$W/new.jsonl" > "$OUTGZ.tmp" && mv "$OUTGZ.tmp" "$OUTGZ"
done
echo "ワイドオッズ: 合計 $(zcat "$OUTGZ" | wc -l) レース"
