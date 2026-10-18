#!/usr/bin/env bash
# 東京・京都・新潟の全レースを集めてシミュレーター用のデータを作り、終わったレースは振り返り、重みを最適化する
# 使い方: bash 自動実行/全レース/run.sh <出力フォルダー> [dbを保存したフォルダー]
#   dbを保存したフォルダー: ArtifactData の list(collection "races", out_dir 指定)で保存した場所。races/<id>.json を探す
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
NOW=$(TZ=JST-9 date +%Y%m%d%H%M)
declare -A PLACE=( [04]=新潟 [05]=東京 [08]=京都 [06]=中山 [09]=阪神 [07]=中京 [01]=札幌 [02]=函館 [03]=福島 [10]=小倉 )
[ -f "$LOGR" ] || echo "raceId,date,place,no,name,grade,star,starProb,honmei,honmeiRank,winner,winnerPop,winnerPredRank,hits3" > "$LOGR"
[ -f "$LOGH" ] || echo "raceId,date,place,surface,dist,grade,name,style,umaban,heads,jisseki,kyori,course,choshi,kishu,odds,predRank,rank,pop" > "$LOGH"

# dbにあるレースを (日付 場所 R) → ファイル で引けるようにする
declare -A DBF
if [ -n "$DBDIR" ]; then
  while IFS=$'\t' read -r key f; do DBF[$key]="$f"; done < <(find "$DBDIR" -name '*.json' -print0 2>/dev/null | xargs -0 -r perl -Mutf8 -MJSON::PP -e '
    for my $f (@ARGV) { open my $h, "<:raw", $f or next; local $/; my $d = eval { JSON::PP->new->utf8->decode(<$h>) } or next;
      my ($id, $x) = ref $d->{data} eq "HASH" ? ($d->{id}, $d->{data}) : ($d->{id}, $d); next unless ref $x eq "HASH" && $x->{date} && $x->{place};
      binmode STDOUT, ":utf8"; print "$x->{date} $x->{place} " . ($x->{no} // "") . "\t$f\n" }')
fi
docid_of() { perl -MJSON::PP -0777 -ne 'my $d = JSON::PP->new->utf8->decode($_); print $d->{id} // ""' "$1"; }
field_of() { perl -MJSON::PP -0777 -ne 'my $d = JSON::PP->new->utf8->decode($_); $d = $d->{data} if ref $d->{data} eq "HASH"; print $d->{'"$2"'} // ""' "$1"; }

for off in -1 0 1 2; do
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
        get "$ID/umabashira.html" "$OUT/tmp/u_$ID.html"
        perl "$HERE/race_json.pl" "$OUT/tmp/u_$ID.html" "$ID" > "$OUT/tmp/r_$ID.json"; RC=$?
        if [ $RC -eq 2 ]; then [ "$R" = "01" ] && break; continue; fi
        [ -z "$TIME" ] && TIME=$(field_of "$OUT/tmp/r_$ID.json" time)
      else RC=9; fi
      HM=$(echo "$TIME" | tr -d ':'); FIN=0
      if [ -n "$HM" ]; then [ "$NOW" -ge "$(TZ=JST-9 date -d "${DISO} ${TIME} 15 minutes" +%Y%m%d%H%M 2>/dev/null || echo 999999999999)" ] && FIN=1; fi
      [ "$off" -lt 0 ] && FIN=1
      if [ $FIN -eq 0 ]; then
        # これからのレース: 自動のレースは作り直し、重賞(Claudeが作ったdbのデータ)は★だけ更新
        if [ $RC -eq 0 ] && { [ -z "$DBFILE" ] || [ "$(docid_of "$DBFILE")" = "k$ID" ]; }; then
          ST=$(perl "$HERE/star.pl" "$OUT/tmp/r_$ID.json" "$MODEL")
          perl -Mutf8 -MJSON::PP -0777 -e 'my $d = JSON::PP->new->utf8->decode(do { local $/; open my $h, "<:raw", $ARGV[0]; <$h> }); my $s = JSON::PP->new->utf8->decode($ARGV[1]);
            $d->{star} = $s->{star}; $d->{starProb} = $s->{starProb}; $d->{starHonmei} = $s->{honmei}; print JSON::PP->new->utf8->canonical->encode($d)' "$OUT/tmp/r_$ID.json" "$ST" > "$OUT/races/k$ID.json"
          printf 'race\tk%s\t%s\n' "$ID" "$OUT/races/k$ID.json" >> "$OUT/manifest.tsv"
        elif [ -n "$DBFILE" ]; then
          DOC=$(docid_of "$DBFILE"); ST=$(perl "$HERE/star.pl" "$DBFILE" "$MODEL")
          perl -Mutf8 -MJSON::PP -e 'my $s = JSON::PP->new->utf8->decode($ARGV[0]); print JSON::PP->new->utf8->canonical->encode({ star => $s->{star}, starProb => $s->{starProb}, starHonmei => $s->{honmei} })' "$ST" > "$OUT/updates/$DOC.json"
          printf 'update\t%s\t%s\n' "$DOC" "$OUT/updates/$DOC.json" >> "$OUT/manifest.tsv"
        fi
        continue
      fi
      # 終わったレース: 結果を取り、予想(dbのデータ。無ければ作り直したもの)と比べる
      get "$ID/raceresult.html" "$OUT/tmp/res_$ID.html"
      perl "$HERE/result_json.pl" "$OUT/tmp/res_$ID.html" > "$OUT/tmp/res_$ID.json" || continue
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
