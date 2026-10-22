# オッズが出る前(能力値だけ)のシミュレーションで、波乱度 sigma をレースの種類ごとに比べる + 仮オッズの温度 T を市場オッズに合わせる
use utf8; use strict; use warnings; binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($gz, $wstr) = @ARGV; my %W = map { split /=/ } split /,/, $wstr;
my %PA = (high => { '逃げ' => -5, '先行' => -2, '差し' => 2, '追込' => 3 }, mid => { '逃げ' => 0, '先行' => 0.5, '差し' => 0, '追込' => -0.5 }, slow => { '逃げ' => 4, '先行' => 2, '差し' => -1.5, '追込' => -4 });
my @SIG = (6, 8, 9, 10, 11, 12, 14); my @T = (4, 5, 6, 7, 8, 9, 10, 12); my $R = 2000; srand(7);
my (%acc, %kl, @over, %seen);
my $z = IO::Uncompress::Gunzip->new($gz);
while (my $l = $z->getline) { my $race = eval { decode_json($l) } or next; next if $seen{$race->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$race->{horses}}; my $n = @hs; next if $n < 5;
  my $cat = ($race->{surface} // '') eq '障' ? '障害' : (($race->{cls} // '') =~ /2歳|新馬/ || ($race->{cond} // '') =~ /ハンデ/) ? '2歳・新馬・ハンデ' : 'その他';
  my $small = ($race->{place} // '') =~ /^(中山|福島|小倉|函館|札幌)$/;
  my ($bias, $draw) = ($race->{surface} // '') eq '障' ? ({ '逃げ' => 1, '先行' => 1, '差し' => 0, '追込' => -1.5 }, 0.3)
    : ($race->{surface} // '') eq 'ダ' ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => -0.5, '追込' => -2 }, -0.2)
    : $small ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => 0, '追込' => -2.5 }, 0.8) : ({ '逃げ' => 0, '先行' => 0.5, '差し' => 0.5, '追込' => 0 }, 0.4);
  my $going = $race->{going} // 0; my $total = $race->{heads} || $n;
  my @ab = map { my $h = $_; my $s = 0; $s += $W{$_} * ($h->{$_} // 60) for keys %W; $s } @hs;
  my @fixed = map { my $h = $hs[$_]; my $s = $ab[$_] + ($bias->{$h->{style} // '差し'} // 0);
    my $u = $h->{umaban} // 0; $s += $draw * (1 - 2 * ($u - 1) / ($total > 1 ? $total - 1 : 1)) if $u >= 1; $s += ($h->{heavy} // 0) * $going * 0.9; $s } 0 .. $n - 1;
  my $nige = grep { ($_->{style} // '') eq '逃げ' } @hs; my $sen = grep { ($_->{style} // '') eq '先行' } @hs;
  my ($hi, $mid, $slow) = (0.25, 0.45, 0.30);
  if ($nige >= 2) { $hi += .15; $slow -= .15 } if ($nige >= 3) { $hi += .10; $slow -= .10 } if ($nige == 0) { $hi -= .10; $slow += .10 }
  if ($sen >= 7) { $hi += .05; $slow -= .05 } if ($sen <= 3) { $hi -= .05; $slow += .05 }
  $hi = .05 if $hi < .05; $slow = .05 if $slow < .05; my $t = $hi + $mid + $slow; ($hi, $mid, $slow) = ($hi / $t, $mid / $t, $slow / $t);
  my @ord = sort { $hs[$a]{rank} <=> $hs[$b]{rank} } 0 .. $n - 1;
  for my $sig (@SIG) { my @win = (0) x $n;
    for (1 .. $R) { my $x = rand(); my $pace = $x < $hi ? 'high' : $x < $hi + $mid ? 'mid' : 'slow'; my ($bi, $bv) = (0, -1e9);
      for my $i (0 .. $n - 1) { my $u = rand() || 1e-12; my $v = $fixed[$i] + $PA{$pace}{$hs[$i]{style} // '差し'} + sqrt(-2 * log($u)) * cos(6.283185307179586 * rand()) * ($sig + $going * 0.6); ($bi, $bv) = ($i, $v) if $v > $bv }
      $win[$bi]++ }
    my @p = map { $_ / $R > 0 ? $_ / $R : 0.3 / $R } @win; my $S = 0; $S += $_ for @p; @p = map { $_ / $S } @p;
    my ($ll, $rest) = (0, 1); for my $k (0 .. 2) { my $w = $ord[$k]; $ll += log($p[$w] / $rest); $rest -= $p[$w] }
    for my $c ($cat, '全体') { my $a = $acc{$c}{$sig} //= { n => 0, ll => 0, w1 => 0 }; $a->{n}++; $a->{ll} += $ll; $a->{w1} += log($p[$ord[0]]) } }
  # 仮オッズ: 能力値の点数 → exp(s/T) を市場の勝率(1/オッズを合計1)に合わせる(交差エントロピー)
  my @mk = map { 1 / $_->{odds} } @hs; my $ov = 0; $ov += $_ for @mk; push @over, $ov; @mk = map { $_ / $ov } @mk;
  for my $T (@T) { my $mx = (sort { $b <=> $a } @ab)[0]; my @e = map { exp(($_ - $mx) / $T) } @ab; my $S = 0; $S += $_ for @e;
    my $ce = 0; $ce -= $mk[$_] * log($e[$_] / $S) for 0 .. $n - 1; $kl{$T}{ce} += $ce; $kl{$T}{n}++; $kl{$T}{w1} += log($e[$ord[0]] / $S) } }
print "== 能力値だけのシミュレーション: 波乱度ごとの 1〜3着の対数尤度/レース(高いほど良い)・1着の対数尤度 ==\n";
for my $c (sort keys %acc) { print "[$c] n=$acc{$c}{6}{n}\n"; for my $s (@SIG) { my $a = $acc{$c}{$s}; printf "  sigma=%-4s ll3=%.4f ll1=%.4f\n", $s, $a->{ll} / $a->{n}, $a->{w1} / $a->{n} } }
print "== 仮オッズの温度 T: 市場の勝率との交差エントロピー(低いほど市場に近い)・1着の対数尤度 ==\n";
printf "  T=%-3s ce=%.4f ll1=%.4f\n", $_, $kl{$_}{ce} / $kl{$_}{n}, $kl{$_}{w1} / $kl{$_}{n} for @T;
@over = sort { $a <=> $b } @over; my $m = 0; $m += $_ for @over; printf "== 1/オッズの合計: 平均 %.3f 中央値 %.3f ==\n", $m / @over, $over[int(@over / 2)];
