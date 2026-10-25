# 「本物の複勝オッズで期待値が基準以上の人気馬の複勝だけ買う」を1日の予算で回したときの、日ごとの収支を出す
# 使い方: perl fuku_day.pl <学習データ.jsonl.gz(カンマ区切りで複数可)> <払戻.jsonl.gz> <複勝オッズ.jsonl.gz> [期待値の下限 1.0] [複勝オッズ下限の上限 3] [1日の予算 10000] [配分 kelly|flat] [分ける日 2026-08-01] [複勝オッズ下限の下限 1] [新馬・障害を除く 0|1]
#   2026-10-23〜 1日の予算は「下限1.2以上・新馬と障害を除く」(1.2 1)。1.2倍未満の大本命・新馬・障害は、どの期待値の帯でも前半・後半とも回収率が100%を切っていた(fuku_cond.pl)
#   3着以内率は 1/単勝オッズ を合計1にした勝率からのHarville式。期待値 = 3着以内率 × 複勝オッズの下限
#   配分: kelly はケリー割合に比例(1レース上限30%・1点100円単位)、flat は同額
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0 max min);
my ($rg, $pg, $fg, $evmin, $omax, $budget, $mode, $split, $omin, $excl) = @ARGV; $omin ||= 1; $excl ||= 0;
$evmin ||= 1.0; $omax ||= 3; $budget ||= 10000; $mode ||= 'kelly'; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %FUKU, %day, %seen);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; my $fk = $FUKU{$r->{id}} or return; return if $excl && (($r->{cls} // q{}) =~ /新馬|障害/ || ($r->{surface} // q{}) eq q{障});
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my %hit = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'複勝'} || []};
  for my $i (0 .. $n - 1) { my $f = $fk->{$hs[$i]{umaban}} or next; my $o = $f->[0];
    next unless $o < $omax && $o >= $omin && $p3[$i] * $o >= $evmin;
    push @{$day{$r->{date}}}, { id => $r->{id}, p => $p3[$i], o => $o, ret => $hit{$hs[$i]{umaban}} // 0 } }
}) for split /,/, $rg;
my %S;
for my $d (sort keys %day) {
  my @b = @{$day{$d}}; my $units = int($budget / 100); my $cap = int($units * 0.3);
  $_->{w} = $mode eq 'flat' ? 1 : max(0.002, ($_->{p} * $_->{o} - 1) / ($_->{o} - 1)) for @b;
  my $tw = sum0(map { $_->{w} } @b);
  $_->{u} = min($cap, max(1, int($units * $_->{w} / $tw))) for @b;
  my $cost = 100 * sum0(map { $_->{u} } @b); my $ret = 100 * sum0(map { $_->{u} * $_->{ret} } @b);
  for my $g ($d lt $split ? '前半' : '後半', '全体') { push @{$S{$g}}, { cost => $cost, ret => $ret, n => scalar @b, hit => scalar grep { $_->{ret} > 0 } @b } }
}
printf "複勝 期待値>=%s 複勝オッズ<%s 予算%d円 %s\n", $evmin, $omax, $budget, $mode;
for my $g (qw(全体 前半 後半)) { my $L = $S{$g} or next;
  my $c = sum0(map { $_->{cost} } @$L); my $rt = sum0(map { $_->{ret} } @$L); my $nb = sum0(map { $_->{n} } @$L); my $nh = sum0(map { $_->{hit} } @$L);
  my ($bal, $peak, $dd) = (0, 0, 0); for (@$L) { $bal += $_->{ret} - $_->{cost}; $peak = max($peak, $bal); $dd = max($dd, $peak - $bal) }
  printf "  %s %3d日 %4d点 合計%8d円 回収率%6.1f%% 収支%+8d円 的中率%5.1f%% 1日で当たる%5.1f%% 1日プラス%5.1f%% 最大落ち込み%7d円\n",
    $g, scalar @$L, $nb, $c, 100 * $rt / $c, $rt - $c, 100 * $nh / $nb, 100 * (grep { $_->{ret} > 0 } @$L) / @$L, 100 * (grep { $_->{ret} > $_->{cost} } @$L) / @$L, $dd;
}
