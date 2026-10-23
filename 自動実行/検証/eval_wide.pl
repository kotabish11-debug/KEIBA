# ワイドを本物の払戻で確かめる。過去のワイドオッズは競馬ラボに残っていないので、2つのやり方で見る
#   1. オッズを使わない: 単勝オッズのHarville式で出した「2頭とも3着以内」の確率の順位(人気の組み合わせ)ごとの回収率
#   2. ワイドオッズを確定の3連複オッズから作る: 3連複の支持率(1/オッズを合計1にしたもの)を同じ2頭を含む組で足すと、その2頭のワイドの支持率になる。
#      ワイドの払戻率0.775を割って「仮のワイドオッズ」とし、確率 × 仮オッズ(期待値)ごとに回収率を出す。仮オッズが本物の払戻とどれだけずれるかも出す
# 使い方: perl eval_wide.pl <学習データ.jsonl.gz> <払戻.jsonl.gz> <確定オッズ_馬連馬単3連複.jsonl.gz> [g2 1.0] [g3 1.0] [分ける日 2026-08-01]
#   g2 g3 は eval_harville.pl と同じ(1.0 1.0 が割引なし。1日の予算の複勝と同じ)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($rg, $pg, $og, $g2, $g3, $split) = @ARGV; $g2 //= 1.0; $g3 //= 1.0; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; return unless $f && -e $f; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %TRIO);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($og, sub { $TRIO{$_[0]{id}} = $_[0]{trio} if $_[0]{trio} });
my @EV = (0, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5);
my (%rank, %ev, %cal, %seen, $nr, $nt);
sub acc { my ($h, $ret, $half) = @_; for my $g ($half, '全体') { my $a = $h->{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } }
sub band { my $o = shift; $o < 3 ? '<3' : $o < 6 ? '3-6' : $o < 10 ? '6-10' : $o < 20 ? '10-20' : $o < 50 ? '20-50' : '50+' }
rd($rg, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; return unless $pay->{'ワイド'};
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 8; $nr++;
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my %hit; $hit{$_->{k}} += $_->{yen} for @{$pay->{'ワイド'}};
  my @q = map { 1 / $_->{odds} } @hs; my $s = 0; $s += $_ for @q; @q = map { $_ / $s } @q;
  my @q2 = map { $_ ** $g2 } @q; my @q3 = map { $_ ** $g3 } @q; my $S2 = 0; $S2 += $_ for @q2; my $S3 = 0; $S3 += $_ for @q3;
  my @U = map { $_->{umaban} } @hs;
  my %pw;  # Harville式で「2頭とも3着以内」の確率
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q2[$j] / ($S2 - $q2[$i]); my $den = $S3 - $q3[$i] - $q3[$j];
    for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; my $p = $pij * $q3[$k] / $den;
      $pw{join '-', sort { $a <=> $b } @U[$_->[0], $_->[1]]} += $p for [$i, $j], [$i, $k], [$j, $k] } } }
  # 1. 人気の組み合わせ: 確率の高い順の何番目の組か
  my @pairs = sort { $pw{$b} <=> $pw{$a} } keys %pw;
  for my $x (0 .. $#pairs) { my $c = $pairs[$x]; my $ret = ($hit{$c} // 0) / 100;
    my $b = $x < 1 ? '1位' : $x < 3 ? '2-3位' : $x < 6 ? '4-6位' : $x < 10 ? '7-10位' : $x < 20 ? '11-20位' : '21位以下';
    acc($rank{$b} //= {}, $ret, $half); acc($rank{'全部'} //= {}, $ret, $half) }
  # 2. 3連複の確定オッズから作る仮のワイドオッズ
  my $tr = $TRIO{$r->{id}} or return; $nt++;
  my ($T, %m) = (0); $T += 1 / $_ for values %$tr;
  for my $c (keys %$tr) { my @h = split /-/, $c; my $v = 1 / $tr->{$c} / $T; $m{"$h[0]-$h[1]"} += $v; $m{"$h[0]-$h[2]"} += $v; $m{"$h[1]-$h[2]"} += $v }
  for my $c (keys %pw) { my $mm = $m{$c} or next; my $o = 0.775 / $mm; my $ret = ($hit{$c} // 0) / 100; my $e = $pw{$c} * $o; my $bd = band($o);
    if ($ret > 0) { my $a = $cal{$bd} //= [0, 0]; $a->[0]++; $a->[1] += $ret / $o }
    for my $th (@EV) { last if $e < $th; acc($ev{$bd}{$th} //= {}, $ret, $half); acc($ev{'全部'}{$th} //= {}, $ret, $half) } }
});
sub row { my $x = shift; join '  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %6d点 的中%5d(%4.1f%%) 回収%6.1f%%", $_, $a->[0], $a->[2], $a->[0] ? 100 * $a->[2] / $a->[0] : 0, $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半) }
print "races: $nr(3連複オッズあり $nt)  g2=$g2 g3=$g3 (前半 < $split <= 後半)\n";
print "== 1. 確率の順位ごと(オッズを使わない。全部買ったとき)\n";
printf "  %-8s %s\n", $_, row($rank{$_}) for grep { $rank{$_} } ('1位', '2-3位', '4-6位', '7-10位', '11-20位', '21位以下', '全部');
print "== 仮オッズのずれ(当たった組の 本物の払戻 / 仮オッズ の平均。1より大きければ本物の方が高い)\n";
printf "  %-6s %5d回  %.2f\n", $_, @{$cal{$_}}[0], $cal{$_}[1] / $cal{$_}[0] for grep { $cal{$_} } ('<3', '3-6', '6-10', '10-20', '20-50', '50+');
print "== 2. 確率 × 仮オッズ(期待値)ごと\n";
for my $bd ('全部', '<3', '3-6', '6-10', '10-20', '20-50', '50+') { next unless $ev{$bd};
  for my $th (@EV) { my $x = $ev{$bd}{$th} or next; printf "  %-6s 期待値>=%-4s %s\n", $bd, $th, row($x) } }
