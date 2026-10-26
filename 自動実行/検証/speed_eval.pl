# 自分で作るスピード指数と、前走の不利(JRAの「競走中の出来事」)が、単勝オッズより当たるかを確かめる(2026-10-26〜)
# 使い方: perl speed_eval.pl [全期間のフォルダー 馬情報/過去レースデータ/全期間] [分ける日 2023-01-01] [書き出し(省略可): 各馬の指数.tsv]
#   入力: <年>/JRA詳細.jsonl(jra_history.sh。タイム・コース・馬のID・出来事)と <年>/レース.jsonl(history.sh。確定の単勝オッズ)・<年>/払戻.jsonl
#   1) 指数: 走破タイムを、コース(場・芝ダ・距離・内外)の基準タイム(前半の勝ち馬〜3着のタイムの中央値)からの差にし、1kmあたり0.1秒 = 1点にする。
#      その日・その場・芝ダの全レースの「指数 − クラスの平均」の平均を馬場差として引く(馬場の速さ・遅さを消す)。斤量は55kgから1kgで2点(重いほど上げる)
#   2) 各馬のレース前の指数: その馬の前5走の指数の最高・前走の指数(障害・取消・中止は除く)。同じレースの中で標準化(z)
#   3) 前走の不利: 前走の出来事に、その馬が被害馬(被害馬：N番)・枠内駐立不良・発走で後手・他の馬の影響・躓くなどで出ている
#   4) 1着の確率を P ∝ exp(a·log q + b·z最高 + c·z前走 + d·不利) で前半に当てはめ、後半で「オッズだけ」(a だけ)と対数尤度を比べる
#   5) 指数の順位 × 人気の帯、不利ありの馬について、3着以内の実際÷市場(Harville)と単勝・複勝の回収率を前半・後半で出す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use List::Util qw(sum0 max min); use Encode qw(encode);
my ($dir, $split, $dump) = @ARGV; $dir ||= encode('UTF-8', '馬情報/過去レースデータ/全期間'); $split ||= '2023-01-01';
# ファイル名はバイト列で扱う(use utf8 の文字列と @ARGV のバイト列を混ぜると日本語のパスが開けない)
my ($FJ, $FR, $FP) = map { encode('UTF-8', $_) } ('JRA詳細.jsonl', 'レース.jsonl', '払戻.jsonl');
my $J = JSON::PP->new->utf8;
sub rd { my ($f, $cb) = @_; open my $h, '<', $f or return; while (my $l = <$h>) { my $x = eval { $J->decode($l) } or next; $cb->($x) } }
sub sec { my $t = shift // ''; return $t =~ /^(\d+):(\d+(?:\.\d)?)$/ ? $1 * 60 + $2 : $t =~ /^\d+(?:\.\d)?$/ ? $t + 0 : undef }
sub med { my @a = sort { $a <=> $b } @_; return undef unless @a; @a % 2 ? $a[$#a / 2] : ($a[@a / 2 - 1] + $a[@a / 2]) / 2 }

# --- 読み込み ---
my (%R, %ODDS, %PAY);
for my $yd (sort glob "$dir/[12][0-9][0-9][0-9]") {
  rd("$yd/$FJ", sub { my $r = shift; $R{$r->{id}} = $r });
  rd("$yd/$FR", sub { my $r = shift; $ODDS{$r->{id}} = { map { $_->{umaban} => $_->{odds} } grep { $_->{odds} } @{$r->{horses}} } });
  rd("$yd/$FP", sub { my $p = shift; $PAY{$p->{id}} = $p->{pay} });
}
my @ids = sort { $R{$a}{date} cmp $R{$b}{date} || $a cmp $b } keys %R;
printf "JRA詳細 %dレース(%s〜%s)・単勝オッズのあるもの %dレース。前半 < %s <= 後半\n", scalar @ids, ($ids[0] ? $R{$ids[0]}{date} : '-'), ($ids[-1] ? $R{$ids[-1]}{date} : '-'),
  scalar(grep { $ODDS{$_} } @ids), $split;

# --- 1) 指数 ---
my $ckey = sub { my $r = $_[0]{race} || {}; return undef if ($r->{surface} // '') !~ /^(芝|ダ)$/ || !$r->{dist}; join '|', substr($_[0]{id}, 8, 2), $r->{surface}, $r->{dist}, ($r->{course} // '') =~ /外/ ? '外' : '' };
my %base;   # コース → 基準タイム(前半の1〜3着の中央値)
{ my %t; for my $id (@ids) { my $r = $R{$id}; next if $r->{date} ge $split; my $k = $ckey->($r) // next;
    push @{$t{$k}}, grep { defined } map { sec($_->{time}) } grep { ($_->{rank} // '') =~ /^[123]$/ } @{$r->{horses}} }
  for (keys %t) { $base{$_} = med(@{$t{$_}}) if @{$t{$_}} >= 5 } }
my (%raw, %par, %clsn);   # raw{id}{umaban} = 馬場差を引く前の指数
for my $id (@ids) { my $r = $R{$id}; my $k = $ckey->($r) // next; my $b = $base{$k} or next; my $d = $r->{race}{dist};
  for my $h (@{$r->{horses}}) { next unless ($h->{rank} // '') =~ /^\d+$/; my $t = sec($h->{time}) // next;
    my $f = ($b - $t) * (1000 / $d) * 10 + 2 * (($h->{kin} // 55) - 55); $raw{$id}{$h->{umaban}} = $f } }
# クラスの平均(前半)。レースの値 = 1〜5着の指数の中央値
my %rval; for my $id (keys %raw) { my $r = $R{$id}; my @top = map { $raw{$id}{$_->{umaban}} } grep { ($_->{rank} // '') =~ /^\d+$/ && $_->{rank} <= 5 && defined $raw{$id}{$_->{umaban}} } @{$r->{horses}}; $rval{$id} = med(@top) if @top >= 3 }
{ my %c; for my $id (keys %rval) { next if $R{$id}{date} ge $split; push @{$c{$R{$id}{race}{cls} // ''}}, $rval{$id} } $par{$_} = sum0(@{$c{$_}}) / @{$c{$_}} for grep { @{$c{$_}} >= 20 } keys %c }
# 馬場差: その日・その場・芝ダのレースの (レースの値 − クラスの平均) の平均
my %var; { my %v; for my $id (keys %rval) { my $p = $par{$R{$id}{race}{cls} // ''}; next unless defined $p; push @{$v{substr($id, 0, 10) . $R{$id}{race}{surface}}}, $rval{$id} - $p }
  for (keys %v) { $var{$_} = @{$v{$_}} >= 2 ? sum0(@{$v{$_}}) / @{$v{$_}} : undef } }
my %fig; for my $id (keys %raw) { my $v = $var{substr($id, 0, 10) . $R{$id}{race}{surface}}; next unless defined $v; $fig{$id}{$_} = $raw{$id}{$_} - $v for keys %{$raw{$id}} }

# --- 3) 不利の印(前走の出来事) ---
my $FURI = qr/枠内駐立不良|発馬|出遅|後手|躓|つまず|他の馬の影響|不利|挟まれ|接触|落鉄|進路が狭く|外側に逃避|内側に逃避/;
my %furi;   # furi{id}{umaban} = 1
for my $id (@ids) { my $r = $R{$id}; my %byname = map { $_->{name} => $_->{umaban} } @{$r->{horses}};
  for my $e (@{$r->{events} || []}) {
    if ($e =~ /被害馬：([^）)]*)/) { my $v = $1; $v =~ tr/０-９/0-9/; $furi{$id}{$_ + 0} = 1 for $v =~ /(\d+)番/g }
    next unless $e =~ $FURI; next if $e =~ /騎手.*(戒告|過怠金|騎乗停止)/ && $e !~ /被害馬/;   # 加害した側の制裁は不利ではない(被害馬は上で拾う)
    for my $nm (keys %byname) { $furi{$id}{$byname{$nm}} = 1 if index($e, $nm . '号') >= 0 } } }

# --- 2) 各馬のレース前の指数(前5走) ---
my (%hist, @rows);   # hist{horseId} = [[date, fig, id, umaban] ...] 古い順
for my $id (@ids) { my $r = $R{$id}; my $od = $ODDS{$id}; my @hs = grep { ($_->{rank} // '') =~ /^\d+$/ } @{$r->{horses}};
  my $sf = $r->{race}{surface} // '';
  if ($od && $sf =~ /^(芝|ダ)$/ && @hs >= 5 && !grep { !$od->{$_->{umaban}} } @hs) {
    my @q = map { 1 / $od->{$_->{umaban}} } @hs; my $s = sum0(@q); @q = map { $_ / $s } @q;
    my @x; for my $i (0 .. $#hs) { my $h = $hs[$i]; my $hh = $hist{$h->{horseId} // ''} || []; my @last = @$hh > 5 ? @$hh[-5 .. -1] : @$hh;
      my @f = grep { defined } map { $_->[1] } @last; my $pr = $last[-1];
      push @x, { u => $h->{umaban}, rank => $h->{rank}, q => $q[$i], best => (@f ? max(@f) : undef), last => ($pr ? $pr->[1] : undef), n => scalar @f,
        furi => ($pr && $furi{$pr->[2]}{$pr->[3]} ? 1 : 0) } }
    for my $k (qw(best last)) { my @v = grep { defined } map { $_->{$k} } @x; next if @v < 3; my $m = sum0(@v) / @v; my $sd = sqrt(sum0(map { ($_ - $m) ** 2 } @v) / @v) || 1;
      $_->{"z$k"} = defined $_->{$k} ? ($_->{$k} - $m) / $sd : 0 for @x }
    for my $o (@x) { $o->{zbest} //= 0; $o->{zlast} //= 0 }
    # Harville の3着以内率(市場)
    my $n = @x; my @p3 = map { $_->{q} } @x;
    for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { next if $j == $i; my $pij = $x[$i]{q} * $x[$j]{q} / (1 - $x[$i]{q}); $p3[$j] += $pij;
        for my $k (0 .. $n - 1) { next if $k == $i || $k == $j; $p3[$k] += $pij * $x[$k]{q} / (1 - $x[$i]{q} - $x[$j]{q}) } } }
    $x[$_]{p3} = min($p3[$_], 0.999) for 0 .. $n - 1;
    my @byf = sort { ($b->{best} // -1e9) <=> ($a->{best} // -1e9) } @x; my $rk = 0; $_->{frank} = defined $_->{best} ? ++$rk : 99 for @byf;
    my @byq = sort { $b->{q} <=> $a->{q} } @x; $byq[$_]{pop} = $_ + 1 for 0 .. $#byq;
    my %tan = map { $_->{k} => $_->{yen} } @{($PAY{$id} || {})->{'単勝'} || []}; my %fk = map { $_->{k} => $_->{yen} } @{($PAY{$id} || {})->{'複勝'} || []};
    $_->{tan} = $tan{$_->{u}} // 0, $_->{fuku} = $fk{$_->{u}} // 0 for @x;
    push @rows, { id => $id, date => $r->{date}, x => \@x, pay => ($PAY{$id} ? 1 : 0) } }
  for my $h (@hs) { next unless $h->{horseId}; push @{$hist{$h->{horseId}}}, [$r->{date}, $fig{$id}{$h->{umaban}}, $id, $h->{umaban}] }
  # 中止・取消の馬も、その回の不利の印のために履歴に入れる(指数は無し)
  for my $h (grep { ($_->{rank} // '') !~ /^\d+$/ && $_->{horseId} } @{$r->{horses}}) { push @{$hist{$h->{horseId}}}, [$r->{date}, undef, $id, $h->{umaban}] } }
my @tr = grep { $_->{date} lt $split } @rows; my @te = grep { $_->{date} ge $split } @rows;
printf "検証に使うレース(芝・ダート、全馬に単勝オッズ): 前半 %d・後半 %d。指数のあるコース %d\n", scalar @tr, scalar @te, scalar keys %base;

# --- 4) 1着の条件付きロジット ---
my @F = (sub { log $_[0]{q} }, sub { $_[0]{zbest} }, sub { $_[0]{zlast} }, sub { $_[0]{furi} });
my @NM = ('log q', 'z最高', 'z前走', '不利');
sub fit { my ($rs, $use) = @_; my @b = map { $_ == 0 ? 1 : 0 } 0 .. $#F;
  for (1 .. 8) { my @g = (0) x @F; my @H = map { [(0) x @F] } @F;
    for my $r (@$rs) { my @v = map { my $o = $_; [map { $F[$_]->($o) } 0 .. $#F] } @{$r->{x}}; my @e = map { my $v = $_; exp(sum0(map { $use->[$_] ? $b[$_] * $v->[$_] : 0 } 0 .. $#F)) } @v; my $s = sum0(@e);
      my @p = map { $_ / $s } @e; my @m = map { my $k = $_; sum0(map { $p[$_] * $v[$_][$k] } 0 .. $#v) } 0 .. $#F;
      for my $i (0 .. $#v) { next unless $r->{x}[$i]{rank} == 1; $g[$_] += $v[$i][$_] - $m[$_] for 0 .. $#F }
      for my $a (0 .. $#F) { for my $c (0 .. $#F) { $H[$a][$c] += sum0(map { $p[$_] * ($v[$_][$a] - $m[$a]) * ($v[$_][$c] - $m[$c]) } 0 .. $#v) } } }
    my @k = grep { $use->[$_] } 0 .. $#F; my @A = map { my $a = $_; [(map { $H[$a][$_] } @k), $g[$a]] } @k;
    for my $c (0 .. $#k) { my $pv = $A[$c][$c] or last; $_ /= $pv for @{$A[$c]}; for my $rw (0 .. $#k) { next if $rw == $c; my $f = $A[$rw][$c]; $A[$rw][$_] -= $f * $A[$c][$_] for 0 .. $#k + 1 } }
    $b[$k[$_]] += $A[$_][-1] for 0 .. $#k }
  return \@b }
sub ll { my ($rs, $b) = @_; my $L = 0; for my $r (@$rs) { my @e = map { my $o = $_; exp(sum0(map { $b->[$_] * $F[$_]->($o) } 0 .. $#F)) } @{$r->{x}}; my $s = sum0(@e);
    for my $i (0 .. $#e) { $L += log($e[$i] / $s) if $r->{x}[$i]{rank} == 1 } } return @$rs ? $L / @$rs : 0 }
if (@tr >= 200 && @te >= 100) {
  print "== 1着の当たり方(後半の1レースあたりの対数尤度。高いほど良い)\n";
  for my $u ([1, 0, 0, 0], [1, 1, 0, 0], [1, 1, 1, 0], [1, 0, 0, 1], [1, 1, 1, 1]) { my $b = fit(\@tr, $u);
    printf "  %-28s 後半 %.5f  前半 %.5f  係数 %s\n", join('+', map { $NM[$_] } grep { $u->[$_] } 0 .. $#F), ll(\@te, $b), ll(\@tr, $b), join(' ', map { sprintf '%s=%.3f', $NM[$_], $b->[$_] } grep { $u->[$_] } 0 .. $#F) } }
else { print "== 1着の当たり方: レースが少ないので省略(前半200・後半100以上で出す)\n" }

# --- 5) 帯ごと ---
sub band { my ($title, $sel) = @_; my %S;
  for my $r (@rows) { for my $o (@{$r->{x}}) { my $k = $sel->($o) // next; for my $g ($r->{date} lt $split ? '前半' : '後半', '全体') { my $s = $S{$k}{$g} ||= {};
        $s->{n}++; $s->{y3} += $o->{rank} <= 3 ? 1 : 0; $s->{p3} += $o->{p3}; if ($r->{pay}) { $s->{np}++; $s->{tan} += $o->{tan}; $s->{fuku} += $o->{fuku} } } } }
  print "== ${title}: 頭数 / 3着内 実際÷市場 / 単勝・複勝の回収率\n";
  for my $k (sort keys %S) { printf "  %-24s %s\n", $k, join '  ', map { my $s = $S{$k}{$_}; $s ? sprintf('%s %6d頭 %.3f 単%5.1f%% 複%5.1f%%', $_, $s->{n}, $s->{y3} / ($s->{p3} || 1), $s->{np} ? $s->{tan} / $s->{np} : 0, $s->{np} ? $s->{fuku} / $s->{np} : 0) : "$_ -" } qw(全体 前半 後半) } }
band('指数の順位(前5走の最高)', sub { my $o = shift; $o->{frank} == 99 ? '9 指数なし' : $o->{frank} == 1 ? '1 1位' : $o->{frank} <= 3 ? '2 2〜3位' : $o->{frank} <= 6 ? '3 4〜6位' : '4 7位以下' });
band('指数1位 × 人気', sub { my $o = shift; return undef unless $o->{frank} == 1; $o->{pop} == 1 ? 'a 1番人気' : $o->{pop} <= 3 ? 'b 2〜3番人気' : $o->{pop} <= 6 ? 'c 4〜6番人気' : 'd 7番人気以下' });
band('指数 z(前5走の最高)', sub { my $o = shift; return undef unless $o->{n}; my $z = $o->{zbest}; $z >= 1.5 ? 'a +1.5以上' : $z >= 0.5 ? 'b +0.5〜1.5' : $z >= -0.5 ? 'c -0.5〜+0.5' : 'd -0.5未満' });
band('前走の不利', sub { my $o = shift; return undef unless $o->{n}; $o->{furi} ? '1 不利あり' : '2 なし' });
band('前走の不利 × 人気', sub { my $o = shift; return undef unless $o->{furi}; $o->{pop} <= 3 ? 'a 1〜3番人気' : $o->{pop} <= 6 ? 'b 4〜6番人気' : 'c 7番人気以下' });

if ($dump) { open my $o, '>:utf8', $dump or die; print $o join("\t", qw(id date umaban rank q p3 pop best last zbest zlast n furi)), "\n";
  for my $r (@rows) { for my $x (@{$r->{x}}) { print $o join("\t", $r->{id}, $r->{date}, @$x{qw(u rank q p3 pop)}, map { defined $_ ? (/\./ ? sprintf('%.3f', $_) : $_) : '' } @$x{qw(best last zbest zlast n furi)}), "\n" } } }
