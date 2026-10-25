# JRA公式の調教動画から読んだ調教タイムが、単勝オッズより当たりに効くかを確かめる(2026-10-26〜)
# 使い方: perl chokyo_eval.pl <調教タイム.tsv(カンマ区切りで複数可。後のファイルの行で前を上書き)> <全期間のフォルダー> [分ける日]
#   動画 → レース: 追い切り日の1〜10日後の重賞(grade あり)のうち、文字認識の馬名と出走馬の名前が一番多く合うもの(3頭以上)
#   馬名 → 出走馬: 似ている度合い(共通部分の文字数)が0.5以上で一番近い馬
#   各馬の「市場の見方」= 単勝オッズを合計1にした勝率・そこからのHarville式の3着以内率。それに対して調教の条件ごとに
#   3着以内 実際÷市場、勝ち 実際÷市場、単勝・複勝の回収率を出す。前半・後半(分ける日)とも同じ向きのものだけが本物の候補
#   さらに「市場の3着以内率のロジット + b × 条件」の b を当てはめ、b と標準誤差(z = b / SE)を出す(|z| が2未満なら偶然と区別できない)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0 max min); use Encode qw(encode);
my ($RF, $PF) = map { encode("UTF-8", $_) } ("レース.jsonl", "払戻.jsonl");   # ファイル名はバイトで組み立てる(引数・glob はバイトのため)
my ($tg, $dir, $split) = @ARGV; $split ||= '2026-04-01';
my $J = JSON::PP->new->utf8;
sub lcs { my ($a, $b) = @_; my @a = split //, $a; my @b = split //, $b; my @p = (0) x (@b + 1);
  for my $x (@a) { my @c = (0); for my $j (1 .. @b) { push @c, $x eq $b[$j - 1] ? $p[$j - 1] + 1 : ($p[$j] > $c[-1] ? $p[$j] : $c[-1]) } @p = @c } $p[-1] }
sub sim { my ($a, $b) = @_; return 0 unless length $a && length $b; 2 * lcs($a, $b) / (length($a) + length($b)) }
# 調教タイム
my (%V, %seenrow);
for my $f (split /,/, $tg) { open my $h, '<:encoding(UTF-8)', $f or die $f; <$h>;
  while (<$h>) { chomp; s/\r//; my @c = split /\t/, $_, -1; next unless @c >= 14 && $c[3] ne '';
    my $k = "$c[0]\t$c[3]"; my %r = (vid => $c[0], year => $c[1], race => $c[2], name => $c[3], date => $c[4], course => $c[5], pos => $c[7], map { ('6F', '5F', '4F', '3F', '2F', '1F')[$_ - 8] => $c[$_] } 8 .. 13);
    # 手で読んだ行(後のファイル)は、似た名前の自動の行を置き換える
    my ($old) = grep { sim($_->{name}, $c[3]) >= 0.5 } @{$V{$c[0]} || []}; if ($old) { %$old = %r } else { push @{$V{$c[0]}}, \%r } } }
# 重賞の結果と払戻
my (@G, %PAY);
for my $y (glob "$dir/*/") { for my $f ("$y$RF") { next unless -s $f; open my $h, '<:raw', $f; while (<$h>) { my $r = eval { $J->decode($_) } or next; push @G, $r if $r->{grade} } }
  if (-s "$y$PF") { open my $h, "<:raw", "$y$PF"; while (<$h>) { my $p = eval { $J->decode($_) } or next; $PAY{$p->{id}} = $p->{pay} } } }
my (@rows, %used, $nv, $nm);
print STDERR "重賞 ", scalar(@G), " レース、払戻 ", scalar(keys %PAY), "\n" if $ENV{DEBUG};
for my $vid (sort keys %V) { my @hs = @{$V{$vid}}; my $year = $hs[0]{year} or next; $nv++;
  my ($last) = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } map { [split m{/}] } grep { m{^\d+/\d+$} } map { $_->{date} } @hs;
  next unless $last; my ($wm, $wd) = @$last;
  my $wdate = sprintf '%04d-%02d-%02d', $year, $wm, $wd;
  my ($best, $bn) = (undef, 0);
  for my $r (@G) { next unless $r->{date} gt $wdate && $r->{date} le do { my @t = split /-/, $wdate; require Time::Local; my $e = Time::Local::timegm(0, 0, 0, $t[2], $t[1] - 1, $t[0]) + 10 * 86400; my @g = gmtime $e; sprintf '%04d-%02d-%02d', $g[5] + 1900, $g[4] + 1, $g[3] };
    my $n = grep { my $x = $_; grep { sim($x->{name}, $_->{name} // '') >= 0.6 } @{$r->{horses}} } @hs; ($best, $bn) = ($r, $n) if $n > $bn }
  print STDERR "$vid $wdate ", ($best ? "$best->{date} $best->{name}" : "-"), " $bn
" if $ENV{DEBUG};
  next unless $best && $bn >= 3; $nm++;
  my @run = grep { ($_->{rank} // '') =~ /^\d+$/ && ($_->{odds} // '') =~ /^[\d.]+$/ && $_->{odds} >= 1 } @{$best->{horses}}; my $n = @run; next if $n < 5;
  my @q = map { 1 / $_->{odds} } @run; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = (0) x $n;
  for my $i (0 .. $n - 1) { $p3[$i] += $q[$i];
    for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  my %fk = map { $_->{k} => $_->{yen} } @{($PAY{$best->{id}} || {})->{'複勝'} || []};
  my @mine;
  for my $x (@hs) { my ($bi, $bs) = (-1, 0.5); for my $i (0 .. $n - 1) { my $v = sim($x->{name}, $run[$i]{name}); ($bi, $bs) = ($i, $v) if $v > $bs } next if $bi < 0 || $used{"$best->{id}:$bi"}++;
    my $h = $run[$bi]; print STDERR "照合 $x->{name} → $h->{name} (", sprintf('%.2f', $bs), ")\n" if $ENV{DEBUG} && $bs < 0.8; my $sak = $x->{course} =~ /坂路/ ? 1 : 0;
    push @mine, { %$x, race_id => $best->{id}, rdate => $best->{date}, grade => $best->{grade}, rname => $best->{name}, horse => $h->{name}, rank => $h->{rank}, odds => $h->{odds}, pop => $h->{pop},
      q => $q[$bi], p3 => $p3[$bi], sak => $sak, fuku => ($h->{rank} <= 3 ? ($fk{$h->{umaban}} // 0) : 0) } }
  # 同じレースの中で比べる: 1F(坂路とそれ以外で分けて)の速さの順位、全体時計の順位
  for my $grp ([grep { $_->{sak} } @mine], [grep { !$_->{sak} } @mine]) { my @g = grep { ($_->{'1F'} // '') ne '' } @$grp; next unless @g >= 2;
    my @o = sort { $a->{'1F'} <=> $b->{'1F'} } @g; $o[$_]{r1F} = $_ / $#o for 0 .. $#o }
  for my $grp ([grep { $_->{sak} } @mine], [grep { !$_->{sak} } @mine]) { my @g = grep { ($_->{'4F'} // '') ne '' } @$grp; next unless @g >= 2;
    my @o = sort { $a->{'4F'} <=> $b->{'4F'} } @g; $o[$_]{r4F} = $_ / $#o for 0 .. $#o }
  push @rows, @mine }
printf "調教動画 %d 本のうち重賞に結び付いたもの %d 本、馬 %d 頭(前半 < %s <= 後半)\n", $nv, $nm // 0, scalar @rows, $split;
my %B;
for my $x (@rows) { my $h = $x->{rdate} lt $split ? '前半' : '後半';
  my @k = ('全部');
  push @k, $x->{sak} ? 'コース:坂路' : 'コース:ウッドなど';
  push @k, '併せ:' . ($x->{pos} && $x->{pos} ne '単走' ? '併せ' : '単走');
  if (($x->{'1F'} // '') ne '') { my $t = $x->{'1F'}; push @k, '1F:' . ($x->{sak} ? ($t < 12.0 ? '坂路12.0未満' : $t < 12.5 ? '坂路12.0-12.4' : '坂路12.5以上') : ($t < 11.3 ? 'W11.3未満' : $t < 11.7 ? 'W11.3-11.6' : 'W11.7以上')) }
  push @k, '1Fの速さ(同じレース):' . ($x->{r1F} <= 0.34 ? '速い方' : $x->{r1F} >= 0.66 ? '遅い方' : '中くらい') if defined $x->{r1F};
  push @k, '4F(全体)の速さ(同じレース):' . ($x->{r4F} <= 0.34 ? '速い方' : $x->{r4F} >= 0.66 ? '遅い方' : '中くらい') if defined $x->{r4F};
  push @k, '人気:' . ($x->{pop} <= 3 ? '1-3番人気' : $x->{pop} <= 7 ? '4-7番人気' : '8番人気以下');
  for my $k (@k) { for my $g ($h, '全体') { my $a = $B{$k}{$g} //= [0, 0, 0, 0, 0, 0, 0]; $a->[0]++; $a->[1] += $x->{rank} <= 3; $a->[2] += $x->{p3}; $a->[3] += $x->{rank} == 1; $a->[4] += $x->{q}; $a->[5] += $x->{rank} == 1 ? $x->{odds} : 0; $a->[6] += $x->{fuku} / 100 } } }
print "条件: 頭数 / 3着内 実際÷市場 / 勝ち 実際÷市場 / 単勝回収率 / 複勝回収率\n";
for my $k (sort { ($a eq '全部' ? 0 : 1) <=> ($b eq '全部' ? 0 : 1) || $a cmp $b } keys %B) { my $x = $B{$k};
  printf "  %-34s %s\n", $k, join('  ', map { my $a = $x->{$_}; $a ? sprintf("%s %4d頭 3着内%.2f 勝ち%.2f 単%4.0f%% 複%4.0f%%", $_, $a->[0], $a->[2] ? $a->[1] / $a->[2] : 0, $a->[4] ? $a->[3] / $a->[4] : 0, 100 * $a->[5] / $a->[0], 100 * $a->[6] / $a->[0]) : () } qw(全体 前半 後半)) }
# 市場の3着以内率に上乗せする効果 b(ロジスティック回帰、1変数ずつ)
sub fitb { my ($xs) = @_; my $b = 0; my $info = 1;
  for (1 .. 25) { my ($g, $hh) = (0, 0); for my $p (@$xs) { my ($y, $p0, $x) = @$p; my $l = log($p0 / (1 - $p0)) + $b * $x; my $pp = 1 / (1 + exp(-$l)); $g += ($y - $pp) * $x; $hh += $pp * (1 - $pp) * $x * $x } last unless $hh; $b += $g / $hh; $info = $hh }
  ($b, 1 / sqrt($info || 1)) }
print "== 市場の3着以内率に上乗せする効果(b > 0 = 条件に当てはまる馬が市場より来る。z = b / 標準誤差)\n";
for my $def (['1Fが同じレースで速い方(0〜1、0が一番速い→ 1-順位)', sub { defined $_[0]{r1F} ? 1 - $_[0]{r1F} : undef }],
             ['4F(全体)が同じレースで速い方', sub { defined $_[0]{r4F} ? 1 - $_[0]{r4F} : undef }],
             ['併せ馬(1)/単走(0)', sub { $_[0]{pos} ? ($_[0]{pos} ne '単走' ? 1 : 0) : undef }],
             ['坂路(1)/それ以外(0)', sub { $_[0]{sak} }],
             ['加速ラップ(終い1Fがその前の2Fの平均より速い=1)', sub { ($_[0]{'3F'} // '') ne '' && ($_[0]{'1F'} // '') ne '' ? ($_[0]{'1F'} < ($_[0]{'3F'} - $_[0]{'1F'}) / 2 ? 1 : 0) : undef }],
             ['ウッドで1Fが11.7以上(1)/ウッドでそれより速い(0)', sub { !$_[0]{sak} && ($_[0]{'1F'} // '') ne '' ? ($_[0]{'1F'} >= 11.7 ? 1 : 0) : undef }],
             ['坂路で1Fが12.0〜12.4(1)/坂路でそれ以外(0)', sub { $_[0]{sak} && ($_[0]{'1F'} // '') ne '' ? ($_[0]{'1F'} >= 12.0 && $_[0]{'1F'} < 12.5 ? 1 : 0) : undef }]) {
  my ($name, $fx) = @$def;
  printf "  %-40s %s\n", $name, join('  ', map { my $g = $_; my @xs = map { my $v = $fx->($_); defined $v ? [($_->{rank} <= 3 ? 1 : 0), min(0.97, max(0.01, $_->{p3})), $v] : () } grep { $g eq '全体' || ($g eq '前半') == ($_->{rdate} lt $split) } @rows;
    @xs >= 30 ? do { my ($b, $se) = fitb(\@xs); sprintf "%s %4d頭 b=%+.2f z=%+.1f", $g, scalar @xs, $b, $b / $se } : () } qw(全体 前半 後半)) }
