#!/usr/bin/env bash
# backfill.sh で集めたレースの、確定の複勝オッズ(下限・上限)を競馬ラボのオッズページから取る
# 使い方: bash 自動実行/全レース/fuku_odds.sh <出力フォルダー> <backfillのフォルダー>...
# 出力: <出力フォルダー>/<レースID>.json  {"<馬番>": [下限, 上限], ...}
set -uo pipefail
OUT="$1"; shift; mkdir -p "$OUT"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
for d in "$@"; do
  for f in "$d"/*.json; do
    ID=$(basename "$f" .json); [ -s "$OUT/$ID.json" ] && continue
    curl -sSL -A "$UA" -H "Accept-Language: ja" -o "$OUT/_o.html" "https://www.keibalab.jp/db/race/$ID/odds.html"; sleep 1.2
    perl -MJSON::PP -0777 -ne '
      my %o; if (/id="oddsTanTable"(.*?)<\/table>/s) { my $t = $1;
        while ($t =~ /<tr[^>]*>(.*?)<\/tr>/sg) { my @c = map { my $x = $_; $x =~ s/<[^>]*>//g; $x =~ s/\s+//g; $x } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
          next unless @c >= 6 && $c[1] =~ /^\d+$/; my ($lo, $hi) = ($c[4], $c[6] // ""); $hi = $c[5] if $hi eq "" || $hi !~ /^[\d.]+$/;
          $o{$c[1]} = [$lo + 0, $hi + 0] if $lo =~ /^[\d.]+$/ && $hi =~ /^[\d.]+$/ } }
      print encode_json(\%o) if %o' "$OUT/_o.html" > "$OUT/$ID.json" || true
    [ -s "$OUT/$ID.json" ] || rm -f "$OUT/$ID.json"
  done
done
rm -f "$OUT/_o.html"
echo "done: $(ls "$OUT" | grep -c json) races"
