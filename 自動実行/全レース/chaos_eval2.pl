# A: 能力値だけで波乱度を広く。B: オッズ90%を混ぜたとき(シミュレーターと同じ合わせ込み)の3着以内率の当たり方
use utf8; use strict; use warnings; binmode STDOUT, ':utf8'; $| = 1;
use JSON::PP; use IO::Uncompress::Gunzip;
my ($gz, $wstr, $part) = @ARGV; my %W = map { split /=/ } split /,/, $wstr;
my %PA = (high => { '逃げ' => -5, '先行' => -2, '差し' => 2, '追込' => 3 }, mid => { '逃げ' => 0, '先行' => 0.5, '差し' => 0, '追込' => -0.5 }, slow => { '逃げ' => 4, '先行' => 2, '差し' => -1.5, '追込' => -4 });
my @SIG = $part eq 'A' ? (12, 14, 16, 18, 20, 24) : (8.5, 11, 14, 18); srand(11);
my (%acc, %seen, $cnt); my $z = IO::Uncompress::Gunzip->new($gz);
sub sim { my ($fx, $st, $sig, $pp, $R, $top3) = @_; my $n = @$fx; my @w = (0) x $n; my @t3 = (0) x $n;
  for (1 .. $R) { my $x = rand(); my $pace = $x < $pp->[0] ? 'high' : $x < $pp->[0] + $pp->[1] ? 'mid' : 'slow'; my @v;
    for my $i (0 .. $n - 1) { my $u = rand() || 1e-12; push @v, $fx->[$i] + $PA{$pace}{$st->[$i]} + sqrt(-2 * log($u)) * cos(6.283185307179586 * rand()) * $sig }
    my @o = sort { $v[$b] <=> $v[$a] } 0 .. $n - 1; $w[$o[0]]++; if ($top3) { $t3[$_]++ for @o[0 .. 2] } }
  return ([map { $_ / $R } @w], [map { $_ / $R } @t3]) }
while (my $l = $z->getline) { my $race = eval { decode_json($l) } or next; next if $seen{$race->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$race->{horses}}; my $n = @hs; next if $n < 5;
  next if $part eq 'B' && ++$cnt % 3;
  my $cat = ($race->{surface} // '') eq '障' ? '障害' : (($race->{cls} // '') =~ /2歳|新馬/ || ($race->{cond} // '') =~ /ハンデ/) ? '2歳・新馬・ハンデ' : 'その他';
  my $small = ($race->{place} // '') =~ /^(中山|福島|小倉|函館|札幌)$/;
  my ($bias, $draw) = ($race->{surface} // '') eq '障' ? ({ '逃げ' => 1, '先行' => 1, '差し' => 0, '追込' => -1.5 }, 0.3)
    : ($race->{surface} // '') eq 'ダ' ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => -0.5, '追込' => -2 }, -0.2)
    : $small ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => 0, '追込' => -2.5 }, 0.8) : ({ '逃げ' => 0, '先行' => 0.5, '差し' => 0.5, '追込' => 0 }, 0.4);
  my $going = $race->{going} // 0; my $total = $race->{heads} || $n; my @st = map { $_->{style} // '差し' } @hs; $_ = exists $PA{mid}{$_} ? $_ : '差し' for @st;
  my @fixed = map { my $h = $_; my $s = 0; $s += $W{$_} * ($h->{$_} // 60) for keys %W; $s += $bias->{$h->{style} // '差し'} // 0;
    my $u = $h->{umaban} // 0; $s += $draw * (1 - 2 * ($u - 1) / ($total > 1 ? $total - 1 : 1)) if $u >= 1; $s += ($h->{heavy} // 0) * $going * 0.9; $s } @hs;
  my $nige = grep { $_ eq '逃げ' } @st; my $sen = grep { $_ eq '先行' } @st;
  my ($hi, $mid, $slow) = (0.25, 0.45, 0.30);
  if ($nige >= 2) { $hi += .15; $slow -= .15 } if ($nige >= 3) { $hi += .10; $slow -= .10 } if ($nige == 0) { $hi -= .10; $slow += .10 }
  if ($sen >= 7) { $hi += .05; $slow -= .05 } if ($sen <= 3) { $hi -= .05; $slow += .05 }
  $hi = .05 if $hi < .05; $slow = .05 if $slow < .05; my $t = $hi + $mid + $slow; my $pp = [$hi / $t, $mid / $t, $slow / $t];
  my @ord = sort { $hs[$a]{rank} <=> $hs[$b]{rank} } 0 .. $n - 1;
  my @mk = map { 1 / $_->{odds} } @hs; my $S = 0; $S += $_ for @mk; @mk = map { $_ / $S } @mk;
  for my $s0 (@SIG) { my $sig = $s0 + $going * 0.6;
    if ($part eq 'A') { my ($w) = sim(\@fixed, \@st, $sig, $pp, 2000, 0); my @p = map { $_ > 0 ? $_ : 0.15 / 2000 } @$w; $S = 0; $S += $_ for @p; @p = map { $_ / $S } @p;
      my ($ll, $rest) = (0, 1); for my $k (0 .. 2) { my $x = $ord[$k]; $ll += log($p[$x] / $rest); $rest -= $p[$x] }
      for my $c ($cat, '全体') { my $a = $acc{$c}{$s0} //= [0, 0]; $a->[0]++; $a->[1] += $ll } next }
    # B: 能力値の勝率とオッズの勝率を90%で混ぜた目標に、地力をずらして合わせる(simulator.html の simulate と同じ)
    my ($w) = sim(\@fixed, \@st, $sig, $pp, 1500, 0); my @pm = map { $_ > 0.3 / 1500 ? $_ : 0.3 / 1500 } @$w;
    my @lg = map { 0.1 * log($pm[$_]) + 0.9 * log($mk[$_]) } 0 .. $n - 1; my $mx = (sort { $b <=> $a } @lg)[0]; my @tg = map { exp($_ - $mx) } @lg; $S = 0; $S += $_ for @tg; @tg = map { $_ / $S } @tg;
    my @adj = @fixed; for my $it (1 .. 8) { my ($sw) = sim(\@adj, \@st, $sig, $pp, 1500, 0); my $err = 0;
      for my $i (0 .. $n - 1) { my $d = log($tg[$i]) - log($sw->[$i] > 0.5 / 1500 ? $sw->[$i] : 0.5 / 1500); $err = abs($d) if abs($d) > $err; my $st2 = 0.35 * $sig * $d; $adj[$i] += $st2 > 8 ? 8 : $st2 < -8 ? -8 : $st2 } last if $err < 0.06 }
    my (undef, $t3) = sim(\@adj, \@st, $sig, $pp, 3000, 1);
    my $c = $acc{"全体"}{$s0} //= [0, 0, 0, 0]; $c->[0]++;
    for my $i (0 .. $n - 1) { my $p = $t3->[$i]; $p = 0.002 if $p < 0.002; $p = 0.998 if $p > 0.998; my $y = $hs[$i]{rank} <= 3 ? 1 : 0; $c->[1] -= $y ? log($p) : log(1 - $p); $c->[2]++ }
    my ($top) = sort { $t3->[$b] <=> $t3->[$a] } 0 .. $n - 1; $c->[3]++ if $hs[$top]{rank} <= 3 } }
if ($part eq 'A') { for my $c (sort keys %acc) { print "[$c]\n"; printf "  sigma=%-4s ll3=%.4f\n", $_, $acc{$c}{$_}[1] / $acc{$c}{$_}[0] for @SIG } }
else { for (@SIG) { my $a = $acc{'全体'}{$_}; printf "sigma=%-4s races=%d 3着以内の対数損失=%.4f 3着以内率1位が3着以内=%.1f%%\n", $_, $a->[0], $a->[1] / $a->[2], 100 * $a->[3] / $a->[0] } }
