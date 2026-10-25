# 単勝オッズから出す確率(シミュレーターの土台)が、実際の着順とどれだけずれているかを測る(2026-10-26〜)
# 使い方: perl calib.pl <レースのファイル(カンマ区切りで複数可。全期間/<年>/レース.jsonl や 平場_*.jsonl.gz)> [分ける日 2016-01-01]
#   勝率 q = (1/単勝オッズ) を合計1にしたもの。3着以内率 = q からの Harville式(fuku_day.pl と同じ)
#   1) オッズ帯ごとに「実際の勝率 ÷ q」「実際の3着以内率 ÷ Harville」を前半・後半・グレード・頭数別に出す(1より大きい = 市場がその帯を軽く見ている)
#   2) q を γ乗して合計1にした勝率で、1着の当たり方(対数尤度)が一番よい γ を前半・後半で探す(シミュレーターの FLB_GAMMA は1.0)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0);
my ($rg, $split) = @ARGV; $split ||= '2016-01-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die "$f"; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
sub band { my ($v, @b) = @_; for my $i (0 .. $#b) { return ($i ? "$b[$i - 1]-" : '<') . $b[$i] if $v < $b[$i] } return "$b[-1]+" }
my @OB = (1.5, 2, 3, 5, 10, 20, 50, 100);
my (%acc, %seen, @races);
for my $f (split /,/, $rg) { rd($f, sub {
  my $r = shift; return if $seen{$r->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && ($_->{odds} // '') =~ /^[\d.]+$/ && $_->{odds} >= 1 } @{$r->{horses} || []}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my $gr = $r->{grade} ? ($r->{grade} =~ /G|Jpn/ ? '重賞' : 'L') : (($r->{cls} // '') =~ /障害/ || ($r->{surface} // '') eq '障' ? '障害' : (($r->{cls} // '') =~ /新馬/ ? '新馬' : '平場'));
  my $hb = band($n, 10, 14, 17);
  my $win = -1;
  for my $i (0 .. $n - 1) { my $h = $hs[$i]; my $w = $h->{rank} == 1 ? 1 : 0; my $t3 = $h->{rank} <= 3 ? 1 : 0; $win = $i if $w;
    my $ob = band($h->{odds}, @OB);
    for my $g ("全体", $half, "グレード:$gr", "頭数:$hb") { my $a = $acc{$g}{$ob} //= [0, 0, 0, 0, 0]; $a->[0]++; $a->[1] += $w; $a->[2] += $q[$i]; $a->[3] += $t3; $a->[4] += $p3[$i] } }
  push @races, [$half, [map { $_->{odds} } @hs], $win] if $win >= 0;
}) }
printf "レース %d(前半 < %s <= 後半)\n", scalar @races, $split;
print "オッズ帯ごと: 頭数 / 勝率 実際÷市場 / 3着以内 実際÷Harville(1より大きい = 市場がその帯を軽く見ている)\n";
for my $g ('全体', '前半', '後半', sort grep { /:/ } keys %acc) {
  print "== $g\n";
  for my $ob (map { band($_ - 0.001, @OB) } (@OB, 1000)) { my $a = $acc{$g}{$ob} or next; next if $a->[0] < 30;
    printf "  %-8s %7d頭  勝率 %5.2f%% ÷ %5.2f%% = %.3f   3着内 %5.1f%% ÷ %5.1f%% = %.3f\n", $ob, $a->[0], 100 * $a->[1] / $a->[0], 100 * $a->[2] / $a->[0], $a->[2] ? $a->[1] / $a->[2] : 0, 100 * $a->[3] / $a->[0], 100 * $a->[4] / $a->[0], $a->[4] ? $a->[3] / $a->[4] : 0 }
}
print "== 勝率を q^γ にしたときの1着の対数尤度(高いほど良い)\n";
for my $half ('前半', '後半') { my @R = grep { $_->[0] eq $half } @races; next unless @R; my @row;
  for my $gm (map { $_ / 100 } (90, 95, 100, 105, 110, 115, 120, 125, 130)) { my $ll = 0;
    for my $r (@R) { my @p = map { (1 / $_) ** $gm } @{$r->[1]}; my $s = sum0(@p); $ll += log($p[$r->[2]] / $s) }
    push @row, sprintf("γ%.2f %.4f", $gm, $ll / @R) }
  printf "  %s %5dレース: %s\n", $half, scalar @R, join('  ', @row) }
