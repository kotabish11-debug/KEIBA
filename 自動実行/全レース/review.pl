# レース後の振り返り: 予想(能力値から計算した順位と◎○▲)と結果を比べ、違った点と次への改善を出す
# 使い方: perl review.pl <レースデータ.json> <result.json> [model.json] > review.json
#   レースデータは db の races/<id> の中身(ArtifactData の保存形式 {"data":{...}} でもよい)
#   出力: { review: {...ページに出す振り返り}, rows: [...馬ごとの記録(最適化用)] }
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;
my ($rf, $resf, $mf) = @ARGV;
sub readj { my $f = shift; open my $fh, '<:raw', $f or die "cannot open $f"; local $/; my $d = JSON::PP->new->utf8->decode(<$fh>); return $d }
my $race = readj($rf); $race = $race->{data} if ref $race->{data} eq 'HASH';
my $res = readj($resf);
my %W = (jisseki => .28, kyori => .17, course => .055, choshi => .245, kishu => .25);
my $star_p = 0.80;
if ($mf && -e $mf) { my $m = readj($mf); %W = %{$m->{weights}} if ref $m->{weights} eq 'HASH'; $star_p = $m->{starTop3} if $m->{starTop3} }
my @FAC = (['jisseki', '実績'], ['kyori', '距離'], ['course', 'コース'], ['choshi', '調子'], ['kishu', '騎手']);

# シミュレーターと同じ、コースの形からの脚質・枠の補正
sub default_bias {
  my $d = shift; my $small = ($d->{place} // '') =~ /^(中山|福島|小倉|函館|札幌)$/ || ($d->{courseNote} // '') =~ /内回り/;
  return ({ '逃げ' => 1, '先行' => 1, '差し' => 0, '追込' => -1.5 }, 0.3) if ($d->{surface} // '') eq '障';
  return ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => -0.5, '追込' => -2 }, 0.5) if ($d->{surface} // '') eq 'ダ';
  return ({ '逃げ' => 1.5, '先行' => 1.5, '差し' => 0, '追込' => -2.5 }, 0.8) if $small;
  return ({ '逃げ' => 0, '先行' => 0.5, '差し' => 0.5, '追込' => 0 }, 0.4);
}
my ($dbias, $ddraw) = default_bias($race);
my $bias = ref $race->{courseBias} eq 'HASH' ? $race->{courseBias} : $dbias;
my $draw = defined $race->{drawBias} ? $race->{drawBias} : $ddraw;
my $going = $race->{going} // 0;

my %rk; my %fin; for my $o (@{$res->{order}}) { $fin{$o->{name}} = $o }
my @hs = grep { !$_->{scratched} } @{$race->{horses}};
my $total = scalar @{$race->{horses}};
# レース直後のJRAの結果ページには人気が無いことがあるので、レース前の単勝オッズの順で補う
{ my $i = 0; my %pp = map { $_->{name} => ++$i } sort { $a->{odds} <=> $b->{odds} } grep { ($_->{odds} // '') =~ /^[\d.]+$/ && $_->{odds} > 0 } @hs;
  for my $o (@{$res->{order}}) { $o->{pop} //= $pp{$o->{name}} if $pp{$o->{name}} } }
for my $h (@hs) {
  my $s = 0; $s += $W{$_->[0]} * ($h->{$_->[0]} // 60) for @FAC;
  $s += $bias->{$h->{style} // '差し'} // 0;
  my $u = $h->{umaban} // 0; $s += $draw * (1 - 2 * ($u - 1) / ($total > 1 ? $total - 1 : 1)) if $u >= 1;
  $s += ($h->{heavy} // 0) * $going * 0.9;
  $h->{_score} = $s;
}
my @pred = sort { $b->{_score} <=> $a->{_score} } @hs;
# 印の順番はシミュレーターと同じ(star.pl の勝率順: 実際のオッズがあれば90%の比重で混ぜたもの)。star.pl が動かなければ能力値の点数順
{ (my $dir = __FILE__) =~ s{[\\/][^\\/]*$}{}; $dir = '.' if $dir eq __FILE__;
  my $out = `perl "$dir/star.pl" "$rf" "${\($mf // '')}" 2>/dev/null`;
  my $st = eval { JSON::PP->new->utf8->decode($out) };
  if ($st && ref $st->{order} eq 'ARRAY') { my %pos; @pos{@{$st->{order}}} = 0 .. $#{$st->{order}}; @pred = sort { ($pos{$a->{name}} // 99) <=> ($pos{$b->{name}} // 99) || $b->{_score} <=> $a->{_score} } @hs } }
my @marks = ('◎', '○', '▲', '△', '△');
$pred[$_]{_mark} = $marks[$_] for 0 .. ($#pred < 4 ? $#pred : 4);
$pred[$_]{_prank} = $_ + 1 for 0 .. $#pred;
my @actual = sort { $a->{rank} <=> $b->{rank} } grep { ($_->{rank} // '') =~ /^\d+$/ } @{$res->{order}};
my @top3 = map { $_->{name} } @actual[0 .. ($#actual < 2 ? $#actual : 2)];
my %by = map { $_->{name} => $_ } @hs;
my $hon = $pred[0]; my $honfin = $fin{$hon->{name}};
my $win = $actual[0]; my $winh = $by{$win->{name}};
my $hits = grep { my $n = $_->{name}; grep { $_ eq $n } @top3 } @pred[0 .. 2];
my $heads = scalar @actual;
sub st_of { my $o = shift; return undef unless $o && $o->{last4} && $heads; my $r = $o->{last4} / $heads; return $r <= 0.12 ? '逃げ' : $r <= 0.35 ? '先行' : $r <= 0.7 ? '差し' : '追込' }

# ---- 違った点 ----
my @diff; my @next;
my $honr = $honfin ? $honfin->{rank} : '?';
if ($honr =~ /^\d+$/ && $honr <= 3) { push @diff, "◎$hon->{name}は${honr}着で、軸は合っていた" }
else { push @diff, "◎$hon->{name}は${honr}着に負けた" }
if ($winh) {
  my $wp = $winh->{_prank};
  push @diff, "勝った$win->{name}(" . ($win->{pop} // '?') . "番人気)は予想${wp}位" . ($winh->{_mark} ? "(印$winh->{_mark})" : '(無印)');
  if ($wp > 1) {
    my @low = sort { $a->[1] <=> $b->[1] } map { [$_->[1], ($winh->{$_->[0]} // 0) - ($hon->{$_->[0]} // 0), $_->[0]] } @FAC;
    my @under = grep { $_->[1] < 0 } @low;
    if (@under) {
      push @diff, "勝ち馬を◎より低く見ていた項目: " . join('、', map { "$_->[0](" . ($winh->{$_->[2]}) . " 対 " . ($hon->{$_->[2]}) . ")" } @under[0 .. ($#under < 1 ? $#under : 1)]);
      my %tip = (
        jisseki => '実績(Ω指数・格)だけで差を付けすぎない。上がり馬・昇級初戦の評価を上げる',
        kyori => '距離経験が少なくても、血統や前走内容で距離適性を見込む',
        course => 'コース経験が浅い馬を低く見すぎない。似たコースの成績も使う',
        choshi => '前走の着順だけで調子を決めない。着差・レースのレベル・不利を確かめる',
        kishu => '騎手のコース成績の差を付けすぎない',
      );
      push @next, $tip{$under[0][2]};
    }
    my $ws = st_of($win); my $ps = $winh->{style} // '';
    push @diff, "勝ち馬の脚質は予想「$ps」、実際は4角" . ($win->{last4} // '?') . "番手($ws)" if $ws && $ps && $ws ne $ps;
  }
}
my @fs = grep { defined } map { st_of($_) } @actual[0 .. ($#actual < 2 ? $#actual : 2)];
my $front = grep { $_ eq '逃げ' || $_ eq '先行' } @fs; my $back = grep { $_ eq '差し' || $_ eq '追込' } @fs;
if (@fs == 3 && $front >= 2 && ($bias->{'差し'} // 0) >= ($bias->{'先行'} // 0)) { push @diff, '上位3頭のうち' . $front . '頭が前で運んだ(前残り)'; push @next, 'このコース・この馬場は前残り。courseBias の逃げ・先行を上げる' }
if (@fs == 3 && $back >= 2 && ($bias->{'先行'} // 0) > ($bias->{'差し'} // 0)) { push @diff, '上位3頭のうち' . $back . '頭が差し・追込(差しが届いた)'; push @next, 'このコースは差しも届く。courseBias の差し・追込を上げる' }
if ($win && ($win->{pop} // 0) >= 7) { push @diff, "$win->{pop}番人気の勝利で波乱"; push @next, '人気薄の激走があり得る条件。chaos(波乱度)を上げ、ヒモに穴馬を入れる' }
if ($win && ($win->{pop} // 0) == 1 && $winh && $winh->{_prank} > 1) { push @next, '1番人気を軽く見すぎた。実際のオッズを予想にもっと混ぜる' }
push @diff, "予想の上位3頭のうち${hits}頭が3着以内";
push @next, '大きなずれはなし。今の重みを続ける' unless @next;

# ---- レースの細部: なぜこの着順になったか(ペース・位置取り・上がり・着差・馬体重・競走中の出来事) ----
# 結果に通過順・上がりが無い(スポーツナビの結果など)ときは、分かる項目だけ書く
my @detail;
sub secs { my $t = shift // ''; return $t =~ /^(\d+):(\d+\.\d)$/ ? $1 * 60 + $2 : $t =~ /^(\d+\.\d)$/ ? $1 : undef }
my @laps = @{$res->{laps} || []}; my $pace = '';
if (@laps >= 5 && $res->{last3f}) {
  my $f3 = 0; $f3 += $laps[$_] for 0 .. 2; my $d = $f3 - $res->{last3f};
  # 1000〜1400mは前半が速いのがふつう、1800m以上は前半が遅いのがふつうなので、目安を距離でずらす
  my $dist = $race->{dist} // 1600; my $adj = $dist <= 1400 ? -1.0 : $dist >= 1800 ? 1.0 : 0; $d -= $adj;
  $pace = $d <= -1.5 ? 'H' : $d >= 1.5 ? 'S' : 'M';
  push @detail, sprintf('ペース: %s(前半3F %.1f・上がり3F %.1f)。%s', { H => 'ハイペース', S => 'スローペース', M => '平均ペース' }->{$pace}, $f3, $res->{last3f},
    { H => '前に行った馬には厳しく、差し・追込が届きやすい', S => '前に行った馬が楽で、後ろの馬は届きにくい', M => '位置取りの有利不利は小さい' }->{$pace});
}
my @f3r = sort { $a->[1] <=> $b->[1] } map { [$_->{name}, $_->{f3}] } grep { ($_->{f3} // '') =~ /^\d+\.\d$/ } @actual;
my %f3rank; $f3rank{$f3r[$_][0]} //= $_ + 1 for 0 .. $#f3r;
my $wsec = secs($win->{time});
my $pos_of = sub { my $o = shift; return '' unless $o->{last4} && $heads; my $r = $o->{last4} / $heads;
  "4角$o->{last4}番手(" . ($r <= 0.2 ? '先頭近く' : $r <= 0.4 ? '前目' : $r <= 0.65 ? '中団' : '後方') . ')' };
my $run_of = sub { my $o = shift; my @x;
  push @x, $pos_of->($o) if $o->{last4};
  push @x, "上がり$o->{f3}(" . ($f3rank{$o->{name}} == 1 ? '最速' : "$f3rank{$o->{name}}位") . ')' if $f3rank{$o->{name}};
  my $s = secs($o->{time}); push @x, sprintf('勝ち馬から%.1f秒差', $s - $wsec) if defined $s && defined $wsec && $o->{rank} > 1;
  push @x, "馬体重$o->{bw}(" . ($o->{bwDiff} > 0 ? '+' : '') . "$o->{bwDiff})" if defined $o->{bwDiff} && abs($o->{bwDiff}) >= 10;
  join('・', @x) };
my $ev_of = sub { my $n = shift; grep { index($_, $n) >= 0 } @{$res->{events} || []} };
# 勝ち馬
if ($win) {
  my @why; my $r4 = ($win->{last4} && $heads) ? $win->{last4} / $heads : undef; my $fr = $f3rank{$win->{name}};
  push @why, '後方から上がり最速で差し切った(末脚の切れ)' if defined $r4 && $r4 > 0.5 && $fr && $fr == 1;
  push @why, '好位〜中団から上がり上位で抜け出した' if defined $r4 && $r4 > 0.3 && $r4 <= 0.5 && $fr && $fr <= 3;
  push @why, '好位〜中団で運び、前の馬が止まったところを抜け出した' if defined $r4 && $r4 > 0.3 && $r4 <= 0.5 && $fr && $fr > 3 && $pace eq 'H';
  push @why, '前で運んでそのまま押し切った' . ($pace eq 'S' ? '(スローで楽に先行できた)' : $pace eq 'H' ? '(ハイペースでも止まらず、力が上)' : '') if defined $r4 && $r4 <= 0.3;
  push @why, 'ハイペースで前が止まり、後ろにいた分が有利だった' if $pace eq 'H' && defined $r4 && $r4 > 0.5;
  if ($winh) {
    push @why, "予想では「$winh->{style}」と見ていたが、実際は" . ($r4 <= 0.3 ? '前で' : '後ろで') . '運んだ(脚質の読み違い)'
      if defined $r4 && $winh->{style} && (($winh->{style} =~ /差し|追込/ && $r4 <= 0.3) || ($winh->{style} =~ /逃げ|先行/ && $r4 > 0.5));
    push @why, "予想時のメモ: " . memo_of($winh) if memo_of($winh) && $winh->{_prank} > 1;
  }
  my $m2 = @actual > 1 ? $actual[1]{margin} : ''; $m2 = '' if ($m2 // '') !~ /\S/;
  push @detail, "勝ち馬 $win->{name}(" . ($win->{pop} // '?') . '番人気・予想' . ($winh ? $winh->{_prank} : '?') . '位): ' . join('・', grep { length } $run_of->($win), $m2 ? '2着に' . ($m2 =~ m{^[\d\s/]+$} ? "${m2}馬身" : $m2) . '差' : ()) . (@why ? '。' . join('。', @why) : '');
}
# 予想時のメモ(note)から、前走と間隔の部分を短く出す
sub memo_of { my $h = shift; my @s = grep { /前走|中\d+週|連闘|休み|間隔|ぶり|昇級|初/ } split /・/, $h->{note} // ''; @s ? join('・', @s[0 .. ($#s < 1 ? $#s : 1)]) : '' }
# 負けた馬の理由(位置取り・ペース・末脚・出遅れ・馬体重・競走中の出来事)
my $lose_of = sub { my ($o, $h) = @_; my @why; my $r4 = ($o->{last4} && $heads) ? $o->{last4} / $heads : undef; my $fr = $f3rank{$o->{name}};
  if (($o->{rank} // '') !~ /^\d+$/) { push @why, "$o->{rank}" }
  else {
    my $s = secs($o->{time}); my $gap = defined $s && defined $wsec ? $s - $wsec : undef;
    push @why, '0.2秒差以内の惜敗で、展開や位置の差' if defined $gap && $gap <= 0.2;
    push @why, 'ハイペースを前で追いかけて最後に止まった' if $pace eq 'H' && defined $r4 && $r4 <= 0.4 && $fr && $fr > $heads * 0.4;
    push @why, 'スローで後ろすぎ、上がりを使っても届かなかった(位置取りの差)' if $pace eq 'S' && defined $r4 && $r4 > 0.5;
    push @why, '末脚は上位だったが位置が後ろだった' if $fr && $fr <= 3 && defined $r4 && $r4 > 0.4 && $pace ne 'S';
    push @why, '良い位置で運んだのに最後の伸びを欠いた(力負け・距離・調子を疑う)' if defined $r4 && $r4 <= 0.4 && $fr && $fr > $heads * 0.4 && $pace ne 'H' && !(defined $gap && $gap <= 0.2);
    push @why, '位置も末脚も足りず、力負け' if defined $r4 && $r4 > 0.4 && $fr && $fr > $heads / 2 && $pace ne 'S';
    # 通過順が3つ以上(1角から出ている)ときだけ出遅れと書く。2つ(3角・4角だけの短距離)なら道中の位置として書く
    my @cs = split /-/, $o->{pass} // ''; my $c1 = $cs[0];
    push @why, @cs >= 3 ? "予想は「$h->{style}」だったが最初のコーナーで${c1}番手。出遅れか行き脚がつかなかった" : "予想は「$h->{style}」だったが3角で${c1}番手と、道中の位置が予想より後ろ"
      if $c1 && $h && $h->{style} && $h->{style} =~ /逃げ|先行/ && $c1 > $heads / 2;
    push @why, "馬体重の大きな増減(" . ($o->{bwDiff} > 0 ? '+' : '') . "$o->{bwDiff}kg)" if defined $o->{bwDiff} && abs($o->{bwDiff}) >= 10;
  }
  push @why, "競走中の出来事: $_" for $ev_of->($o->{name});
  @why };
# ◎が負けた理由
if ($honfin && ($honfin->{rank} // '') ne '1') {
  my @why = $lose_of->($honfin, $hon);
  push @detail, "◎$honfin->{name}は$honfin->{rank}着: " . join('・', grep { length } $run_of->($honfin)) . (@why ? '。' . join('。', @why) : '。数字の上では目立った不利は無く、勝ち馬との力の差');
}
# 予想上位の大敗・予想下位の好走
for my $h (@pred[1 .. ($#pred < 2 ? $#pred : 2)]) { my $o = $fin{$h->{name}} or next; next unless ($o->{rank} // '') !~ /^\d+$/ || $o->{rank} > $heads / 2;
  my @why = $lose_of->($o, $h); push @detail, "$h->{_mark}$h->{name}は$o->{rank}着と大敗: " . join('・', grep { length } $run_of->($o)) . (@why ? '。' . join('。', @why) : '') }
for my $o (@actual[1 .. ($#actual < 2 ? $#actual : 2)]) { my $h = $by{$o->{name}} or next; next unless $h->{_prank} >= 6;
  push @detail, "予想$h->{_prank}位の$o->{name}が$o->{rank}着(" . ($o->{pop} // '?') . "番人気): " . join('・', grep { length } $run_of->($o)) . (memo_of($h) ? "。予想時のメモ: " . memo_of($h) : '') }
# 競走中の出来事(上で触れていないもの。出走制限のお知らせは除く)
my %said = map { $_ => 1 } map { /競走中の出来事: (.*)/ ? $1 : () } @detail;
push @detail, "競走中の出来事: $_" for grep { !$said{$_} && !/出走制限|出走できない/ } @{$res->{events} || []};

my $starred = $race->{star} ? JSON::PP::true : JSON::PP::false;
my %review = (
  at => do { my @t = gmtime(time + 9 * 3600); sprintf('%04d-%02d-%02dT%02d:%02d:00+09:00', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]) },
  marks => [map { { mark => $_->{_mark}, name => $_->{name}, rank => ($fin{$_->{name}} ? $fin{$_->{name}}{rank} : undef) } } grep { $_->{_mark} } @pred],
  top3 => [map { { rank => $_->{rank}, name => $_->{name}, pop => $_->{pop}, predRank => ($by{$_->{name}} ? $by{$_->{name}}{_prank} : undef) } } @actual[0 .. ($#actual < 2 ? $#actual : 2)]],
  honmeiRank => ($honr =~ /^\d+$/ ? $honr + 0 : undef), hits3 => $hits + 0,
  win => (($honr // '') eq '1' ? JSON::PP::true : JSON::PP::false),
  place => (($honr =~ /^\d+$/ && $honr <= 3) ? JSON::PP::true : JSON::PP::false),
  star => $starred, diff => \@diff, next => \@next, (@detail ? (detail => \@detail) : ()),
  basis => '能力値と脚質・枠の補正から計算した順位(オッズは混ぜない)で比較',
);
my @rows = map { my $h = $_; my $f = $fin{$h->{name}};
  { raceId => $race->{id}, date => $race->{date}, place => $race->{place}, surface => $race->{surface}, dist => $race->{dist}, grade => ($race->{grade} // ''),
    name => $h->{name}, style => $h->{style}, umaban => $h->{umaban}, heads => $heads,
    (map { ($_->[0] => $h->{$_->[0]}) } @FAC), odds => $h->{odds}, predRank => $h->{_prank},
    rank => ($f && ($f->{rank} // '') =~ /^\d+$/ ? $f->{rank} + 0 : undef), pop => ($f ? $f->{pop} : undef) } } @hs;
print JSON::PP->new->canonical->pretty->encode({ review => \%review, result => { order => [map { { rank => $_->{rank}, name => $_->{name}, pop => $_->{pop}, odds => $_->{odds} } } @actual] }, rows => \@rows });
