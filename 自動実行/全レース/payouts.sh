#!/usr/bin/env bash
# 学習データ(平場_*.jsonl.gz)のレースの全券種の払戻を競馬ラボから集める。1日の予算の買い方を本物の配当で確かめるため
# 使い方: bash 自動実行/全レース/payouts.sh [学習データ.jsonl.gz ...]   (省略すると 馬情報/過去レースデータ/平場_*.jsonl.gz 全部)
# 出力: 馬情報/過去レースデータ/払戻.jsonl.gz(1行1レース。pay_json.pl の形)。取得済みのレースは飛ばすので、何度でも足せる
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUTGZ="$ROOT/馬情報/過去レースデータ/払戻.jsonl.gz"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
[ $# -eq 0 ] && set -- "$ROOT"/馬情報/過去レースデータ/平場_*.jsonl.gz
[ -s "$OUTGZ" ] && zcat "$OUTGZ" > "$W/have.jsonl" || : > "$W/have.jsonl"
grep -o '"id":"[0-9]*"' "$W/have.jsonl" | tr -dc '0-9\n' | sort -u > "$W/have.txt"
for g in "$@"; do zcat "$g" | grep -o '"id":"[0-9]\{12\}"' | grep -o '[0-9]\{12\}'; done | sort -u | comm -23 - "$W/have.txt" > "$W/todo.txt"
echo "払戻: $(wc -l < "$W/todo.txt") レースを取得"
# 3本並行で取り、100レースごとに保存する(途中で止まっても無駄にならない)
cp "$W/have.jsonl" "$W/new.jsonl"; n=0; mkdir -p "$W/h"
split -l 100 "$W/todo.txt" "$W/part_"
for part in "$W"/part_*; do
  xargs -P 3 -I{} sh -c 'curl -sSL -m 30 -A "$1" -H "Accept-Language: ja" -o "$2/{}.html" "https://www.keibalab.jp/db/race/{}/raceresult.html"; sleep 1' _ "$UA" "$W/h" < "$part"
  while read -r ID; do perl "$HERE/pay_json.pl" "$W/h/$ID.html" "$ID" >> "$W/new.jsonl" && n=$((n + 1)); rm -f "$W/h/$ID.html"; done < "$part"
  gzip -c "$W/new.jsonl" > "$OUTGZ.tmp" && mv "$OUTGZ.tmp" "$OUTGZ"
done
gzip -c "$W/new.jsonl" > "$OUTGZ.tmp" && mv "$OUTGZ.tmp" "$OUTGZ"
echo "払戻: $n レースを追加(合計 $(zcat "$OUTGZ" | wc -l))"
