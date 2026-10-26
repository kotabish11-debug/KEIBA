#!/usr/bin/env bash
# 全期間のデータ集め(history.sh = 競馬ラボ、history_wide.sh = スポーツナビ)を裏で最後まで回す。PC収集(run_pc.ps1)が毎回起動し、動いていれば何もしない
# 2つは別のサイトなので同時に回す。それぞれ5分ごとに 全期間/.<名前>.lock を更新し、30分以上更新の無いロックは止まったものとみなす
# ログ: 自動実行/logs/history_<日付>.log。競馬ラボの分が全部終わったら 全期間/済み_keibalab を作り、それ以降は競馬ラボには行かない
# ワイドは毎回「まだ取っていないレース」だけ取る(競馬ラボの分が増えるたびに追いかける)
# JRA詳細(jra_history.sh = JRA公式の過去レース結果。タイム・通過順・馬体重・ハロンタイム・競走中の出来事)も別のサイトなので同時に回す(2026-10-26〜)。
#   毎回、取っていない開催日だけ取る(終わっても次の回で新しい開催日を足す)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/馬情報/過去レースデータ/全期間"; mkdir -p "$OUT" "$ROOT/自動実行/logs"
LOG="$ROOT/自動実行/logs/history_$(date +%Y%m%d).log"
run() {
  local name=$1; shift; local lock="$OUT/.$name.lock"
  [ -e "$OUT/済み_$name" ] && return 0
  if [ -e "$lock" ] && [ $(( $(date +%s) - $(date -r "$lock" +%s) )) -lt 1800 ]; then return 0; fi
  touch "$lock"
  echo "[$(date '+%Y-%m-%d %H:%M')] $name 開始" >> "$LOG"
  "$@" >> "$LOG" 2>&1 & local pid=$!
  while kill -0 "$pid" 2>/dev/null; do touch "$lock"; sleep 300 & wait $! 2>/dev/null; done
  wait "$pid"; local rc=$?
  echo "[$(date '+%Y-%m-%d %H:%M')] $name 終了 (終了コード $rc)" >> "$LOG"
  [ "$rc" -eq 0 ] && [ "$name" = keibalab ] && grep -q "全期間: 完了" "$LOG" && touch "$OUT/済み_$name"
  rm -f "$lock"
}
# 競馬ラボの後にワイドをもう一度回す(競馬ラボが新しく集めた分のワイドも取るため)
run keibalab bash "$HERE/history.sh" 20050101 20261025 &
run jra bash "$HERE/jra_history.sh" 200501 &
( sleep 600; run wide bash "$HERE/history_wide.sh"; wait; ) &
wait
run wide bash "$HERE/history_wide.sh"
