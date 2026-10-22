# シミュレーターの馬券の候補(推定オッズで出した期待値)が、本物の払戻でどれだけ戻ったかを券種・期待値の帯ごとに出す
# 使い方: perl eval_cands.pl <bt.jsonl> <払戻.jsonl.gz> [分ける日 YYYY-MM-DD]
#   各候補を100円ずつ買ったとして、点数・的中数・回収率を出す。分ける日を指定すると、その日より前(前半)と以後(後半)を別に出す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($bt, $pg, $split) = @ARGV; $split //= '2026-08-01';
my $J = JSON::PP->new->utf8;
my %PAY; my $z = IO::Uncompress::Gunzip->new($pg) or die;
while (my $l = $z->getline) { my $p = eval { $J->decode($l) } or next; $PAY{$p->{id}} = $p->{pay} }
my @EV = (0, 0.8, 0.9, 1.0, 1.1, 1.2, 1.5, 2.0);
my %acc; my $races = 0;
open my $h, '<:raw', $bt or die;
while (my $l = <$h>) {
  my $r = eval { $J->decode($l) } or next; my $pay = $PAY{$r->{id}} or next; next if $r->{error}; $races++;
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my %hit; for my $t (keys %$pay) { $hit{$t}{$_->{k}} += $_->{yen} for @{$pay->{$t}} }
  for my $c (@{$r->{c}}) {
    my ($type, $k, $p, $odds) = @$c; my $ev = $p * $odds; my $ret = ($hit{$type}{$k} // 0) / 100;
    my $band = $type eq '単勝' || $type eq '複勝' ? ($odds < 4 ? '<4' : $odds < 10 ? '4-10' : '10+') : ($odds < 10 ? '<10' : $odds < 30 ? '10-30' : $odds < 100 ? '30-100' : '100+');
    for my $e (@EV) { next if $ev < $e;
      for my $g ($half, '全体') { my $a = $acc{$type}{$band}{$e}{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } }
  }
}
print "races with payouts: $races (前半 < $split <= 後半)\n";
for my $type ('単勝', '複勝', 'ワイド', '馬連', '馬単', '3連複', '3連単') {
  print "== $type\n";
  for my $band (sort keys %{$acc{$type} || {}}) {
    for my $e (@EV) { my $x = $acc{$type}{$band}{$e} or next;
      printf "  %-6s 期待値>=%-4s %s\n", $band, $e, join('  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %6d点 的中%5d 回収%6.1f%%", $_, $a->[0], $a->[2], $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半)) }
  }
}
