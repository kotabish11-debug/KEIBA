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
    my ($hd) = $cell =~ /(\d+)頭\d+番/;
    my ($pass) = $cell =~ /class="zensou std11"><span[^>]*>\s*(.*?)\s*<\/span>/s;
    my ($rn) = $cell =~ /class="zensoname">\s*([^<]*?)\s*</s;
    my %circ; my @cc = split //, '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$cc[$_]} = $_ + 1 for 0 .. $#cc;
    my @pos = map { $circ{$_} } grep { exists $circ{$_} } split //, ($pass // '');
    push @{$zen[$i]}, { rank => $rank, heads => $hd, last => $pos[-1], race => $rn // '' };
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
  my $iv = $intv[$i] // ''; my ($wk) = $iv =~ /中(\d+)週/;
  $choshi -= 6 if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
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
  push @horses, \%hh;
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
