#!/usr/bin/env bash
# 競馬ニュースの見出しを集め、まだ取り込んでいないものだけを TSV で標準出力に出す
# 使い方: bash 自動実行/ニュース/collect.sh [--all]
#   列: id 取得元 日時 分類(配信元) 見出し URL
#   取り込み済みの id は 馬情報/ニュース/取得済み.tsv に入っている(--all を付けると全部出す)
#   取得元: スポーツナビ競馬ニュース(2ページ)・JRAニュース(今月と先月)・競馬ラボ トピックス
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SEEN="$ROOT/馬情報/ニュース/取得済み.tsv"
TMP="$(mktemp -d)"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
get() { curl -sSL --max-time 30 -A "$UA" -H "Accept-Language: ja" -o "$TMP/$1" "$2" || echo "# 取得失敗: $2" >&2; sleep 1; }

get y1.html "https://sports.yahoo.co.jp/list/news/keiba?genre=keiba"
get y2.html "https://sports.yahoo.co.jp/list/news/keiba?genre=keiba&page=2"
YM="$(TZ=JST-9 date +%Y%m)"
PM="$(TZ=JST-9 date -d "$(TZ=JST-9 date +%Y-%m-01) -1 day" +%Y%m)"
get j1.raw "https://www.jra.go.jp/news/$YM/"
get j2.raw "https://www.jra.go.jp/news/$PM/"
for f in j1 j2; do [ -s "$TMP/$f.raw" ] && iconv -f SHIFT_JIS -t UTF-8//IGNORE "$TMP/$f.raw" > "$TMP/$f.html" 2>/dev/null; done
get k1.html "https://www.keibalab.jp/topics/"

{
  for f in y1 y2; do [ -s "$TMP/$f.html" ] && perl "$HERE/parse.pl" yahoo "$TMP/$f.html"; done
  [ -s "$TMP/j1.html" ] && perl "$HERE/parse.pl" jra "$TMP/j1.html" "$YM"
  [ -s "$TMP/j2.html" ] && perl "$HERE/parse.pl" jra "$TMP/j2.html" "$PM"
  [ -s "$TMP/k1.html" ] && perl "$HERE/parse.pl" keibalab "$TMP/k1.html"
} | awk -F'\t' '!seen[$1]++' > "$TMP/all.tsv"

if [ "${1:-}" = "--all" ] || [ ! -s "$SEEN" ]; then
  cat "$TMP/all.tsv"
else
  awk -F'\t' 'NR==FNR { seen[$1]=1; next } !seen[$1]' "$SEEN" "$TMP/all.tsv"
fi
echo "# 見出し $(wc -l < "$TMP/all.tsv") 件を取得($(TZ=JST-9 date '+%Y-%m-%d %H:%M'))" >&2
rm -rf "$TMP"
