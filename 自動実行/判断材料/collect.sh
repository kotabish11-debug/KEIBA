#!/usr/bin/env bash
# 競馬ラボから1レース分の判断材料を集めて、markdownで標準出力に出す
# 使い方: bash 自動実行/判断材料/collect.sh <競馬ラボのレースID>
#   レースID = 年4桁+月日4桁+場コード2桁+R2桁(例: 202610180811 = 2026/10/18 京都11R)
#   場コード: 01札幌 02函館 03福島 04新潟 05東京 06中山 07中京 08京都 09阪神 10小倉
# 出走馬が出る前(特別登録前)でも、過去10年の傾向は出せる
set -euo pipefail
ID="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CSV="$ROOT/馬情報/種牡馬リーディング_2026_中央.csv"
TMP="$(mktemp -d)"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
get() { curl -sSL -A "$UA" -H "Accept-Language: ja" -o "$TMP/$2" "https://www.keibalab.jp/db/race/$ID/$1"; sleep 2; }
get "" race.html; get past.html past.html; get umabashira.html umabashira.html
TITLE="$(grep -o '<title>[^<]*' "$TMP/race.html" | head -1 | sed 's/<title>//')"
echo "<!-- 競馬ラボ $ID: $TITLE / 取得 $(TZ=JST-9 date '+%Y-%m-%d %H:%M') -->"
echo "## 過去10年の勝ち馬"
perl "$HERE/past.pl" "$TMP/past.html" > "$TMP/past.tsv"
perl "$HERE/winners.pl" < "$TMP/past.tsv"
echo
echo "## 過去10年の1〜3着の傾向"
perl "$HERE/past_summary.pl" < "$TMP/past.tsv" | sed 's/^/- /'
echo
perl "$HERE/umabashira.pl" "$TMP/umabashira.html" > "$TMP/mat.tsv" || true
if [ "$(grep -vc '^#' "$TMP/mat.tsv" || true)" -gt 1 ]; then
  echo "## コースの傾向(競馬ラボ・コース全体の集計)"
  grep '^#' "$TMP/mat.tsv" | sed 's/^# /- /'
  echo
  echo "## 出走馬ごとの材料"
  perl "$HERE/horse_table.pl" "$TMP/mat.tsv" "$CSV"
else
  echo "(出走馬の馬柱はまだ出ていない)"
fi
rm -rf "$TMP"
