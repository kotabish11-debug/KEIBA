# 単勝オッズから出した組の確率(推計オッズ)の帯ごとに、3連単・馬単・3連複・馬連を全部買ったときの本物の回収率(2026-10-27〜)
# 小幡・太宰(2014)「競馬とプロスペクト理論」: 2009年の3連単は Harville の推計オッズ約31倍未満の組が買われておらず、約500倍以上の組が買われすぎ。今も同じか確かめる
# 使い方: perl exotic_harville.pl <レース.jsonl(カンマ区切りで複数可)> <払戻.jsonl(カンマ区切り)> [分ける年 2020] [1 = 新馬・障害を除く]
#   式: H = Harville式 / D = 2着0.85乗・3着0.70乗の割引(star.pl・p3_fit.pl と同じ)
#   帯: 推計オッズ(1 ÷ 確率)を 10 の 1/4 乗ごと(1, 1.8, 3.2, 5.6, 10, 18, 32, 56, 100 …倍)。払戻は1着同着などで複数あればすべて足す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0 min);
my ($rg, $pg, $split, $excl) = @ARGV; $split ||= 2020; $excl //= 1;
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; open my $z, '<', $f or die "$f: $!"; while (my $l = <$z>) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my @T = qw(3連単 馬単 3連複 馬連); my @M = qw(H D); my $NB = 32; my $L10 = 4 / log(10);
my (%PAY, %seen, %C);   # $C{type}{model}{year}[bucket] = [点数, 払戻(100円あたり), 的中]
rd($_, sub { $PAY{$_[0]{id}} = $_[0]{pay} }) for split /,/, $pg;
sub bk { my $p = shift; my $b = int(-log($p) * $L10); $b < 0 ? 0 : $b >= $NB ? $NB - 1 : $b }
my $nr = 0;
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++;
  return if $excl && (($r->{cls} // q{}) =~ /新馬|障害/ || ($r->{surface} // q{}) eq q{障});
  my $pay = $PAY{$r->{id}} or return; return unless $pay->{'3連単'};
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my $y = substr($r->{date}, 0, 4); $nr++;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my %ix; $ix{$hs[$_]{umaban}} = $_ for 0 .. $n - 1;
  for my $m (@M) {
    my ($a2, $a3) = $m eq 'H' ? (1, 1) : (0.85, 0.70);
    my @rr = map { $_ ** $a2 } @q; my $sr = sum0(@rr); @rr = map { $_ / $sr } @rr;
    my @ss = map { $_ ** $a3 } @q; my $sx = sum0(@ss); @ss = map { $_ / $sx } @ss;
    my (@P2, @P3);   # 順番つきの2頭・3頭の確率
    for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i;
      my $pij = $q[$i] * $rr[$j] / (1 - $rr[$i]); $P2[$i][$j] = $pij; my $d = 1 - $ss[$i] - $ss[$j];
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $P3[$i][$j][$k] = $d > 0 ? $pij * $ss[$k] / $d : 1e-12 } } }
    my $cy = sub { $C{$_[0]}{$m}{$y} ||= [map { [0, 0, 0] } 1 .. $NB] };
    my ($c3t, $c2t, $c3f, $c2f) = map { $cy->($_) } @T;
    for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i;
      $c2t->[bk($P2[$i][$j])][0]++;
      $c2f->[bk($P2[$i][$j] + $P2[$j][$i])][0]++ if $i < $j;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j;
        $c3t->[bk($P3[$i][$j][$k])][0]++;
        $c3f->[bk($P3[$i][$j][$k] + $P3[$i][$k][$j] + $P3[$j][$i][$k] + $P3[$j][$k][$i] + $P3[$k][$i][$j] + $P3[$k][$j][$i])][0]++ if $i < $j && $j < $k } } }
    # 当たりの組
    for my $t (@T) { for my $w (@{$pay->{$t} || []}) {
      my @u = map { $ix{$_} } split /-/, $w->{k}; next if grep { !defined } @u;
      my $p = $t eq '3連単' ? $P3[$u[0]][$u[1]][$u[2]] : $t eq '馬単' ? $P2[$u[0]][$u[1]]
        : $t eq '馬連' ? $P2[$u[0]][$u[1]] + $P2[$u[1]][$u[0]]
        : sum0(map { $P3[$_->[0]][$_->[1]][$_->[2]] } ([@u[0,1,2]], [@u[0,2,1]], [@u[1,0,2]], [@u[1,2,0]], [@u[2,0,1]], [@u[2,1,0]]));
      next unless $p; my $c = $cy->($t)->[bk($p)]; $c->[1] += $w->{yen} / 100; $c->[2]++ } }
  }
}) for split /,/, $rg;
my @Y = sort keys %{$C{'3連単'}{H}};
printf "レース %d(%s〜%s、前半 < %d <= 後半%s)\n", $nr, $Y[0], $Y[-1], $split, $excl ? '、新馬・障害を除く' : '';
sub agg { my ($t, $m, $f) = @_; my @a = map { [0, 0, 0] } 1 .. $NB; for my $y (grep { $f->($_) } @Y) { my $c = $C{$t}{$m}{$y} or next; for my $b (0 .. $NB - 1) { $a[$b][$_] += $c->[$b][$_] for 0 .. 2 } } \@a }
sub roi { my ($a, $lo, $hi) = @_; my ($n, $r, $h) = (0, 0, 0); for my $b ($lo .. $hi) { $n += $a->[$b][0]; $r += $a->[$b][1]; $h += $a->[$b][2] } ($n, $n ? 100 * $r / $n : 0, $h) }
for my $t (@T) { for my $m (@M) {
  my $A = agg($t, $m, sub { 1 }); my $F = agg($t, $m, sub { $_[0] < $split }); my $B = agg($t, $m, sub { $_[0] >= $split });
  printf "\n== %s %s: 推計オッズの帯ごと(全部買った回収率)\n", $t, $m;
  my $last = 0; for my $b (0 .. $NB - 1) { $last = $b if $A->[$b][0] }
  my $b = 0; while ($b <= $last) { my $e = $b >= 12 ? min($b + 3, $last) : $b;   # 1000倍以上は10倍ごとにまとめる
    my ($n, $ra, $h) = roi($A, $b, $e); my (undef, $rf) = roi($F, $b, $e); my (undef, $rb) = roi($B, $b, $e);
    printf "  %7.1f〜%-8.1f倍 %9d点 的中%6d 回収 全体%6.1f%% 前半%6.1f%% 後半%6.1f%%\n", 10 ** ($b / 4), 10 ** (($e + 1) / 4), $n, $h, $ra, $rf, $rb if $n;
    $b = $e + 1 }
  print "  -- 推計オッズ X倍未満を全部買う(年ごと)\n";
  for my $hi (2, 4, 6, 8, 10) { my ($n, $ra) = roi($A, 0, $hi - 1); my (undef, $rf) = roi($F, 0, $hi - 1); my (undef, $rb) = roi($B, 0, $hi - 1);
    printf "  %6.1f倍未満 %8d点 全体%6.1f%% 前半%6.1f%% 後半%6.1f%% | %s\n", 10 ** ($hi / 4), $n, $ra, $rf, $rb,
      join ' ', map { my (undef, $ry) = roi(agg($t, $m, do { my $yy = $_; sub { $_[0] eq $yy } }), 0, $hi - 1); sprintf '%s:%.0f', substr($_, 2), $ry } @Y } } }
