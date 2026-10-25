#!/usr/bin/env bash
# JRA公式YouTubeの調教動画を全部(一覧の 年 が入っているもの)文字認識で読み、馬情報/調教タイム_JRA動画_自動.tsv を作り直す(2026-10-26〜)
# 使い方: bash 自動実行/YouTube/chokyo_all.sh   (読んだ動画は 映像/調教_<ID>/ocr.tsv が残るので飛ばす。途中で止めてもやり直せる)
# ログ: 自動実行/logs/chokyo_all.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
LOG="$ROOT/自動実行/logs/chokyo_all.log"; exec >> "$LOG" 2>&1
LIST="$ROOT/馬情報/JRA公式_調教動画一覧.tsv"; OUT="$ROOT/馬情報/調教タイム_JRA動画_自動.tsv"
echo "[$(date '+%F %T')] 開始"
bash "$HERE/jra_chokyo.sh" list
tail -n +2 "$LIST" | awk -F'\t' '$2 != ""' | while IFS=$'\t' read -r ID Y R SEC; do
  [ -s "$HERE/映像/調教_$ID/ocr.tsv" ] && continue
  echo "[$(date '+%T')] $ID $Y $R"
  bash "$HERE/chokyo_ocr.sh" "$ID" "$Y" "$R" < /dev/null > /dev/null || echo "失敗 $ID"
  sleep 5
done
{ printf '動画ID\t年\tレース\t馬名(文字認識のまま)\t追い切り日\tコース\t馬場\t併せ\t6F\t5F\t4F\t3F\t2F\t1F\tメモ\n'
  tail -n +2 "$LIST" | awk -F'\t' '$2 != ""' | while IFS=$'\t' read -r ID Y R SEC; do
    [ -s "$HERE/映像/調教_$ID/ocr.tsv" ] && perl "$HERE/chokyo_parse.pl" < /dev/null "$HERE/映像/調教_$ID/ocr.tsv" "$ID" "$Y" "$R"; done; } > "$OUT"
echo "[$(date '+%F %T')] 終了 $(($(wc -l < "$OUT") - 1)) 頭 → $OUT"
