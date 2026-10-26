# 発走前のオッズの動き(前日・朝からどれだけ売れたか)が、確定オッズ以上に当たりに効くかを確かめる(2026-10-26〜)
# 使い方: perl odds_move.pl [オッズの推移のフォルダー 馬情報/オッズの推移] [結果 馬情報/予想と結果_馬ごと.csv] [分ける日]
#   オッズの推移 = run.sh が取った回ごとの {馬番: [単勝, 複勝下限, 上限]}。結果の odds は確定の単勝オッズ
#   動き = 確定オッズ ÷ 最初に取った単勝オッズ(1より小さい = 売れた)。直前の動き = 確定 ÷ 最後に取った単勝オッズ
#   動きの帯ごとに、3着以内の実際 ÷ 確定オッズのHarville式、勝率の実際 ÷ 確定オッズの勝率、単勝の回収率を出す
#   1より大きく、前半・後半とも同じ向きなら、オッズの動きは確定オッズに織り込み切れていない(= 買う判断に使える)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0 min);
my ($dir, $csv, $split) = @ARGV; $dir ||= '馬情報/オッズの推移'; $csv ||= '馬情報/予想と結果_馬ごと.csv';
my $J = JSON::PP->new->utf8;
my %snap;   # id => [ [at, {馬番 => 単勝}] ... ]
for my $f (glob "$dir/*.jsonl") { open my $h, '<', $f or next;
  while (my $l = <$h>) { my $x = eval { $J->decode($l) } or next; my %o = map { $_ => $x->{fuku}{$_}[0] } grep { ref $x->{fuku}{$_} eq 'ARRAY' && ($x->{fuku}{$_}[0] // 0) > 0 } keys %{$x->{fuku}};
    push @{$snap{$x->{id}}}, [$x->{at}, \%o] if %o } }
my %race;   # id => { date, h => { 馬番 => {o, rank} } }
open my $c, '<:utf8', $csv or die "$csv: $!"; my @hd = split /,/, scalar <$c>; chomp $hd[-1]; my %ix = map { $hd[$_] => $_ } 0 .. $#hd;
while (<$c>) { chomp; my @v = split /,/; (my $id = $v[$ix{raceId}]) =~ s/^k//; next unless $snap{$id};
  next unless ($v[$ix{rank}] // '') =~ /^\d+$/ && ($v[$ix{odds}] // '') =~ /^[\d.]+$/ && $v[$ix{odds}] >= 1;
  $race{$id}{date} = $v[$ix{date}]; $race{$id}{h}{$v[$ix{umaban}]} = { o => $v[$ix{odds}], rank => $v[$ix{rank}] } }
my @dates = sort map { $_->{date} } values %race; $split ||= @dates ? $dates[int(@dates / 2)] : '9999';
my (%S, $nr);
for my $id (keys %race) { my $R = $race{$id}; my @u = sort { $a <=> $b } keys %{$R->{h}}; my $n = @u; next if $n < 5;
  my @sn = sort { $a->[0] cmp $b->[0] } @{$snap{$id}}; next if @sn < 2; $nr++;
  my @q = map { 1 / $R->{h}{$_}{o} } @u; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = @q;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  for my $i (0 .. $n - 1) { my $h = $R->{h}{$u[$i]}; my $o0 = $sn[0][1]{$u[$i]} or next; my $oL = $sn[-1][1]{$u[$i]} || $o0;
    for my $kind (['朝から', $h->{o} / $o0], ['直前', $h->{o} / $oL]) { my $m = $kind->[1];
      my $b = $m < 0.6 ? '1 0.6未満(大きく売れた)' : $m < 0.8 ? '2 0.6-0.8' : $m < 0.95 ? '3 0.8-0.95' : $m < 1.05 ? '4 0.95-1.05(動かず)' : $m < 1.25 ? '5 1.05-1.25' : $m < 1.6 ? '6 1.25-1.6' : '7 1.6以上(大きく売れなかった)';
      for my $g ('全体', $R->{date} lt $split ? '前半' : '後半') { my $x = $S{$kind->[0]}{$b}{$g} ||= {};
        $x->{n}++; $x->{y3} += $h->{rank} <= 3 ? 1 : 0; $x->{p3} += min($p3[$i], 0.999); $x->{y1} += $h->{rank} == 1 ? 1 : 0; $x->{q} += $q[$i]; $x->{tan} += $h->{rank} == 1 ? $h->{o} : 0 } } } }
printf "レース %d(オッズを2回以上取れて結果のあるもの。前半 < %s <= 後半)\n", $nr // 0, $split;
print "帯: 頭数 / 3着内 実際÷市場 / 勝率 実際÷市場 / 単勝回収率(確定オッズ)。頭数が少ない帯は偶然の幅が大きい(目安: 3着内の実際÷市場の誤差は ±1/√(3着以内の数))\n";
for my $k ('朝から', '直前') { print "== $k(確定オッズ ÷ ", $k eq '朝から' ? '最初に取ったオッズ' : '最後に取ったオッズ', ")\n";
  for my $b (sort keys %{$S{$k}}) { printf "  %-26s %s\n", substr($b, 2), join '  ', map { my $x = $S{$k}{$b}{$_};
      $x ? sprintf('%s %5d頭 3着内 %.2f 勝率 %.2f 単 %5.1f%%', $_, $x->{n}, $x->{y3} / $x->{p3}, $x->{q} ? $x->{y1} / $x->{q} : 0, 100 * $x->{tan} / $x->{n}) : "$_ -" } qw(全体 前半 後半) } }
