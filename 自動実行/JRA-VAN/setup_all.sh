#!/bin/bash
# JRA-VAN の過去分をまとめて取り込む(JV-Link は同時に1つしか動かないので順番に)
#   坂路(SLOP/HC)・ウッド(WOOD/WC): 2005年から全部(セットアップ。正式契約でないと -301)
#   時系列オッズ(0B41/O1): JRA-VAN に残っている約1年分。キーは通常取得の RA から作る
# 出力は 馬情報/JRA-VAN/(PCだけ。.gitignore 済み)
cd "$(dirname "$0")/../.."
D=馬情報/JRA-VAN; J=自動実行/JRA-VAN/jvget.exe
mkdir -p $D
log() { iconv -f cp932 -t utf-8 | grep -v ' 件$' >> $D/setup_log.txt; }
rm -f $D/slop.txt $D/wood.txt $D/o1_raw.txt
$J open SLOP 20050101000000 4 $D/slop.txt HC 2>&1 | log
$J open WOOD 20050101000000 4 $D/wood.txt WC 2>&1 | log
[ -s $D/keys_1y.txt ] || { $J open RACE 20250901000000 1 $D/ra_1y.txt RA 2>&1 | log; cut -c12-27 $D/ra_1y.txt | sort -u | awk '$0>="2025"' > $D/keys_1y.txt; }
$J rt 0B41 $D/keys_1y.txt $D/o1_raw.txt 2>&1 | log
perl 自動実行/JRA-VAN/odds_ts.pl $D/o1_raw.txt > $D/オッズの推移_1年.jsonl
wc -l $D/*.txt $D/*.jsonl >> $D/setup_log.txt
