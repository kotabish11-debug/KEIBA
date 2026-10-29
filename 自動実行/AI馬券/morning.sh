#!/usr/bin/env bash
# AI馬券の朝の準備(day.ps1 が呼ぶ。約15分): JRA-VAN の差分 → 先週までの結果 → 今日の出馬表 → 特徴量(過去走・調教)
# 使い方: bash 自動実行/AI馬券/morning.sh [日付 YYYYMMDD(省略で今日)]
#   終了コード 3 = 今日は中央競馬が無い(day.ps1 はそこで終わる)
# 出力: 馬情報/JRA-VAN/AI馬券/work/entries_<日付>.jsonl・today_<日付>.pkl(PCだけ)
set -uo pipefail
cd "$(dirname "$0")/../.."
DAY="${1:-$(TZ=JST-9 date +%Y%m%d)}"; ISO="${DAY:0:4}-${DAY:4:2}-${DAY:6:2}"
W=馬情報/JRA-VAN/AI馬券/work; mkdir -p "$W"
PY="$LOCALAPPDATA/Programs/Python/Python312/python.exe"; export PYTHONIOENCODING=utf-8
# 1. JRA-VAN(出馬表の最新・調教・前日までの成績)
bash 自動実行/JRA-VAN/update.sh
# 2. 先週までの結果(JRA詳細)。PC収集の裏の集め(history_bg.sh)が動いていなければ、今月分の取っていない開催日だけ
A=馬情報/過去レースデータ/全期間
if [ ! -e "$A/.jra.lock" ] || [ $(( $(date +%s) - $(date -r "$A/.jra.lock" +%s) )) -ge 1800 ]; then
  bash 自動実行/全レース/jra_history.sh "${DAY:0:6}" "${DAY:0:6}" 15 > /dev/null 2>&1
fi
# 3. 今日の出馬表
"$PY" 自動実行/AI馬券/entries.py "$DAY" "$W/entries_$DAY.jsonl" || exit 1
[ -s "$W/entries_$DAY.jsonl" ] || { echo "$ISO: 中央競馬なし"; exit 3; }
# 4. 特徴量(全期間 + 今日のレース → 今日の行だけ残す)
"$PY" -W ignore 自動実行/検証/lgbm_features.py "$A" 馬情報/JRA-VAN/馬DB "--extra=$W/entries_$DAY.jsonl" "$W/all.pkl" 2>&1 | tail -1
"$PY" -W ignore 自動実行/検証/lgbm_chokyo.py "$W/all.pkl" 馬情報/JRA-VAN "$W/today_$DAY.pkl" --upcoming 2>&1 | tail -1
rm -f "$W/all.pkl"
[ -s "$W/today_$DAY.pkl" ] || exit 1
# 5. 前の日までの結果を記録に埋める
"$PY" 自動実行/AI馬券/settle.py
echo "$ISO: 準備できた"
