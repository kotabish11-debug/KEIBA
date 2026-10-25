# 資金5000円(競馬用に分けたお金)を、シミュレーターの「1日の予算」の資金モード(標準の複勝・1点 = 資金の5%・1日は資金の半分まで)で
# 始めた日から回したら、今いくらになっているかを、本物の払戻で日ごとに記録する(まだ検証に使っていない新しいレースでの成績の確かめ)
# 使い方: perl bankroll_track.pl <学習データ.jsonl.gz(カンマ区切り)> <払戻.jsonl.gz> <複勝オッズ.jsonl.gz> [始めた日 2026-10-24] [初めの資金 5000] > 馬情報/資金の記録_5000円から.md
#   オッズは確定オッズで選ぶ(実際は購入時のオッズで選ぶので少しずれる)。週1回のPC収集(backfill_weekly.sh)が新しいレースを足したあとに作り直す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0 max min);
my ($rg, $pg, $fg, $from, $start) = @ARGV; $from ||= '2026-10-24'; $start ||= 5000;
my ($FRAC, $DAYMAX) = (0.05, 0.5);
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%PAY, %FUKU, %day, %seen, %name);
rd($pg, sub { $PAY{$_[0]{id}} = $_[0]{pay} });
rd($fg, sub { $FUKU{$_[0]{id}} = $_[0]{fuku} });
rd($_, sub {
  my $r = shift; return if $seen{$r->{id}}++ || $r->{date} lt $from; $day{$r->{date}} //= [];
  my $pay = $PAY{$r->{id}} or return; my $fk = $FUKU{$r->{id}} or return;
  return if ($r->{cls} // '') =~ /新馬|障害/ || ($r->{surface} // '') eq '障';
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; return if $n < 5;
  my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q; my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i]; for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my %hit = map { $_->{k} => $_->{yen} / 100 } @{$pay->{'複勝'} || []};
  for my $i (0 .. $n - 1) { my $f = $fk->{$hs[$i]{umaban}} or next; my $o = $f->[0]; my $ev = $p3[$i] * $o;
    next unless $o >= 1.2 && $o < 3 && $ev >= 1.0;
    push @{$day{$r->{date}}}, { race => "$r->{place}$r->{no}R", horse => $hs[$i]{name}, o => $o, ev => $ev, ret => $hit{$hs[$i]{umaban}} // 0 } }
}) for split /,/, $rg;
my $bal = $start; my ($cost, $ret, $nb, $nh) = (0, 0, 0, 0); my @rows;
for my $d (sort keys %day) {
  my @c = sort { $b->{ev} <=> $a->{ev} } @{$day{$d}}; 
  if (!@c || $bal < 100) { push @rows, "| $d | 0 | 0 | 0 | " . sprintf("%d", $bal) . " | 買う点なし |"; next }
  my $u = max(100, int($bal * $FRAC / 100) * 100); my $k = min(scalar @c, max(1, int($bal * $DAYMAX / $u))); @c = @c[0 .. $k - 1];
  my $dc = $u * @c; my $dr = sum0(map { $u * $_->{ret} } @c); $bal += $dr - $dc;
  $cost += $dc; $ret += $dr; $nb += @c; $nh += grep { $_->{ret} > 0 } @c;
  push @rows, sprintf('| %s | %d | %d | %d | %d | %s |', $d, scalar @c, $dc, $dr, $bal, join('、', map { "$_->{race} $_->{horse}" . ($_->{ret} > 0 ? "○$_->{ret}倍" : '×') } @c));
}
print "# 資金の記録(${start}円から・${from}〜)\n\n";
print "シミュレーターの「1日の予算」に資金を入れたときと同じ買い方(標準の人気馬の複勝・1点 = 資金の5%・1日は資金の半分まで)を、本物の払戻で回した記録。\n";
print "自動実行/検証/bankroll_track.pl が週1回(PC収集)作り直す。選ぶときのオッズは確定オッズなので、実際に買ったときと少しずれる。\n\n";
printf "- 今の資金: **%d円**(初め %d円・%+d円)\n", $bal, $start, $bal - $start;
printf "- %d点・的中%d点(%.0f%%)・使った %d円・戻り %d円・回収率 %.1f%%\n", $nb, $nh, $nb ? 100 * $nh / $nb : 0, $cost, $ret, $cost ? 100 * $ret / $cost : 0;
print "- 目安: 過去の検証は回収率123%(4〜7月105%・8〜10月143%)。300点ほどたまっても100%を下回るなら、買い方を見直す\n\n";
print "| 日付 | 点数 | 使った | 戻り | 資金 | 買った馬(○は的中・払戻の倍率) |\n|---|---|---|---|---|---|\n";
print "$_\n" for @rows;
