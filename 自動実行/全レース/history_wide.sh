#!/usr/bin/env bash
# history.sh が集めた全期間のレースの、確定のワイドオッズ(下限・上限)をスポーツナビから集める(2026-10-26〜)
# スポーツナビは短い間に何本も取ると「ページは現在表示できません」になる(2026-10-26 に3本並行で制限された)ので、1本ずつ間隔を空け、制限されたら30分休む
# 使い方: bash 自動実行/全レース/history_wide.sh [最大の分数]   (省略すると全部終わるまで)
# 出力: 馬情報/過去レースデータ/全期間/<年>/ワイド.jsonl {"id","wide":{"<馬番>-<馬番>":[下限,上限]}}。新しいレースから順に集め、取得済みは飛ばす
#   スポーツナビの開催ID(年2+場2+回2+日2)は 全期間/スポーツナビ開催ID.tsv に、ワイドが無かったレースは 全期間/ワイド無し.txt に残す
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/馬情報/過去レースデータ/全期間"
MAXMIN="${1:-0}"; START=$(date +%s)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
KAI="$OUT/スポーツナビ開催ID.tsv"; NONE="$OUT/ワイド無し.txt"; touch "$KAI" "$NONE"
over() { [ "$MAXMIN" -gt 0 ] && [ $(( ($(date +%s) - START) / 60 )) -ge "$MAXMIN" ]; }
# スポーツナビのページを取る。制限のページなら30分休んでやり直す(3回まで)
yget() {
  for t in 1 2 3 4; do
    curl -sSL -m 30 -A "$UA" -o "$2" "$1"; sleep 3
    grep -q "現在表示できません" "$2" 2>/dev/null || [ ! -s "$2" ] || return 0
    [ "$t" -eq 4 ] && break
    echo "$(date '+%m/%d %H:%M') スポーツナビに制限されたので30分休む"; sleep 1800
  done
  echo "スポーツナビの制限が続くので止めます"; exit 1
}

cat "$OUT"/*/ワイド.jsonl 2>/dev/null | grep -o '"id":"[0-9]*"' | grep -o '[0-9]\{12\}' | cat - "$NONE" | sort -u > "$W/have.txt"
cat "$OUT"/*/レース.jsonl 2>/dev/null | grep -o '^{[^{]*"id":"[0-9]*"' | grep -o '"id":"[0-9]*"' | grep -o '[0-9]\{12\}' | sort -u | comm -23 - "$W/have.txt" | sort -r > "$W/todo.txt"
echo "ワイド: $(wc -l < "$W/todo.txt") レースを取得"
n=0
while read -r ID; do
  over && { echo "時間切れ(ワイド $n レース取得)"; exit 0; }
  K="${ID:0:8}${ID:8:2}"
  if ! grep -q "^$K	" "$KAI"; then
    # その月の日程ページから、全部の開催日・場の開催IDを覚える
    Y=${ID:0:4}; M=$((10#${ID:4:2}))
    yget "https://sports.yahoo.co.jp/keiba/schedule/monthly/?year=$Y&month=$M" "$W/sch.html"
    YM="${ID:0:6}" perl -ne 'BEGIN{$/=undef} my $c=0; while (/(\d{1,2})日（.{1,6}?）|\/keiba\/race\/list\/(\d{8})/g) { if (defined $1) { $c=$1; next } printf "%s%02d%s\t%s\n", $ENV{YM}, $c, substr($2,2,2), $2 if $c }' "$W/sch.html" >> "$KAI" 2>/dev/null
    grep -q "^$K	" "$KAI" || printf '%s\t-\n' "$K" >> "$KAI"
  fi
  YK=$(grep -m1 "^$K	" "$KAI" | cut -f2)
  if [ "$YK" = - ]; then echo "$ID" >> "$NONE"; continue; fi
  yget "https://sports.yahoo.co.jp/keiba/race/odds/wide/$YK${ID:10:2}?ninki=0" "$W/w.html"
  J=$(perl "$HERE/yahoo.pl" wide "$W/w.html" 2>/dev/null)
  if [ -n "$J" ] && [ "$J" != "{}" ]; then printf '{"id":"%s","wide":%s}\n' "$ID" "$J" >> "$OUT/${ID:0:4}/ワイド.jsonl"; n=$((n + 1)); else echo "$ID" >> "$NONE"; fi
done < "$W/todo.txt"
echo "ワイド: $n レースを追加"
