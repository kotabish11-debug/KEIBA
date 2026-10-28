#!/bin/bash
# 大きいデータ(RACE など)のセットアップを、1年ずつに区切って並べて取り込む(2026-10-27)
#   JV-Link は対象ファイルが多いと1件ごとの読み出しが遅い(RACE を1986年から一度に読むと1秒に約24件、丸1日以上)。
#   fromtime を「開始-終了」で区切ると1秒に約2,500件になり、別のプロセスで同時にも読める(仕様書 Ver4.6.0〜の読み出し終了ポイント)
# 使い方: bash setup_parallel.sh <データ種別> [始まりの年 1986] [終わりの年 今年] [同時の数 4]
#   出力 = 馬情報/JRA-VAN/全データ/<データ種別>/<年>.txt(全レコード種別)。済んだ年は 済み.txt に書き、やり直すときは飛ばす
cd "$(dirname "$0")/../.."
S=$1; Y0=${2:-1986}; Y1=${3:-$(date +%Y)}; P=${4:-4}
D=馬情報/JRA-VAN/全データ/$S; LOG=馬情報/JRA-VAN/setup_log.txt
mkdir -p $D; touch $D/済み.txt
one() {
  local y=$1
  grep -qx $y $D/済み.txt && return
  rm -f $D/$y.txt
  local out; out=$(自動実行/JRA-VAN/jvget.exe open $S ${y}0101000000-$((y + 1))0101000000 4 $D/$y.txt 2>&1)
  local rc=$?
  echo "$(date +%H:%M) $S $y $(echo "$out" | iconv -f cp932 -t utf-8 | grep -v ' 件$' | tr '\n' ' ')" >> $LOG
  [ $rc -eq 0 ] && echo $y >> $D/済み.txt
}
export -f one; export S D LOG
seq $Y0 $Y1 | xargs -P $P -I{} bash -c 'one {}'
echo "$(date +%H:%M) $S $Y0-$Y1 終わり($(wc -l < $D/済み.txt)年分)" >> $LOG
