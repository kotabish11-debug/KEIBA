#!/usr/bin/env bash
# 学習データ(平場_*.jsonl.gz)のレースの確定の複勝オッズ(下限・上限)を競馬ラボから集めて、1つのファイルに足す(fuku_odds.sh の並行・追記版)
# 使い方: bash 自動実行/全レース/fuku_odds_all.sh [学習データ.jsonl.gz ...]
# 出力: 馬情報/過去レースデータ/複勝オッズ.jsonl.gz(1行1レース {"id","fuku":{"<馬番>":[下限,上限]}})。初回は 複勝オッズ_2026-08-01_10-19.jsonl.gz の分を引き継ぐ
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; D="$ROOT/馬情報/過去レースデータ"
OUTGZ="$D/複勝オッズ.jsonl.gz"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
[ $# -eq 0 ] && set -- "$D"/平場_*.jsonl.gz
{ [ -s "$OUTGZ" ] && zcat "$OUTGZ"; [ -s "$D/複勝オッズ_2026-08-01_10-19.jsonl.gz" ] && zcat "$D/複勝オッズ_2026-08-01_10-19.jsonl.gz"; } | perl -ne 'print if /"id":"(\d+)"/ && !$s{$1}++' > "$W/new.jsonl"
grep -o '"id":"[0-9]\{12\}"' "$W/new.jsonl" | grep -o '[0-9]\{12\}' | sort -u > "$W/have.txt"
for g in "$@"; do zcat "$g" | grep -o '"id":"[0-9]\{12\}"' | grep -o '[0-9]\{12\}'; done | sort -u | comm -23 - "$W/have.txt" > "$W/todo.txt"
echo "複勝オッズ: $(wc -l < "$W/todo.txt") レースを取得"
mkdir -p "$W/h"; split -l 90 "$W/todo.txt" "$W/part_"
for part in "$W"/part_*; do
  xargs -P 3 -I{} sh -c 'curl -sSL -m 30 -A "$1" -H "Accept-Language: ja" -o "$2/{}.html" "https://www.keibalab.jp/db/race/{}/odds.html"; sleep 1' _ "$UA" "$W/h" < "$part"
  while read -r ID; do
    ID="$ID" perl -MJSON::PP -0777 -ne '
      my %o; if (/id="oddsTanTable"(.*?)<\/table>/s) { my $t = $1;
        while ($t =~ /<tr[^>]*>(.*?)<\/tr>/sg) { my @c = map { my $x = $_; $x =~ s/<[^>]*>//g; $x =~ s/\s+//g; $x } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
          next unless @c >= 6 && $c[1] =~ /^\d+$/; my ($lo, $hi) = ($c[4], $c[6] // ""); $hi = $c[5] if $hi eq "" || $hi !~ /^[\d.]+$/;
          $o{$c[1]} = [$lo + 0, $hi + 0] if $lo =~ /^[\d.]+$/ && $hi =~ /^[\d.]+$/ } }
      print JSON::PP->new->canonical->encode({ id => $ENV{ID}, fuku => \%o }), "\n" if %o' "$W/h/$ID.html" >> "$W/new.jsonl" 2>/dev/null
    rm -f "$W/h/$ID.html"
  done < "$part"
  gzip -c "$W/new.jsonl" > "$OUTGZ.tmp" && mv "$OUTGZ.tmp" "$OUTGZ"
done
echo "複勝オッズ: 合計 $(zcat "$OUTGZ" | wc -l) レース"
