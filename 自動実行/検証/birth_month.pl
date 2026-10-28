# 生まれ月ごとに、2歳戦・3歳前半(1〜6月)の勝率と3着以内率がオッズの見込みとずれるか(2026-10-27〜)
# J-STAGE「競馬」の論文(生まれ月の相対年齢効果・子馬の発育)と、新馬戦の見方.md の「生まれ月はオッズにほとんど反映されない」を確かめる
# 使い方: perl 自動実行/検証/birth_month.pl [最初の年 2017] [最後の年 2026] [1 = 出走馬の95%以上が馬DBにいるレースだけ]
#   生年月日は 馬情報/馬DB/競走馬/*年生.tsv と 登録.tsv。馬DBは最近走った馬から入るので、古いレースは「長く走った馬」に偏る(全グループの市場比が1を超える)。
#   月どうしの比較で見るか、3つ目を 1 にして偏りのないレースだけで見る。馬DBの遡り(概要.md)が進んだら、3つ目を 1 にして全期間で確かめ直す
#   見込み: 勝率は単勝オッズの逆数を合計1にしたもの、3着以内は2着0.85乗・3着0.70乗の割引式(star.pl と同じ)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0);
#   4つ目に 馬情報/JRA-VAN/馬DB を渡すと、JRA-VAN で補った全部入り版(1986年からの全馬。PCだけ)の生年月日を使う(2026-10-29〜)
my ($y0, $y1, $clean, $DB) = @ARGV; $y0 ||= 2017; $y1 ||= 2026; $clean //= 0; utf8::decode($DB) if defined $DB; $DB ||= '馬情報/馬DB';
my $J = JSON::PP->new->utf8; my %B;
for my $f (glob "$DB/競走馬/*年生.tsv") { open my $h, '<:utf8', $f or die "$f: $!"; my $hd = <$h>; chomp $hd; my @c = split /\t/, $hd; my %i; @i{@c} = 0 .. $#c;
  while (<$h>) { chomp; my @x = split /\t/; my $d = $x[$i{'生年月日'}] // next; $B{"$x[$i{'馬名'}]|$1"} = $2 + 0 if $d =~ /^(\d{4})-(\d\d)-\d\d$/ } }
if (open my $h, '<:utf8', '馬情報/馬DB/登録.tsv') { <$h>; while (<$h>) { chomp; my @x = split /\t/; $B{"$x[1]|$1"} //= $2 + 0 if ($x[5] // '') =~ /^(\d{4})-(\d\d)-\d\d$/ } }
sub grp { my $m = shift; $m <= 3 ? '1-3月' : $m <= 5 ? '4-5月' : '6月以降' }
my %S;   # "区分|月|期間" => [頭数, 1着, 勝率の見込み, 3着以内, 3着以内の見込み]
for my $y ($y0 .. $y1) { open my $z, '<', "馬情報/過去レースデータ/全期間/$y/レース.jsonl" or next;
  while (my $l = <$z>) { my $r = eval { $J->decode($l) } or next; my $cls = $r->{cls} // '';
    next if ($r->{surface} // '') eq '障' || $cls =~ /障害/;
    my ($mo) = $r->{date} =~ /^\d{4}-(\d\d)/; $mo += 0; my $age;
    if ($cls =~ /^2歳/) { $age = 2 } elsif ($cls =~ /^3歳/ && $cls !~ /以上/ && $mo <= 6) { $age = 3 } else { next }
    my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; my $n = @hs; next if $n < 5;
    my $by = $y - $age; next if $clean && (grep { !defined $B{"$_->{name}|$by"} } @hs) > 0.05 * $n;
    my @q = map { 1 / $_->{odds} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
    my @a = map { $_ ** 0.85 } @q; my $sa = sum0(@a); @a = map { $_ / $sa } @a; my @b = map { $_ ** 0.70 } @q; my $sb = sum0(@b); @b = map { $_ / $sb } @b; my @p3 = (0) x $n;
    for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $a[$j] / (1 - $a[$i]); $p3[$i] += $pij; $p3[$j] += $pij;
      my $d = 1 - $b[$i] - $b[$j]; next if $d <= 0; $p3[$_] += $pij * $b[$_] / $d for grep { $_ != $i && $_ != $j } 0 .. $n - 1 } }
    my $bk = $age == 2 ? '2歳' : '3歳1-6月'; my $per = $y <= 2020 ? '前' : '後'; my $new = $cls =~ /新馬/ ? '新馬' : '新馬以外';
    for my $i (0 .. $n - 1) { my $m = $B{"$hs[$i]{name}|$by"} // next; my $g = grp($m);
      for my $k ("$bk|$g|$per", "$bk|$g|計", "$bk $new|$g|計") { my $c = $S{$k} ||= [0, 0, 0, 0, 0];
        $c->[0]++; $c->[1]++ if $hs[$i]{rank} == 1; $c->[2] += $q[$i]; $c->[3]++ if $hs[$i]{rank} <= 3; $c->[4] += $p3[$i] } } } }
printf "%d〜%d年%s(市場比 = 実際 ÷ オッズの見込み)\n", $y0, $y1, $clean ? '、出走馬の95%以上が馬DBにいるレースだけ' : '';
my %done; for my $k (sort keys %S) { my ($bk, undef, $p) = split /\|/, $k; next if $done{"$bk|$p"}++;
  printf "\n== %s(%s)\n", $bk, $p eq '計' ? '全期間' : $p eq '前' ? '2020年まで' : '2021年から';
  for my $g ('1-3月', '4-5月', '6月以降') { my $c = $S{"$bk|$g|$p"} or next;
    printf "  %-6s %6d頭 勝率%5.1f%% 市場比%5.2f (z%+.1f) | 3着内%5.1f%% 市場比%5.2f (z%+.1f)\n", $g, $c->[0], 100 * $c->[1] / $c->[0], $c->[1] / $c->[2], ($c->[1] - $c->[2]) / sqrt($c->[2]),
      100 * $c->[3] / $c->[0], $c->[3] / $c->[4], ($c->[3] - $c->[4]) / sqrt($c->[4] * (1 - $c->[4] / $c->[0])) } }
