#!/usr/bin/env bash
# JRA公式の「過去レース結果検索」から、全レースの細部(走破タイム・着差・通過順・上がり・馬体重・斤量・性齢・枠・調教師・馬のID・ブリンカー・ハロンタイム・競走中の出来事)を集める(2026-10-26〜)
# 目的: 自分のスピード指数(馬場とペースで補正したタイム)と、前走の不利(出来事の被害馬・発走の遅れなど)がオッズより当たるかを確かめる。
#   history.sh(競馬ラボ)のレース.jsonl には着順・オッズ・4角・上がりしかなく、この確かめができなかった
# 使い方: bash 自動実行/全レース/jra_history.sh [開始の年月 YYYYMM] [終了の年月 YYYYMM] [最大の分数]   (省略すると 200501〜今月・時間制限なし)
#   新しい月から順に集める。取得済みの開催日(JRA済み日.txt)は飛ばすので、途中で止めても続きから再開できる
# 出力: 馬情報/過去レースデータ/全期間/<年>/JRA詳細.jsonl  1行1レース {id, date, race{dist surface course going weather cls kinType}, laps, last3f, events, horses[jra.pl result の order]}
#   id は history.sh と同じ(YYYYMMDD + 場コード2桁 + レース番号2桁)なので、レース.jsonl(確定オッズ・人気)とそのまま突き合わせられる
#   出来事(events)はJRAのページに2018年ごろから載っている。ハロンタイム・通過順は2010年には載っている
#   大きいのでGitHubには送らない(全期間/ は .gitignore)。競馬ラボとは別のサイトなので history.sh と同時に回してよい
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${JRA_OUT:-$ROOT/馬情報/過去レースデータ/全期間}"   # JRA_OUT は試すとき用
FROM="${1:-200501}"; TO="${2:-$(TZ=Asia/Tokyo date +%Y%m)}"; MAXMIN="${3:-0}"
START=$(date +%s)
export UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
export HERE
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
over() { [ "$MAXMIN" -gt 0 ] && [ $(( ($(date +%s) - START) / 60 )) -ge "$MAXMIN" ]; }
jget() { curl -sSL -m 30 -A "$UA" -o "$2" -d "cname=$1" "https://www.jra.go.jp/JRADB/accessS.html"; sleep 0.7; }
export -f jget

# 年月 → 月のページの cname の末尾2桁。検索ページの objParam["YYMM"]="XX" から取る
jget pw01skl00999999/B3 "$W/search.html"
grep -o 'objParam\["[0-9]\{4\}"\]="[0-9A-F]\{2\}"' "$W/search.html" | sed 's/objParam\["\([0-9]*\)"\]="\(..\)"/\1 \2/' > "$W/param.txt"
[ -s "$W/param.txt" ] || { echo "JRAの検索ページが読めない(つながらない可能性)。止めます"; exit 1; }
# 今月・先月の開催日は過去検索に出ないことがあるので、結果のトップ(最近の開催日の一覧)も見る
jget pw01sli00/AF "$W/top.html"

# 1レース分: ページを取り、jra.pl result で読んで1行のJSONにする。xargs から呼ぶ
race() {
  local cn="$1" dir="$2" f; f="$dir/$(echo "$cn" | tr '/' '_')"
  jget "$cn" "$f.html"
  perl "$HERE/jra.pl" result "$f.html" > "$f.json" 2>/dev/null || { rm -f "$f.json"; return 0; }
  CN="$cn" perl -MJSON::PP -0777 -ne '
    my $d = decode_json($_); my ($v, $r, $ymd) = $ENV{CN} =~ /^pw01sde10(\d{2})\d{8}(\d{2})(\d{8})\//; exit 0 unless $ymd;
    my %o = (id => "$ymd$v$r", date => sprintf("%s-%s-%s", substr($ymd,0,4), substr($ymd,4,2), substr($ymd,6,2)), horses => $d->{order});
    $o{$_} = $d->{$_} for grep { exists $d->{$_} } qw(race laps last3f events);
    print JSON::PP->new->canonical->encode(\%o), "\n"' "$f.json" > "$f.line" 2>/dev/null
  return 0
}
export -f race

M="$TO"
while [ "$M" -ge "$FROM" ]; do
  Y=${M:0:4}; YD="$OUT/$Y"; mkdir -p "$YD"; touch "$YD/JRA済み日.txt"
  NEXT=$(date -d "${M:0:4}-${M:4:2}-01 -1 month" +%Y%m)
  P=$(awk -v k="${M:2:4}" '$1 == k { print $2 }' "$W/param.txt")
  if [ -z "$P" ]; then M=$NEXT; continue; fi
  over && { echo "時間切れ: $M から再開"; exit 0; }
  jget "pw01skl10$M/$P" "$W/month.html"
  # 開催日ごとの一覧(場コード・日付)。新しい日から
  grep -ho "pw01srl10[0-9]*/[0-9A-F]\{2\}" "$W/month.html" "$W/top.html" | grep "^pw01srl10[0-9]\{10\}$M" | sort -u | awk '{ print substr($0, 20, 8), $0 }' | sort -r > "$W/days.txt"
  while read -r D CN; do
    KEY="$D ${CN:9:2}"
    grep -qx "$KEY" "$YD/JRA済み日.txt" && continue
    [ "$D" -ge "$(TZ=Asia/Tokyo date +%Y%m%d)" ] && continue   # 今日以降(結果がまだ)は取らない
    over && { echo "時間切れ: $M から再開"; exit 0; }
    jget "$CN" "$W/day.html"
    rm -rf "$W/h"; mkdir -p "$W/h"
    grep -o "pw01sde10[0-9]*/[0-9A-F]\{2\}" "$W/day.html" | sort -u > "$W/races.txt"
    N=$(wc -l < "$W/races.txt"); [ "$N" -eq 0 ] && continue
    xargs -P 2 -I{} bash -c 'race "$1" "$2"' _ {} "$W/h" < "$W/races.txt"
    ok=$(cat "$W/h"/*.line 2>/dev/null | grep -c '^{')
    cat "$W/h"/*.line 2>/dev/null | grep '^{' >> "$YD/JRA詳細.jsonl"
    echo "$D 場${CN:9:2}: $ok / $N レース"
    [ "$ok" -gt 0 ] && echo "$KEY" >> "$YD/JRA済み日.txt"
  done < "$W/days.txt"
  M=$NEXT
done
echo "JRA詳細: 完了 ($FROM〜$TO)"
