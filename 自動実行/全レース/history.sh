#!/usr/bin/env bash
# 2005年以降の全レース(重賞・G1・障害・新馬を含む)の結果・確定オッズ・払戻を集める。買い方(複勝・ワイドなど)を長い期間・全クラスで確かめるため(2026-10-26〜)
# 使い方: bash 自動実行/全レース/history.sh [開始日 YYYYMMDD] [終了日 YYYYMMDD] [最大の分数]   (省略すると 20050101〜昨日・時間制限なし)
#   新しい日から順に集める。取得済みの日(済み日.txt)は飛ばすので、途中で止めても続きから再開できる。最大の分数を過ぎたら止まる(PC収集から少しずつ回すため)
# 出力: 馬情報/過去レースデータ/全期間/<年>/ に 1行1レースの
#   レース.jsonl     {id date place no name grade surface dist cond cls going weather heads horses[{umaban name rank pop odds last4 f3 jockey}]}
#                    平場_*.jsonl.gz と同じ項目名なので、自動実行/検証/ のスクリプトにそのまま渡せる(能力値は入らない)
#                    cls は平場_*と同じ書き方(3歳上1勝クラス など)。旧クラス名(500万・1000万・1600万)は今の名前に直す
#   払戻.jsonl       pay_json.pl の形   複勝オッズ.jsonl {"id","fuku":{"<馬番>":[下限,上限]}}
#   ワイド.jsonl     {"id","wide":{"<馬番>-<馬番>":[下限,上限]}}  スポーツナビは制限が厳しいので history_wide.sh がゆっくり別に集める
#   大きいのでGitHubには送らない(.gitignore)。検証は PC で行う。複勝オッズは2005年ごろからしか残っていない
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/馬情報/過去レースデータ/全期間"
FROM="${1:-20050101}"; TO="${2:-$(TZ=Asia/Tokyo date -d yesterday +%Y%m%d)}"; MAXMIN="${3:-0}"
START=$(date +%s)
export UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
over() { [ "$MAXMIN" -gt 0 ] && [ $(( ($(date +%s) - START) / 60 )) -ge "$MAXMIN" ]; }

# 1レース分のページ(結果・単複オッズ)を取る。xargs から呼ぶ
fetch() {
  curl -sSL -m 30 -A "$UA" -H "Accept-Language: ja" -o "$2/$1.res.html" "https://www.keibalab.jp/db/race/$1/raceresult.html"; sleep 1
  curl -sSL -m 30 -A "$UA" -H "Accept-Language: ja" -o "$2/$1.odds.html" "https://www.keibalab.jp/db/race/$1/odds.html"; sleep 1
  return 0
}
export -f fetch

D="$TO"
while [ "$D" -ge "$FROM" ]; do
  Y=${D:0:4}; YD="$OUT/$Y"; mkdir -p "$YD"; touch "$YD/済み日.txt"
  NEXT=$(date -d "${D:0:4}-${D:4:2}-${D:6:2} -1 day" +%Y%m%d)
  if grep -qx "$D" "$YD/済み日.txt"; then D=$NEXT; continue; fi
  over && { echo "時間切れ: $D から再開"; exit 0; }
  # 競馬ラボのその日のレース一覧(開催の無い日も見る。ページが取れなかったときは止める)
  curl -sSL -m 30 -A "$UA" -H "Accept-Language: ja" -o "$W/day.html" "https://www.keibalab.jp/db/race/$D/"; sleep 1
  grep -q "<title>" "$W/day.html" || { echo "$D: 一覧が取れない(競馬ラボにつながらない可能性)。止めます"; exit 1; }
  grep -o "/db/race/${D}[0-9]\{4\}/" "$W/day.html" | sed 's#/db/race/##; s#/##' | sort -u > "$W/todo.txt"
  N=$(wc -l < "$W/todo.txt")
  if [ "$N" -eq 0 ]; then echo "$D" >> "$YD/済み日.txt"; D=$NEXT; continue; fi
  rm -rf "$W/h"; mkdir -p "$W/h"
  xargs -P 3 -I{} bash -c 'fetch "$1" "$2"' _ {} "$W/h" < "$W/todo.txt"
  ok=0
  while read -r ID; do
    H="$W/h/$ID"
    perl "$HERE/result_json.pl" "$H.res.html" > "$W/res.json" 2>/dev/null || continue
    perl -Mutf8 -MJSON::PP -0777 -e '
      my ($id, $resf, $html) = @ARGV; local $/; open my $fh, "<:raw", $resf or die; my $res = JSON::PP->new->utf8->decode(<$fh>);
      open my $hh, "<:raw", $html or die; my $h = <$hh>; utf8::decode($h);
      my %P = qw(01 札幌 02 函館 03 福島 04 新潟 05 東京 06 中山 07 中京 08 京都 09 阪神 10 小倉);
      my ($name, $gr) = $h =~ /class="raceTitle[^"]*"[^>]*>\s*(.*?)\s*<span class="std8">\s*(.*?)\s*<\/span>/s; $name //= ""; $name =~ s/<[^>]*>//g;
      my ($wg) = $h =~ /class="weather_ground[^"]*">(.*?)<\/ul>/s; my @wg = ($wg // "") =~ /<li[^>]*>\s*([^<]*?)\s*<\/li>/g;
      my ($cc) = $h =~ /class="classCourseSyokin[^"]*"[^>]*>(.*?)<\/ul>/s; my @li = map { my $x = $_; $x =~ s/<[^>]*>//g; $x =~ s/&nbsp;/ /g; $x =~ s/\x{3000}/ /g; $x =~ s/^\s+|\s+$//g; $x } (($cc // "") =~ /<li[^>]*>(.*?)<\/li>/sg);
      my $cond = $li[0] // ""; my ($cls) = $cond =~ /^(\S+)/; $cls //= "";
      # 特別・重賞は条件の行の先頭がクラス。平場(未勝利・新馬・1勝クラスなど)はレース名(サラ系2歳未勝利)がクラス
      if ($cls !~ /歳/) { $cls = $name; $cls =~ s/^サラ系//; $cond = "$cls $cond" }
      $cls =~ s/以上/上/; $cls =~ s/500万(下)?/1勝クラス/; $cls =~ s/1000万(下)?/2勝クラス/; $cls =~ s/1600万(下)?/3勝クラス/;
      my ($sf, $dist) = ($li[1] // "") =~ /^(\S*?)(\d{3,4})m/; $sf //= "";
      my $surface = $cls =~ /障害/ || $sf =~ /障/ ? "障" : $sf =~ /ダ/ ? "ダ" : $sf =~ /芝/ ? "芝" : $sf;
      $gr //= ""; $gr =~ tr/ＧⅠⅡⅢＪｐｎＬ（）/G123JpnL()/; $gr =~ s/[()]//g;
      my @hs = map { my $o = $_; +{ map { exists $o->{$_} ? ($_ => $o->{$_}) : () } qw(umaban name rank pop odds last4 f3 jockey) } } @{$res->{order}};
      print JSON::PP->new->utf8->canonical->encode({ id => $id, date => sprintf("%s-%s-%s", substr($id,0,4), substr($id,4,2), substr($id,6,2)),
        place => $P{substr($id,8,2)}, no => substr($id,10,2) + 0, name => $name, grade => $gr, surface => $surface, dist => ($dist // 0) + 0,
        cond => $cond, cls => $cls, weather => $wg[0] // "", going => $wg[1] // "", heads => $res->{heads} // scalar(@hs), horses => \@hs }), "\n";
    ' "$ID" "$W/res.json" "$H.res.html" >> "$YD/レース.jsonl" || continue
    perl "$HERE/pay_json.pl" "$H.res.html" "$ID" >> "$YD/払戻.jsonl" 2>/dev/null
    ID="$ID" perl -MJSON::PP -0777 -ne '
      my %o; if (/id="oddsTanTable"(.*?)<\/table>/s) { my $t = $1;
        while ($t =~ /<tr[^>]*>(.*?)<\/tr>/sg) { my @c = map { my $x = $_; $x =~ s/<[^>]*>//g; $x =~ s/\s+//g; $x } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
          next unless @c >= 6 && $c[1] =~ /^\d+$/; my ($lo, $hi) = ($c[4], $c[6] // ""); $hi = $c[5] if $hi eq "" || $hi !~ /^[\d.]+$/;
          $o{$c[1]} = [$lo + 0, $hi + 0] if $lo =~ /^[\d.]+$/ && $hi =~ /^[\d.]+$/ } }
      print JSON::PP->new->canonical->encode({ id => $ENV{ID}, fuku => \%o }), "\n" if %o' "$H.odds.html" >> "$YD/複勝オッズ.jsonl" 2>/dev/null
    ok=$((ok + 1))
  done < "$W/todo.txt"
  echo "$D: $ok / $N レース"
  # 一部取れなかった日も済みにする(結果の無い中止レースなど)。全部取れなかった日は次の実行でやり直す
  [ "$ok" -gt 0 ] && echo "$D" >> "$YD/済み日.txt"
  D=$NEXT
done
echo "全期間: 完了 ($FROM〜$TO)"
