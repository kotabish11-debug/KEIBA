# JRA-VAN の時系列オッズ(0B41 の O1 レコード)を、odds_move.pl が読む形(馬情報/オッズの推移 と同じ)に直す
# 使い方: perl odds_ts.pl <O1のファイル(jvget.exe rt 0B41 の出力)...> > 出力.jsonl
#   1行 = 1レース1回: {"id": yyyymmdd+場+R, "at": "yyyy-mm-ddThh:mm", "kubun", "fuku": {馬番: [単勝, 複勝下限, 上限]}}
#   データ区分 1=中間 2=前日最終 だけを使う(3最終・4,5確定は確定オッズと同じなので「動き」に入れない)
use strict; use warnings;
use JSON::PP;
my $J = JSON::PP->new->canonical;
my %seen;
while (my $l = <>) {
  next unless substr($l, 0, 2) eq 'O1';
  my $kubun = substr($l, 2, 1); next unless $kubun eq '1' || $kubun eq '2';
  my ($y, $md, $jyo, $r, $ht) = (substr($l, 11, 4), substr($l, 15, 4), substr($l, 19, 2), substr($l, 25, 2), substr($l, 27, 8));
  my $id = "$y$md$jyo$r";
  my $at = sprintf '%s-%s-%sT%s:%s', $y, substr($ht, 0, 2), substr($ht, 2, 2), substr($ht, 4, 2), substr($ht, 6, 2);
  next if $seen{"$id $at"}++;
  my %f;
  for my $i (0 .. 27) {
    my $t = substr($l, 43 + 8 * $i, 8); my $u = substr($t, 0, 2); next unless $u =~ /^\d\d$/ && $u > 0;
    my $o = substr($t, 2, 4); next unless $o =~ /^\d{4}$/ && $o > 0;
    $f{$u + 0} = [$o / 10];
  }
  for my $i (0 .. 27) {
    my $t = substr($l, 267 + 12 * $i, 12); my $u = substr($t, 0, 2); next unless $u =~ /^\d\d$/ && $f{$u + 0};
    my ($lo, $hi) = (substr($t, 2, 4), substr($t, 6, 4));
    push @{$f{$u + 0}}, $lo / 10, $hi / 10 if $lo =~ /^\d{4}$/ && $hi =~ /^\d{4}$/ && $lo > 0;
  }
  next unless %f;
  print $J->encode({ id => $id, at => $at, kubun => $kubun + 0, fuku => { map { $_ => $f{$_} } keys %f } }), "\n";
}
