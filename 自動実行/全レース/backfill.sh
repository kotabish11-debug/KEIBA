#!/usr/bin/env bash
# 終わったレースを、レース前の馬柱(能力値の自動計算+生のデータ)と結果の組で集める。重みやオッズの比重を当てはめ直すための学習データ
# 使い方: bash 自動実行/全レース/backfill.sh <出力フォルダー> <開始日 YYYYMMDD> <終了日 YYYYMMDD>
# 出力: <出力フォルダー>/<レースID>.json(1レース1ファイル。取得済みは飛ばすので、途中で止めてもやり直せる)
#   { id, date, place, surface, dist, cls, going, heads, horses: [ 能力値(race_json.pl) + 生のデータ(features.pl) + rank・pop・odds(確定) ] }
# 重賞は race_json.pl が能力値を作らないので入らない
set -uo pipefail
OUT="$1"; FROM="$2"; TO="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$OUT/_tmp"; mkdir -p "$OUT" "$TMP"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
get() { curl -sSL -A "$UA" -H "Accept-Language: ja" -o "$2" "https://www.keibalab.jp/db/race/$1"; sleep 1.2; }
D="$FROM"
while [ "$D" -le "$TO" ]; do
  get "$D/" "$TMP/day.html"
  for ID in $(grep -o "/db/race/${D}[0-9]\{4\}/" "$TMP/day.html" | sed 's#/db/race/##; s#/##' | sort -u); do
    [ -s "$OUT/$ID.json" ] && continue
    get "$ID/umabashira.html" "$TMP/u.html"
    perl "$HERE/race_json.pl" "$TMP/u.html" "$ID" > "$TMP/r.json" 2>/dev/null || continue
    perl "$HERE/features.pl" "$TMP/u.html" > "$TMP/f.json" 2>/dev/null || continue
    get "$ID/raceresult.html" "$TMP/res.html"
    perl "$HERE/result_json.pl" "$TMP/res.html" > "$TMP/res.json" 2>/dev/null || continue
    perl -Mutf8 -MJSON::PP -e '
      my $J = JSON::PP->new->utf8; my @d = map { local $/; open my $h, "<:raw", $_ or die; $J->decode(<$h>) } @ARGV[0 .. 2];
      my ($r, $f, $res) = @d; my %f = map { $_->{name} => $_ } @{$f->{horses}}; my %o = map { $_->{name} => $_ } @{$res->{order}};
      my @hs;
      for my $h (@{$r->{horses}}) {
        my $x = $f{$h->{name}} or next; my $o = $o{$h->{name}} or next;
        my %y = map { $_ => $h->{$_} } grep { exists $h->{$_} } qw(name umaban waku style jisseki kyori course choshi kishu heavy sireType damsireType mustLead fromShort);
        $y{axisPt} = 0; $y{axisPt} += $_->{pt} for @{$h->{axisCheck} // []};
        $y{$_} = $x->{$_} for grep { $_ ne "name" && $_ ne "umaban" && $_ ne "odds" } keys %$x;
        $y{rank} = $o->{rank}; $y{pop} = $o->{pop}; $y{odds} = $o->{odds}; $y{last4} = $o->{last4}; $y{f3} = $o->{f3};
        push @hs, \%y;
      }
      my ($cls) = ($r->{cond} // "") =~ /^(\S+)/;
      print JSON::PP->new->utf8->canonical->encode({ id => $r->{keibalabId}, date => $r->{date}, place => $r->{place}, no => $r->{no}, surface => $r->{surface},
        dist => $r->{dist}, cond => $r->{cond}, cls => $cls, going => $r->{going}, heads => scalar @hs, horses => \@hs });
    ' "$TMP/r.json" "$TMP/f.json" "$TMP/res.json" > "$OUT/$ID.json" || rm -f "$OUT/$ID.json"
  done
  D=$(date -d "${D:0:4}-${D:4:2}-${D:6:2} +1 day" +%Y%m%d)
done
rm -rf "$TMP"
echo "done: $(ls "$OUT"/*.json 2>/dev/null | wc -l) races"
