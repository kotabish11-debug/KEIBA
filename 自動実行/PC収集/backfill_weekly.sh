#!/usr/bin/env bash
# 学習データ(終わった平場のレース)を週1回まとめて足す。PC収集の run_pc.ps1 から呼ばれる(競馬ラボはPCからしかつながらない)
# 前回の終了日(backfill_last.txt)から7日以上たっていれば、翌日〜昨日の分を backfill.sh で集めて
# 馬情報/過去レースデータ/平場_<開始>_<終了>.jsonl.gz(1行1レース)に保存する
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
STATE="$HERE/backfill_last.txt"
LAST=$(cat "$STATE" 2>/dev/null || echo 20261019)
FROM=$(date -d "$LAST +1 day" +%Y%m%d)
TO=$(TZ=Asia/Tokyo date -d "yesterday" +%Y%m%d)
if [ $(( ( $(date -d "$TO" +%s) - $(date -d "$LAST" +%s) ) / 86400 )) -lt 7 ]; then
  echo "学習データ: 前回 $LAST から7日未満のため見送り"; exit 0
fi
W=$(mktemp -d)
bash "$ROOT/自動実行/全レース/backfill.sh" "$W/bf" "$FROM" "$TO"
N=$(ls "$W/bf"/*.json 2>/dev/null | wc -l)
if [ "$N" -eq 0 ]; then echo "学習データ: $FROM〜$TO は0レース(競馬ラボにつながらない可能性)"; exit 1; fi
F="$ROOT/馬情報/過去レースデータ/平場_${FROM:0:4}-${FROM:4:2}-${FROM:6:2}_${TO:4:2}-${TO:6:2}.jsonl.gz"
for f in "$W/bf"/*.json; do cat "$f"; echo; done | grep -v '^$' | gzip > "$F"
echo "$TO" > "$STATE"
echo "学習データ: $FROM〜$TO の $N レースを $(basename "$F") に保存"

# 1日の予算の買い方(人気馬の複勝)を、増えたデータで確かめ直す(2026-10-23〜)。払戻と確定の複勝オッズを足し、全期間と直近の成績を 馬情報/複勝の買い方_成績.md に追記する
bash "$ROOT/自動実行/全レース/payouts.sh" "$F"
bash "$ROOT/自動実行/全レース/fuku_odds_all.sh" "$F"
G="$ROOT/馬情報/過去レースデータ"; ALL=$(ls "$G"/平場_*.jsonl.gz | paste -sd, -)
REC="$ROOT/馬情報/複勝の買い方_成績.md"
[ -f "$REC" ] || printf '# 1日の予算の買い方(人気馬の複勝)の成績\n\n本物の払戻で、学習データが増えるたびに確かめ直した記録(backfill_weekly.sh が追記)。買い方は「単勝オッズからのHarville式の3着以内率 × 複勝オッズの下限 ≥ 1.0」。\n各回の「後半」は、その回に足した期間(まだ検証に使っていない新しいレース)の成績。回収率が100%%を下回り続けるようなら、1日の予算の買い方を見直す。\n' > "$REC"
{ echo; echo "## $(TZ=Asia/Tokyo date +%Y-%m-%d) 時点(〜$TO、今回追加 $N レース)"; echo '```'
  for a in "1.0 3" "1.0 2"; do perl "$ROOT/自動実行/検証/fuku_day.pl" "$ALL" "$G/払戻.jsonl.gz" "$G/複勝オッズ.jsonl.gz" $a 10000 flat "${FROM:0:4}-${FROM:4:2}-${FROM:6:2}"; done
  echo '```'; } >> "$REC"
echo "複勝の買い方: 成績を $REC に追記"
