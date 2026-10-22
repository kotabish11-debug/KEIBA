# シミュレーターの確率 × 本物の(確定)オッズ = 期待値 で買ったとき、本物の払戻でどれだけ戻ったかを出す
# 使い方: perl eval_real.pl <bt.jsonl> <払戻.jsonl.gz> <確定オッズ_馬連馬単3連複.jsonl.gz> <複勝オッズ.jsonl.gz> [分ける日 2026-08-01]
#   単勝は確定の単勝オッズ、複勝は確定の複勝オッズの下限、馬連・馬単・3連複は確定オッズで期待値を出す
#   券種・オッズの帯・期待値の下限ごとに、100円ずつ買ったときの点数・的中数・回収率を前半/後半/全体で出す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip;
my ($bt, $pg, $og, $fg, $split) = @ARGV; $split ||= '2026-08-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; return unless $f && -e $f; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %ODDS, %FUKU);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($og, sub { $ODDS{$_[0]{id}} = $_[0] });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
my %TK = ('馬連' => 'uren', '馬単' => 'utan', '3連複' => 'trio');
my @EV = (0, 0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0);
my %acc; my %n;
open my $h, '<:raw', $bt or die;
while (my $l = <$h>) {
  my $r = eval { $J->decode($l) } or next; next if $r->{error}; my $pay = $PAY{$r->{id}} or next;
  my $half = $r->{date} lt $split ? '前半' : '後半';
  my %hit; for my $t (keys %$pay) { $hit{$t}{$_->{k}} += $_->{yen} for @{$pay->{$t}} }
  my $od = $ODDS{$r->{id}}; my $fk = $FUKU{$r->{id}};
  $n{od}++ if $od; $n{fk}++ if $fk;
  for my $c (@{$r->{c}}) {
    my ($type, $k, $p) = @$c; my $o;
    if ($type eq '単勝') { $o = $c->[3] }
    elsif ($type eq '複勝') { next unless $fk && $fk->{$k}; $o = $fk->{$k}[0] }
    elsif ($TK{$type}) { next unless $od; $o = $od->{$TK{$type}}{$k} or next }
    else { next }
    my $ev = $p * $o; my $ret = ($hit{$type}{$k} // 0) / 100;
    my $band = $o < 3 ? '<3' : $o < 6 ? '3-6' : $o < 10 ? '6-10' : $o < 20 ? '10-20' : $o < 50 ? '20-50' : $o < 100 ? '50-100' : '100+';
    for my $e (@EV) { next if $ev < $e;
      for my $g ($half, '全体') { for my $b ($band, '全部') { my $a = $acc{$type}{$b}{$e}{$g} //= [0, 0, 0]; $a->[0]++; $a->[1] += $ret; $a->[2]++ if $ret > 0 } } }
  }
}
print "確定オッズあり $n{od} レース / 複勝オッズあり $n{fk} レース(前半 < $split <= 後半)\n";
for my $type ('単勝', '複勝', '馬連', '馬単', '3連複') {
  print "== $type\n";
  for my $band ('全部', '<3', '3-6', '6-10', '10-20', '20-50', '50-100', '100+') { next unless $acc{$type}{$band};
    for my $e (@EV) { my $x = $acc{$type}{$band}{$e} or next;
      printf "  %-6s 期待値>=%-4s %s\n", $band, $e, join('  ', map { my $a = $x->{$_} || [0, 0, 0]; sprintf "%s %6d点 的中%5d 回収%6.1f%%", $_, $a->[0], $a->[2], $a->[0] ? 100 * $a->[1] / $a->[0] : 0 } qw(全体 前半 後半)) }
  }
}
