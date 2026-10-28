#!/bin/bash
# JRA-VAN の新しいデータを差分だけ取り込む(PC収集 run_pc.ps1 が毎回呼ぶ。setup_everything.sh と setup_parallel.sh RACE が済んでから)
#   蓄積系: 前回の「最終」の時刻から通常取得(option 1)し、全データ/<データ種別>.txt に足す(RACE・SLOP・WOOD は 全データ/<データ種別>/<今年>.txt)
#   時系列オッズ: 直近8日のレースで、まだ取っていないものの 0B41(単複枠)・0B42(馬連)を取る
cd "$(dirname "$0")/../.."
D=馬情報/JRA-VAN/全データ; J=自動実行/JRA-VAN/jvget.exe; LOG=馬情報/JRA-VAN/update_log.txt
grep -qx 2026 $D/RACE/済み.txt 2>/dev/null || { echo "$(date '+%F %H:%M') セットアップがまだなので見送り" >> $LOG; exit 0; }
ps -ef | grep -q '[s]etup_' && exit 0
Y=$(date +%Y)
for S in YSCH TOKU COMM HOYU HOSN BLDN DIFN MING SNPN RACE SLOP WOOD; do
  last=$(cat $D/last_$S.txt 2>/dev/null)
  [ -z "$last" ] && last=$(grep "JVOpen $S = 0" 馬情報/JRA-VAN/setup_log.txt | grep -o '最終 [0-9]\{14\}' | grep -o '[0-9]\{14\}' | sort | tail -1)
  [ -z "$last" ] && continue
  F=$D/$S.txt; [ -d $D/$S ] && F=$D/$S/$Y.txt
  out=$($J open $S $last 1 $F 2>&1 | iconv -f cp932 -t utf-8)
  echo "$(date '+%F %H:%M') $(echo "$out" | grep -v ' 件$' | tr '\n' ' ')" >> $LOG
  ts=$(echo "$out" | grep -o '最終 [0-9]\{14\}' | grep -o '[0-9]\{14\}' | tail -1)
  [ -n "$ts" ] && echo $ts > $D/last_$S.txt
done
# 時系列オッズ(JRA-VAN に約1年しか残らないので、毎回取りためる)
since=$(date -d '8 days ago' +%Y%m%d); today=$(date +%Y%m%d)
cat $D/RACE/$((Y - 1)).txt $D/RACE/$Y.txt 2>/dev/null | grep -a '^RA' | cut -c12-27 | awk -v a=$since -v b=$today 'substr($0,1,8)>=a && substr($0,1,8)<b' | sort -u > $D/.keys_new
for S in 0B41 0B42; do
  F=$D/$S.txt; [ $S = 0B41 ] && F=馬情報/JRA-VAN/o1_raw.txt
  cut -c12-27 $F 2>/dev/null | sort -u > $D/.keys_have
  comm -23 $D/.keys_new $D/.keys_have > $D/.keys_get
  [ -s $D/.keys_get ] && $J rt $S $D/.keys_get $F 2>&1 | iconv -f cp932 -t utf-8 | sed "s/^/$(date '+%F %H:%M') $S /" >> $LOG
done
perl 自動実行/JRA-VAN/odds_ts.pl 馬情報/JRA-VAN/o1_raw.txt > 馬情報/JRA-VAN/オッズの推移_1年/all.jsonl
rm -f $D/.keys_new $D/.keys_have $D/.keys_get
# 馬DB の全部入り版(馬情報/JRA-VAN/馬DB/。PCだけ)を、取り込んだ新しい分で作り直す(2026-10-29〜)
perl 自動実行/馬DB/jv.pl >> $LOG 2>&1
