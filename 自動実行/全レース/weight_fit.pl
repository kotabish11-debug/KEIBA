# 能力値5項目の重み(合計1)と尺度を、Plackett-Luce(上位3着)で当てはめ・比較する
use utf8; use strict; use warnings; binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($split, $gz) = @ARGV; my @K = qw(jisseki kyori course choshi kishu);
my $z = IO::Uncompress::Gunzip->new($gz); my (@tr, @te, %seen);
while (my $l = $z->getline) { my $r = eval { decode_json($l) } or next; next if $seen{$r->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; next if @hs < 5;
  my $it = { X => [map { my $h = $_; [map { ($h->{$_} // 60) / 10 } @K] } @hs], rk => [map { $_->{rank} } @hs] };
  if (!$split || $r->{date} lt $split) { push @tr, $it } else { push @te, $it } }
# 重み w と尺度 lam での対数尤度と勝率など
sub ev { my ($w, $lam, $set) = @_; my ($ll, $win, $t3, $n) = (0, 0, 0, 0);
  for my $it (@$set) { my @u = map { my $x = $_; my $s = 0; $s += $w->[$_] * $x->[$_] for 0 .. 4; $lam * $s } @{$it->{X}};
    my @o = sort { $it->{rk}[$a] <=> $it->{rk}[$b] } 0 .. $#u; my %out;
    for my $k (0 .. 2) { my @lv = grep { !$out{$_} } 0 .. $#u; my $mx = -1e9; $mx = $u[$_] > $mx ? $u[$_] : $mx for @lv; my $S = 0; $S += exp($u[$_] - $mx) for @lv; $ll += $u[$o[$k]] - $mx - log($S); $out{$o[$k]} = 1 }
    my @p = sort { $u[$b] <=> $u[$a] } 0 .. $#u; $n++; $win++ if $it->{rk}[$p[0]] == 1; $t3++ if $it->{rk}[$p[0]] <= 3 }
  return ($ll / $n, 100 * $win / $n, 100 * $t3 / $n) }
sub bestlam { my ($w, $set) = @_; my ($bl, $bv) = (1, -1e9); for (my $l = 0.2; $l <= 4; $l += 0.1) { my ($v) = ev($w, $l, $set); ($bl, $bv) = ($l, $v) if $v > $bv } $bl }
# 座標探索で重みを当てはめ(合計1・各0.05以上)
sub fitw { my ($set) = @_; my @w = (.2) x 5; my $lam = bestlam(\@w, $set); my ($cur) = ev(\@w, $lam, $set);
  for my $step (0.05, 0.02, 0.01, 0.005) { my $imp = 1; while ($imp) { $imp = 0;
    for my $i (0 .. 4) { for my $j (0 .. 4) { next if $i == $j; my @c = @w; $c[$i] += $step; $c[$j] -= $step; next if $c[$j] < 0.05;
      my $l2 = bestlam(\@c, $set); my ($v) = ev(\@c, $l2, $set); if ($v > $cur + 1e-6) { @w = @c; $lam = $l2; $cur = $v; $imp = 1 } } } } }
  return (\@w, $lam) }
my %cand = ('初期値' => [.35, .15, .15, .20, .15], '今(36レース)' => [.275, .125, .255, .188, .157]);
my ($fw, $fl) = fitw(\@tr); $cand{'当てはめ'} = $fw;
printf "train %d / test %d\n", scalar @tr, scalar @te;
for my $c (sort keys %cand) { my $w = $cand{$c}; my $l = bestlam($w, \@tr); my ($ll, $wi, $t3) = ev($w, $l, @te ? \@te : \@tr);
  printf "%-12s %s lam=%.1f  test ll/R=%.4f ◎勝率=%.1f%% ◎3着内=%.1f%%\n", $c, join(' ', map { sprintf "%s=%.3f", $K[$_], $w->[$_] } 0 .. 4), $l, $ll, $wi, $t3 }
