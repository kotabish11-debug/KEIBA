# 複勝オッズを足すと「3着以内」の予想が良くなるかを調べる
# 使い方: perl fuku_eval.pl <テスト開始日 YYYY-MM-DD> <複勝オッズ(fuku_odds.sh の出力フォルダーか、まとめた .jsonl.gz)> <過去レースデータ(.jsonl.gz かフォルダー)>...
# 比べるもの(どれも各馬の3着以内率):
#   A 単勝オッズだけ(2着0.85乗・3着0.70乗で割り引いたHarville式。star.pl と同じ)
#   B 複勝オッズだけ(下限と上限の幾何平均の逆数を、合計が3着までの頭数になるように割り戻す)
#   C AとBをロジスティック回帰で組み合わせる(テスト開始日より前のレースで当てはめ)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip qw($GunzipError);
my ($split, $fdir, @src) = @ARGV;
my $J = JSON::PP->new->utf8;
my @texts; for my $d (@src) { if (-d $d) { for my $f (glob("$d/*.json")) { open my $h, '<:raw', $f or next; local $/; push @texts, scalar <$h> } }
  elsif ($d =~ /\.gz$/) { my $z = IO::Uncompress::Gunzip->new($d) or die "$GunzipError"; while (my $l = $z->getline) { push @texts, $l } } }
# 複勝オッズ: フォルダー(1レース1ファイル)か、まとめた .jsonl.gz({"id":..,"fuku":{馬番:[下限,上限]}} が1行1レース)
my %FUKU; if ($fdir =~ /.gz$/) { my $z = IO::Uncompress::Gunzip->new($fdir) or die "$GunzipError"; while (my $l = $z->getline) { my $x = $J->decode($l); $FUKU{$x->{id}} = $x->{fuku} } }
my (%seen, @rows);   # 1行 = 1頭: [テストか, 3着以内か, A, B, レースの番号]
my $ri = 0;
for my $t (@texts) {
  my $r = eval { $J->decode($t) } or next; next if $seen{$r->{id}}++;
  my $fo = $FUKU{$r->{id}}; if (!$fo) { my $ff = "$fdir/$r->{id}.json"; next unless -d $fdir && -s $ff; $fo = do { open my $h, '<:raw', $ff; local $/; $J->decode(<$h>) } }
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{umaban} && $fo->{$_->{umaban}} && $fo->{$_->{umaban}}[0] > 0 } @{$r->{horses}};
  my $n = @hs; next if $n < 8;   # 7頭立て以下は複勝が2着まで
  my @pw = map { 1 / $_->{odds} } @hs; my $s = 0; $s += $_ for @pw; @pw = map { $_ / $s } @pw;
  my @A = (0) x $n;
  for my $i (0 .. $n - 1) { $A[$i] += $pw[$i]; my @r2 = grep { $_ != $i } 0 .. $n - 1; my @x2 = map { $pw[$_] ** 0.85 } @r2; my $t2 = 0; $t2 += $_ for @x2;
    for my $a (0 .. $#r2) { my $j = $r2[$a]; my $pij = $pw[$i] * $x2[$a] / $t2; $A[$j] += $pij; my @r3 = grep { $_ != $i && $_ != $j } 0 .. $n - 1;
      my @x3 = map { $pw[$_] ** 0.70 } @r3; my $t3 = 0; $t3 += $_ for @x3; $A[$r3[$_]] += $pij * $x3[$_] / $t3 for 0 .. $#r3 } }
  my @B = map { my $o = $fo->{$_->{umaban}}; 1 / sqrt($o->[0] * ($o->[1] || $o->[0])) } @hs; $s = 0; $s += $_ for @B; @B = map { 3 * $_ / $s } @B;
  my $test = $r->{date} ge $split ? 1 : 0;
  push @rows, [$test, ($hs[$_]{rank} <= 3 ? 1 : 0), $A[$_], $B[$_], $ri] for 0 .. $n - 1; $ri++;
}
sub cl { my $p = shift; $p < 0.002 ? 0.002 : $p > 0.998 ? 0.998 : $p }
sub lg { my $p = cl(shift); log($p / (1 - $p)) }
# C: logit(p) = b0 + b1*logit(A) + b2*logit(B) をニュートン法で当てはめ
my @b = (0, 1, 0);
for (1 .. 25) {
  my @g = (0, 0, 0); my @H = ([0, 0, 0], [0, 0, 0], [0, 0, 0]);
  for my $x (grep { !$_->[0] } @rows) { my @z = (1, lg($x->[2]), lg($x->[3])); my $u = 0; $u += $b[$_] * $z[$_] for 0 .. 2; my $p = 1 / (1 + exp(-$u));
    for my $i (0 .. 2) { $g[$i] += ($x->[1] - $p) * $z[$i]; $H[$i][$_] += $p * (1 - $p) * $z[$i] * $z[$_] for 0 .. 2 } }
  # 3x3 を解く
  my @M = map { [@{$H[$_]}, $g[$_]] } 0 .. 2;
  for my $c (0 .. 2) { my $v = $M[$c][$c] || 1e-9; for my $r (0 .. 2) { next if $r == $c; my $f = $M[$r][$c] / $v; $M[$r][$_] -= $f * $M[$c][$_] for 0 .. 3 } }
  $b[$_] += $M[$_][3] / ($M[$_][$_] || 1e-9) for 0 .. 2;
}
my %race; push @{$race{$_->[4]}}, $_ for @rows;
for my $x (@rows) { my $u = $b[0] + $b[1] * lg($x->[2]) + $b[2] * lg($x->[3]); push @$x, 1 / (1 + exp(-$u)) }
printf "8頭立て以上 %dレース(テスト %dレース)。C = %.3f + %.3f×logit(A) + %.3f×logit(B)\n", scalar(keys %race), scalar(grep { $_->[0][0] } values %race), @b;
for my $m ([2, 'A 単勝オッズだけ'], [3, 'B 複勝オッズだけ'], [5, 'C 単勝+複勝']) {
  my ($k, $name) = @$m; my ($ll, $nh, $hon, $cov, $nr) = (0, 0, 0, 0, 0);
  for my $id (keys %race) { my @hs = @{$race{$id}}; next unless $hs[0][0];
    $nr++; for my $x (@hs) { my $p = cl($x->[$k]); $ll += $x->[1] ? log($p) : log(1 - $p); $nh++ }
    my @o = sort { $b->[$k] <=> $a->[$k] } @hs; $hon += $o[0][1]; $cov += $_->[1] for @o[0 .. 2] }
  printf "%-14s テスト: 3着以内の対数損失 %.4f  3着以内率1位の馬が3着以内 %.1f%%  上位3頭のうち3着以内 %.3f頭\n", $name, -$ll / ($nh || 1), 100 * $hon / ($nr || 1), $cov / ($nr || 1);
}
