# 1日のまとめと反省点: その日の全レースの予想・結果・払戻をまとめ、反省点と次にやることを出す(run.sh が結果の増えた日ごとに作り直す)
# 使い方: perl daily.pl <日付 YYYY-MM-DD> <馬情報フォルダー> [最適化前のmodel.json] [最適化後のmodel.json] > 馬情報/今日のまとめ/<日付>.md
#         perl daily.pl trend <馬情報フォルダー> > 馬情報/今日のまとめ/成績の推移.md
# 使う記録: 予想と結果_レース.csv・予想と結果_馬ごと.csv・印と払戻.csv・買い目の記録.csv・当日バイアス.tsv・振り返り/<日付>.md
#   印どおりの買い方は 100円ずつの仮の成績(シミュレーターの推奨ではない)。推奨の買い方は「標準の複勝」(買い目の記録.csv)
#   今のファイルに「## Claudeの反省と最適化」の欄があれば、そこから下はそのまま残す(PC収集の夜の回がClaudeの見立てを書く)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
use JSON::PP;
utf8::decode($_) for @ARGV;   # フォルダー名(馬情報)を文字として扱い、ファイル名の日本語とつなげる
my ($day, $dir, $mb, $ma) = @ARGV;
die "使い方: perl daily.pl <日付>|trend <馬情報フォルダー> [model前] [model後]\n" unless $day && $dir;

sub read_csv { my $f = shift; my @rows; return @rows unless -e $f; open my $fh, '<:utf8', $f or return @rows; my $hd = <$fh> // ''; $hd =~ s/\r?\n$//; $hd =~ s/^\x{feff}//; my @h = split /,/, $hd;
  while (<$fh>) { s/\r?\n$//; next unless length; my @v = split /,/, $_, -1; my %r; @r{@h} = @v; push @rows, \%r } return @rows }
sub readj { my $f = shift; return undef unless $f && -e $f; open my $fh, '<:raw', $f or return undef; local $/; my $d = eval { JSON::PP->new->utf8->decode(<$fh>) }; return $d }
sub pct { my ($a, $b) = @_; return $b ? sprintf('%.0f%%', 100 * $a / $b) : '-' }
sub yen { my $v = shift; 1 while $v =~ s/^(\d+)(\d{3})/$1,$2/; "${v}円" }

my @LR = read_csv("$dir/予想と結果_レース.csv");
my @LH = read_csv("$dir/予想と結果_馬ごと.csv");
my @MK = read_csv("$dir/印と払戻.csv");
my @BY = read_csv("$dir/買い目の記録.csv");

# 払戻「券種:組番=円 組番=円;…」→ { 券種 => { 正規化した組番 => 円 } }。馬単・3連単以外は馬番を小さい順に並べる
sub ordered { $_[0] =~ /馬単|3連単/ }
sub norm { my ($t, $k) = @_; return $k if ordered($t); join '-', sort { $a <=> $b } split /-/, $k }
sub parse_pay { my %p; for my $s (split /;/, shift // '') { my ($t, $b) = split /:/, $s, 2; next unless $b; for (split / /, $b) { my ($k, $y) = split /=/; $p{$t}{norm($t, $k)} = $y } } \%p }
# 印どおりの買い方(100円ずつ)。marks: ◎ ○ ▲ △の馬番。戻り値 [点数, 的中点数, 払戻]
sub combos { my ($n, @a) = @_; return ([]) if $n == 0; return () unless @a; my ($h, @t) = @a; ((map { [$h, @$_] } combos($n - 1, @t)), combos($n, @t)) }
sub bet { my ($pay, $t, @kumi) = @_; my ($n, $hit, $ret) = (0, 0, 0);
  for my $k (@kumi) { next if grep { !defined $_ || $_ eq '' } @$k; $n++; my $y = $pay->{$t}{norm($t, join '-', @$k)}; if ($y) { $hit++; $ret += $y } } [$n, $hit, $ret] }
my @PLANS = (
  ['単勝 ◎', sub { my ($p, $m) = @_; bet($p, '単勝', [$m->{h}]) }],
  ['複勝 ◎', sub { my ($p, $m) = @_; bet($p, '複勝', [$m->{h}]) }],
  ['単勝 1番人気', sub { my ($p, $m) = @_; bet($p, '単勝', [$m->{p1}]) }],
  ['複勝 1番人気', sub { my ($p, $m) = @_; bet($p, '複勝', [$m->{p1}]) }],
  ['ワイド ◎-○', sub { my ($p, $m) = @_; bet($p, 'ワイド', [$m->{h}, $m->{t}]) }],
  ['馬連 ◎-○', sub { my ($p, $m) = @_; bet($p, '馬連', [$m->{h}, $m->{t}]) }],
  ['馬単 ◎→○', sub { my ($p, $m) = @_; bet($p, '馬単', [$m->{h}, $m->{t}]) }],
  ['ワイド ◎-印4頭 流し', sub { my ($p, $m) = @_; bet($p, 'ワイド', map { [$m->{h}, $_] } @{$m->{aite}}) }],
  ['馬連 ◎-印4頭 流し', sub { my ($p, $m) = @_; bet($p, '馬連', map { [$m->{h}, $_] } @{$m->{aite}}) }],
  ['3連複 ◎○▲', sub { my ($p, $m) = @_; bet($p, '3連複', [$m->{h}, $m->{t}, $m->{a}]) }],
  ['3連複 ◎軸-印4頭 流し', sub { my ($p, $m) = @_; bet($p, '3連複', map { [$m->{h}, @$_] } combos(2, @{$m->{aite}})) }],
  ['3連単 ◎→○→▲', sub { my ($p, $m) = @_; bet($p, '3連単', [$m->{h}, $m->{t}, $m->{a}]) }],
  ['3連単 1→2→3番人気', sub { my ($p, $m) = @_; bet($p, '3連単', [$m->{p1}, $m->{p2}, $m->{p3}]) }],
);
sub marks_of { my $r = shift; my @rk = grep { length } split / /, $r->{renka} // '';
  +{ h => $r->{honmei}, t => $r->{taikou}, a => $r->{tanana}, aite => [grep { length } ($r->{taikou}, $r->{tanana}, @rk)], p1 => $r->{pop1}, p2 => $r->{pop2}, p3 => $r->{pop3} } }
sub plan_stats { my @rows = @_; my %s; for my $r (@rows) { next if $r->{grade}; my $p = parse_pay($r->{pay}); my $m = marks_of($r);
    for my $pl (@PLANS) { my $x = $pl->[1]->($p, $m); $s{$pl->[0]}[$_] += $x->[$_] for 0 .. 2 } } \%s }
sub fuku_stats { my @rows = @_; my ($n, $hit, $ret, $races) = (0, 0, 0, 0); my %rc;
  for my $b (@rows) { $rc{$b->{raceId}}++; next unless length($b->{umaban} // ''); $n++; $hit++ if $b->{pay}; $ret += $b->{pay} || 0 } [$n, $hit, $ret, scalar keys %rc] }
sub honmei_stats { my @r = @_; my $n = @r; my $w = grep { ($_->{honmeiRank} // '') eq '1' } @r; my $t3 = grep { ($_->{honmeiRank} // '') =~ /^[123]$/ } @r; ($n, $w, $t3) }
sub fav_stats { my ($ids, $h) = @_; my %id = map { $_ => 1 } @$ids; my @f = grep { $id{$_->{raceId}} && ($_->{pop} // '') eq '1' && ($_->{rank} // '') =~ /^\d+$/ } @$h;
  (scalar(@f), scalar(grep { $_->{rank} == 1 } @f), scalar(grep { $_->{rank} <= 3 } @f)) }

if ($day eq 'trend') {
  my %d; $d{$_->{date}} = 1 for @LR;
  print "# 成績の推移(1日のまとめ)\n\n自動実行/全レース/daily.pl が結果の入るたびに作り直す。日ごとの詳しいまとめと反省点は同じフォルダーの <日付>.md。\n";
  print "印どおりの買い方は100円ずつの仮の成績で、推奨ではない(推奨は標準の複勝)。重賞は印どおりの成績から外す。\n\n";
  print "| 日付 | レース | ◎勝率 | ◎3着内 | 1番人気 勝率 | 1番人気 3着内 | ★ 3着内 | 標準の複勝 点数・回収率 | 馬連◎-○ 回収率 | 3連複◎軸流し 回収率 |\n|---|---|---|---|---|---|---|---|---|---|\n";
  my (@aLR, @aMK, @aBY);
  for my $dt (sort keys %d) {
    my @r = grep { $_->{date} eq $dt } @LR; my @m = grep { $_->{date} eq $dt } @MK; my @b = grep { $_->{date} eq $dt } @BY;
    push @aLR, @r; push @aMK, @m; push @aBY, @b;
    print row($dt, \@r, \@m, \@b);
  }
  print row('**合計**', \@aLR, \@aMK, \@aBY);
  sub row { my ($dt, $r, $m, $b) = @_; my ($n, $w, $t3) = honmei_stats(@$r); my ($fn, $fw, $f3) = fav_stats([map { $_->{raceId} } @$r], \@LH);
    my @st = grep { $_->{star} } @$r; my $st3 = grep { ($_->{honmeiRank} // '') =~ /^[123]$/ } @st;
    my $fk = fuku_stats(@$b); my $ps = plan_stats(@$m);
    my $roi = sub { my $x = $ps->{$_[0]}; $x && $x->[0] ? pct($x->[2], 100 * $x->[0]) : '-' };
    sprintf "| %s | %d | %s | %s | %s | %s | %s | %s |  %s | %s |\n", $dt, $n, pct($w, $n), pct($t3, $n), pct($fw, $fn), pct($f3, $fn),
      (@st ? "$st3/" . scalar(@st) : '-'), ($fk->[0] ? "$fk->[0]点・" . pct($fk->[2], 100 * $fk->[0]) : ($fk->[3] ? '0点' : '-')), $roi->('馬連 ◎-○'),$roi->('3連複 ◎軸-印4頭 流し') }
  exit 0;
}

# ---- 1日のまとめ ----
my @R = grep { $_->{date} eq $day } @LR; die "$day の記録がありません\n" unless @R;
my %rid = map { $_->{raceId} => 1 } @R;
my @H = grep { $rid{$_->{raceId}} } @LH;
my @M = grep { $_->{date} eq $day } @MK;
my @B = grep { $_->{date} eq $day } @BY;
my ($n, $w, $t3) = honmei_stats(@R); my ($fn, $fw, $f3) = fav_stats([keys %rid], \@LH);
my %fav = map { $_->{raceId} => $_ } grep { ($_->{pop} // '') eq '1' } @H;
my @rev; my @next;   # 反省点・次にやること
my @out;
push @out, "# $day のまとめと反省点\n";
push @out, "自動実行/全レース/daily.pl が結果の入るたびに作り直す(レースごとの振り返りは 馬情報/振り返り/$day.md)。日をまたいだ成績は 成績の推移.md。\n";

# 1. 予想の成績
push @out, "## 1. 予想の成績\n";
push @out, "| | レース | 勝率 | 3着以内率 |\n|---|---|---|---|";
push @out, "| ◎(シミュレーターの本命) | $n | " . pct($w, $n) . " | " . pct($t3, $n) . " |";
push @out, "| 1番人気(比べる基準) | $fn | " . pct($fw, $fn) . " | " . pct($f3, $fn) . " |";
my %pl; push @{$pl{$_->{place}}}, $_ for @R;
for my $p (sort keys %pl) { my ($a, $b, $c) = honmei_stats(@{$pl{$p}}); push @out, "| ◎ $p | $a | " . pct($b, $a) . " | " . pct($c, $a) . " |" }
my @st = grep { $_->{star} } @R; my $st3 = grep { ($_->{honmeiRank} // '') =~ /^[123]$/ } @st;
push @out, "| ★(◎の3着以内率が基準以上) | " . scalar(@st) . " | " . pct(scalar(grep { ($_->{honmeiRank} // '') eq '1' } @st), scalar @st) . " | " . pct($st3, scalar @st) . " |" if @st;
my $hits = 0; $hits += ($_->{hits3} // 0) for @R;
push @out, "\n- 予想の上位3頭のうち3着以内に来た数: 平均 " . sprintf('%.2f', $n ? $hits / $n : 0) . " 頭(全部当たると3頭)";
my @notfav = grep { $fav{$_->{raceId}} && $fav{$_->{raceId}}{name} ne $_->{honmei} } @R;
if (@notfav) { my $nw = grep { ($_->{honmeiRank} // '') =~ /^[123]$/ } @notfav; my $fw2 = grep { ($fav{$_->{raceId}}{rank} // '') =~ /^[123]$/ } @notfav;
  push @out, "- ◎が1番人気と違ったレース: " . scalar(@notfav) . " レース。◎の3着以内 $nw 回・1番人気の3着以内 $fw2 回";
  if ($fw2 > $nw + 1) { push @rev, "◎を1番人気から外したレースで1番人気のほうが来ていた($fw2 対 $nw)。人気を外す根拠が弱い"; push @next, "◎が1番人気と違うレースの共通点(能力値のどの項目が差を付けたか)を 振り返り/$day.md で確かめ、その項目の重みを見直す" }
  elsif ($nw > $fw2 + 1) { push @rev, "◎を1番人気から外したレースは当たっていた($nw 対 $fw2)。この判断は続けてよい" } }
if ($fn && $n && $t3 / $n < $f3 / $fn - 0.08) { push @rev, "◎の3着以内率(" . pct($t3, $n) . ")が1番人気(" . pct($f3, $fn) . ")より低い。今日は人気どおりのほうが当たった" }
for my $x (grep { ($_->{honmeiRank} // '') !~ /^[123]$/ } @st) { push @rev, "★の$x->{place}$x->{no}R $x->{name}で◎$x->{honmei}が" . ($x->{honmeiRank} || '?') . "着。理由は 振り返り/$day.md のレースの細部" }
if (@st && $st3 / @st < 0.7) { push @rev, "★が " . scalar(@st) . " レース中 $st3 回しか3着以内に来ていない(目標83%)。★の基準は optimize.pl が自動で上げる" }
my @upset = grep { ($_->{winnerPop} || 0) >= 7 } @R;
if (@upset) { push @out, "- 7番人気以下の勝ち: " . join('、', map { "$_->{place}$_->{no}R $_->{winner}($_->{winnerPop}番人気・予想$_->{winnerPredRank}位)" } @upset);
  push @rev, "7番人気以下が " . scalar(@upset) . " レースで勝った" . (@upset >= 4 ? "。荒れた日で、印どおりの3連系は取りにくい" : '') }
my @miss = grep { ($_->{winnerPredRank} || 0) >= 8 && ($_->{winnerPop} || 99) <= 3 } @R;
push @rev, "人気(3番人気以内)の勝ち馬を予想8位以下にしていた: " . join('、', map { "$_->{place}$_->{no}R $_->{winner}($_->{winnerPop}番人気・予想$_->{winnerPredRank}位)" } @miss) . "。能力値が実力を表せていない馬" if @miss;

# 2. 買い目の成績
push @out, "\n## 2. 買い目の成績(100円ずつ・本物の払戻)\n";
my $fk = fuku_stats(@B);
if ($fk->[3]) {
  push @out, "- **標準の複勝**(シミュレーターの推奨・重賞/新馬/障害は除く): $fk->[3] レース中 $fk->[0] 点・的中 $fk->[1] 点(" . pct($fk->[1], $fk->[0]) . ")・使った " . yen(100 * $fk->[0]) . "・戻り " . yen($fk->[2]) . "・回収率 **" . pct($fk->[2], 100 * $fk->[0]) . "**";
  my @bb = grep { length($_->{umaban} // '') } @B;
  push @out, "  - " . join('、', map { "$_->{place}$_->{no}R $_->{horse}(下限$_->{fukuLo}倍)" . ($_->{pay} ? "○$_->{pay}円" : '×') } @bb) if @bb;
  my $all = fuku_stats(@BY);
  push @out, "  - 記録を始めてからの合計: $all->[0] 点・的中 " . pct($all->[1], $all->[0]) . "・回収率 " . pct($all->[2], 100 * $all->[0]) . "(過去の検証は123%)" if $all->[0];
  if ($fk->[0] >= 3 && $fk->[2] < 100 * $fk->[0] * 0.8) { push @rev, "標準の複勝が回収率" . pct($fk->[2], 100 * $fk->[0]) . "。1日だけでは振れが大きいので買い方はまだ変えない(300点で100%未満なら見直す)" }
  if ($all->[0] >= 300 && $all->[2] < 100 * $all->[0]) { push @next, "標準の複勝が $all->[0] 点で100%を下回った。資金計画の決まりどおり買い方を見直す(fuku_cond.pl で条件を探し直す)" }
} else { push @out, "- 標準の複勝: この日はレース前の複勝オッズ(db の fuku)と払戻がそろったレースが無く、成績を出せない" }
if (@M) {
  my $ps = plan_stats(@M); my $nr = grep { !$_->{grade} } @M;
  push @out, "\n印どおりに買っていたら(推奨ではない仮の成績・平場 $nr レース):\n";
  push @out, "| 買い方 | 点数 | 的中 | 使った | 戻り | 回収率 |\n|---|---|---|---|---|---|";
  for my $pl (@PLANS) { my $x = $ps->{$pl->[0]} or next; next unless $x->[0];
    push @out, "| $pl->[0] | $x->[0] | $x->[1] | " . yen(100 * $x->[0]) . " | " . yen($x->[2]) . " | " . pct($x->[2], 100 * $x->[0]) . " |" }
  my @good = grep { my $x = $ps->{$_->[0]}; $x && $x->[0] >= 5 && $x->[2] >= 100 * $x->[0] * 1.2 } @PLANS;
  push @rev, "印どおりで回収率120%以上: " . join('、', map { $_->[0] } @good) . "。1日だけの結果なので、続くかは 成績の推移.md で見る" if @good;
  # 配当の荒れ具合
  my (%mx, %sum, %cnt); my @big;
  for my $r (@M) { my $p = parse_pay($r->{pay}); for my $t (keys %$p) { for my $k (keys %{$p->{$t}}) { my $y = $p->{$t}{$k}; $sum{$t} += $y; $cnt{$t}++; $mx{$t} = [$y, "$r->{place}$r->{no}R"] if !$mx{$t} || $y > $mx{$t}[0] } }
    my ($y) = sort { $b <=> $a } values %{$p->{'3連単'} || {}}; push @big, "$r->{place}$r->{no}R " . yen($y) if $y && $y >= 100000 }
  push @out, "\nこの日の配当(100円あたり):\n";
  push @out, "| 券種 | 平均 | 最高 |\n|---|---|---|";
  for my $t (grep { $cnt{$_} } qw(単勝 複勝 枠連 ワイド 馬連 馬単 3連複 3連単)) { push @out, "| $t | " . yen(int($sum{$t} / $cnt{$t})) . " | " . yen($mx{$t}[0]) . "($mx{$t}[1]) |" }
  push @out, "\n- 3連単10万円以上: " . join('、', @big) if @big;
} else { push @out, "- 印どおりの成績: 払戻の記録(印と払戻.csv)がまだ無い" }

# 3. 馬場の傾向(4角の位置・枠)
my (@bias, @ball); if (open my $fh, q{<:utf8}, "$dir/当日バイアス.tsv") { <$fh>; while (<$fh>) { s/\r?\n$//; my @v = split /\t/; push @ball, \@v; push @bias, \@v if $v[0] eq $day } }
# 比べる基準: 記録のある全部の日の3着以内の馬で、4角で前1/3にいた割合(ふつうでも半分ほどある)
my ($bf, $bn) = (0, 0); for my $v (@ball) { next unless ($v->[7] // q{}) =~ /^[123]$/ && length($v->[6] // q{}) && $v->[5]; $bn++; $bf++ if $v->[6] <= $v->[5] / 3 } my $base = $bn ? $bf / $bn : 0.5;
if (@bias) {
  push @out, "\n## 3. 馬場の傾向(3着以内の馬)\n";
  push @out, "| 場・芝ダ | レース | 4角で前(前から1/3以内) | 内枠(馬番が前半) |\n|---|---|---|---|";
  my %g; for my $v (@bias) { next unless ($v->[7] // '') =~ /^[123]$/ && $v->[5]; push @{$g{"$v->[1] $v->[2]"}}, $v }
  for my $k (sort keys %g) { my @x = @{$g{$k}}; my %rc = map { $_->[3] => 1 } @x; my $nr = keys %rc;
    my $front = grep { length($_->[6] // '') && $_->[6] <= $_->[5] / 3 } @x; my $fx = grep { length($_->[6] // '') } @x;
    my $inner = grep { $_->[4] <= $_->[5] / 2 } @x;
    push @out, "| $k | $nr | " . pct($front, $fx) . " | " . pct($inner, scalar @x) . " |";
    next if $nr < 4;
    if ($fx && $front / $fx >= $base + 0.15) { push @rev, "$k は前に行った馬が残った(" . pct($front, $fx) . ")"; push @next, "同じ開催の $k は先行馬を上に見る(当日バイアスは run.sh が dayBias で自動反映。翌日も同じ傾向か確かめる)" }
    elsif ($fx && $front / $fx <= $base - 0.15) { push @rev, "$k は差し・追込が届いた(4角で前の馬の3着以内は" . pct($front, $fx) . ")"; push @next, "同じ開催の $k は差し馬を上に見る(翌日も同じ傾向か確かめる)" }
    if (@x >= 9 && ($inner / @x >= 0.75 || $inner / @x <= 0.25)) { push @rev, "$k は" . ($inner / @x >= 0.75 ? '内' : '外') . "枠が来た(内枠の割合" . pct($inner, scalar @x) . ")" } }
  push @out, "\n(比べる基準: 記録のある全部の日で、3着以内の馬が4角で前1/3にいた割合は" . pct($bf, $bn) . "。内枠はおよそ50%。基準から15ポイント以上離れた馬場だけ反省点に書く)";
}

# 4. 振り返りでよく出た改善点
if (open my $fh, '<:utf8', "$dir/振り返り/$day.md") { my %c; while (<$fh>) { next unless s/^- 次への改善: //; s/\r?\n$//; $c{$_}++ for grep { length } split / \/ / }
  if (%c) { push @out, "\n## 4. レースごとの振り返りでよく出た改善点\n"; my @k = (sort { $c{$b} <=> $c{$a} || $a cmp $b } keys %c)[0 .. 4];
    push @out, "- $_($c{$_}レース)" for grep { defined } @k;
    my ($top) = @k; push @next, "いちばん多かった改善点「$top」は fit.pl で当たりが増えるか確かめてから入れる(1日だけで重みを動かさない)" if $top && $c{$top} >= 8 } }
# ◎の負け方の内訳(振り返りの「レースの細部」で◎が4着以下だったレースの理由を数える)
if (open my $fh, '<:utf8', "$dir/振り返り/$day.md") {
  my @kinds = (['ハイペースを前で追いかけて', 'ハイペースを前で追いかけて止まった'], ['スローで後ろすぎ', 'スローで後ろすぎて届かなかった'], ['位置が後ろだった', '末脚は上位だが位置が後ろ'],
    ['最後の伸びを欠いた', '良い位置から伸びを欠いた'], ['力負け', '位置も末脚も足りない力負け'], ['出遅れか行き脚', '出遅れ・行き脚がつかない'], ['道中の位置が予想より後ろ', '先行と見たのに道中で後ろ'], ['馬体重の大きな増減', '馬体重の大きな増減'], ['競走中の出来事', '競走中の出来事(不利など)'], ['勝ち馬との力の差', '目立った敗因なし']);
  my (%k, $n); while (<$fh>) { next unless /^\s+- ◎\S+は(\d+|[^\d\s]+)着: (.*)/; my ($rk, $t) = ($1, $2); next if $rk =~ /^[123]$/; $n++; for my $x (@kinds) { $k{$x->[1]}++ if index($t, $x->[0]) >= 0 } }
  if ($n) { push @out, "\n## 4-2. ◎が4着以下に負けた理由の内訳($n レース。1レースに複数あり)\n";
    push @out, "- $_: $k{$_}" for sort { $k{$b} <=> $k{$a} || $a cmp $b } keys %k;
    my ($top) = sort { $k{$b} <=> $k{$a} || $a cmp $b } grep { $_ ne '目立った敗因なし' } keys %k;
    if ($top && $k{$top} >= 3) { push @rev, "◎の負け方で多かったのは「$top」($k{$top}レース)";
      my %fix = ('ハイペースを前で追いかけて止まった' => '先行馬が多いレース(逃げ・先行の頭数)ではペースが速くなると見て、先行の◎を割り引く条件を fit.pl で確かめる',
        'スローで後ろすぎて届かなかった' => '逃げ馬が少ないレースはスローと見て、差しの◎を割り引く条件を fit.pl で確かめる',
        '末脚は上位だが位置が後ろ' => '差し・追込の◎は複勝・ワイドの軸にとどめ、単勝は控える',
        '出遅れ・行き脚がつかない' => '出遅れ癖(前走までの1角の位置)を note に出し、先行と見る脚質の判定を見直す',
        '先行と見たのに道中で後ろ' => '脚質(style)の判定を見直す。前走の位置だけでなく、近走の通過順の平均で先行かどうかを決める',
        '馬体重の大きな増減' => '当日の馬体重が±10kg以上の◎は割り引く条件を fit.pl で確かめる');
      push @next, $fix{$top} if $fix{$top} } } }

# 5. 最適化
my ($b0, $b1) = (readj($mb), readj($ma));
if ($b1 && ref $b1->{weights} eq 'HASH') {
  my %jp = (jisseki => '実績', kyori => '距離', course => 'コース', choshi => '調子', kishu => '騎手');
  push @out, "\n## 5. 最適化(optimize.pl)\n";
  push @out, "- 重み: " . join('、', map { my $o = $b0 && $b0->{weights} ? $b0->{weights}{$_} : undef; "$jp{$_} " . (defined $o && abs($o - $b1->{weights}{$_}) > 1e-9 ? "$o→" : '') . $b1->{weights}{$_} } qw(jisseki kyori course choshi kishu));
  push @out, "- ★の基準(◎の3着以内率): " . ($b0 && ($b0->{starTop3} // 0) != ($b1->{starTop3} // 0) ? "$b0->{starTop3}→" : '') . ($b1->{starTop3} // '-');
  push @out, "- $b1->{note}" if $b1->{note};
  push @out, "- 重みは過去1,868レースの値に強く寄せているので、1日の結果では大きく動かない(動かしすぎて外れるのを防ぐため)";
}

# 6. 反省点と次にやること
push @out, "\n## 6. 反省点\n";
push @out, @rev ? map { "- $_" } @rev : "- 目立った外れ方は無かった";
push @out, "\n## 7. 次にやること\n";
push @out, @next ? map { "- $_" } @next : "- 今の買い方・重みのまま続ける";

# Claudeの欄を残す
my $keep = ''; if (open my $fh, '<:utf8', "$dir/今日のまとめ/$day.md") { local $/; my $c = <$fh>; $keep = $1 if $c =~ /(\n## Claudeの反省と最適化.*)\z/s }
print join("\n", @out), "\n", ($keep || "\n## Claudeの反省と最適化\n\n(PC収集の夜の回が、上のまとめと作業の記録を読んで書く)\n");
