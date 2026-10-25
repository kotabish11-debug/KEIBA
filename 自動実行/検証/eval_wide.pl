# ワイドを「単勝オッズからのHarville式で出した2頭とも3着以内の確率 × 確定のワイドオッズの下限 = 期待値」で選んだとき、本物の払戻でどれだけ戻ったかを出す
# (1日の予算の複勝と同じ考え方。複勝で利益が出たので、ワイドにも同じずれがあるかを確かめる)
# 使い方: perl eval_wide.pl <学習データ.jsonl.gz(カンマ区切りで複数可)> <払戻.jsonl.gz> <確定オッズ_ワイド.jsonl.gz> [分ける日 2026-08-01] [新馬・障害を除く 0|1]
#   ワイドオッズの下限の帯・期待値の下限ごとに、100円ずつ買ったときの点数・的中率・回収率を前半/後半/全体で出す。最後に人気の組み合わせ別も出す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0);
my ($rg, $pg, $wg, $split, $excl) = @ARGV; $split ||= '2026-08-01'; $excl ||= 0;
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %WIDE, %acc, %pop, %seen, $nr);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($wg, sub { $WIDE{$_[0]{id}} = $_[0]{wide} });
my @EV = (0, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5);
sub band { my $o = shift; $o < 2 ? '<2' : $o < 3 ? '2-3' : $o < 5 ? '3-5' : $o < 10 ? '5-10' : $o < 20 ? '10-20' : $o < 50 ? '20-50' : '50+' }
sub add { my ($h, $k, $ret, $half) = @_; for my $g ($half, '全体') { my $a = $h->{$k}{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } }
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; my $wo = $WIDE{$r->{id}} or return;
  return if $excl && (($r->{cls} // '') =~ /新馬|障害/ || ($r->{surface} // '') eq '障');
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5; $nr++;
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my %hit = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'ワイド'} || []};
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @U = map { $_->{umaban} } @hs; my %P;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]);
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; my $p = $pij * $q[$k] / (1 - $q[$i] - $q[$j]);
        $P{join '-', sort { $a <=> $b } @U[$_->[0], $_->[1]]} += $p for [$i, $j], [$i, $k], [$j, $k] } } }
  my %pp = map { $_->{umaban} => $_->{pop} } @hs;
  for my $c (keys %P) { my $w = $wo->{$c} or next; my $o = $w->[0]; next unless $o >= 1;
    my $ev = $P{$c} * $o; my $ret = $hit{$c} // 0; my $bd = band($o);
    for my $e (@EV) { last if $ev < $e; add($acc{$bd} //= {}, $e, $ret, $half); add($acc{"全部"} //= {}, $e, $ret, $half) }
    if ($ev >= 1) { my ($x, $y) = sort { $a <=> $b } map { $pp{$_} // 99 } split /-/, $c; add(\%pop, ($x > 3 ? '4+' : $x) . '-' . ($y > 6 ? '7+' : $y), $ret, $half) }
  }
}) for split /,/, $rg;
print "ワイド races: $nr(前半 < $split <= 後半)" . ($excl ? " 新馬・障害を除く" : "") . "\n";
sub line { my $x = shift; join '  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %6d点 的中%5.1f%% 回収%6.1f%%", $_, $a->[0], $a->[0] ? 100 * $a->[2] / $a->[0] : 0, $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半) }
for my $b ('全部', '<2', '2-3', '3-5', '5-10', '10-20', '20-50', '50+') { next unless $acc{$b};
  print "== ワイドオッズ下限 $b\n"; for my $e (@EV) { my $x = $acc{$b}{$e} or next; printf "  期待値>=%-4s %s\n", $e, line($x) } }
print "== 期待値1.0以上の人気の組み合わせ(人気の上位-下位)\n";
printf "  %-6s %s\n", $_, line($pop{$_}) for sort { $pop{$b}{'全体'}[0] <=> $pop{$a}{'全体'}[0] } keys %pop;
