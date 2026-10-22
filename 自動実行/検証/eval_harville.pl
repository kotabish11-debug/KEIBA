# 単勝オッズから割り引いたHarville式(2着は勝率の g2 乗、3着は g3 乗で選ぶ。star.pl と同じ考え方)で各馬券の確率を出し、
# 本物の確定オッズとの積(期待値)ごとに、本物の払戻での回収率を出す。シミュレーターの確率より当たるか・儲かるかを比べるため
# 使い方: perl eval_harville.pl <学習データ.jsonl.gz> <払戻.jsonl.gz> <確定オッズ_馬連馬単3連複.jsonl.gz> <複勝オッズ.jsonl.gz> [g2 0.85] [g3 0.70] [分ける日 2026-08-01] [券種の絞り込み(正規表現)]
#   勝率の土台は 1/単勝オッズ を合計1にしたもの。複勝は確定の複勝オッズの下限で期待値を出す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($rg, $pg, $og, $fg, $g2, $g3, $split, $only) = @ARGV; $g2 //= 0.85; $g3 //= 0.70; $split ||= '2026-08-01'; $only //= ''; utf8::decode($only);
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; return unless $f && -e $f; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %ODDS, %FUKU);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($og, sub { $ODDS{$_[0]{id}} = $_[0] });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
my @EV = (0, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5);
my (%acc, %seen, $nr);
sub add { my ($type, $o, $ev, $ret, $half) = @_;
  my $band = $o < 3 ? '<3' : $o < 6 ? '3-6' : $o < 10 ? '6-10' : $o < 20 ? '10-20' : $o < 50 ? '20-50' : $o < 100 ? '50-100' : '100+';
  for my $e (@EV) { last if $ev < $e; for my $g ($half, '全体') { for my $b ($band, '全部') { my $a = $acc{$type}{$b}{$e}{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } } } }
rd($rg, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; my $od = $ODDS{$r->{id}}; my $fk = $FUKU{$r->{id}};
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5; $nr++;
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my %hit; for my $t (keys %$pay) { $hit{$t}{$_->{k}} += $_->{yen} for @{$pay->{$t}} }
  my @q = map { 1 / $_->{odds} } @hs; my $s = 0; $s += $_ for @q; @q = map { $_ / $s } @q;
  my @q2 = map { $_ ** $g2 } @q; my @q3 = map { $_ ** $g3 } @q; my $S2 = 0; $S2 += $_ for @q2; my $S3 = 0; $S3 += $_ for @q3;
  my @U = map { $_->{umaban} } @hs;
  my $want3 = '3連複' =~ /$only/ && $od;  # 3連複を見ないときは組を作らない(遅いため)
  my (%ex, %qu, %tr, @p3);
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q2[$j] / ($S2 - $q2[$i]);
      $ex{"$U[$i]-$U[$j]"} = $pij; $qu{join '-', sort { $a <=> $b } $U[$i], $U[$j]} += $pij; $p3[$j] += $pij;
      my $den = $S3 - $q3[$i] - $q3[$j];
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; my $p = $pij * $q3[$k] / $den; $p3[$k] += $p; next unless $want3; $tr{join '-', sort { $a <=> $b } @U[$i, $j, $k]} += $p } } }
  for my $i (0 .. $n - 1) {
    add('単勝', $hs[$i]{odds}, $q[$i] * $hs[$i]{odds}, ($hit{'単勝'}{$U[$i]} // 0) / 100, $half) if '単勝' =~ /$only/;
    if ($fk && $fk->{$U[$i]} && '複勝' =~ /$only/) { my $o = $fk->{$U[$i]}[0]; add('複勝', $o, $p3[$i] * $o, ($hit{'複勝'}{$U[$i]} // 0) / 100, $half) }
  }
  return unless $od;
  for ([ '馬連', 'uren', \%qu ], [ '馬単', 'utan', \%ex ], [ '3連複', 'trio', \%tr ]) { my ($t, $k, $P) = @$_; next unless $t =~ /$only/;
    for my $c (keys %$P) { my $o = $od->{$k}{$c} or next; add($t, $o, $P->{$c} * $o, ($hit{$t}{$c} // 0) / 100, $half) } }
});
print "races: $nr  g2=$g2 g3=$g3 (前半 < $split <= 後半)\n";
for my $type ('単勝', '複勝', '馬連', '馬単', '3連複') { next unless $acc{$type};
  print "== $type\n";
  for my $band ('全部', '<3', '3-6', '6-10', '10-20', '20-50', '50-100', '100+') { next unless $acc{$type}{$band};
    for my $e (@EV) { my $x = $acc{$type}{$band}{$e} or next;
      printf "  %-6s 期待値>=%-4s %s\n", $band, $e, join('  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %6d点 的中%5d 回収%6.1f%%", $_, $a->[0], $a->[2], $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半)) }
  }
}
