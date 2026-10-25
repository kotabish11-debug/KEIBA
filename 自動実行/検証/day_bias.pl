# 当日の馬場の偏り(同じ日・同じ場・同じ馬場の、前のレースで前に行った馬が残ったか)が、後のレースでオッズ以上に効くかを確かめる(2026-10-26〜)
# 使い方: perl day_bias.pl <レースのファイル(カンマ区切りで複数可。全期間/<年>/レース.jsonl など。古い順でなくてよい)> [分ける日 2016-01-01] [払戻.jsonl(省略可)]
#   各馬の脚質 = その馬の前走まで(最大5走)の 4角の位置 ÷ 頭数 の平均(0 = 先頭、1 = 最後方)。2走以上あるときだけ使う
#   当日の偏り = その日の同じ場・同じ馬場の、前のレース(2レース以上)の3着以内の馬の 4角の位置÷頭数 の平均 − 全体の平均。マイナス = 前が残っている
#   偏り(前有利 / 普通 / 後有利)× 脚質(先行 / 中団 / 後方)ごとに、3着以内の実際 ÷ 単勝オッズのHarville式、勝率の実際 ÷ 市場、単勝・複勝の回収率を出す
#   1より大きく、前半・後半とも同じ向きなら、その組み合わせは市場が当日の偏りを織り込み切れていない
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use IO::Uncompress::Gunzip; use List::Util qw(sum0);
my ($rg, $split, $pg) = @ARGV; $split ||= '2016-01-01';
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; my $z = IO::Uncompress::Gunzip->new($f) or die "$f"; while (my $l = $z->getline) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
my (%seen, @R, %FUKU);
rd($pg, sub { my %h = map { $_->{k} => $_->{yen} } @{$_[0]{pay}{'複勝'} || []}; $FUKU{$_[0]{id}} = \%h }) if $pg;
for my $f (split /,/, $rg) { rd($f, sub {
  my $r = shift; return if $seen{$r->{id}}++;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && ($_->{odds} // '') =~ /^[\d.]+$/ && $_->{odds} >= 1 } @{$r->{horses} || []}; return if @hs < 5;
  my $surf = $r->{surface} // ''; return if $surf eq '障' || $surf eq '';
  push @R, { id => $r->{id}, date => $r->{date}, place => $r->{place} // substr($r->{id}, 8, 2), surf => $surf, no => $r->{no} // substr($r->{id}, 10, 2) + 0, hs => \@hs };
}) }
@R = sort { $a->{date} cmp $b->{date} || $a->{place} cmp $b->{place} || $a->{no} <=> $b->{no} } @R;
# 全体の平均(3着以内の馬の 4角の位置÷頭数)
my @all = map { my $r = $_; my $n = @{$r->{hs}}; map { ($_->{last4} // 0) > 0 ? $_->{last4} / $n : () } grep { $_->{rank} <= 3 } @{$r->{hs}} } @R;
my $base = sum0(@all) / (@all || 1);
my (%hist, %day, %acc);
for my $r (@R) {
  my $n = @{$r->{hs}}; my $dk = "$r->{date} $r->{place} $r->{surf}";
  my $prev = $day{$dk} //= [];
  my $bias; if (@$prev >= 2) { $bias = sum0(@$prev) / @$prev - $base }
  my $bb = !defined $bias ? undef : $bias < -0.05 ? '前有利' : $bias > 0.05 ? '後有利' : '普通';
  if ($bb) {
    my @q = map { 1 / $_->{odds} } @{$r->{hs}}; my $s = sum0(@q); @q = map { $_ / $s } @q;
    my @p3 = (0) x $n;
    for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
      for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
        for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
    my $half = $r->{date} lt $split ? '前半' : '後半';
    for my $i (0 .. $n - 1) { my $h = $r->{hs}[$i]; my $hh = $hist{$h->{name} // ''} or next; next if @$hh < 2;
      my $st = sum0(@$hh) / @$hh; my $sb = $st < 0.3 ? '先行' : $st > 0.6 ? '後方' : '中団';
      my $fk = $FUKU{$r->{id}}; my $fret = $fk && $h->{rank} <= 3 ? ($fk->{$h->{umaban} // ''} // 0) / 100 : 0;
      for my $g ($half, '全体') { my $a = $acc{"$bb×$sb"}{$g} //= [0, 0, 0, 0, 0, 0, 0];
        $a->[0]++; $a->[1] += $h->{rank} <= 3; $a->[2] += $p3[$i]; $a->[3] += $h->{rank} == 1; $a->[4] += $q[$i]; $a->[5] += $h->{rank} == 1 ? $h->{odds} : 0; $a->[6] += $fret } }
  }
  # このレースの結果を、当日の偏りと各馬の脚質に足す(次のレースから使う)
  push @$prev, map { $_->{last4} / $n } grep { $_->{rank} <= 3 && ($_->{last4} // 0) > 0 } @{$r->{hs}};
  for my $h (@{$r->{hs}}) { next unless ($h->{last4} // 0) > 0 && $h->{name}; my $x = $hist{$h->{name}} //= []; push @$x, $h->{last4} / $n; shift @$x if @$x > 5 }
}
printf "レース %d  3着以内の馬の4角の位置÷頭数の平均 %.3f(前半 < %s <= 後半)\n", scalar @R, $base, $split;
print "当日の偏り×脚質: 頭数 / 3着内 実際÷Harville / 勝率 実際÷市場 / 単勝回収率", ($pg ? " / 複勝回収率" : ""), "\n";
for my $k (map { my $b = $_; map { "$b×$_" } qw(先行 中団 後方) } qw(前有利 普通 後有利)) { my $x = $acc{$k} or next;
  printf "  %-10s %s\n", $k, join("  ", map { my $a = $x->{$_}; sprintf "%s %6d頭 3着内%.3f 勝率%.3f 単%5.1f%%%s", $_, $a->[0], $a->[2] ? $a->[1] / $a->[2] : 0, $a->[4] ? $a->[3] / $a->[4] : 0, 100 * $a->[5] / $a->[0], $pg ? sprintf(" 複%5.1f%%", 100 * $a->[6] / $a->[0]) : '' } grep { $x->{$_} } qw(全体 前半 後半)) }
