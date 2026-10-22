# シミュレーターの勝率(能力値の勝率とオッズの勝率を比重 blend で混ぜる)× 確定オッズ = 期待値 ごとの単勝の回収率
use utf8; use strict; use warnings; binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($gz, $wstr, $lam) = @ARGV; my %W = map { split /=/ } split /,/, $wstr;
my @BL = (0.6, 0.8, 0.9, 1.0); my @EV = (0, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0);
my (%r, %seen); my $z = IO::Uncompress::Gunzip->new($gz);
while (my $l = $z->getline) { my $race = eval { decode_json($l) } or next; next if $seen{$race->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$race->{horses}}; my $n = @hs; next if $n < 5;
  my @s = map { my $h = $_; my $v = 0; $v += $W{$_} * ($h->{$_} // 60) for keys %W; $lam * $v / 10 } @hs;
  my $mx = (sort { $b <=> $a } @s)[0]; my @pm = map { exp($_ - $mx) } @s; my $S = 0; $S += $_ for @pm; @pm = map { $_ / $S } @pm;
  my @mk = map { 1 / $_->{odds} } @hs; $S = 0; $S += $_ for @mk; @mk = map { $_ / $S } @mk;
  for my $bl (@BL) { my @lg = map { (1 - $bl) * log($pm[$_]) + $bl * log($mk[$_]) } 0 .. $n - 1; my $m = (sort { $b <=> $a } @lg)[0];
    my @p = map { exp($_ - $m) } @lg; $S = 0; $S += $_ for @p; @p = map { $_ / $S } @p;
    for my $i (0 .. $n - 1) { my $ev = $p[$i] * $hs[$i]{odds}; my $pay = $hs[$i]{rank} == 1 ? $hs[$i]{odds} : 0;
      for my $e (@EV) { next if $ev < $e; my $a = $r{$bl}{$e} //= [0, 0, 0]; $a->[0]++; $a->[1] += $pay; $a->[2]++ if $pay } } } }
for my $bl (@BL) { print "blend=$bl\n"; for my $e (@EV) { my $a = $r{$bl}{$e} or next; printf "  EV>=%-4s 買い %6d点 的中 %5d 回収率 %.1f%%\n", $e, $a->[0], $a->[2], 100 * $a->[1] / $a->[0] } }
