#!/usr/bin/perl
# 騎手のコース連対率を「ベイズ推定(少ない騎乗数の率を、その騎手の全体の率→全騎手の平均へ寄せる)」で作り、
# そのままの率(騎乗5回以上ならそのまま使う。今の race_json.pl と同じ)より当たるかを、使っていない期間で確かめる
# (YouTube「はじめての統計学」のベイズ推定・ベイズ更新の回から。出典: 馬情報/はじめての統計学_まとめ.md)
#
# 使い方: perl 自動実行/検証/jockey_eb.pl 馬情報/過去レースデータ/全期間 [当てはめの終わり 2021-12-31] [確かめの終わり 2026-03-31]
#  - 騎手の全体の連対率は前の365日、コース(場・芝ダ・距離)の連対率は前の3年。その日のレースは入れない
#  - ベイズ推定: 全体 m = (連対 + K·全騎手の平均) ÷ (騎乗 + K)、コース r = (コースの連対 + k·m) ÷ (コースの騎乗 + k)。
#    K・k は事前分布の重さ(「K回ぶん平均の成績を見たことにする」)。当てはめの期間で一番当たる K・k を選び、確かめの期間で比べる
#  - 当たり方は、レースの中で勝つ馬の確率 exp(β·点)/Σexp(β·点) の対数尤度(1頭あたり)。オッズ無し(仮オッズ)と、市場の勝率に足したときの両方
use strict; use warnings; use utf8; use JSON::PP; use Encode qw(encode);
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
sub fn { encode('UTF-8', $_[0]) }
my ($DIR, $FIT_END, $TEST_END) = @ARGV; $FIT_END //= '2021-12-31'; $TEST_END //= '2026-03-31';
die "使い方: perl jockey_eb.pl <全期間のフォルダー> [2021-12-31] [2026-03-31]\n" unless $DIR && -d $DIR;
my $START = '2017-01-01';
sub days { my ($y, $m, $d) = split /-/, shift; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }
my %PLACE = ('01' => '札幌', '02' => '函館', '03' => '福島', '04' => '新潟', '05' => '東京', '06' => '中山', '07' => '中京', '08' => '京都', '09' => '阪神', '10' => '小倉');

my (%odds, @races);
for my $yd (sort glob("$DIR/*")) {
  next unless -d $yd && $yd =~ /\/(\d{4})$/;
  if (open my $f, '<', "$yd/" . fn('レース.jsonl')) { while (<$f>) { my $r = eval { decode_json($_) } or next;
    $odds{$r->{id}}{$_->{umaban}} = $_->{odds} for grep { $_->{umaban} && $_->{odds} } @{$r->{horses} || []} } }
  if (open my $f, '<', "$yd/" . fn('JRA詳細.jsonl')) { while (<$f>) { my $r = eval { decode_json($_) } or next; push @races, $r } }
}
@races = sort { $a->{date} cmp $b->{date} || $a->{id} cmp $b->{id} } @races;
my %seen; @races = grep { !$seen{$_->{id}}++ } @races;
print STDERR scalar(@races), " レース\n";

# 騎手ごと・コースごとの、日付つきの連対の記録(前の365日・3年を数える)
my (%ev, %cnt);   # キー → [[日, 連対], ...] / キー → [先頭の位置, 騎乗, 連対]
sub add { my ($k, $d, $t) = @_; push @{$ev{$k}}, [$d, $t]; my $c = $cnt{$k} //= [0, 0, 0]; $c->[1]++; $c->[2] += $t }
sub get { my ($k, $from) = @_; my $c = $cnt{$k} or return (0, 0); my $e = $ev{$k};
  while ($c->[0] < @$e && $e->[$c->[0]][0] < $from) { $c->[1]--; $c->[2] -= $e->[$c->[0]][1]; $c->[0]++ } ($c->[1], $c->[2]) }
my ($gN, $gW) = (0, 0);   # 全騎手の連対率(前の365日の近似として、通算を使う)
my @rows;   # 確かめる馬: [期間 0=当てはめ 1=確かめ, レース番号, 勝ち, 市場の勝率, 騎手N, 騎手W, コースn, コースw, 全体の平均]
my $ri = 0; my %byday; push @{$byday{$_->{date}}}, $_ for @races;
for my $date (sort keys %byday) {
  my $d = days($date); my @todo;
  for my $r (@{$byday{$date}}) {
    my $R = $r->{race} || {}; my $surf = $R->{surface} // ''; next if ($R->{course} // '') =~ /障|→/ || $surf =~ /障/; $surf = 'ダ' if $surf =~ /^ダ/;
    my $ck = ($PLACE{substr($r->{id}, 8, 2)} // '') . $surf . ($R->{dist} // 0);
    my @H = grep { $_->{jockey} && ($_->{rank} // '') =~ /^\d+$/ } @{$r->{horses} || []}; next if @H < 5;
    my $o = $odds{$r->{id}} || {};
    my $evalr = $date ge $START && $date le $TEST_END && !grep { !$o->{$_->{umaban}} } @H;
    my $g = $gN ? $gW / $gN : 0.14; my $id = $ri++;
    if ($evalr) { my $s = 0; $s += 1 / $o->{$_->{umaban}} for @H;
      for my $h (@H) { (my $jk = $h->{jockey}) =~ s/^[A-Za-z]\.//; my ($N, $W) = get("J$jk", $d - 365); my ($n, $w) = get("C$jk\t$ck", $d - 3 * 365);
        push @rows, [$date le $FIT_END ? 0 : 1, $id, $h->{rank} == 1 ? 1 : 0, (1 / $o->{$h->{umaban}}) / $s, $N, $W, $n, $w, $g] } }
    push @todo, map { (my $jk = $_->{jockey}) =~ s/^[A-Za-z]\.//; ["J$jk", "C$jk\t$ck", $_->{rank} <= 2 ? 1 : 0] } @H;
  }
  for (@todo) { add($_->[0], $d, $_->[2]); add($_->[1], $d, $_->[2]); $gN++; $gW += $_->[2] }
}
print STDERR scalar(@rows), " 頭(当てはめ ", scalar(grep { !$_->[0] } @rows), ")\n";

# 点の作り方。返すのは連対率(0〜1)
sub lg { my $p = shift; $p = 0.005 if $p < 0.005; $p = 0.995 if $p > 0.995; log($p / (1 - $p)) }
my %M = (
  'そのまま(コース5回以上、無ければ平均)' => sub { my $x = shift; $x->[6] >= 5 ? $x->[7] / $x->[6] : $x->[8] },
  'そのまま(騎手の全体の率)' => sub { my $x = shift; $x->[4] >= 5 ? $x->[5] / $x->[4] : $x->[8] },
);
for my $K (10, 30, 100) { for my $k (5, 20, 50, 200) {
  $M{sprintf 'ベイズ K=%d k=%d', $K, $k} = sub { my $x = shift; my $m = ($x->[5] + $K * $x->[8]) / ($x->[4] + $K); ($x->[7] + $k * $m) / ($x->[6] + $k) } } }
$M{"$_ (logit)"} = do { my $g = $M{$_}; sub { lg($g->($_[0])) } } for grep { /^そのまま\(コース|K=10 k=200/ } keys %M;
# β を1つだけ当てはめる(条件付きロジット、ニュートン法)。点 = 連対率(「(logit)」は連対率の logit)
my @GR; { my %R; push @{$R{$_->[0]}{$_->[1]}}, $_ for @rows; @GR = map { [values %{$R{$_} || {}}] } 0, 1 }
sub ll { my ($set, $f, $mk, $be) = @_; my ($L, $G, $Hs, $n) = (0, 0, 0, 0);
  for my $rr (@{$GR[$set]}) { my @x = map { $f->($_) } @$rr; my @s = map { ($mk ? log($rr->[$_][3]) : 0) + $be * $x[$_] } 0 .. $#x;
    my $mx = $s[0]; for (@s) { $mx = $_ if $_ > $mx } my @e = map { exp($_ - $mx) } @s; my $Z = 0; $Z += $_ for @e; my ($ex, $ex2) = (0, 0);
    for (0 .. $#e) { my $p = $e[$_] / $Z; $ex += $p * $x[$_]; $ex2 += $p * $x[$_] ** 2; if ($rr->[$_][2]) { $L += $s[$_] - $mx - log($Z); $G += $x[$_] } }
    $G -= $ex if grep { $_->[2] } @$rr; $Hs -= $ex2 - $ex ** 2; $n += @$rr }
  ($L, $G, $Hs, $n) }
sub fit { my ($f, $mk) = @_; my $be = 0; for (1 .. 12) { my (undef, $G, $H) = ll(0, $f, $mk, $be); last if !$H; my $st = $G / $H; $be -= $st; last if abs($st) < 1e-4 } $be }
for my $mk (0, 1) {
  print $mk ? "\n## 市場の勝率(1/オッズ)に足したとき(0 ならオッズに織り込み済み)\n" : "## オッズ無し(仮オッズ。騎手の点だけでどれだけ勝ち馬を当てるか)\n";
  print "| 点の作り方 | β | 当てはめ期間の対数尤度/頭 | 確かめ期間の対数尤度/頭 | 確かめ期間の差(×1000) |\n|---|---|---|---|---|\n";
  my ($L0) = ll(1, sub { 0 }, $mk, 0); my (undef, undef, undef, $n1) = ll(1, sub { 0 }, $mk, 0); my ($F0, undef, undef, $n0) = ll(0, sub { 0 }, $mk, 0);
  printf "| 騎手を見ない | 0 | %.5f | %.5f | 0 |\n", $F0 / $n0, $L0 / $n1;
  for my $name (sort keys %M) { my $be = fit($M{$name}, $mk); my ($F) = ll(0, $M{$name}, $mk, $be); my ($L) = ll(1, $M{$name}, $mk, $be);
    printf "| %s | %.3f | %.5f | %.5f | %+.2f |\n", $name, $be, $F / $n0, $L / $n1, ($L - $L0) / $n1 * 1000 }
}
