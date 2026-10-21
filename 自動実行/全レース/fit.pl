# 集めた過去のレース(backfill.sh の出力)から、どの情報が当たりに効くかを調べる
# 使い方: perl fit.pl <テスト開始日 YYYY-MM-DD> <フォルダー>... > 結果.json
#   テスト開始日より前のレースで当てはめ、以後のレースで確かめる(未来のデータで当てはめない)
# モデル: 1〜3着の順番の確率(Plackett-Luce = 1着を全馬から、2着を残りから、3着を残りから選ぶ条件付きロジット)。ニュートン法、L2正則化
# 出力: 各モデルのテストでの成績(対数尤度・◎の勝率・◎の3着以内率・上位3頭のうち実際の3着以内の頭数)と係数
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use JSON::PP;
my ($split, @dirs) = @ARGV;
my $J = JSON::PP->new->utf8;
my @races;
# 引数はフォルダー(1レース1ファイル)か、まとめた .jsonl.gz(馬情報/過去レースデータ/)
use IO::Uncompress::Gunzip qw($GunzipError);
my @texts; for my $d (@dirs) { if (-d $d) { for my $f (glob("$d/*.json")) { open my $h, '<:raw', $f or next; local $/; push @texts, scalar <$h> } }
  elsif ($d =~ /.gz$/) { my $z = IO::Uncompress::Gunzip->new($d) or die "$GunzipError"; while (my $l = $z->getline) { push @texts, $l } } }
for my $t (@texts) { { my $r = eval { $J->decode($t) } or next;
  my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{odds} && $_->{odds} >= 1 } @{$r->{horses}}; next if @hs < 5; $r->{horses} = \@hs; push @races, $r } }
@races = sort { $a->{date} cmp $b->{date} || $a->{id} cmp $b->{id} } @races;
my %seenid; @races = grep { !$seenid{$_->{id}}++ } @races;
print STDERR scalar(@races), " races\n";

sub cap { my ($v, $lo, $hi) = @_; $v < $lo ? $lo : $v > $hi ? $hi : $v }
# ---- 特徴量 ----
my @F = qw(lmk ab jisseki kyori course choshi kishu omega r1 m1 a1 p1 pr1 bestA3 avgR3 debut lintv layoff weight wdiff10 jc sc tj
  drawT drawD nige senko oikomi kin surfChg dchg age axis);
sub feats {
  my ($r) = @_; my @hs = @{$r->{horses}};
  my $t = 0; $t += 1 / $_->{odds} for @hs;
  my @om = sort { $a <=> $b } grep { defined } map { $_->{omega} } @hs; my $omed = @om ? $om[int(@om / 2)] : 80;
  my @kk = map { $_->{kin} // 55 } @hs; my $km = 0; $km += $_ for @kk; $km /= @kk;
  my @X;
  for my $h (@hs) {
    my %x; my @rs = @{$h->{runs} // []}; my $p = $rs[0];
    $x{lmk} = log((1 / $h->{odds}) / $t);
    $x{ab} = (.35 * ($h->{jisseki} // 60) + .15 * ($h->{kyori} // 60) + .15 * ($h->{course} // 60) + .2 * ($h->{choshi} // 60) + .15 * ($h->{kishu} // 60)) / 10;
    $x{$_} = ($h->{$_} // 60) / 10 for qw(jisseki kyori course choshi kishu);
    $x{omega} = (($h->{omega} // ($omed - 5)) - $omed) / 10;
    $x{debut} = $p ? 0 : 1;
    $x{r1} = $p && $p->{rank} ? cap($p->{rank}, 1, 12) : 6;
    my $mg = $p && defined $p->{margin} ? $p->{margin} : 1; $mg = -$mg if $p && ($p->{rank} // 0) == 1; $x{m1} = cap($mg, -1, 3);
    $x{a1} = $p && $p->{agariRank} ? cap($p->{agariRank}, 1, 12) : 6;
    $x{p1} = $p && $p->{pop} ? cap($p->{pop}, 1, 14) : 7;
    $x{pr1} = $p && $p->{pop} && $p->{rank} ? cap($p->{pop} - $p->{rank}, -10, 10) : 0;   # 人気より上の着順なら+
    my @a3 = grep { $_ } map { $_->{agariRank} } @rs[0 .. ($#rs < 2 ? $#rs : 2)]; $x{bestA3} = @a3 ? cap((sort { $a <=> $b } @a3)[0], 1, 12) : 6;
    my @r3 = grep { $_ } map { $_->{rank} } @rs[0 .. ($#rs < 2 ? $#rs : 2)]; my $s = 0; $s += cap($_, 1, 14) for @r3; $x{avgR3} = @r3 ? $s / @r3 : 7;
    my $iw = $h->{intvWeeks} // 8; $x{lintv} = log(cap($iw, 1, 60)); $x{layoff} = $iw >= 20 ? 1 : 0;
    $x{weight} = (($h->{weight} // 470) - 470) / 40; $x{wdiff10} = defined $h->{weightDiff} && abs($h->{weightDiff}) >= 10 ? 1 : 0;
    $x{jc} = ($h->{jcRuns} // 0) >= 10 ? $h->{jcRate} / 10 : 1.5;
    $x{sc} = ($h->{scRuns} // 0) >= 10 ? $h->{scRate} / 10 : 1.5;
    $x{tj} = ($h->{tjRuns} // 0) >= 5 ? $h->{tjRate} / 10 : 1.5;
    my $pos = $h->{umaban} && @hs > 1 ? ($h->{umaban} - 1) / ($r->{heads} > 1 ? $r->{heads} - 1 : 1) : 0.5;   # 0=最内 1=大外
    $x{drawT} = $r->{surface} eq '芝' ? $pos : 0; $x{drawD} = $r->{surface} eq 'ダ' ? $pos : 0;
    my $st = $h->{style} // '差し'; $x{nige} = $st eq '逃げ' ? 1 : 0; $x{senko} = $st eq '先行' ? 1 : 0; $x{oikomi} = $st eq '追込' ? 1 : 0;
    $x{kin} = ($h->{kin} // $km) - $km;
    $x{surfChg} = $p && $p->{surf} && $p->{surf} ne $r->{surface} ? 1 : 0;
    $x{dchg} = $p && $p->{dist} ? cap(($r->{dist} - $p->{dist}) / 400, -2, 2) : 0;
    $x{age} = cap($h->{age} // 3, 2, 8);
    $x{axis} = ($h->{axisPt} // 0) / 5;
    push @X, [map { $x{$_} } @F];
  }
  return \@X;
}
my (@train, @test);
for my $r (@races) { my $X = feats($r); my @rk = map { $_->{rank} } @{$r->{horses}}; my $item = { X => $X, rank => \@rk, r => $r }; if ($r->{date} lt $split) { push @train, $item } else { push @test, $item } }
print STDERR scalar(@train), " train / ", scalar(@test), " test\n";
my %FI; @FI{@F} = 0 .. $#F;
# 標準化(学習データで)
my (@mu, @sd);
{ my @s = (0) x @F; my @q = (0) x @F; my $c = 0; for my $it (@train) { for my $x (@{$it->{X}}) { $s[$_] += $x->[$_], $q[$_] += $x->[$_] ** 2 for 0 .. $#F; $c++ } }
  for (0 .. $#F) { $mu[$_] = $s[$_] / $c; my $v = $q[$_] / $c - $mu[$_] ** 2; $sd[$_] = $v > 1e-9 ? sqrt($v) : 1 } }

# Plackett-Luce(上位 $K 着まで)の対数尤度・勾配・ヘッセ行列
sub pl {
  my ($items, $cols, $beta, $K, $want) = @_; my $d = @$cols; my $ll = 0; my @g = (0) x $d; my @H = map { [(0) x $d] } 1 .. $d;
  for my $it (@$items) {
    my @Z = map { my $x = $_; [map { ($x->[$_] - $mu[$_]) / $sd[$_] } @$cols] } @{$it->{X}};
    my @u = map { my $z = $_; my $s = 0; $s += $beta->[$_] * $z->[$_] for 0 .. $d - 1; $s } @Z;
    my @ord = sort { $it->{rank}[$a] <=> $it->{rank}[$b] } 0 .. $#Z; my %out;
    for my $k (0 .. $K - 1) {
      last if $k > $#ord; my $w = $ord[$k]; my @live = grep { !$out{$_} } 0 .. $#Z; last if @live < 2;
      my $mx = -1e9; $mx = $u[$_] > $mx ? $u[$_] : $mx for @live; my @e = map { exp($u[$_] - $mx) } @live; my $S = 0; $S += $_ for @e;
      $ll += $u[$w] - $mx - log($S);
      if ($want) {
        my @m = (0) x $d; for my $j (0 .. $#live) { my $p = $e[$j] / $S; $m[$_] += $p * $Z[$live[$j]][$_] for 0 .. $d - 1 }
        $g[$_] += $Z[$w][$_] - $m[$_] for 0 .. $d - 1;
        for my $j (0 .. $#live) { my $p = $e[$j] / $S; my $z = $Z[$live[$j]]; for my $a (0 .. $d - 1) { my $za = $z->[$a] - $m[$a]; next unless $za; for my $b (0 .. $a) { $H[$a][$b] += $p * $za * ($z->[$b] - $m[$b]) } } }
      }
      $out{$w} = 1;
    }
  }
  if ($want) { for my $a (0 .. $d - 1) { for my $b (0 .. $a) { $H[$b][$a] = $H[$a][$b] } } }
  return ($ll, \@g, \@H);
}
sub solve { my ($A, $b) = @_; my $n = @$b; my @M = map { [@{$A->[$_]}, $b->[$_]] } 0 .. $n - 1;
  for my $c (0 .. $n - 1) { my $p = $c; for my $r ($c + 1 .. $n - 1) { $p = $r if abs($M[$r][$c]) > abs($M[$p][$c]) } @M[$c, $p] = @M[$p, $c];
    my $v = $M[$c][$c] || 1e-12; for my $r (0 .. $n - 1) { next if $r == $c; my $f = $M[$r][$c] / $v; next unless $f; $M[$r][$_] -= $f * $M[$c][$_] for $c .. $n } }
  return [map { $M[$_][$n] / ($M[$_][$_] || 1e-12) } 0 .. $n - 1] }
sub fit {
  my ($names, $K, $lam) = @_; my @cols = map { $FI{$_} } @$names; my $d = @cols; my @beta = (0) x $d;
  for my $iter (1 .. 12) {
    my ($ll, $g, $H) = pl(\@train, \@cols, \@beta, $K, 1);
    $g->[$_] -= $lam * $beta[$_] for 0 .. $d - 1; $H->[$_][$_] += $lam for 0 .. $d - 1;
    my $step = solve($H, $g); my $mx = 0; for (0 .. $d - 1) { $beta[$_] += $step->[$_]; $mx = abs($step->[$_]) if abs($step->[$_]) > $mx }
    last if $mx < 1e-4;
  }
  my (undef, undef, $H) = pl(\@train, \@cols, \@beta, $K, 1); $H->[$_][$_] += $lam for 0 .. $d - 1;
  my @se = map { my @e = (0) x $d; $e[$_] = 1; my $c = solve($H, \@e); sqrt(abs($c->[$_])) } 0 .. $d - 1;
  return (\@cols, \@beta, \@se);
}
# テストでの成績
sub evaluate {
  my ($cols, $beta, $set) = @_; my ($ll) = pl($set, $cols, $beta, 3, 0); my ($w, $t3, $cov, $n) = (0, 0, 0, 0);
  for my $it (@$set) {
    my @u = map { my $x = $_; my $s = 0; $s += $beta->[$_] * (($x->[$cols->[$_]] - $mu[$cols->[$_]]) / $sd[$cols->[$_]]) for 0 .. $#$cols; $s } @{$it->{X}};
    my @o = sort { $u[$b] <=> $u[$a] } 0 .. $#u; $n++;
    $w++ if $it->{rank}[$o[0]] == 1; $t3++ if $it->{rank}[$o[0]] <= 3; $cov += grep { $it->{rank}[$_] <= 3 } @o[0 .. 2];
  }
  return { ll => sprintf('%.1f', $ll), llPerRace => sprintf('%.4f', $ll / ($n || 1)), honmeiWin => sprintf('%.1f', 100 * $w / $n), honmeiTop3 => sprintf('%.1f', 100 * $t3 / $n), top3in3 => sprintf('%.3f', $cov / $n), races => $n };
}
my @ABIL = qw(jisseki kyori course choshi kishu);
my @EXTRA = grep { !/^(lmk|ab|jisseki|kyori|course|choshi|kishu)$/ } @F;
my %models = (
  '1_オッズだけ' => ['lmk'],
  '2_能力値の合計だけ(今の重み)' => ['ab'],
  '3_能力値5項目' => [@ABIL],
  '4_オッズ+能力値の合計' => ['lmk', 'ab'],
  '5_オッズ+能力値5項目' => ['lmk', @ABIL],
  '6_オッズ+能力値+追加の情報' => ['lmk', @ABIL, @EXTRA],
  '7_オッズ+追加の情報' => ['lmk', @EXTRA],
  '8_オッズ+効いた4つ(軸の減点・休み明け・芝ダ替わり・追込)' => [qw(lmk axis layoff surfChg oikomi)],
  '9_オッズ+効いた4つ+前走の人気と着順' => [qw(lmk axis layoff surfChg oikomi pr1 r1 p1)],
);
my %out;
for my $m (sort keys %models) {
  my ($cols, $beta, $se) = fit($models{$m}, 3, 1.0);
  $out{$m} = { test => evaluate($cols, $beta, \@test), train => evaluate($cols, $beta, \@train),
    coef => { map { $F[$cols->[$_]] => { b => sprintf('%.3f', $beta->[$_]), z => sprintf('%.1f', $beta->[$_] / ($se->[$_] || 1)), raw => sprintf('%.4f', $beta->[$_] / $sd[$cols->[$_]]) } } 0 .. $#$cols } };
  print STDERR "$m: ", $J->canonical->encode($out{$m}{test}), "\n";
}
print JSON::PP->new->canonical->pretty->encode({ races => scalar @races, train => scalar @train, test => scalar @test, split => $split, models => \%out,
  featureMean => { map { $F[$_] => sprintf('%.3f', $mu[$_]) } 0 .. $#F }, featureSd => { map { $F[$_] => sprintf('%.3f', $sd[$_]) } 0 .. $#F } });
