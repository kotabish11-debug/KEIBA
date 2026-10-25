# 人気馬の複勝の買い方(1日の予算)を、レースや馬の条件で分けて回収率を出す。回収率がはっきり高い・低い条件を探すため
# 使い方: perl fuku_cond.pl <学習データ.jsonl.gz(カンマ区切りで複数可)> <払戻.jsonl.gz> <複勝オッズ.jsonl.gz> [期待値の下限 1.0] [複勝オッズ下限の上限 3] [分ける日 2026-08-01]
#   3着以内率・期待値は fuku_day.pl と同じ(1/単勝オッズ を合計1にした勝率からのHarville式 × 複勝オッズの下限)。各点100円の同額買い
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0);
my ($rg, $pg, $fg, $evmin, $omax, $split) = @ARGV;
$evmin ||= 1.0; $omax ||= 3; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
sub band { my ($v, @b) = @_; return '?' unless defined $v && $v ne ''; for my $i (0 .. $#b) { return ($i ? "$b[$i - 1]-" : '<') . $b[$i] if $v < $b[$i] } return "$b[-1]+" }
my (%PAY, %FUKU, %acc, %seen);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++; my $pay = $PAY{$r->{id}} or return; my $fk = $FUKU{$r->{id}} or return;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my %hit = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'複勝'} || []};
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my @pick;
  for my $i (0 .. $n - 1) { my $h = $hs[$i]; my $f = $fk->{$h->{umaban}} or next; my $o = $f->[0];
    next unless $o >= 1 && $o < $omax && $p3[$i] * $o >= $evmin; push @pick, [$i, $o] }
  for my $pk (@pick) { my ($i, $o) = @$pk; my $h = $hs[$i]; my $ev = $p3[$i] * $o; my $ret = $hit{$h->{umaban}} // 0;
    my $cls = $r->{cls} // ''; $cls = $cls =~ /新馬/ ? '新馬' : $cls =~ /未勝利/ ? '未勝利' : $cls =~ /1勝/ ? '1勝' : $cls =~ /2勝/ ? '2勝' : $cls =~ /3勝/ ? '3勝' : $cls =~ /障害/ ? '障害' : $cls =~ /オープン|OP|L/ ? 'OP' : $cls;
    my %f = (
      '全部' => '', '馬場' => $r->{surface} // '?', '距離' => band($r->{dist}, 1400, 1700, 2100), '頭数' => band($r->{heads} // $n, 10, 13, 16),
      'クラス' => $cls, '場' => $r->{place} // '?', '馬場状態' => $r->{going} || '?', '月' => substr($r->{date}, 5, 2), 'R' => band($r->{no}, 4, 7, 10),
      '人気' => $h->{pop} // '?', '単勝オッズ' => band($h->{odds}, 2, 3, 4, 6, 10), '複勝オッズ下限' => band($o, 1.2, 1.5, 2, 2.5), '期待値' => band($ev, 1.05, 1.1, 1.2, 1.3),
      '脚質' => $h->{style} || '?', '性' => $h->{sex} || '?', '年齢' => $h->{age} // '?', '枠' => band($h->{waku}, 3, 6),
      '複勝下限/単勝' => band($o / $h->{odds}, 0.4, 0.5, 0.6, 0.7), '同じレースの点数' => scalar(@pick), '曜日' => (qw(日 月 火 水 木 金 土))[(localtime(do { my ($y, $m, $d) = split /-/, $r->{date}; require Time::Local; Time::Local::timelocal(0, 0, 12, $d, $m - 1, $y) }))[6]],
    );
    for my $k (keys %f) { for my $g ($half, '全体') { my $a = $acc{$k}{$f{$k}}{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } }
  }
}) for split /,/, $rg;
printf "複勝 期待値>=%s 複勝オッズ下限<%s(前半 < %s <= 後半)\n", $evmin, $omax, $split;
for my $k ('全部', '馬場', '距離', '頭数', 'クラス', '場', '馬場状態', '月', '曜日', 'R', '人気', '単勝オッズ', '複勝オッズ下限', '期待値', '複勝下限/単勝', '同じレースの点数', '脚質', '性', '年齢', '枠') {
  print "== $k\n";
  for my $v (sort { $acc{$k}{$b}{'全体'}[0] <=> $acc{$k}{$a}{'全体'}[0] } keys %{$acc{$k} || {}}) { my $x = $acc{$k}{$v};
    printf "  %-10s %s\n", $v, join('  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %4d点 的中%5.1f%% 回収%6.1f%%", $_, $a->[0], $a->[0] ? 100 * $a->[2] / $a->[0] : 0, $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半)) }
}
