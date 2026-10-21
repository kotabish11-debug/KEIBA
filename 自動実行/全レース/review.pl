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
my %W = (jisseki => .35, kyori => .15, course => .15, choshi => .20, kishu => .15);
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

my $starred = $race->{star} ? JSON::PP::true : JSON::PP::false;
my %review = (
  at => do { my @t = gmtime(time + 9 * 3600); sprintf('%04d-%02d-%02dT%02d:%02d:00+09:00', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]) },
  marks => [map { { mark => $_->{_mark}, name => $_->{name}, rank => ($fin{$_->{name}} ? $fin{$_->{name}}{rank} : undef) } } grep { $_->{_mark} } @pred],
  top3 => [map { { rank => $_->{rank}, name => $_->{name}, pop => $_->{pop}, predRank => ($by{$_->{name}} ? $by{$_->{name}}{_prank} : undef) } } @actual[0 .. ($#actual < 2 ? $#actual : 2)]],
  honmeiRank => ($honr =~ /^\d+$/ ? $honr + 0 : undef), hits3 => $hits + 0,
  win => (($honr // '') eq '1' ? JSON::PP::true : JSON::PP::false),
  place => (($honr =~ /^\d+$/ && $honr <= 3) ? JSON::PP::true : JSON::PP::false),
  star => $starred, diff => \@diff, next => \@next,
  basis => '能力値と脚質・枠の補正から計算した順位(オッズは混ぜない)で比較',
);
my @rows = map { my $h = $_; my $f = $fin{$h->{name}};
  { raceId => $race->{id}, date => $race->{date}, place => $race->{place}, surface => $race->{surface}, dist => $race->{dist}, grade => ($race->{grade} // ''),
    name => $h->{name}, style => $h->{style}, umaban => $h->{umaban}, heads => $heads,
    (map { ($_->[0] => $h->{$_->[0]}) } @FAC), odds => $h->{odds}, predRank => $h->{_prank},
    rank => ($f && ($f->{rank} // '') =~ /^\d+$/ ? $f->{rank} + 0 : undef), pop => ($f ? $f->{pop} : undef) } } @hs;
print JSON::PP->new->canonical->pretty->encode({ review => \%review, result => { order => [map { { rank => $_->{rank}, name => $_->{name}, pop => $_->{pop}, odds => $_->{odds} } } @actual] }, rows => \@rows });
