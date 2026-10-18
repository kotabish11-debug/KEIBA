# ★(自信の高いレース)の判定。シミュレーターと同じ考え方で◎の3着以内率を出す
# 使い方: perl star.pl <レースデータ.json> [model.json]  → {"star":true/false,"starProb":0.83,"honmei":"馬名","honmeiTop3":0.83}
# ★の条件: ◎の3着以内率が model.json の starTop3(初期0.80)以上、かつ ◎が単勝1番人気
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;
my ($rf, $mf) = @ARGV;
sub readj { my $f = shift; open my $fh, '<:raw', $f or die "cannot open $f"; local $/; JSON::PP->new->utf8->decode(<$fh>) }
my $race = readj($rf); $race = $race->{data} if ref $race->{data} eq 'HASH';
my %W = (jisseki => .35, kyori => .15, course => .15, choshi => .20, kishu => .15); my $thr = 0.80;
if ($mf && -e $mf) { my $m = readj($mf); %W = %{$m->{weights}} if ref $m->{weights} eq 'HASH'; $thr = $m->{starTop3} if $m->{starTop3} }
my @hs = grep { !$_->{scratched} } @{$race->{horses} || []};
my $n = @hs; if ($n < 3) { print encode_json({ star => JSON::PP::false }); exit }
my $small = ($race->{place} // '') =~ /^(中山|福島|小倉|函館|札幌)$/ || ($race->{courseNote} // '') =~ /内回り/;
my ($bias, $draw) = ($race->{surface} // '') eq '障' ? ({ '逃げ' => 1, '先行' => 1, '差し' => 0, '追込' => -1.5 }, 0.3)
  : ($race->{surface} // '') eq 'ダ' ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => -0.5, '追込' => -2 }, 0.5)
  : $small ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => 0, '追込' => -2.5 }, 0.8) : ({ '逃げ' => 0, '先行' => 0.5, '差し' => 0.5, '追込' => 0 }, 0.4);
$bias = $race->{courseBias} if ref $race->{courseBias} eq 'HASH'; $draw = $race->{drawBias} if defined $race->{drawBias};
my $going = $race->{going} // 0; my $total = scalar @{$race->{horses}};
my @fixed = map { my $h = $_; my $s = 0; $s += $W{$_} * ($h->{$_} // 60) for keys %W; $s += $bias->{$h->{style} // '差し'} // 0;
  my $u = $h->{umaban} // 0; $s += $draw * (1 - 2 * ($u - 1) / ($total > 1 ? $total - 1 : 1)) if $u >= 1; $s += ($h->{heavy} // 0) * $going * 0.9; $s } @hs;
my $sigma = ($race->{chaos} // 8) + $going * 0.6;
my %PA = (high => { '逃げ' => -5, '先行' => -2, '差し' => 2, '追込' => 3 }, mid => { '逃げ' => 0, '先行' => 0.5, '差し' => 0, '追込' => -0.5 }, slow => { '逃げ' => 4, '先行' => 2, '差し' => -1.5, '追込' => -4 });
my $nige = grep { ($_->{style} // '') eq '逃げ' } @hs; my $sen = grep { ($_->{style} // '') eq '先行' } @hs;
my ($hi, $mid, $slow) = (0.25, 0.45, 0.30);
if ($nige >= 2) { $hi += .15; $slow -= .15 } if ($nige >= 3) { $hi += .10; $slow -= .10 } if ($nige == 0) { $hi -= .10; $slow += .10 }
if ($sen >= 7) { $hi += .05; $slow -= .05 } if ($sen <= 3) { $hi -= .05; $slow += .05 }
$hi = .05 if $hi < .05; $slow = .05 if $slow < .05; my $t = $hi + $mid + $slow; ($hi, $mid, $slow) = ($hi / $t, $mid / $t, $slow / $t);
srand(20261018);
my $R = 20000; my @win = (0) x $n; my @top3 = (0) x $n;
for (1 .. $R) {
  my $x = rand(); my $pace = $x < $hi ? 'high' : $x < $hi + $mid ? 'mid' : 'slow';
  my @p = map { my $u = rand() || 1e-12; $fixed[$_] + $PA{$pace}{$hs[$_]{style} // '差し'} + sqrt(-2 * log($u)) * cos(6.283185307179586 * rand()) * $sigma } 0 .. $n - 1;
  my @o = sort { $p[$b] <=> $p[$a] } 0 .. $n - 1; $win[$o[0]]++; $top3[$o[$_]]++ for 0 .. 2;
}
my @pw = map { $_ / $R } @win; my @p3 = map { $_ / $R } @top3;
my $real = !grep { $_->{oddsKari} || !($_->{odds} && $_->{odds} >= 1) } @hs;
if ($real) {
  # オッズを60%の比重で混ぜる(シミュレーターの初期設定と同じ)。3着以内率は混ぜた勝率からHarville式で出す
  my @mk = map { (1 / $_->{odds}) ** 1.15 } @hs; my $s = 0; $s += $_ for @mk; @mk = map { $_ / $s } @mk;
  my @lg = map { 0.4 * log($pw[$_] > 0 ? $pw[$_] : 0.3 / $R) + 0.6 * log($mk[$_]) } 0 .. $n - 1;
  my $mx = (sort { $b <=> $a } @lg)[0]; my @e = map { exp($_ - $mx) } @lg; $s = 0; $s += $_ for @e; @pw = map { $_ / $s } @e;
  @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; for my $k (0 .. $n - 1) { next if $k == $i || $k == $j;
    my $p = $pw[$i] * $pw[$j] / (1 - $pw[$i]) * $pw[$k] / (1 - $pw[$i] - $pw[$j]); $p3[$i] += $p; $p3[$j] += $p; $p3[$k] += $p } } }
}
my ($hon) = sort { $pw[$b] <=> $pw[$a] } 0 .. $n - 1;
my ($fav) = sort { ($hs[$a]{odds} // 999) <=> ($hs[$b]{odds} // 999) } 0 .. $n - 1;
my $star = ($p3[$hon] >= $thr && $hon == $fav) ? 1 : 0;
print JSON::PP->new->canonical->encode({ star => ($star ? JSON::PP::true : JSON::PP::false), starProb => int($p3[$hon] * 1000 + 0.5) / 1000,
  honmei => $hs[$hon]{name}, threshold => $thr, oddsReal => ($real ? JSON::PP::true : JSON::PP::false) }), "\n";
