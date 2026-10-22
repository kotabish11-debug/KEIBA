#!/usr/bin/env bash
# 東京・京都・新潟の全レースを集めてシミュレーター用のデータを作り、終わったレースは振り返り、重みを最適化する
# 使い方: bash 自動実行/全レース/run.sh <出力フォルダー> [dbを保存したフォルダー]
#   dbを保存したフォルダー: ArtifactData の list(collection "races", out_dir 指定)で保存した場所。races/<id>.json を探す
# 取得元: 競馬ラボ(keibalab.jp)につながらなければ、スポーツナビ(yahoo.pl)の出馬表・馬ページ・結果で作る。SOURCE=yahoo か SOURCE=keibalab で決め打ちできる
#   スポーツナビでは馬ページを1頭ずつ取るので、1回の実行で取るのは YBUDGET 秒(既定300)まで。取り切れなかったレースは次の実行に回す
# 出力: <出力フォルダー>/manifest.tsv に「何をdbに書くか」を1行ずつ出す(定期実行のClaudeがこれを見て書き込む)
#   race   <doc_id> <file>  … races/<doc_id> を set(新規または作り直し)
#   update <doc_id> <file>  … races/<doc_id> を update(★・結果・振り返りを足す)
#   model  config/model <file> … config/model を set(最適化した重みと★の基準)
set -uo pipefail
OUT="$1"; DBDIR="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
VENUES="${VENUES:-04 05 08}"   # 04新潟 05東京 08京都
MODEL="$HERE/model.json"
LOGR="$ROOT/馬情報/予想と結果_レース.csv"; LOGH="$ROOT/馬情報/予想と結果_馬ごと.csv"
mkdir -p "$OUT/races" "$OUT/updates" "$OUT/tmp" "$ROOT/馬情報/振り返り"
: > "$OUT/manifest.tsv"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
get() { curl -sSL -A "$UA" -H "Accept-Language: ja" -o "$2" "https://www.keibalab.jp/db/race/$1"; sleep 1.5; }
SOURCE="${SOURCE:-}"
if [ -z "$SOURCE" ]; then
  SOURCE=keibalab
  curl -sS -m 20 -o /dev/null -A "$UA" https://www.keibalab.jp/ 2>/dev/null || { sleep 10; curl -sS -m 20 -o /dev/null -A "$UA" https://www.keibalab.jp/ 2>/dev/null; } || SOURCE=yahoo
fi
echo "取得元: $SOURCE"
YBUDGET="${YBUDGET:-300}"; YSTART=$SECONDS; HC="$OUT/hc"; mkdir -p "$HC"
yget() { curl -sSL -A "$UA" -o "$2" "https://sports.yahoo.co.jp/keiba/$1"; sleep 0.3; }
# 日付と場コード → スポーツナビの開催ID(8桁: 年2+場2+回2+日2)を YK に入れる(月の日程ページから引く)
declare -A YKAI
ykai() {
  local key="$1 $2"
  if [ -z "${YKAI[$key]+x}" ]; then
    local sf="$OUT/tmp/sch_${1:0:4}${1:5:2}.html"
    [ -s "$sf" ] || yget "schedule/monthly/?year=${1:0:4}&month=$((10#${1:5:2}))" "$sf"
    YKAI[$key]=$(perl "$HERE/yahoo.pl" list "$sf" "$1" "$2" 2>/dev/null)
  fi
  YK="${YKAI[$key]}"
}
# スポーツナビの出馬表と馬ページから $OUT/tmp/r_$ID.json を作る(終了コードは race_json.pl と同じ。馬ページが取り切れなければ 4)
ybuild() {
  ykai "$DISO" "$V"; [ -z "$YK" ] && return 2
  yget "race/denma/$YK$R" "$OUT/tmp/yd_$ID.html"
  # 馬ページは3つずつ並べて取る(取得済みの馬は飛ばす)。持ち時間を過ぎたら取らない
  if [ $((SECONDS - YSTART)) -lt "$YBUDGET" ]; then
    perl "$HERE/yahoo.pl" need "$OUT/tmp/yd_$ID.html" "$DBFILE" | while read -r hid; do [ -s "$HC/$hid.html" ] || echo "$hid"; done |
      xargs -r -P 3 -I{} sh -c 'curl -sSL -m 30 -A "$1" -o "$2/{}.html" "https://sports.yahoo.co.jp/keiba/directory/horse/{}/"; sleep 0.3' _ "$UA" "$HC"
  fi
  perl "$HERE/yahoo.pl" raw "$OUT/tmp/yd_$ID.html" "$HC" "$ID" "$DBFILE" > "$OUT/tmp/yr_$ID.json" || return $?
  perl "$HERE/race_json.pl" "$OUT/tmp/yr_$ID.json" "$ID" > "$OUT/tmp/r_$ID.json"
}
NOW=$(TZ=JST-9 date +%Y%m%d%H%M)
declare -A PLACE=( [04]=新潟 [05]=東京 [08]=京都 [06]=中山 [09]=阪神 [07]=中京 [01]=札幌 [02]=函館 [03]=福島 [10]=小倉 )
[ -f "$LOGR" ] || echo "raceId,date,place,no,name,grade,star,starProb,honmei,honmeiRank,winner,winnerPop,winnerPredRank,hits3" > "$LOGR"
[ -f "$LOGH" ] || echo "raceId,date,place,surface,dist,grade,name,style,umaban,heads,jisseki,kyori,course,choshi,kishu,odds,predRank,rank,pop" > "$LOGH"
# 当日のトラックバイアス用(終わったレースの全着順。bias.pl が読む)
BIASF="$ROOT/馬情報/当日バイアス.tsv"
[ -f "$BIASF" ] || printf 'date\tplace\tsurface\traceId\tumaban\theads\tlast4\trank\tpop\tsireType\n' > "$BIASF"

# dbにあるレースを (日付 場所 R) → ファイル で引けるようにする
declare -A DBF
if [ -n "$DBDIR" ]; then
  while IFS=$'\t' read -r key f; do DBF[$key]="$f"; done < <(find "$DBDIR" -name '*.json' -print0 2>/dev/null | xargs -0 -r perl -Mutf8 -MJSON::PP -e '
    for my $f (@ARGV) { open my $h, "<:raw", $f or next; local $/; my $d = eval { JSON::PP->new->utf8->decode(<$h>) } or next;
      my ($id, $x) = ref $d->{data} eq "HASH" ? ($d->{id}, $d->{data}) : ($d->{id}, $d); next unless ref $x eq "HASH" && $x->{date} && $x->{place};
      binmode STDOUT, ":utf8"; print "$x->{date} $x->{place} " . ($x->{no} // "") . "\t$f\n" }')
fi
docid_of() { perl -MJSON::PP -0777 -ne 'my $d = JSON::PP->new->utf8->decode($_); print $d->{id} // ""' "$1"; }
field_of() { [ -f "$1" ] || return 0; perl -MJSON::PP -0777 -ne 'my $d = JSON::PP->new->utf8->decode($_); $d = $d->{data} if ref $d->{data} eq "HASH"; print $d->{'"$2"'} // ""' "$1"; }

# 出馬表が出ていれば先の日も入れる(木曜に日曜・祝日月曜の登録が出る)。R1が無い日は1回の取得で飛ばすので軽い
for off in -1 $(seq 0 "${AHEAD:-6}"); do
  D=$(TZ=JST-9 date -d "$off day" +%Y%m%d); DISO="${D:0:4}-${D:4:2}-${D:6:2}"
  for V in $VENUES; do
    for R in 01 02 03 04 05 06 07 08 09 10 11 12; do
      ID="$D$V$R"; KEY="$DISO ${PLACE[$V]} $((10#$R))"; DBFILE="${DBF[$KEY]:-}"
      STAGE=""; [ -n "$DBFILE" ] && STAGE=$(field_of "$DBFILE" stage)
      HASREV=""; [ -n "$DBFILE" ] && HASREV=$(field_of "$DBFILE" review)
      [ -n "$HASREV" ] && continue
      # 発走時刻を過ぎて15分たっていれば、結果を取りにいく
      TIME=""; [ -n "$DBFILE" ] && TIME=$(field_of "$DBFILE" time)
      if [ -z "$DBFILE" ] || [ "$off" -ge 0 ]; then
        if [ "$SOURCE" = yahoo ]; then ybuild; RC=$?
        else
          get "$ID/umabashira.html" "$OUT/tmp/u_$ID.html"
          perl "$HERE/race_json.pl" "$OUT/tmp/u_$ID.html" "$ID" > "$OUT/tmp/r_$ID.json"; RC=$?
        fi
        if [ $RC -eq 2 ]; then [ "$R" = "01" ] && break; continue; fi
        [ -z "$TIME" ] && TIME=$(field_of "$OUT/tmp/r_$ID.json" time)
      else RC=9; fi
      HM=$(echo "$TIME" | tr -d ':'); FIN=0
      if [ -n "$HM" ]; then [ "$NOW" -ge "$(TZ=JST-9 date -d "${DISO} ${TIME} 15 minutes" +%Y%m%d%H%M 2>/dev/null || echo 999999999999)" ] && FIN=1; fi
      [ "$off" -lt 0 ] && FIN=1
      if [ $FIN -eq 0 ]; then
        # これからのレース: 自動のレースは作り直し、重賞(Claudeが作ったdbのデータ)は★だけ更新
        # その日の同じ場・同じ馬場で終わったレースから、当日のトラックバイアスを推定する(根拠が足りなければ空)
        SRC="$OUT/tmp/r_$ID.json"; [ $RC -ne 0 ] && SRC="$DBFILE"
        DAYB=""; [ -n "$SRC" ] && DAYB=$(perl "$HERE/bias.pl" "$BIASF" "$DISO" "${PLACE[$V]}" "$(field_of "$SRC" surface)")
        # 当日と前日は、スポーツナビの単勝・複勝オッズ(1日の予算の複勝の買い方が使う)。fukuAt は取った時刻
        FUKU=""; if [ "$off" -le 1 ]; then ykai "$DISO" "$V"; if [ -n "$YK" ]; then yget "race/odds/tfw/$YK$R" "$OUT/tmp/tfw_$ID.html"; FUKU=$(perl "$HERE/yahoo.pl" fuku "$OUT/tmp/tfw_$ID.html" 2>/dev/null); fi; fi
        FUKUAT=$(TZ=JST-9 date +%Y-%m-%dT%H:%M:00+09:00)
        if [ $RC -eq 0 ] && { [ -z "$DBFILE" ] || [ "$(docid_of "$DBFILE")" = "k$ID" ]; }; then
          ST=$(perl "$HERE/star.pl" "$OUT/tmp/r_$ID.json" "$MODEL")
          perl -Mutf8 -MJSON::PP -0777 -e 'my $d = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $ARGV[0]; <$h> }); my $s = JSON::PP->new->utf8->decode($ARGV[1]);
            $d->{star} = $s->{star}; $d->{starProb} = $s->{starProb}; $d->{starHonmei} = $s->{honmei}; $d->{dayBias} = JSON::PP->new->utf8->decode($ARGV[2]) if $ARGV[2];
            if ($ARGV[3]) { $d->{fuku} = JSON::PP->new->utf8->decode($ARGV[3]); $d->{fukuAt} = $ARGV[4] }
            print JSON::PP->new->utf8->canonical->encode($d)' "$OUT/tmp/r_$ID.json" "$ST" "$DAYB" "$FUKU" "$FUKUAT" > "$OUT/races/k$ID.json"
          printf 'race\tk%s\t%s\n' "$ID" "$OUT/races/k$ID.json" >> "$OUT/manifest.tsv"
        elif [ -n "$DBFILE" ]; then
          DOC=$(docid_of "$DBFILE"); ST=$(perl "$HERE/star.pl" "$DBFILE" "$MODEL")
          perl -Mutf8 -MJSON::PP -e 'my $s = JSON::PP->new->utf8->decode($ARGV[0]); my %u = (star => $s->{star}, starProb => $s->{starProb}, starHonmei => $s->{honmei});
            $u{dayBias} = JSON::PP->new->utf8->decode($ARGV[1]) if $ARGV[1]; if ($ARGV[2]) { $u{fuku} = JSON::PP->new->utf8->decode($ARGV[2]); $u{fukuAt} = $ARGV[3] } print JSON::PP->new->utf8->canonical->encode(\%u)' "$ST" "$DAYB" "$FUKU" "$FUKUAT" > "$OUT/updates/$DOC.json"
          printf 'update\t%s\t%s\n' "$DOC" "$OUT/updates/$DOC.json" >> "$OUT/manifest.tsv"
        fi
        continue
      fi
      # 終わったレース: 結果を取り、予想(dbのデータ。無ければ作り直したもの)と比べる
      if [ "$SOURCE" = yahoo ]; then
        ykai "$DISO" "$V"; [ -z "$YK" ] && continue
        yget "race/result/$YK$R" "$OUT/tmp/res_$ID.html"
        perl "$HERE/yahoo.pl" result "$OUT/tmp/res_$ID.html" > "$OUT/tmp/res_$ID.json" || continue
      else
        get "$ID/raceresult.html" "$OUT/tmp/res_$ID.html"
        perl "$HERE/result_json.pl" "$OUT/tmp/res_$ID.html" > "$OUT/tmp/res_$ID.json" || continue
      fi
      PRED="$DBFILE"; [ -z "$PRED" ] && [ $RC -eq 0 ] && PRED="$OUT/tmp/r_$ID.json"
      [ -z "$PRED" ] && continue
      DOC=$(docid_of "$PRED"); [ -z "$DOC" ] && DOC="k$ID"
      perl "$HERE/review.pl" "$PRED" "$OUT/tmp/res_$ID.json" "$MODEL" > "$OUT/tmp/rev_$ID.json" || continue
      # すでに結果が記録されているレース(重賞など)は結果を上書きせず、振り返りだけ足す
      perl -Mutf8 -MJSON::PP -0777 -e 'my $r = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $ARGV[0]; <$h> });
        my @top = @{$r->{result}{order}}; my %u = (review => $r->{review});
        utf8::decode($ARGV[1]); if ($ARGV[1] ne "結果確定") { $u{stage} = "結果確定"; $u{result} = { order => [map { $_->{name} } @top[0 .. ($#top < 4 ? $#top : 4)]], detail => [@top[0 .. ($#top < 4 ? $#top : 4)]] } }
        print JSON::PP->new->utf8->canonical->encode(\%u)' "$OUT/tmp/rev_$ID.json" "$STAGE" > "$OUT/updates/$DOC.json"
      if [ -n "$DBFILE" ]; then printf 'update\t%s\t%s\n' "$DOC" "$OUT/updates/$DOC.json" >> "$OUT/manifest.tsv"
      else perl -Mutf8 -MJSON::PP -0777 -e 'my ($a, $b) = map { JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $_; <$h> }) } @ARGV; $a->{$_} = $b->{$_} for keys %$b; print JSON::PP->new->utf8->canonical->encode($a)' "$PRED" "$OUT/updates/$DOC.json" > "$OUT/races/$DOC.json"
        printf 'race\t%s\t%s\n' "$DOC" "$OUT/races/$DOC.json" >> "$OUT/manifest.tsv"; fi
      # 記録(まだ書いていないレースだけ)
      if ! grep -q "^$DOC," "$LOGR"; then
        perl -Mutf8 -MJSON::PP -0777 -e 'binmode STDOUT, ":utf8"; my ($pf, $rf, $lr, $lh) = @ARGV;
          my $p = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $pf; <$h> }); $p = $p->{data} if ref $p->{data} eq "HASH";
          my $r = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $rf; <$h> }); my $v = $r->{review};
          my $id = $r->{rows}[0]{raceId} // $p->{id}; my ($w) = @{$v->{top3}}; my ($hm) = @{$v->{marks}};
          open my $A, ">>:utf8", $lr; print $A join(",", $id, $p->{date}, $p->{place}, $p->{no}, $p->{name}, $p->{grade} // "", $p->{star} ? 1 : 0, $p->{starProb} // "", $hm->{name}, $hm->{rank} // "", $w->{name}, $w->{pop} // "", $w->{predRank} // "", $v->{hits3}), "\n";
          open my $B, ">>:utf8", $lh; for my $x (@{$r->{rows}}) { print $B join(",", map { my $t = $x->{$_} // ""; $t =~ s/,/、/g; $t } qw(raceId date place surface dist grade name style umaban heads jisseki kyori course choshi kishu odds predRank rank pop)), "\n" }' \
          "$PRED" "$OUT/tmp/rev_$ID.json" "$LOGR" "$LOGH"
        # 当日のトラックバイアス用に、全着順の馬番・4角の位置・人気を残す
        perl -Mutf8 -MJSON::PP -0777 -e 'binmode STDOUT, ":utf8"; my ($pf, $rf, $id, $out) = @ARGV;
          my $p = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $pf; <$h> }); $p = $p->{data} if ref $p->{data} eq "HASH";
          my $r = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $rf; <$h> });
          my %st = map { $_->{name} => ($_->{sireType} // "") } @{$p->{horses} || []};
          open my $A, ">>:utf8", $out; for my $x (@{$r->{order} || []}) { next unless ($x->{rank} // "") =~ /^\d+$/;
            print $A join("\t", $p->{date}, $p->{place}, $p->{surface} // "", $id, $x->{umaban} // "", $r->{heads} // "", $x->{last4} // "", $x->{rank}, $x->{pop} // "", $st{$x->{name}} // ""), "\n" }' \
          "$PRED" "$OUT/tmp/res_$ID.json" "$ID" "$BIASF"
        # 振り返りを日ごとのファイルにも残す
        perl -Mutf8 -MJSON::PP -0777 -e 'binmode STDOUT, ":utf8"; my ($pf, $rf) = @ARGV;
          my $p = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $pf; <$h> }); $p = $p->{data} if ref $p->{data} eq "HASH";
          my $v = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $rf; <$h> })->{review};
          print "\n## $p->{place}$p->{no}R $p->{name}" . ($p->{grade} ? " ($p->{grade})" : "") . ($p->{star} ? " ★" : "") . "\n";
          print "- 予想: " . join(" ", map { "$_->{mark}$_->{name}(" . ($_->{rank} // "?") . "着)" } @{$v->{marks}}) . "\n";
          print "- 結果: " . join(" ", map { "$_->{rank}着 $_->{name}(" . ($_->{pop} // "?") . "番人気・予想" . ($_->{predRank} // "?") . "位)" } @{$v->{top3}}) . "\n";
          print "- 違った点: " . join(" / ", @{$v->{diff}}) . "\n- 次への改善: " . join(" / ", @{$v->{next}}) . "\n"' \
          "$PRED" "$OUT/tmp/rev_$ID.json" >> "$ROOT/馬情報/振り返り/$DISO.md.tmp"
      fi
    done
  done
done
# 日ごとの振り返りファイルにまとめる
mkdir -p "$ROOT/馬情報/振り返り"
for t in "$ROOT"/馬情報/振り返り/*.md.tmp; do [ -e "$t" ] || continue; f="${t%.tmp}"; [ -f "$f" ] || echo "# $(basename "$f" .md) の予想の振り返り" > "$f"; cat "$t" >> "$f"; rm -f "$t"; done 2>/dev/null
# 重みと★の基準を最適化
perl "$HERE/optimize.pl" "$LOGH" "$LOGR" "$MODEL" > "$OUT/model.json" && cp "$OUT/model.json" "$MODEL"
printf 'model\tconfig/model\t%s\n' "$OUT/model.json" >> "$OUT/manifest.tsv"
echo "manifest: $(wc -l < "$OUT/manifest.tsv") 件"; cut -f1 "$OUT/manifest.tsv" | sort | uniq -c
