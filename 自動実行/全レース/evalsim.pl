# シミュレーターと同じ計算(star.pl と同じ: 能力値→脚質・枠・馬場の補正→展開と乱数で走らせる→オッズを混ぜる)を過去のレースで回し、
# 「オッズの比重」「オッズの補正(べき乗)」「荒れ具合(乱数の大きさ)」のどの組み合わせが一番当たるかを調べる
# 使い方: perl evalsim.pl <model.json> <フォルダー>... > 結果.tsv
#   出力: sigma(荒れ具合) gamma(オッズのべき乗) blend(オッズの比重) races 対数尤度/レース ◎勝率 ◎3着内率 上位3頭の3着内頭数
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use JSON::PP;
my ($mf, @dirs) = @ARGV;
my $J = JSON::PP->new->utf8;
my %W = (jisseki => .35, kyori => .15, course => .15, choshi => .20, kishu => .15);
if ($mf && -e $mf) { open my $m, '<:raw', $mf; local $/; my $x = $J->decode(<$m>); %W = %{$x->{weights}} if ref $x->{weights} eq 'HASH' }
my @races;
# 引数はフォルダー(1レース1ファイル)か、まとめた .jsonl.gz(馬情報/過去レースデータ/)
use IO::Uncompress::Gunzip qw($GunzipError);
my @texts; for my $d (@dirs) { if (-d $d) { for my $f (glob("$d/*.json")) { open my $h, '<:raw', $f or next; local $/; push @texts, scalar <$h> } }
  elsif ($d =~ /.gz$/) { my $z = IO::Uncompress::Gunzip->new($d) or die "$GunzipError"; while (my $l = $z->getline) { push @texts, $l } } }
for my $t (@texts) { { my $r = eval { $J->decode($t) } or next;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; next if @hs < 5; $r->{horses} = \@hs; push @races, $r } }
my %seen; @races = grep { !$seen{$_->{id}}++ } @races;
print STDERR scalar(@races), " races\n";
my %PA = (high => { '逃げ' => -5, '先行' => -2, '差し' => 2, '追込' => 3 }, mid => { '逃げ' => 0, '先行' => 0.5, '差し' => 0, '追込' => -0.5 }, slow => { '逃げ' => 4, '先行' => 2, '差し' => -1.5, '追込' => -4 });
my @SIG = (6, 8.5, 11); my @GAM = (1.0, 1.15, 1.22, 1.3, 1.45); my @BL = (0, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0);
my $R = 3000;
my %acc;
srand(20261021);
for my $race (@races) {
  my @hs = @{$race->{horses}}; my $n = @hs;
  my $small = ($race->{place} // '') =~ /^(中山|福島|小倉|函館|札幌)$/;
  my ($bias, $draw) = ($race->{surface} // '') eq '障' ? ({ '逃げ' => 1, '先行' => 1, '差し' => 0, '追込' => -1.5 }, 0.3)
    : ($race->{surface} // '') eq 'ダ' ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => -0.5, '追込' => -2 }, -0.2)
    : $small ? ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => 0, '追込' => -2.5 }, 0.8) : ({ '逃げ' => 0, '先行' => 0.5, '差し' => 0.5, '追込' => 0 }, 0.4);
  my $going = $race->{going} // 0; my $total = $race->{heads} || $n;
  my @fixed = map { my $h = $_; my $s = 0; $s += $W{$_} * ($h->{$_} // 60) for keys %W; $s += $bias->{$h->{style} // '差し'} // 0;
    my $u = $h->{umaban} // 0; $s += $draw * (1 - 2 * ($u - 1) / ($total > 1 ? $total - 1 : 1)) if $u >= 1; $s += ($h->{heavy} // 0) * $going * 0.9; $s } @hs;
  my $nige = grep { ($_->{style} // '') eq '逃げ' } @hs; my $sen = grep { ($_->{style} // '') eq '先行' } @hs;
  my ($hi, $mid, $slow) = (0.25, 0.45, 0.30);
  if ($nige >= 2) { $hi += .15; $slow -= .15 } if ($nige >= 3) { $hi += .10; $slow -= .10 } if ($nige == 0) { $hi -= .10; $slow += .10 }
  if ($sen >= 7) { $hi += .05; $slow -= .05 } if ($sen <= 3) { $hi -= .05; $slow += .05 }
  $hi = .05 if $hi < .05; $slow = .05 if $slow < .05; my $t = $hi + $mid + $slow; ($hi, $mid, $slow) = ($hi / $t, $mid / $t, $slow / $t);
  my @ord = sort { $hs[$a]{rank} <=> $hs[$b]{rank} } 0 .. $n - 1;
  for my $sig (@SIG) {
    my @win = (0) x $n;
    for (1 .. $R) {
      my $x = rand(); my $pace = $x < $hi ? 'high' : $x < $hi + $mid ? 'mid' : 'slow';
      my ($bi, $bv) = (0, -1e9);
      for my $i (0 .. $n - 1) { my $u = rand() || 1e-12; my $v = $fixed[$i] + $PA{$pace}{$hs[$i]{style} // '差し'} + sqrt(-2 * log($u)) * cos(6.283185307179586 * rand()) * $sig; ($bi, $bv) = ($i, $v) if $v > $bv }
      $win[$bi]++;
    }
    my @pm = map { $_ / $R > 0 ? $_ / $R : 0.3 / $R } @win;
    for my $gam (@GAM) {
      my @mk = map { (1 / $_->{odds}) ** $gam } @hs; my $s = 0; $s += $_ for @mk; @mk = map { $_ / $s } @mk;
      for my $bl (@BL) {
        next if $gam != 1.15 && $bl == 0;   # オッズを使わないときはべき乗に関係しない
        my @lg = map { (1 - $bl) * log($pm[$_]) + $bl * log($mk[$_]) } 0 .. $n - 1;
        my $mx = (sort { $b <=> $a } @lg)[0]; my @e = map { exp($_ - $mx) } @lg; my $S = 0; $S += $_ for @e; my @p = map { $_ / $S } @e;
        # 1〜3着の順番の対数尤度(Harville)
        my ($ll, $rest) = (0, 1); for my $k (0 .. 2) { last if $k >= $n; my $w = $ord[$k]; $ll += log($p[$w] / $rest); $rest -= $p[$w] }
        # 上位3頭の3着以内率(Harville)
        my @p3 = (0) x $n;
        for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $p[$i] * $p[$j] / (1 - $p[$i]);
          for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; my $q = $pij * $p[$k] / (1 - $p[$i] - $p[$j]); $p3[$i] += $q; $p3[$j] += $q; $p3[$k] += $q } } }
        my ($hon) = sort { $p[$b] <=> $p[$a] } 0 .. $n - 1; my @t3 = (sort { $p3[$b] <=> $p3[$a] } 0 .. $n - 1)[0 .. 2];
        my $a = $acc{"$sig\t$gam\t$bl"} //= { n => 0, ll => 0, w => 0, t3 => 0, cov => 0 };
        $a->{n}++; $a->{ll} += $ll; $a->{w}++ if $hs[$hon]{rank} == 1; $a->{t3}++ if $hs[$hon]{rank} <= 3; $a->{cov} += grep { $hs[$_]{rank} <= 3 } @t3;
      }
    }
  }
}
print "sigma\tgamma\tblend\traces\tllPerRace\thonmeiWin\thonmeiTop3\ttop3in3\n";
for my $k (sort { $acc{$b}{ll} <=> $acc{$a}{ll} } keys %acc) { my $a = $acc{$k};
  printf "%s\t%d\t%.4f\t%.1f\t%.1f\t%.3f\n", $k, $a->{n}, $a->{ll} / $a->{n}, 100 * $a->{w} / $a->{n}, 100 * $a->{t3} / $a->{n}, $a->{cov} / $a->{n} }
