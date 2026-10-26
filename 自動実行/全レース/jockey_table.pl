#!/usr/bin/perl
# 騎手の連対率の表(jockey.tsv)を作る。race_json.pl が、騎手のコース連対率の無いJRA公式・スポーツナビのレースで騎手の点に使う
# 使い方: perl 自動実行/全レース/jockey_table.pl 馬情報/過去レースデータ/全期間 > 自動実行/全レース/jockey.tsv
#   (全期間のデータはPCにしか無いので、PCの run.sh が1日1回作り直し、PC収集がコミットする。クラウドはコミットされた表を使う)
# 中身: G 全騎手の連対率 / J 騎手 前の365日の騎乗 連対 / C 騎手 コース(場・芝ダ・距離) 前の3年の騎乗 連対。障害は入れない
# 使い方の決め方は 自動実行/検証/jockey_eb.pl(2017〜2026/3、ベイズ推定で寄せる K=10・k=200 が一番当たった)
use strict; use warnings; use utf8; use JSON::PP; use Encode qw(encode);
binmode STDOUT, ':utf8';
my $DIR = shift or die "使い方: perl jockey_table.pl <全期間のフォルダー>\n";
sub days { my ($y, $m, $d) = split /-/, shift; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }
my %PLACE = ('01' => '札幌', '02' => '函館', '03' => '福島', '04' => '新潟', '05' => '東京', '06' => '中山', '07' => '中京', '08' => '京都', '09' => '阪神', '10' => '小倉');
my @yd = grep { -d $_ && /\/(\d{4})$/ } sort glob("$DIR/*"); @yd = @yd[-4 .. -1] if @yd > 4;
my (@R, %seen, $last);
for my $yd (@yd) { open my $f, '<', "$yd/" . encode('UTF-8', 'JRA詳細.jsonl') or next;
  while (<$f>) { my $r = eval { decode_json($_) } or next; next if $seen{$r->{id}}++; push @R, $r; $last = $r->{date} if !$last || $r->{date} gt $last } }
die "JRA詳細.jsonl がありません\n" unless $last;
my $L = days($last); my (%J, %C, $gn, $gw);
for my $r (@R) {
  my $d = days($r->{date}); next if $d <= $L - 3 * 365;
  my $R = $r->{race} || {}; my $surf = $R->{surface} // ''; next if ($R->{course} // '') =~ /障|→/ || $surf =~ /障/; $surf = 'ダ' if $surf =~ /^ダ/;
  my $ck = ($PLACE{substr($r->{id}, 8, 2)} // '') . $surf . ($R->{dist} // 0);
  for my $h (grep { $_->{jockey} && ($_->{rank} // '') =~ /^\d+$/ } @{$r->{horses} || []}) {
    (my $jk = $h->{jockey}) =~ s/^[A-Za-zＡ-Ｚａ-ｚ][.．]//; my $t = $h->{rank} <= 2 ? 1 : 0;
    $C{$jk}{$ck}[0]++; $C{$jk}{$ck}[1] += $t;
    if ($d > $L - 365) { $J{$jk}[0]++; $J{$jk}[1] += $t; $gn++; $gw += $t }
  }
}
print "# 最後のレース $last。G=全騎手の連対率、J=騎手の前の365日(騎乗・連対)、C=騎手のコースの前の3年(騎乗・連対)\n";
printf "G\t%.4f\n", $gw / $gn;
for my $jk (sort keys %J) { print "J\t$jk\t$J{$jk}[0]\t$J{$jk}[1]\n";
  print "C\t$jk\t$_\t$C{$jk}{$_}[0]\t$C{$jk}{$_}[1]\n" for sort keys %{$C{$jk} || {}} }
