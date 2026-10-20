# 競馬ラボの馬柱ページ1つから、シミュレーター用のレースデータ(JSON)を作る。能力値はデータから自動で計算する
# 使い方: perl race_json.pl <umabashira.html> <競馬ラボのレースID> > out.json
# 重賞(G1・G2・G3・J重賞)は Claude が判断材料を見て能力値を付けるので、ここでは作らない(終了コード 3)
# 出走馬が出ていないページは終了コード 2
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;

my ($file, $kid) = @ARGV;
open my $fh, '<:utf8', $file or die "cannot open $file";
local $/; my $h = <$fh>;

sub txt { my $t = shift // ''; $t =~ s/<[^>]*>//g; $t =~ s/&nbsp;/ /g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub sect { my $n = shift; return $1 if $h =~ /<!-- \Q$n\E -->(.*?)<!-- /s; '' }
sub clamp { my ($v, $lo, $hi) = @_; $v < $lo ? $lo : $v > $hi ? $hi : $v }
# 行の中の一番外側の <td> だけを取り出す(前走欄は td の中に表があるため)
sub top_tds {
  my $s = shift; my @cells; my ($depth, $start) = (0, -1);
  while ($s =~ /<(\/?)(td|table)\b[^>]*>/g) {
    my ($close, $tag) = ($1, $2); my $pos = pos($s);
    if ($tag eq 'table') { $depth += $close ? -1 : 1; next }
    next if $depth > 0;
    if (!$close) { $start = $pos }
    elsif ($start >= 0) { push @cells, substr($s, $start, $pos - length($&) - $start); $start = -1 }
  }
  return @cells;
}

# ---- レース情報 ----
my ($title) = $h =~ /<title>([^<|]*)/; $title //= '';
exit 2 if $title =~ /レース一覧/ || $title eq '';
# 重賞の判定: タイトルには格が無いので、本文の「レース名 (ＧⅠ)」の表記で見る
my $body = txt($h);
my $grade = '';
if ($body =~ /[(（]\s*(Ｊ・|J・|Ｊ|J)?\s*(ＧⅠ|ＧⅡ|ＧⅢ|GⅠ|GⅡ|GⅢ|GIII|GII|GI|Ｇ１|Ｇ２|Ｇ３|JpnⅠ|JpnⅡ|JpnⅢ)\s*[)）]/) {
  my %g = ('ＧⅠ' => 'GI', 'GⅠ' => 'GI', 'GI' => 'GI', 'Ｇ１' => 'GI', 'ＧⅡ' => 'GII', 'GⅡ' => 'GII', 'GII' => 'GII', 'Ｇ２' => 'GII', 'ＧⅢ' => 'GIII', 'GⅢ' => 'GIII', 'GIII' => 'GIII', 'Ｇ３' => 'GIII');
  $grade = ($1 ? 'J・' : '') . ($g{$2} // $2);
}
exit 3 if $grade;
my ($rname) = $title =~ /^\s*(.*?)【/; $rname //= $title; $rname =~ s/^サラ系//; $rname =~ s/の馬柱$//; $rname =~ s/(出馬表|、予想).*$//; $rname =~ s/\s+$//;
my ($y, $mo, $d, $place, $no) = $title =~ /【(\d{4})年(\d{1,2})月(\d{1,2})日(\D+?)(\d{1,2})R】/;
exit 2 unless $y;
my $date = sprintf('%04d-%02d-%02d', $y, $mo, $d);
my $page = txt($h);
my ($surf, $dist, $heads, $time) = $page =~ /(芝|ダ|障)(?:\S*?)(\d{3,4})m (\d+)頭 ?(\d{1,2}:\d{2})発走/;
$surf //= '芝'; $dist //= 0; $time //= '';
my $straight = $page =~ /直(?:線)?\s*1000m|直1000/ ? 1 : 0;
my %dirs = ('東京' => '左', '新潟' => '左', '京都' => '右', '中山' => '右', '阪神' => '右', '中京' => '左', '福島' => '右', '小倉' => '右', '札幌' => '右', '函館' => '右');
my $dir = $straight ? '直' : ($dirs{$place} // '');
my ($weight_rule) = $page =~ /(定量|別定|馬齢|ハンデ)/; $weight_rule //= '';
my ($cls) = $page =~ /(\d歳(?:以上|上)?(?:新馬|未勝利|\d勝クラス|オープン)|障害\S*?(?:未勝利|オープン))/; $cls //= '';
my $cond = join(' ', grep { $_ ne '' } $cls, $weight_rule);
my ($baba) = $page =~ /\| ?(良|稍重|重|不良) ?\|/;

# ---- 出走馬 ----
my $nm = sect('馬名等');
my %seen; my @names = grep { !$seen{$_}++ } ($nm =~ /data-hsnm="([^"]+)"/g);
my $n = @names; exit 2 if $n < 2;
sub row { my $s = sect(shift); my @c = map { txt($_) } top_tds($s); return @c[-$n .. -1] if @c >= $n; return () }
my @umaban = row('馬番'); my @waku = row('枠番');
my @jockey = row('騎手'); my @kin = row('斤量'); my @odds = row('単勝'); my @bw = row('馬体重');
my @intv = row('間隔'); my @omega = row('Ω指数'); my @sexage = row('性·齢');
my @jc = row('騎手コース');
# 成績表(距離・コース・馬場): 1頭に1つの小さな表。列ごとに [1着,2着,3着,着外]
sub rec_tables {
  my $s = sect(shift); my @out;
  for my $cell (top_tds($s)) {
    if ($cell =~ /<table class="ResultBox[^"]*">(.*?)<\/table>/s) {
      my $t = $1; my @hd = map { txt($_) } ($t =~ /<th>(.*?)<\/th>/sg); my @rows;
      while ($t =~ /<tr>\s*(<td>.*?)<\/tr>/sg) { push @rows, [map { txt($_) } ($1 =~ /<td>(.*?)<\/td>/sg)] }
      my %r; for my $c (0 .. $#hd) { $r{$hd[$c]} = [map { $_->[$c] // 0 } @rows] } push @out, \%r;
    } else { push @out, undef }
  }
  return @out[-$n .. -1] if @out >= $n; return (undef) x $n;
}
my @rdist = rec_tables('距離'); my @rcourse = rec_tables('コース'); my @rgoing = rec_tables('馬場状態');
# 前走(最大5走): 着順・頭数・4角の位置・レース名
my @zen = map { [] } 1 .. $n;
for my $k (1 .. 5) {
  last unless $h =~ /<tr class="zensou$k">(.*?)(?=<tr class="zensou|<!-- )/s; my $s = $1;
  my @c = top_tds($s); next if @c < $n; @c = @c[-$n .. -1];
  for my $i (0 .. $n - 1) {
    my $cell = $c[$i]; next unless $cell =~ /cyakuJun/;
    my ($rank) = $cell =~ /class="cyakuJun[^"]*">\s*(\d+)/;
    my ($hd, $pu) = $cell =~ /(\d+)頭(\d+)番/;
    my ($psurf, $pdist, $pgoing) = $cell =~ /<li>\s*(芝|ダ|障)(\d+)\S*?(良|稍|重|不)\S*\s*<\/li>/;
    $pdist *= 100 if defined $pdist && $pdist < 100;
    my ($pplace) = $cell =~ /daybaba">\s*<li>\s*\d*(\D+?)\d*\s*<\/li>/;
    # 着差: 勝ち馬なら2着との差、負けた馬なら勝ち馬との差(秒)
    my ($pmargin) = $cell =~ /class="std11">\s*[^<\d(]+\(\s*(\d+(?:\.\d+)?)\s*\)\s*<\/td>/;
    my ($pass) = $cell =~ /class="zensou std11"><span[^>]*>\s*(.*?)\s*<\/span>/s;
    my ($rn) = $cell =~ /class="zensoname">\s*([^<]*?)\s*</s;
    my %circ; my @cc = split //, '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$cc[$_]} = $_ + 1 for 0 .. $#cc;
    my @pos = map { $circ{$_} } grep { exists $circ{$_} } split //, ($pass // '');
    push @{$zen[$i]}, { rank => $rank, heads => $hd, last => $pos[-1], first => $pos[0], umaban => $pu, surf => $psurf, dist => $pdist, going => $pgoing, place => $pplace, margin => $pmargin, race => $rn // '' };
  }
}
# 脚質マーク(逃・先・差・追の順に▲が付く)
my @legs; while ($nm =~ /<ul class="dbrunstyle2 legs">(.*?)<\/ul>/sg) { push @legs, [map { txt($_) } ($1 =~ /<li[^>]*>(.*?)<\/li>/sg)] }

my @STY = ('逃げ', '先行', '差し', '追込');
sub rate { my $r = shift; return (undef, 0) unless $r; my ($w, $p2, $p3, $o) = map { $_ // 0 } @$r; my $runs = $w + $p2 + $p3 + $o; return (undef, 0) unless $runs; return (($w + 0.7 * $p2 + 0.5 * $p3) / $runs, $runs) }
my @valid_omega = grep { /^\d+$/ } @omega;
my @so = sort { $a <=> $b } @valid_omega; my $med = @so ? $so[int(@so / 2)] : 80;
my @horses;
for my $i (0 .. $n - 1) {
  my $name = $names[$i];
  my $om = ($omega[$i] // '') =~ /^(\d+)$/ ? $1 : $med - 5;
  my $jisseki = clamp(int($om - 8 + 0.5), 40, 95);
  my ($dr, $dn) = rate($rdist[$i] ? $rdist[$i]{'当該'} : undef);
  my $kyori = defined $dr ? clamp(int(60 + 32 * $dr + 0.5), 50, 92) : 66;
  # コース成績は表の最後の列(この競馬場のこの馬場)
  my $ctab = $rcourse[$i]; my $cr; my $cn = 0;
  if ($ctab) { my @keys = grep { $_ ne '全' && $_ !~ /^全/ } keys %$ctab; my ($last) = grep { /^\Q@{[substr($place,0,1)]}\E/ } @keys; ($cr, $cn) = rate($ctab->{$last // ''}) }
  my $course = defined $cr ? clamp(int(60 + 32 * $cr + 0.5), 50, 92) : 66;
  my $z = $zen[$i]; my $choshi = 65;
  if (@$z && $z->[0]{rank}) { my $r = $z->[0]{rank}; $choshi = $r == 1 ? 90 : $r == 2 ? 84 : $r == 3 ? 80 : $r <= 5 ? 74 : $r <= 9 ? 64 : 56 }
  # 着順だけでなく着差も見る: 掲示板外でも勝ち馬と0.3秒差以内なら力は近い / 2・3着でも1秒以上離されたら中身は薄い / 0.5秒以上の完勝は上積み
  my $zm = (@$z && defined $z->[0]{margin}) ? $z->[0]{margin} : undef; my $mnote = '';
  if (defined $zm && $z->[0]{rank}) {
    my $r = $z->[0]{rank};
    if ($r == 1 && $zm >= 0.5) { $choshi += 2; $mnote = "前走${zm}秒差の完勝(+2)" }
    elsif ($r >= 4 && $zm <= 0.3) { $choshi += 4; $mnote = "前走${r}着でも勝ち馬と${zm}秒差(+4)" }
    elsif ($r >= 4 && $zm <= 0.5) { $choshi += 2; $mnote = "前走${r}着でも勝ち馬と${zm}秒差(+2)" }
    elsif ($r >= 2 && $r <= 3 && $zm >= 1.0) { $choshi -= 4; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-4)" }
    elsif ($r >= 2 && $r <= 3 && $zm >= 0.6) { $choshi -= 2; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-2)" }
  }
  my $iv = $intv[$i] // ''; my ($wk) = $iv =~ /中(\d+)週/;
  $choshi -= 6 if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
  $choshi -= 3 if defined $wk && $wk >= 26;   # 半年以上の休み明けは、人気でも勝ち切れないことが多い
  my ($jr, $jn) = ($jc[$i] // '') =~ /([\d.]+)%\s*\[(\d+)\]/;
  my $kishu = (defined $jn && $jn >= 5) ? clamp(int(58 + 0.8 * $jr + 0.5), 55, 92) : 66;
  # 脚質: 前走の4角位置の平均。無ければ脚質マーク
  my @ratios = map { $_->{last} / $_->{heads} } grep { $_->{last} && $_->{heads} } @$z;
  my $style;
  if (@ratios) { my $m = 0; $m += $_ for @ratios; $m /= @ratios; $style = $m <= 0.12 ? '逃げ' : $m <= 0.35 ? '先行' : $m <= 0.7 ? '差し' : '追込' }
  elsif ($legs[$i]) { for my $k (0 .. 3) { if (($legs[$i][$k] // '') eq '▲') { $style = $STY[$k]; last } } }
  $style //= '差し';
  my $heavy = 0; my $g = $rgoing[$i];
  if ($g) { my ($w, $p, $runs) = (0, 0, 0); for my $k (keys %$g) { next unless $k =~ /稍|重|不/; my ($a, $b, $c, $o) = map { $_ // 0 } @{$g->{$k}}; $w += $a; $p += $a + $b + $c; $runs += $a + $b + $c + $o }
    $heavy = $w >= 1 ? 2 : ($runs >= 1 && $p / $runs >= 0.4) ? 1 : ($runs >= 2 && $p == 0) ? -1 : 0 }
  my $od = ($odds[$i] // '') =~ /^([\d.]+)/ ? $1 + 0 : undef;
  my @notes = ("Ω指数 " . (($omega[$i] // '') =~ /^\d+$/ ? $omega[$i] : 'なし'));
  push @notes, "前走 $z->[0]{race} $z->[0]{rank}着" if @$z && $z->[0]{rank};
  push @notes, $mnote if $mnote;
  push @notes, "初出走" unless @$z;
  push @notes, "休み明け($iv)" if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
  push @notes, "騎手のこのコース連対率 $jr%" if defined $jn && $jn >= 5;
  my %hh = (name => $name, jockey => ($jockey[$i] // '未定'), style => $style,
    jisseki => $jisseki, kyori => $kyori, course => $course, choshi => clamp($choshi, 40, 95), kishu => $kishu, heavy => $heavy,
    note => join('・', @notes) . '(自動計算)');
  my $u = ($umaban[$i] // '') =~ /^(\d+)$/ ? $1 + 0 : undef; $hh{umaban} = $u;
  $hh{waku} = $1 + 0 if ($waku[$i] // '') =~ /^(\d+)$/;
  if (defined $od) { $hh{odds} = $od; $hh{oddsKari} = JSON::PP::false } else { $hh{oddsKari} = JSON::PP::true }
  if (($bw[$i] // '') =~ /^(\d{3})\s*\(\s*([＋－+\-]?)\s*(\d+)\s*\)/) { $hh{weight} = $1 + 0; my $s = ($2 eq '－' || $2 eq '-') ? -1 : 1; $hh{weightDiff} = $s * $3 }
  # 新馬戦は馬格のある馬が有利(ダートは500kg以上と460kg未満で差が大きい。芝は460kgが境目)
  if ($cls =~ /新馬/ && defined $hh{weight}) {
    my $wt = $hh{weight}; my $adj = 0;
    if ($surf eq 'ダ') { $adj = $wt >= 500 ? 3 : $wt < 460 ? -3 : 0 } else { $adj = $wt < 460 ? -2 : 0 }
    if ($adj) { $hh{jisseki} = clamp($hh{jisseki} + $adj, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・新馬で馬体重${wt}kg(${\($adj > 0 ? '+' : '')}$adj)$1/ }
  }
  # 馬体重の増減: 大きく動いた馬は嫌われてオッズが上がるので、はっきり悪いサインのときだけ割り引く
  #  -20kg以上は成績が大きく落ちる / 2・3歳のマイナス2桁(成長期に減る)/ 夏(6〜9月)や滞在競馬(北海道・小倉)で減る / 6歳以上の大幅増(太め残り)
  if (defined $hh{weightDiff}) {
    my $wd = $hh{weightDiff}; my ($age) = ($sexage[$i] // '') =~ /(\d+)$/; $age //= 0; my $wadj = 0; my @ww;
    if ($wd <= -20) { $wadj -= 4; push @ww, "馬体重${wd}kg" }
    elsif ($wd <= -10) {
      if ($age >= 2 && $age <= 3) { $wadj -= 2; push @ww, "2〜3歳で馬体重${wd}kg" }
      if ($mo >= 6 && $mo <= 9) { $wadj -= 1; push @ww, '夏に減少' }
      if ($place =~ /^(札幌|函館|小倉)$/) { $wadj -= 1; push @ww, '滞在競馬で減少' }
    }
    if ($wd >= 10 && $age >= 6) { $wadj -= 2; push @ww, "${age}歳で馬体重+${wd}kg(太め残りの恐れ)" }
    if ($wadj) { $hh{choshi} = clamp($hh{choshi} + $wadj, 40, 95); my $w = join('・', @ww); $hh{note} =~ s/(\(自動計算\))$/・${w}($wadj)$1/ }
  }
  # 馬格: 大きい馬ほど成績も回収率も良い(400kg未満の複勝率約7%、500kg台は約25%)。新馬戦は上で別に見ている
  if ($cls !~ /新馬/ && defined $hh{weight}) {
    my $wt = $hh{weight}; my $sz = $wt < 420 ? -2 : $wt >= 500 ? 1 : 0;
    if ($sz) { $hh{jisseki} = clamp($hh{jisseki} + $sz, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・馬体重${wt}kg(${\($sz > 0 ? '+' : '')}$sz)$1/ }
  }
  # 展開の材料: 近3走で2回以上1角先頭なら「逃げにこだわる馬」、前走より200m以上の延長で逃げ・先行なら「短い距離からの延長組」(前半が速くなりやすい)
  if (@$z) {
    my @r3 = @{$z}[0 .. ($#$z < 2 ? $#$z : 2)];
    $hh{mustLead} = JSON::PP::true if (grep { ($_->{first} // 0) == 1 } @r3) >= 2;
    $hh{fromShort} = JSON::PP::true if $z->[0]{dist} && $dist - $z->[0]{dist} >= 200 && $style =~ /逃げ|先行/;
  }
  # 危険な人気馬の条件(前走の好走が条件に恵まれたもの)と、その逆の巻き返し
  if (@$z && $z->[0]{rank}) {
    my $p = $z->[0]; my $r = $p->{rank}; my @why; my $adj = 0;
    # 前走逃げて好走: 同じ形を再現できるとは限らない(同型がいればさらに不利。下でまとめて引く)
    if (($p->{first} // 0) == 1 && $r <= 3) { $adj -= 2; push @why, '前走逃げて好走'; $hh{_prevLead} = 1 }
    # 前走の道悪で好走 → 今回良馬場 / 前走の道悪で凡走 → 今回良馬場
    if (defined $baba && $baba eq '良' && ($p->{going} // '') =~ /^(重|不)$/) {
      if ($r <= 3) { $adj -= 3; push @why, '前走は道悪で好走・今回は良' } elsif ($r >= 6) { $adj += 2; push @why, '前走は道悪で凡走・今回は良' }
    }
    # 枠の替わり: 芝は内→外が不利、ダートは外→内が不利(砂をかぶる)。逆は巻き返し
    my $u = $hh{umaban};
    if (defined $u && $p->{umaban} && $p->{heads} && ($p->{surf} // '') eq $surf && $surf ne '障') {
      my $pin = $p->{umaban} <= $p->{heads} * 0.3; my $pout = $p->{umaban} > $p->{heads} * 0.7;
      my $nin = $u <= $n * 0.3; my $nout = $u > $n * 0.7;
      my ($good_from, $good_to) = $surf eq '芝' ? ($pin, $nout) : ($pout, $nin);
      my ($bad_from, $bad_to) = $surf eq '芝' ? ($pout, $nin) : ($pin, $nout);
      if ($good_from && $good_to && $r <= 3) { $adj -= 3; push @why, $surf eq '芝' ? '前走内枠で好走・今回外枠' : '前走外枠で好走・今回内枠' }
      elsif ($bad_from && $bad_to && $r >= 4) { $adj += 2; push @why, $surf eq '芝' ? '前走外枠で凡走・今回内枠' : '前走内枠で凡走・今回外枠' }
    }
    # 距離ローテ: 東京芝1400は前走1600m以上からの短縮が好成績・1200m以下からの延長は不振。東京ダ1600は短縮が好成績
    my $pd = $p->{dist};
    if ($pd && $place eq '東京' && $surf eq '芝' && $dist == 1400) {
      if ($pd >= 1600) { $adj += 2; push @why, "前走${pd}mから短縮" } elsif ($pd <= 1200) { $adj -= 2; push @why, "前走${pd}mから延長" }
    }
    if ($pd && $place eq '東京' && $surf eq 'ダ' && $dist == 1600 && $pd >= 1700) { $adj += 2; push @why, "前走${pd}mから短縮" }
    if ($pd && $place eq '東京' && $surf eq 'ダ' && $dist == 1600 && $pd <= 1200) { $adj -= 2; push @why, "前走${pd}mから延長(最後の坂で止まりやすい)" }
    # 京都: 芝1400(外回り)は1600m以上からの短縮、芝2200は2400m以上からの短縮が好成績
    if ($pd && $place eq '京都' && $surf eq '芝' && !$straight) {
      if ($dist == 1400 && $pd >= 1600) { $adj += 2; push @why, "前走${pd}mから短縮" }
      if ($dist == 2200 && $pd >= 2400) { $adj += 2; push @why, "前走${pd}mから短縮" }
    }
    # 阪神(直線に急坂)で前に行って止まった馬が、平坦な京都の直線なら粘れる
    if ($place eq '京都' && ($p->{place} // '') eq '阪神' && ($p->{first} // 99) <= 3 && $r >= 4 && $r <= 9 && ($p->{surf} // '') eq $surf) { $adj += 2; push @why, '前走阪神の坂で失速・今回平坦' }
    # 競馬場のタイプ替わり(直線の坂・コースの広さ)。好走した舞台と今回で求められる適性が違えば割り引き、逆なら巻き返し
    my $pp = $p->{place} // '';
    if ($pp && $pp ne $place && ($p->{surf} // '') eq $surf && $surf ne '障') {
      my %steep = map { $_ => 1 } qw(中山 阪神 中京); my %flat = map { $_ => 1 } qw(京都 新潟 小倉 函館 札幌 福島);
      my %big = map { $_ => 1 } qw(東京 阪神 京都 新潟); my %small = map { $_ => 1 } qw(中山 中京 福島 小倉 函館 札幌);
      if ($r <= 3 && $flat{$pp} && $steep{$place}) { $adj -= 2; push @why, "前走は平坦の${pp}で好走・今回は急坂" }
      elsif ($r >= 4 && $r <= 9 && $steep{$pp} && $flat{$place} && !grep { /阪神の坂/ } @why) { $adj += 1; push @why, "前走は急坂の${pp}で凡走・今回は平坦" }
      if ($r <= 3 && $small{$pp} && $big{$place}) { $adj -= 1; push @why, "前走は小回りの${pp}で好走・今回は大箱" }
    }
    # 同じ場でスタートが後ろにずれて1角まで長くなる距離(ダ1800→1900など)は、短い方で届かなかった差し馬が届く
    if ($pd && ($p->{place} // '') eq $place && ($p->{surf} // '') eq $surf && $p->{last} && $p->{heads} && $p->{last} / $p->{heads} > 0.35 && $r >= 2 && $r <= 6) {
      my %longer = ('中山芝1800' => 2000, '中京芝2000' => 2200, '中京ダ1800' => 1900, '京都ダ1800' => 1900, '阪神ダ1800' => 2000, '阪神芝2000' => 2200);
      my $to = $longer{"$place$surf$pd"};
      if ($to && $to == $dist) { $adj += 2; push @why, "前走${pd}mで差し届かず・今回1角まで長い${dist}m" }
    }
    $adj = clamp($adj, -5, 5);   # いくつ重なっても補正は±5まで
    if ($adj) { $hh{choshi} = clamp($hh{choshi} + $adj, 40, 95); my $w = join('・', @why); $hh{note} =~ s/(\(自動計算\))$/・${w}(${\($adj > 0 ? '+' : '')}$adj)$1/ }
  }
  # ダートの砂かぶり: 近5走のダートで、内枠から馬群の中(4角が前3割より後ろ)を通った走り
  #   好走(3着以内か勝ち馬と0.3秒差以内)があれば「砂をかぶっても走れる」→ 先行争いが激しくなる3勝クラス以上の差し・追込は +2
  #   凡走(6着以下で0.6秒以上)しかなく、今回も内枠の差し・追込なら「砂をかぶると崩れる」→ -2
  if ($surf eq 'ダ' && $style =~ /差し|追込/ && @$z) {
    my ($tough, $weak) = (0, 0);
    for my $p (@$z) {
      next unless ($p->{surf} // '') eq 'ダ' && $p->{umaban} && $p->{heads} && $p->{last} && $p->{rank};
      next unless $p->{umaban} <= $p->{heads} * 0.4 && $p->{last} > $p->{heads} * 0.3;
      if ($p->{rank} <= 3 || ($p->{margin} // 9) <= 0.3) { $tough++ } elsif ($p->{rank} >= 6 && ($p->{margin} // 0) >= 0.6) { $weak++ }
    }
    my $u = $hh{umaban}; my ($sa, $sw) = (0, '');
    if ($tough && $cls =~ /[3３]勝|オープン/) { $sa = 2; $sw = '内枠で砂をかぶっても好走歴・上のクラスで差しが届きやすい' }
    elsif (!$tough && $weak && defined $u && $n >= 10 && $u <= $n * 0.3) { $sa = -2; $sw = '内枠で砂をかぶって凡走歴・今回も内枠' }
    if ($sa) { $hh{choshi} = clamp($hh{choshi} + $sa, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・${sw}(${\($sa > 0 ? '+' : '')}$sa)$1/ }
  }
  push @horses, \%hh;
}
# 前走逃げて好走した馬は、ほかに逃げ馬がいるとマークされ、ペースも厳しくなりやすい
my $leaders = grep { $_->{style} eq '逃げ' } @horses;
for my $x (@horses) {
  next unless delete $x->{_prevLead};
  if ($leaders >= 2) { $x->{choshi} = clamp($x->{choshi} - 2, 40, 95); $x->{note} =~ s/(\(自動計算\))$/・逃げ馬がほかにもいる(-2)$1/ }
}
# 仮オッズ: オッズがまだ無い馬は、能力値から人気を想定して付ける(1/オッズの合計が約1.25)
my %W = (jisseki => .35, kyori => .15, course => .15, choshi => .20, kishu => .15);
my @score = map { my $x = $_; my $s = 0; $s += $W{$_} * $x->{$_} for keys %W; $s } @horses;
my @e = map { exp($_ / 4) } @score; my $sum = 0; $sum += $_ for @e;
for my $i (0 .. $#horses) { next if defined $horses[$i]{odds}; my $p = $e[$i] / $sum * 1.25; $horses[$i]{odds} = clamp(int(1 / $p * 10 + 0.5) / 10, 1.2, 300) }
@horses = sort { ($a->{umaban} // 99) <=> ($b->{umaban} // 99) } @horses;

my $chaos = 8.5; $chaos = 9.5 if $cls =~ /2歳|新馬/ || $weight_rule eq 'ハンデ'; $chaos = 9 if $surf eq '障';
my $nowj = do { my @t = gmtime(time + 9 * 3600); sprintf('%04d-%02d-%02dT%02d:%02d:00+09:00', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]) };
my %doc = (id => "k$kid", name => $rname, grade => '', date => $date, place => $place, no => $no + 0, time => $time,
  surface => $surf, dist => $dist + 0, dir => $dir, courseNote => ($straight ? '直線' : ''), cond => $cond,
  stage => ((grep { defined $_->{umaban} } @horses) ? '枠順確定' : '出走確定'), chaos => $chaos,
  weather => '', going => (defined $baba ? {'良' => 0, '稍重' => 1, '重' => 2, '不良' => 3}->{$baba} : undef),
  updatedAt => $nowj, source => '競馬ラボ(能力値は自動計算)', memo => '全レース自動追加。能力値はΩ指数・距離/コース成績・前走・騎手のコース連対率から自動で計算',
  auto => JSON::PP::true, keibalabId => "$kid", horses => \@horses);
print JSON::PP->new->canonical->pretty->encode(\%doc);
