#!/bin/bash
# JRA-VAN から過去分を取れるデータを全部取り込む(2026-10-27 ユーザー指示「取り込めるものはすべて、なるべく早く」)
#   蓄積系はセットアップ(option 4)で1986年から、全レコード種別をそのまま <データ種別>.txt に(1行1レコード、Shift-JIS)
#   時系列オッズは約1年分: 0B41(単複枠)は setup_all.sh で取得済み、ここで 0B42(馬連)を取る
#   JV-Link は同時に1つしか動かないので順番に。済んだものは 済み.txt に書き、やり直すときは飛ばす
# 使い方: bash 自動実行/JRA-VAN/setup_everything.sh   (ログ = 馬情報/JRA-VAN/setup_log.txt)
cd "$(dirname "$0")/../.."
D=馬情報/JRA-VAN/全データ; J=自動実行/JRA-VAN/jvget.exe; LOG=馬情報/JRA-VAN/setup_log.txt
mkdir -p $D; touch $D/済み.txt
log() { iconv -f cp932 -t utf-8 | grep -v ' 件$' | sed "s/^/$(date +%H:%M) /" >> $LOG; }
# 小さいものから(早く使えるように)。RACE がいちばん大きい
for S in YSCH TOKU COMM HOYU HOSN BLDN DIFN MING SNPN RACE SLOP WOOD; do
  grep -qx $S $D/済み.txt && continue
  rm -f $D/$S.txt
  $J open $S 19860101000000 4 $D/$S.txt 2>&1 | log
  [ ${PIPESTATUS[0]} -eq 0 ] && echo $S >> $D/済み.txt
done
if ! grep -qx 0B42 $D/済み.txt; then
  rm -f $D/0B42.txt
  $J rt 0B42 馬情報/JRA-VAN/keys_1y.txt $D/0B42.txt 2>&1 | log && echo 0B42 >> $D/済み.txt
fi
echo "$(date +%H:%M) 終わり" >> $LOG
ls -la $D >> $LOG
