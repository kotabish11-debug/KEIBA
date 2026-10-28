# JRA-VAN の全調教(坂路 HC 2005〜・ウッド WC 2021/7〜)が、確定オッズ以上に当たりに効くかを確かめる(2026-10-27)
# 使い方: perl jv_chokyo_eval.pl [馬情報/JRA-VAN] [分ける日 2016-01-01]
#   結果 = 馬情報/JRA-VAN/結果_馬ごと.csv(results_csv.pl。新馬・障害を除く平場と重賞)
#   市場の見方 = 単勝オッズの Harville 式を p3_fit.pl の式で直した3着以内率(logit p = -0.133 + 0.752·logit H - 0.036·(logit H)²)
#   条件の帯ごとに 3着以内の実際÷市場・z(偶然なら ±2 の中)・単勝回収率 を、全体 / 前半 / 後半 で出す
#   自己比較(本数・時計)は、その馬の2年以内の前走たち(2走以上)の平均と比べる。美浦の坂路は2023-10の改修前後で比べない
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use Time::Local qw(timegm);
use List::Util qw(sum0 min max);
use Encode qw(decode_utf8);
my ($D, $split) = map { decode_utf8($_) } @ARGV; $D ||= '馬情報/JRA-VAN'; $split ||= '2016-01-01';
my $D0 = timegm(0, 0, 0, 1, 0, 2000);
sub dn { my ($y, $m, $d) = $_[0] =~ /^(\d{4})-?(\d\d)-?(\d\d)/ or return 0; int((timegm(0, 0, 0, $d, $m - 1, $y) - $D0) / 86400) }
my $splitN = dn($split);
my $MIHO_NEW = dn('2023-10-01');

# 1. 結果と市場の3着以内率
my (%race, %runs);
open my $c, '<', "$D/結果_馬ごと.csv" or die "$D/結果_馬ごと.csv: $!"; <$c>;
while (<$c>) { chomp; my ($id, $date, $u, $rk, $o, $hid) = split /,/; next unless $hid;
  push @{$race{$id}}, { d => dn($date), u => $u, rk => $rk, o => $o, hid => $hid } }
close $c;
# 複勝の払戻(100円あたり)
my %fuku; { use JSON::PP; my $J = JSON::PP->new->utf8;
  for my $pf (map { decode_utf8($_) } glob "馬情報/過去レースデータ/全期間/*/払戻.jsonl") { open my $h, '<', $pf or next;
    while (my $l = <$h>) { my $x = eval { $J->decode($l) } or next; next unless $race{$x->{id}};
      $fuku{$x->{id}}{$_->{k}} = $_->{yen} / 100 for @{$x->{pay}{'複勝'} || []} } } }
my $nrun = 0;
for my $id (keys %race) { my $R = $race{$id}; my $n = @$R; next if $n < 5;
  my @q = map { 1 / $_->{o} } @$R; my $s = sum0(@q); @q = map { $_ / $s } @q;
  my @p3 = @q;
  for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $q[$i] * $q[$j] / (1 - $q[$i]); $p3[$j] += $pij;
      for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $q[$k] / (1 - $q[$i] - $q[$j]) } } }
  for my $i (0 .. $n - 1) { my $h = min(max($p3[$i], 1e-4), 0.999); my $L = log($h / (1 - $h));
    my $z = -0.133 + 0.752 * $L - 0.036 * $L * $L; $R->[$i]{p3} = 1 / (1 + exp(-$z)); $R->[$i]{race} = $id;
    push @{$runs{$R->[$i]{hid}}}, $R->[$i]; $nrun++ } }
print STDERR "出走 $nrun\n";

# 2. 調教(出走した馬だけ)。1本 = pack(日, 種類(0坂路/1ウッド)*2+美浦0/栗東1, 4F×10, 1F×10, その前の1F×10)
my %w;
sub rd { my ($f, $wood) = @_; open my $h, '<', $f or die "$f: $!"; my $n = 0;
  while (my $l = <$h>) { my $hid = substr($l, 24, 10); next unless $runs{$hid};
    my ($t4, $l2, $l1);
    if ($wood) { ($t4, $l2, $l1) = (substr($l, 79, 4), substr($l, 97, 3), substr($l, 100, 3)) }
    else { ($t4, $l2, $l1) = (substr($l, 34, 4), substr($l, 52, 3), substr($l, 55, 3)) }
    $_ = /^\d+$/ ? $_ + 0 : 0 for $t4, $l2, $l1;
    $w{$hid} .= pack('nCnnn', dn(substr($l, 12, 8)), ($wood ? 2 : 0) + substr($l, 11, 1), $t4, $l1, $l2); $n++ }
  print STDERR "$f $n\n" }
rd("$D/slop.txt", 0); rd("$D/wood.txt", 1);

# 3. 馬ごとに、出走ごとの特徴を作る
my @feat;   # [run, {特徴}]
for my $hid (keys %runs) {
  my @W = sort { $a->[0] <=> $b->[0] } map { [unpack 'nCnnn', substr($w{$hid} // '', 9 * $_, 9)] } 0 .. length($w{$hid} // '') / 9 - 1;
  my @prev;
  for my $r (sort { $a->{d} <=> $b->{d} } @{$runs{$hid}}) {
    my $d = $r->{d}; my %f = (n14 => 0, sl => 0, wd => 0);
    my $best;   # 7日以内の坂路でいちばん速い4F
    for my $x (@W) { next if $x->[0] >= $d || $x->[0] < $d - 14; $f{n14}++; $x->[1] >= 2 ? $f{wd}++ : $f{sl}++;
      next if $x->[1] >= 2 || $x->[0] < $d - 7 || !$x->[2];
      $best = $x if !$best || $x->[2] < $best->[2] }
    if ($best) { $f{fs} = $best->[2] / 10; $f{fs1} = $best->[3] / 10 if $best->[3]; $f{acc} = $best->[3] && $best->[4] ? ($best->[3] < $best->[4] ? 1 : 0) : undef;
      $f{era} = ($best->[1] & 1) . ($best->[1] & 1 ? '' : $best->[0] >= $MIHO_NEW ? 'n' : 'o') }
    my @pp = grep { $_->{d} >= $d - 730 } @prev;
    if (@pp >= 2) { $f{dn} = $f{n14} - sum0(map { $_->{n14} } @pp) / @pp;
      my @ps = grep { defined $_->{fs} && $_->{era} eq ($f{era} // '-') } @pp;
      $f{dfs} = $f{fs} - sum0(map { $_->{fs} } @ps) / @ps if defined $f{fs} && @ps >= 2;
      my @pw = grep { $_->{n14} } @pp;
      if (@pw >= 2 && $f{n14} && $d >= dn('2021-10-01')) { my $pwr = sum0(map { $_->{wd} / $_->{n14} } @pw) / @pw; my $nwr = $f{wd} / $f{n14};
        $f{sw} = $pwr >= 0.6 && $nwr < 0.3 ? 'ウッド中心→坂路中心' : $pwr < 0.3 && $nwr >= 0.6 ? '坂路中心→ウッド中心' : $pwr >= 0.6 && $nwr >= 0.6 ? 'ウッド中心のまま' : $pwr < 0.3 && $nwr < 0.3 ? '坂路中心のまま' : undef } }
    push @prev, { d => $d, n14 => $f{n14}, wd => $f{wd}, fs => $f{fs}, era => $f{era} // '-' };
    push @feat, [$r, \%f] } }
undef %w;

# 同じレースの中での坂路の時計の順位(時計のある馬が4頭以上)
my %byrace; push @{$byrace{$_->[0]{race}}}, $_ for grep { defined $_->[1]{fs} } @feat;
for my $L (values %byrace) { next if @$L < 4; my @s = sort { $a->[1]{fs} <=> $b->[1]{fs} } @$L;
  for my $i (0 .. $#s) { $s[$i][1]{rk} = $i < @s / 3 ? '速い1/3' : $i >= 2 * @s / 3 ? '遅い1/3' : '真ん中' } }

# 4. 帯ごとの集計
my %S;
sub add { my ($k, $b, $r) = @_; for my $g ('全体', $r->{d} < $splitN ? '前半' : '後半') { my $x = $S{$k}{$b}{$g} ||= {};
    $x->{n}++; $x->{y} += $r->{rk} <= 3 ? 1 : 0; $x->{p} += $r->{p3}; $x->{v} += $r->{p3} * (1 - $r->{p3}); $x->{tan} += $r->{rk} == 1 ? $r->{o} : 0; $x->{fk} += $fuku{$r->{race}}{$r->{u}} // 0 }
  add("人気 $k", $b, $r) if $k !~ /^人気 / && $r->{o} < 5 }   # 単勝5倍未満だけ(今の買い方は人気馬の複勝)
for (@feat) { my ($r, $f) = @$_;
  add('全部', '全部', $r);
  add('2週間の本数', $f->{n14} == 0 ? '0本' : $f->{n14} <= 2 ? '1-2本' : $f->{n14} <= 4 ? '3-4本' : $f->{n14} <= 6 ? '5-6本' : '7本以上', $r);
  add('本数 − ふだん', $f->{dn} <= -2 ? '2本以上少ない' : $f->{dn} < -0.5 ? '少し少ない' : $f->{dn} <= 0.5 ? 'ふだん通り' : $f->{dn} < 2 ? '少し多い' : '2本以上多い', $r) if defined $f->{dn};
  add('最終の坂路4F − ふだん', $f->{dfs} <= -2 ? '2秒以上速い' : $f->{dfs} <= -0.7 ? '0.7-2秒速い' : $f->{dfs} < 0.7 ? 'ふだん通り' : $f->{dfs} < 2 ? '0.7-2秒遅い' : '2秒以上遅い', $r) if defined $f->{dfs};
  add('坂路4Fの同じレースでの順位', $f->{rk}, $r) if $f->{rk};
  add('坂路の終い1F', $f->{fs1} < 12.0 ? '12.0未満' : $f->{fs1} < 12.5 ? '12.0-12.4' : $f->{fs1} < 13.0 ? '12.5-12.9' : '13.0以上', $r) if $f->{fs1};
  add('坂路の加速ラップ', $f->{acc} ? '加速' : '減速', $r) if defined $f->{acc};
  add('坂路とウッド(2021/10〜)', $f->{sw}, $r) if $f->{sw};
  # 組み合わせ: A = 本数がふだんより多い(0.5本超)、B = 坂路の終い1F 12.5未満、C = 加速ラップ
  if (defined $f->{dn} && $f->{fs1}) { my ($A, $B, $C) = ($f->{dn} > 0.5, $f->{fs1} < 12.5, $f->{acc});
    add('組み合わせ', ($A ? 'A' : '-') . ($B ? 'B' : '-') . ($C ? 'C' : '-'), $r);
    add('組み合わせ', 'AB 終い12.0未満', $r) if $A && $f->{fs1} < 12.0 }
  # race_json.pl の調教の点(2026-10-29〜): +2 = 本数がふだんより多い・終い12.0未満、+1 = ABC か 本数2本以上多い か 終い12.0未満、-1 = 2週間に0本
  my $A = defined $f->{dn} && $f->{dn} > 0.5; my $s1 = $f->{fs1} // 99;
  add('調教の点(race_json.pl)', $A && $s1 < 12.0 ? '+2' : (($A && $s1 < 12.5 && $f->{acc}) || ($f->{dn} // 0) >= 2 || $s1 < 12.0) ? '+1' : $f->{n14} == 0 ? '-1' : '0', $r) }

printf "出走 %d頭(前半 < %s <= 後半)。3着内 = 実際÷市場、z = (実際−市場)/√Σp(1−p)、単・複 = 単勝・複勝の回収率\n", scalar @feat, $split;
my @K = ('全部', '2週間の本数', '本数 − ふだん', '最終の坂路4F − ふだん', '坂路4Fの同じレースでの順位', '坂路の終い1F', '坂路の加速ラップ', '坂路とウッド(2021/10〜)', '組み合わせ', '調教の点(race_json.pl)');
for my $k (@K, map { "人気 $_" } @K) {
  print "== $k\n";
  for my $b (sort keys %{$S{$k}}) { printf "  %-14s %s\n", $b, join '  ', map { my $x = $S{$k}{$b}{$_};
      $x && $x->{p} ? sprintf('%s %6d頭 %.3f z%+5.1f 単%5.1f%% 複%5.1f%%', $_, $x->{n}, $x->{y} / $x->{p}, ($x->{y} - $x->{p}) / sqrt($x->{v} || 1), 100 * $x->{tan} / $x->{n}, 100 * $x->{fk} / $x->{n}) : "$_ -" } qw(全体 前半 後半) } }
