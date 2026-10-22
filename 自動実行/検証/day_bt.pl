# 「1日の予算」の買い方を過去の日で再現し、本物の払戻で収支を出す
# 使い方: perl day_bt.pl <bt.jsonl> <払戻.jsonl.gz> <買い方> [1日の予算(円) 10000] [分ける日 2026-08-01]
#   買い方: cur:<style><evMin>  … 今のシミュレーター(pickBets の結果。例 cur:balance1.1)
#           rule:<券種>:<期待値の下限>:<期待値の上限>:<推定オッズの下限>:<推定オッズの上限>[:<レースの最大点数>] … 条件に合う候補だけ買う(例 rule:複勝:1.0:9:3:10)
#           複数の rule は + でつなぐ
#   配分は simulator.html の dayAllocate・allocate と同じ(ケリー割合の合計で配分、1レース上限30%・最低300円、点数は予算で絞る)
#   出力: 日数・買ったレース数・合計金額・回収率・1日で当たる率・1日でプラスの率・最大の連敗(日)・最大の落ち込み
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0 min max);
my ($bt, $pg, $strat, $budget, $split) = @ARGV; $budget ||= 10000; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
my %PAY; my $z = IO::Uncompress::Gunzip->new($pg) or die;
while (my $l = $z->getline) { my $p = eval { $J->decode($l) } or next; $PAY{$p->{id}} = $p->{pay} }
my $STAR_TOP3 = 0.8; my $DAY_STAR = 1.3; my $CAP = 0.3; my $MINU = 3;

sub kelly { my ($p, $o) = @_; $o > 1 ? max(0.002, ($p * $o - 1) / ($o - 1)) : 0.002 }
# ★: 勝率1位の馬が1番人気で、3着以内率が基準以上
sub is_star { my $r = shift; my @w = @{$r->{win}}; my ($hon) = sort { $w[$b] <=> $w[$a] } 0 .. $#w; my ($fav) = sort { $r->{odds}[$a] <=> $r->{odds}[$b] } 0 .. $#w;
  $hon == $fav && $r->{top3}[$hon] >= $STAR_TOP3 }
sub pick {
  my $r = shift;
  if ($strat =~ /^cur:(\w+?)([\d.]+)$/) { return map { { type => $_->[0], k => $_->[1], p => $_->[2], odds => $_->[3], cover => $_->[4] } } @{$r->{picks}{"$1$2"} || []} }
  my @out;
  for my $rule (split /\+/, $strat) {
    my (undef, $type, $elo, $ehi, $olo, $ohi, $max) = split /:/, $rule; $max ||= 99;
    my @c = grep { $_->[0] eq $type && $_->[2] * $_->[3] >= $elo && $_->[2] * $_->[3] < $ehi && $_->[3] >= $olo && $_->[3] < $ohi } @{$r->{c}};
    @c = sort { ($b->[2] * $b->[3] - 1) * sqrt($b->[2]) <=> ($a->[2] * $a->[3] - 1) * sqrt($a->[2]) } @c;
    push @out, map { { type => $_->[0], k => $_->[1], p => $_->[2], odds => $_->[3] } } @c[0 .. min($#c, $max - 1)];
  }
  @out;
}
# simulator.html の allocate と同じ
sub allocate {
  my ($bets, $units) = @_; return () unless @$bets && $units >= 1;
  my @l = map { { %$_, w => kelly($_->{p}, $_->{odds}) } } @$bets;
  for my $b (grep { $_->{cover} } @l) { my ($w) = grep { $_->{type} eq 'ワイド' && $_->{k} eq $b->{k} } @l; $b->{w} = min($b->{w}, $w->{w} * 0.25) if $w }
  @l = sort { $b->{w} <=> $a->{w} } @l;
  my $cap = $units <= 10 ? 2 : $units <= 20 ? 3 : $units; @l = @l[0 .. $cap - 1] if @l > $cap;
  my $tw = sum0(map { $_->{w} } @l); my $used = 0;
  for (@l) { $_->{u} = max(1, int($_->{w} / $tw * $units)); $used += $_->{u} }
  while ($used > $units) { my ($m) = sort { $b->{u} <=> $a->{u} } @l; $m->{u}--; $used-- }
  my @fr = sort { $b->[0] <=> $a->[0] } map { [$l[$_]{w} / $tw * $units - $l[$_]{u}, $_] } 0 .. $#l; my $k = 0;
  while ($used < $units) { $l[$fr[$k % @fr][1]]{u}++; $used++; $k++ }
  grep { $_->{u} > 0 } @l;
}
# simulator.html の dayAllocate と同じ
sub day_allocate {
  my ($items, $units) = @_; my @pool = @$items; my $cap = max($MINU, int($units * $CAP)); my @sh;
  while (1) {
    my $tw = sum0(map { $_->{w} } @pool); @sh = map { { x => $_, s => $units * $_->{w} / $tw } } @pool;
    for (1 .. 20) { my @over = grep { $_->{s} > $cap } @sh; last unless @over; $_->{s} = $cap, $_->{fixed} = 1 for @over;
      my @free = grep { !$_->{fixed} } @sh; my $rest = $units - sum0(map { $_->{s} } grep { $_->{fixed} } @sh); my $fw = sum0(map { $_->{x}{w} } @free);
      last if !@free || $rest <= 0; $_->{s} = $rest * $_->{x}{w} / $fw for @free }
    my @small = grep { $_->{s} < $MINU } @sh; last if !@small || @pool <= 1;
    my ($worst) = sort { $a->{x}{w} <=> $b->{x}{w} } @small; @pool = grep { $_ != $worst->{x} } @pool;
  }
  $_->{u} = min($cap, int($_->{s})) for @sh; my $used = sum0(map { $_->{u} } @sh);
  my $limit = min($units, sum0(map { min($cap, POSIX::ceil($_->{s})) } @sh));
  my @ord = sort { ($b->{s} - $b->{u}) <=> ($a->{s} - $a->{u}) } @sh;
  for (my $k = 0; $used < $limit && $k < @ord * 2; $k++) { my $o = $ord[$k % @ord]; if ($o->{u} < $cap && $o->{u} < POSIX::ceil($o->{s})) { $o->{u}++; $used++ } }
  grep { $_->{u} >= 1 && ($_->{u} >= $MINU || $units < $MINU) } @sh;
}
use POSIX ();
my %day;
open my $h, '<:raw', $bt or die;
while (my $l = <$h>) { my $r = eval { $J->decode($l) } or next; next if $r->{error} || !$PAY{$r->{id}}; push @{$day{$r->{date}}}, $r }
my %S;
for my $d (sort keys %day) {
  my @items;
  for my $r (@{$day{$d}}) { my @g = pick($r) or next; my $w = sum0(map { kelly($_->{p}, $_->{odds}) } @g) * (is_star($r) ? $DAY_STAR : 1); push @items, { r => $r, g => \@g, w => $w } }
  my ($cost, $ret, $nr, $hitR) = (0, 0, 0, 0);
  for my $o (@items ? day_allocate(\@items, int($budget / 100)) : ()) {
    my $r = $o->{x}{r}; my $pay = $PAY{$r->{id}}; my %hit; for my $t (keys %$pay) { $hit{$t}{$_->{k}} += $_->{yen} for @{$pay->{$t}} }
    my $rr = 0; for my $b (allocate($o->{x}{g}, $o->{u})) { $cost += $b->{u} * 100; $rr += $b->{u} * ($hit{$b->{type}}{$b->{k}} // 0) }
    $ret += $rr; $nr++; $hitR++ if $rr > 0;
  }
  next unless $cost;
  for my $g ($d lt $split ? '前半' : '後半', '全体') { push @{$S{$g}}, { cost => $cost, ret => $ret, nr => $nr, hitR => $hitR } }
}
printf "%-28s 予算%d円\n", $strat, $budget;
for my $g (qw(全体 前半 後半)) { my $L = $S{$g} or next;
  my $c = sum0(map { $_->{cost} } @$L); my $rt = sum0(map { $_->{ret} } @$L); my $nr = sum0(map { $_->{nr} } @$L); my $hr = sum0(map { $_->{hitR} } @$L);
  my ($bal, $peak, $dd, $streak, $ms) = (0, 0, 0, 0, 0);
  for (@$L) { $bal += $_->{ret} - $_->{cost}; $peak = max($peak, $bal); $dd = max($dd, $peak - $bal); if ($_->{ret} > $_->{cost}) { $streak = 0 } else { $ms = max($ms, ++$streak) } }
  printf "  %s %3d日 %4dレース 合計%8d円 回収率%6.1f%% 収支%+8d円 レース的中%5.1f%% 1日で当たる%5.1f%% 1日プラス%5.1f%% 最大連敗%2d日 最大落ち込み%7d円\n",
    $g, scalar @$L, $nr, $c, 100 * $rt / $c, $rt - $c, 100 * $hr / max(1, $nr), 100 * (grep { $_->{ret} > 0 } @$L) / @$L, 100 * (grep { $_->{ret} > $_->{cost} } @$L) / @$L, $ms, $dd;
}
