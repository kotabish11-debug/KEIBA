# 資金(競馬用に分けたお金)を、1日の予算の買い方(標準: 人気馬の複勝)で回し続けたら、どれくらいで目標に届くかをモンテカルロで出す
# 過去の開催日(買う点がない日も含む)を無作為に選び直して並べ、毎日「その日の朝の資金 × 1点の割合」を1点の金額にして同額で買う
# 使い方: perl bankroll_sim.pl <学習データ.jsonl.gz(カンマ区切り)> <払戻.jsonl.gz> <複勝オッズ.jsonl.gz> [初めの資金 5000] [目標 300000000]
#           [1点の上限 100000] [年の開催日 110] [試行 2000] [回収率の割引(実際の配当に掛ける。0.89なら123%→110%相当) 1] [1点の割合 0.02,0.05,0.1,0.15,0.22]
#   1点の上限: 大きく買うと自分の馬券で複勝オッズが下がる(平場の複勝の売上は1レース千万円前後)。上限を超える分は買わない
#   年の開催日: JRAは土日・祝日で年に約110日(全場の合計ではなく日付の数)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0 max min);
my ($rg, $pg, $fg, $start, $goal, $cap, $dpy, $trials, $disc, $fl) = @ARGV;
$start ||= 5000; $goal ||= 3e8; $cap ||= 100000; $dpy ||= 110; $trials ||= 2000; $disc ||= 1; $fl ||= '0.02,0.05,0.1,0.15,0.22';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %FUKU, %day, %seen);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++; $day{$r->{date}} //= [];
  my $pay = $PAY{$r->{id}} or return; my $fk = $FUKU{$r->{id}} or return;
  return if ($r->{cls} // '') =~ /新馬|障害/ || ($r->{surface} // '') eq '障';
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q; my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i]; for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my %hit = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'複勝'} || []};
  for my $i (0 .. $n - 1) { my $f = $fk->{$hs[$i]{umaban}} or next; my $o = $f->[0];
    push @{$day{$r->{date}}}, ($hit{$hs[$i]{umaban}} // 0) * $disc if $o >= 1.2 && $o < 3 && $p3[$i] * $o >= 1.0 }
}) for split /,/, $rg;
my @D = map { $day{$_} } sort keys %day;
my @all = map { @$_ } @D;
printf "開催日 %d日(買う点がある日 %d日)・%d点・1点あたりの回収率 %.1f%%(割引 %.2f)・1日平均 %.1f点\n", scalar @D, scalar(grep { @$_ } @D), scalar @all, 100 * sum0(@all) / @all, $disc, @all / @D;
printf "初め %d円 → 目標 %s円・1点の上限 %d円・年 %d開催日・%d回の試行\n", $start, $goal, $cap, $dpy, $trials;
my @MS = (50000, 500000, 5000000, 30000000, $goal);
srand(20261024);
for my $f (split /,/, $fl) {
  my (%reach, $bust, @end1, @end3, @end10); my $maxd = $dpy * 30;
  for (1 .. $trials) {
    my $b = $start; my $d = 0; my %got;
    while ($d < $maxd) {
      my $bets = $D[int rand @D]; $d++;
      if (@$bets) {
        my $u = min($cap, max(100, int($b * $f / 100) * 100));
        my $nb = min(scalar @$bets, int($b / $u)); last if $nb < 1;
        $b += $u * ($_ - 1) for @$bets[0 .. $nb - 1];
      }
      for my $m (@MS) { $got{$m} //= $d if $b >= $m }
      push @end1, $b if $d == $dpy; push @end3, $b if $d == 3 * $dpy; push @end10, $b if $d == 10 * $dpy;
      last if $b >= $goal || $b < 100;
    }
    $bust++ if $b < 100;
    push @{$reach{$_}}, $got{$_} // 9e9 for @MS;
  }
  my $med = sub { my @s = sort { $a <=> $b } @_; $s[int(@s / 2)] };
  my $yrs = sub { my $v = shift; $v >= 9e9 ? '30年以内に届かない' : sprintf('%.1f年', $v / $dpy) };
  printf "== 1点 = 資金の%d%%  破産(100円を切る) %.0f%%\n", 100 * $f, 100 * ($bust // 0) / $trials;
  for my $m (@MS) { my @t = @{$reach{$m}}; my $p = grep { $_ < 9e9 } @t;
    printf "   %11s円 に届く確率 %5.1f%%  かかる期間(中央値) %s\n", $m, 100 * $p / $trials, $yrs->($med->(@t)) }
  printf "   資金の中央値: 1年後 %s円 / 3年後 %s円 / 10年後 %s円\n", map { @$_ ? sprintf('%d', $med->(@$_)) : '-' } \@end1, \@end3, \@end10;
}
