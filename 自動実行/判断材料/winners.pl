# 過去10年の勝ち馬の表(markdown)を出す。入力: past.pl の出力(TSV)
use utf8; use strict; binmode STDOUT,':utf8'; binmode STDIN,':utf8';
<STDIN>;
print "| 年 | 勝ち馬 | 馬番 | 人気 | 騎手 | 通過 | 前走 |\n|---|---|---|---|---|---|---|\n";
while(<STDIN>){ chomp; my @f=split /\t/; next unless $f[1] eq '1';
  print "| $f[0] | $f[3] | $f[2] | $f[5] | $f[6] | $f[10] | $f[13] $f[16]人$f[17]着 |\n" }
