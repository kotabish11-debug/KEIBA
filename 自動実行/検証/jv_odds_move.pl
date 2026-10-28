# 買う前に見えるオッズの動き(JRA-VAN の時系列オッズ)が、確定オッズ以上に当たりに効くかを確かめる(2026-10-27)
# odds_move.pl の「直前」は締切1分前→確定の動きで、買う時には分からない。ここでは締切1分前までに見える動きだけを使う
# 使い方: perl jv_odds_move.pl [馬情報/JRA-VAN] [分ける日 2026-04-01] [買う時 = 締切の何分前 1]
#   o1_raw.txt(jvget.exe rt 0B41)の データ区分 1=中間 3=最終(締切)。締切 = 区分3の発表時刻
#   見る時点 = 締切 lag 分前までの最後の中間(買う時)。比べる時点 = 買う時の10分前・30分前・当日の最初
#   動き = 買う時のオッズ ÷ 比べる時点のオッズ(1より小さい = 売れてきた)
#   帯ごとに 3着内 実際÷市場(確定オッズの Harville 式を p3_fit.pl の式で直したもの)・単勝/複勝の回収率(確定の払戻)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use Encode qw(decode_utf8); use List::Util qw(sum0 min max);
my ($D, $split, $lag) = map { decode_utf8($_) } @ARGV; $D ||= '馬情報/JRA-VAN'; $split ||= '2026-04-01'; $lag ||= 1;   # 買う時 = 締切 $lag 分前

# 1. 時系列オッズ: id => { close => 分, s => [[分, 日付, {馬番 => 単勝}]] }
my %T;
open my $h, '<', "$D/o1_raw.txt" or die "$D/o1_raw.txt: $!";
while (my $l = <$h>) {
  next unless $l =~ /^O1([13])/; my $k = $1;
  my $id = substr($l, 11, 8) . substr($l, 19, 2) . substr($l, 25, 2);
  my $t = substr($l, 27, 8); my $day = substr($t, 0, 4); my $min = substr($t, 4, 2) * 60 + substr($t, 6, 2);
  if ($k eq '3') { $T{$id}{close} = $min; $T{$id}{cday} = $day; next }
  my %o;
  for my $i (0 .. 27) { my $s = substr($l, 43 + 8 * $i, 8); my $u = substr($s, 0, 2); next unless $u =~ /^\d\d$/ && $u > 0;
    my $v = substr($s, 2, 4); $o{$u + 0} = $v / 10 if $v =~ /^\d{4}$/ && $v > 0 }
  push @{$T{$id}{s}}, [$min, $day, \%o] if %o;
}
close $h;

# 2. 結果と複勝の払戻
my %R;
open my $c, '<', "$D/結果_馬ごと.csv" or die; <$c>;
while (<$c>) { chomp; my ($id, $date, $u, $rk, $o) = split /,/; next unless $T{$id};
  push @{$R{$id}{h}}, { u => $u, rk => $rk, o => $o }; $R{$id}{date} = $date }
close $c;
my %fuku; my $J = JSON::PP->new->utf8;
for my $pf (map { decode_utf8($_) } glob "馬情報/過去レースデータ/全期間/202[56]/払戻.jsonl") { open my $p, '<', $pf or next;
  while (my $l = <$p>) { my $x = eval { $J->decode($l) } or next; next unless $R{$x->{id}};
    $fuku{$x->{id}}{$_->{k}} = $_->{yen} / 100 for @{$x->{pay}{'複勝'} || []} } }

# 3. 集計
my (%S, $nr);
for my $id (keys %R) {
  my $X = $T{$id}; next unless defined $X->{close};
  my @s = sort { $a->[0] <=> $b->[0] } grep { $_->[1] eq $X->{cday} && $_->[0] <= $X->{close} - $lag } @{$X->{s} || []};
  next if @s < 3;
  my $buy = $s[-1]; next if $X->{close} - $buy->[0] > $lag + 2;
  my %at = (buy => $buy->[2]);
  for my $back ([10, '10分前'], [30, '30分前']) { my ($x) = grep { $_->[0] <= $buy->[0] - $back->[0] } reverse @s; $at{$back->[1]} = $x->[2] if $x }
  $at{'当日の最初'} = $s[0][2];
  my $Hs = $R{$id}{h}; my $n = @$Hs; next if $n < 5; $nr++;
  my @q = map { 1 / $_->{o} } @$Hs; my $sq = sum0(@q); @q = map { $_ / $sq } @q;
  my @p3 = @q;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  for my $i (0 .. $n - 1) { my $m = $Hs->[$i]; my $ob = $at{buy}{$m->{u}} or next;
    my $hh = min(max($p3[$i], 1e-4), 0.999); my $L = log($hh / (1 - $hh)); my $p = 1 / (1 + exp(-(-0.133 + 0.752 * $L - 0.036 * $L * $L)));
    for my $k ('10分前', '30分前', '当日の最初') { my $o0 = $at{$k} && $at{$k}{$m->{u}} or next; my $mv = $ob / $o0;
      my $b = $mv < 0.7 ? '1 0.7未満(大きく売れてきた)' : $mv < 0.85 ? '2 0.7-0.85' : $mv < 0.95 ? '3 0.85-0.95' : $mv < 1.05 ? '4 0.95-1.05(動かず)' : $mv < 1.2 ? '5 1.05-1.2' : $mv < 1.5 ? '6 1.2-1.5' : '7 1.5以上(売れなくなった)';
      for my $pop ('全部', $ob < 5 ? '買う時5倍未満' : $ob < 15 ? '買う時5-15倍' : '買う時15倍以上') {
        for my $g ('全体', $R{$id}{date} lt $split ? '前半' : '後半') { my $x = $S{$k}{$pop}{$b}{$g} ||= {};
          $x->{n}++; $x->{y} += $m->{rk} <= 3 ? 1 : 0; $x->{p} += $p; $x->{v} += $p * (1 - $p);
          $x->{tan} += $m->{rk} == 1 ? $m->{o} : 0; $x->{fk} += $fuku{$id}{$m->{u}} // 0 } } } } }

printf "レース %d(前半 < %s <= 後半)。動き = 買う時(締切 $lag 分前)のオッズ ÷ 比べる時点のオッズ。3着内 = 実際÷市場、z、単・複 = 確定の払戻での回収率\n", $nr // 0, $split;
for my $k ('10分前', '30分前', '当日の最初') { for my $pop ('全部', '買う時5倍未満', '買う時5-15倍', '買う時15倍以上') {
    print "== $k から / $pop\n";
    for my $b (sort keys %{$S{$k}{$pop}}) { printf "  %-22s %s\n", substr($b, 2), join '  ', map { my $x = $S{$k}{$pop}{$b}{$_};
        $x && $x->{p} ? sprintf('%s %5d頭 %.2f z%+5.1f 単%6.1f%% 複%6.1f%%', $_, $x->{n}, $x->{y} / $x->{p}, ($x->{y} - $x->{p}) / sqrt($x->{v} || 1), 100 * $x->{tan} / $x->{n}, 100 * $x->{fk} / $x->{n}) : "$_ -" } qw(全体 前半 後半) } } }
