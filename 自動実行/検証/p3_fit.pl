# 単勝オッズから出す3着以内率の式を比べ、一番合う式で選んだ複勝が本物の払戻で100%を超えるかを確かめる(2026-10-26〜)
# 使い方: perl p3_fit.pl <レース.jsonl(カンマ区切りで複数可)> <払戻.jsonl> <複勝オッズ.jsonl> [分ける日 2023-07-01]
#   式: H = Harville式(2着・3着も単勝の支持率どおり。fuku_day.pl と同じ) / D = 2着0.85乗・3着0.70乗の割引(star.pl と同じ) / L = logit(H) をロジスティック回帰で直したもの(前半で当てはめ)
#   1) 後半の対数損失・帯ごとの実際÷予想 で式を比べる  2) 各式の期待値(3着以内率 × 複勝オッズの下限)の帯ごとに、複勝を100円ずつ買った回収率を前半・後半・年ごとに出す(新馬・障害を除く)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0 max min);
my ($rg, $pg, $fg, $split) = @ARGV; $split ||= '2023-07-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; open my $z, '<', $f or die "$f: $!"; while (my $l = <$z>) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
sub p3 { my ($q, $a2, $a3) = @_; my $n = @$q;
  my @r = map { $_ ** $a2 } @$q; my $sr = sum0(@r); @r = map { $_ / $sr } @r;
  my @s = map { $_ ** $a3 } @$q; my $ss = sum0(@s); @s = map { $_ / $ss } @s;
  my @p = @$q;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q->[$i] * $r[$j] / (1 - $r[$i]); $p[$j] += $pij;
      my $d = 1 - $s[$i] - $s[$j]; next if $d <= 0;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p[$k] += $pij * $s[$k] / $d } } }
  return [map { min($_, 0.999) } @p] }
my (%PAY, %FUKU, %seen, @H);   # @H: 1頭ごと { date, y(3着以内), pH, pD, o(複勝下限), ret, excl }
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my $pH = p3(\@q, 1, 1); my $pD = p3(\@q, 0.85, 0.70);
  my $fk = $FUKU{$r->{id}} || {}; my %hit = map { $_->{k} => $_->{yen} / 100 } @{($PAY{$r->{id}} || {})->{'複勝'} || []};
  my $ex = (($r->{cls} // q{}) =~ /新馬|障害/ || ($r->{surface} // q{}) eq q{障}) ? 1 : 0;
  for my $i (0 .. $n - 1) { my $f = $fk->{$hs[$i]{umaban}};
    push @H, { d => $r->{date}, y => ($hs[$i]{rank} <= 3 ? 1 : 0), pH => $pH->[$i], pD => $pD->[$i], o => ($f ? $f->[0] : 0), ret => $hit{$hs[$i]{umaban}} // 0, ex => $ex, pay => (%hit ? 1 : 0) } }
}) for split /,/, $rg;
sub lg { my $p = shift; $p = min(max($p, 1e-6), 1 - 1e-6); log($p / (1 - $p)) }
# ロジスティック回帰 logit(p) = b0 + b1 * logit(pH) + b2 * logit(pH)^2 を前半で当てはめ(ニュートン法)
my @tr = grep { $_->{d} lt $split } @H; my @b = (0, 1, 0);
for (1 .. 25) { my (@g, @h); @g = (0) x 3; @h = map { [(0) x 3] } 1 .. 3;
  for (@tr) { my $x = lg($_->{pH}); my @v = (1, $x, $x * $x); my $z = sum0(map { $b[$_] * $v[$_] } 0 .. 2); my $p = 1 / (1 + exp(-$z));
    for my $a (0 .. 2) { $g[$a] += ($_->{y} - $p) * $v[$a]; $h[$a][$_] += $p * (1 - $p) * $v[$a] * $v[$_] for 0 .. 2 } }
  # 3x3 を解く
  my @A = map { [@{$h[$_]}, $g[$_]] } 0 .. 2;
  for my $c (0 .. 2) { my $pv = $A[$c][$c]; $_ /= $pv for @{$A[$c]}; for my $rw (0 .. 2) { next if $rw == $c; my $f = $A[$rw][$c]; $A[$rw][$_] -= $f * $A[$c][$_] for 0 .. 3 } }
  $b[$_] += $A[$_][3] for 0 .. 2 }
$_->{pL} = do { my $x = lg($_->{pH}); 1 / (1 + exp(-($b[0] + $b[1] * $x + $b[2] * $x * $x))) } for @H;
printf "頭数 %d(前半 < %s <= 後半)  L の係数 b0=%.3f b1=%.3f b2=%.4f\n", scalar @H, $split, @b;
print "== 後半の対数損失(低いほど良い)と、予想の帯ごとの 実際÷予想\n";
my @te = grep { $_->{d} ge $split } @H;
for my $m (qw(pH pD pL)) { my $ll = -sum0(map { my $p = min(max($_->{$m}, 1e-6), 1 - 1e-6); $_->{y} ? log($p) : log(1 - $p) } @te) / @te;
  my %bd; for (@te) { my $p = $_->{$m}; my $k = $p < .05 ? 'a<5%' : $p < .1 ? 'b5-10' : $p < .2 ? 'c10-20' : $p < .35 ? 'd20-35' : $p < .5 ? 'e35-50' : $p < .7 ? 'f50-70' : $p < .85 ? 'g70-85' : 'h85+'; $bd{$k}[0]++; $bd{$k}[1] += $_->{y}; $bd{$k}[2] += $p }
  printf "  %s %.5f  %s\n", $m, $ll, join ' ', map { sprintf '%s:%.3f', substr($_, 1), $bd{$_}[1] / $bd{$_}[2] } sort keys %bd }
print "== 複勝(新馬・障害を除く・複勝オッズ下限1.1倍以上)の期待値の帯ごとの回収率\n";
for my $m (qw(pH pD pL)) { for my $lo (0.9, 1.0, 1.05, 1.1, 1.2) { for my $om ([1.1, 3], [3, 999]) {
  my %S; for (@H) { next if $_->{ex} || !$_->{o} || !$_->{pay} || $_->{o} < $om->[0] || $_->{o} >= $om->[1]; my $ev = $_->{$m} * $_->{o}; next if $ev < $lo;
    for my $g ($_->{d} lt $split ? '前半' : '後半', '全体', substr($_->{d}, 0, 4)) { $S{$g}[0]++; $S{$g}[1] += $_->{ret}; $S{$g}[2]++ if $_->{ret} > 0 } }
  next unless $S{'全体'};
  printf "  %s 期待値>=%-4s 下限%s-%s倍 %s | 年 %s\n", $m, $lo, @$om, join('  ', map { sprintf '%s %5d点 回収%6.1f%%', $_, $S{$_}[0], 100 * $S{$_}[1] / $S{$_}[0] } grep { $S{$_} } qw(全体 前半 後半)),
    join(' ', map { sprintf '%s:%.0f%%', substr($_, 2), 100 * $S{$_}[1] / $S{$_}[0] } grep { /^\d{4}$/ } sort keys %S) } } }
