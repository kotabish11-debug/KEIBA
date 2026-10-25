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
# ワイドの確定オッズ(スポーツナビ)も足して、ワイドの買い方の検証(eval_wide.pl)に使う
bash "$ROOT/自動実行/全レース/payouts.sh" "$F"
bash "$ROOT/自動実行/全レース/fuku_odds_all.sh" "$F"
bash "$ROOT/自動実行/全レース/wide_odds_all.sh" "$F"
G="$ROOT/馬情報/過去レースデータ"; ALL=$(ls "$G"/平場_*.jsonl.gz | paste -sd, -)
REC="$ROOT/馬情報/複勝の買い方_成績.md"
[ -f "$REC" ] || printf '# 1日の予算の買い方(人気馬の複勝)の成績\n\n本物の払戻で、学習データが増えるたびに確かめ直した記録(backfill_weekly.sh が追記)。買い方は「単勝オッズからのHarville式の3着以内率 × 複勝オッズの下限 ≥ 1.0」。\n各回の「後半」は、その回に足した期間(まだ検証に使っていない新しいレース)の成績。回収率が100%%を下回り続けるようなら、1日の予算の買い方を見直す。\n' > "$REC"
{ echo; echo "## $(TZ=Asia/Tokyo date +%Y-%m-%d) 時点(〜$TO、今回追加 $N レース)"; echo '```'
  # 今の買い方(複勝オッズ1.2倍以上・新馬と障害を除く。2026-10-23〜)の標準・的中重視と、比べるための絞る前の買い方
  for a in "1.0 3 1.2 1" "1.0 2 1.2 1" "1.0 3 1 0"; do set -- $a
    perl "$ROOT/自動実行/検証/fuku_day.pl" "$ALL" "$G/払戻.jsonl.gz" "$G/複勝オッズ.jsonl.gz" $1 $2 10000 flat "${FROM:0:4}-${FROM:4:2}-${FROM:6:2}" $3 $4; done
  # 資金5000円を「1点 = 資金の5%」で2026-10-24から回した記録(ユーザーの資金計画。馬情報/資金計画_5000円から.md)は別ファイルに作り直す
  perl "$ROOT/自動実行/検証/bankroll_track.pl" "$ALL" "$G/払戻.jsonl.gz" "$G/複勝オッズ.jsonl.gz" 2026-10-24 5000 > "$ROOT/馬情報/資金の記録_5000円から.md"
  # 買い方「複勝+ワイド」(2026-10-24〜)の1日の予算での成績
  perl "$ROOT/自動実行/検証/combo_day.pl" "$ALL" "$G/払戻.jsonl.gz" "$G/複勝オッズ.jsonl.gz" "$G/確定オッズ_ワイド.jsonl.gz" 3 1 1.1 3 10000 "${FROM:0:4}-${FROM:4:2}-${FROM:6:2}"
  # ワイドオッズ下限3倍未満の帯の期待値ごとの成績(1.1以上で112%だったのが続くか)
  perl "$ROOT/自動実行/検証/eval_wide.pl" "$ALL" "$G/払戻.jsonl.gz" "$G/確定オッズ_ワイド.jsonl.gz" "${FROM:0:4}-${FROM:4:2}-${FROM:6:2}" 0 | awk '/^ワイド races/{print} /^== ワイドオッズ下限 (<2|2-3)$/{p=1; print; next} /^==/{p=0} p'
  echo '```'; } >> "$REC"
echo "複勝の買い方: 成績を $REC に追記"
