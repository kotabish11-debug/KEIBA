# 1日の予算の買い方(人気馬の複勝 + 人気馬どうしのワイド)を、日ごとの収支で出す(fuku_day.pl のワイド入り版。シミュレーターの1日の予算と同じ選び方)
# 使い方: perl combo_day.pl <学習データ.jsonl.gz(カンマ区切りで複数可)> <払戻.jsonl.gz> <複勝オッズ.jsonl.gz> <確定オッズ_ワイド.jsonl.gz>
#           [複勝オッズ下限の上限 3] [ワイドも買う 1|0] [ワイドの期待値の下限 1.1] [ワイドオッズ下限の上限 3] [1日の予算 10000] [分ける日 2026-08-01]
#   複勝: 3着以内率 × 複勝オッズの下限 ≥ 1.0、下限1.2倍以上。ワイド: 2頭とも3着以内の確率 × ワイドオッズの下限 ≥ 期待値の下限。確率はどちらも単勝オッズのHarville式
#   新馬・障害は買わない。予算は全部の点に同額(1点は予算の30%まで)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0 max min);
my ($rg, $pg, $fg, $wg, $fmax, $useW, $wev, $wmax, $budget, $split) = @ARGV;
$fmax ||= 3; $useW //= 1; $wev ||= 1.1; $wmax ||= 3; $budget ||= 10000; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %FUKU, %WIDE, %day, %seen);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($wg, sub { $WIDE{$_[0]{id}} = $_[0]{wide} }) if $useW;
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; my $fk = $FUKU{$r->{id}} or return;
  return if ($r->{cls} // '') =~ /新馬|障害/ || ($r->{surface} // '') eq '障';
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @U = map { $_->{umaban} } @hs; my @p3 = (0) x $n; my %P;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; my $p = $pij * $q[$k] / (1 - $q[$i] - $q[$j]); $p3[$k] += $p;
        $P{join '-', sort { $a <=> $b } @U[$_->[0], $_->[1]]} += $p for [$i, $j], [$i, $k], [$j, $k] } } }
  my %hf = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'複勝'} || []};
  my %hw = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'ワイド'} || []};
  for my $i (0 .. $n - 1) { my $f = $fk->{$U[$i]} or next; my $o = $f->[0];
    next unless $o >= 1.2 && $o < $fmax && $p3[$i] * $o >= 1.0;
    push @{$day{$r->{date}}}, { t => '複勝', ret => $hf{$U[$i]} // 0 } }
  my $wo = $useW ? $WIDE{$r->{id}} : undef; return unless $wo;
  for my $c (keys %P) { my $w = $wo->{$c} or next; my $o = $w->[0];
    next unless $o >= 1 && $o < $wmax && $P{$c} * $o >= $wev;
    push @{$day{$r->{date}}}, { t => 'ワイド', ret => $hw{$c} // 0 } }
}) for split /,/, $rg;
my %S;
for my $d (sort keys %day) {
  my @b = @{$day{$d}}; my $units = int($budget / 100); my $u = min(max(1, int($units * 0.3)), max(1, int($units / @b)));
  my $cost = 100 * $u * @b; my $ret = 100 * $u * sum0(map { $_->{ret} } @b);
  for my $g ($d lt $split ? '前半' : '後半', '全体') { push @{$S{$g}}, { cost => $cost, ret => $ret, b => \@b } }
}
printf "複勝 1.2〜%s倍%s 予算%d円 同額 新馬・障害を除く\n", $fmax, ($useW ? " + ワイド 期待値>=$wev 下限<$wmax" : ''), $budget;
for my $g (qw(全体 前半 後半)) { my $L = $S{$g} or next;
  my $c = sum0(map { $_->{cost} } @$L); my $rt = sum0(map { $_->{ret} } @$L);
  my @all = map { @{$_->{b}} } @$L; my %cnt; my %hit; for (@all) { $cnt{$_->{t}}++; $hit{$_->{t}}++ if $_->{ret} > 0 }
  my ($bal, $peak, $dd) = (0, 0, 0); for (@$L) { $bal += $_->{ret} - $_->{cost}; $peak = max($peak, $bal); $dd = max($dd, $peak - $bal) }
  printf "  %s %3d日 %4d点(%s) 回収率%6.1f%% 収支%+8d円 的中率%5.1f%% 1日で当たる%5.1f%% 1日プラス%5.1f%% 最大落ち込み%7d円\n",
    $g, scalar @$L, scalar @all, join('・', map { "$_$cnt{$_}" . sprintf('(的中%.0f%%)', 100 * ($hit{$_} // 0) / $cnt{$_}) } sort keys %cnt), 100 * $rt / $c, $rt - $c,
    100 * sum0(map { $_->{ret} > 0 ? 1 : 0 } @all) / @all, 100 * (grep { grep { $_->{ret} > 0 } @{$_->{b}} } @$L) / @$L, 100 * (grep { $_->{ret} > $_->{cost} } @$L) / @$L, $dd;
}
