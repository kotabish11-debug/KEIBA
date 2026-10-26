# 競馬ラボの馬柱ページ1つから、シミュレーター用のレースデータ(JSON)を作る。能力値はデータから自動で計算する
# 使い方: perl race_json.pl <umabashira.html> <競馬ラボのレースID> > out.json
#   keibalab.jp に接続できないときは、スポーツナビから作った素データ(yahoo.pl raw の出力、拡張子 .json)を馬柱の代わりに渡せる
#   JRA公式から作った素データ(jra.pl raw の出力、src が jra)も同じ形で渡せる
# 重賞(G1・G2・G3・J重賞)は Claude が判断材料を見て能力値を付けるので、ここでは作らない(終了コード 3)
# 出走馬が出ていないページは終了コード 2
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;

my ($file, $kid) = @ARGV;
open my $fh, '<:utf8', $file or die "cannot open $file";
local $/; my $h = <$fh>;
my $RAW = $file =~ /\.json$/ ? JSON::PP->new->decode($h) : undef;
my $SRCN = $RAW && ($RAW->{src} // "") eq "jra" ? "JRA公式" : "スポーツナビ";

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
exit 2 if !$RAW && ($title =~ /レース一覧/ || $title eq '');
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
exit 2 unless $y || $RAW;
my $date = $RAW ? '' : sprintf('%04d-%02d-%02d', $y, $mo, $d);
my $page = txt($h);
my ($surf, $dist, $heads, $time) = $page =~ /(芝|ダ|障)(?:\S*?)(\d{3,4})m (\d+)頭 ?(\d{1,2}:\d{2})発走/;
$surf //= '芝'; $dist //= 0; $time //= '';
my $straight = $page =~ /直(?:線)?\s*1000m|直1000/ ? 1 : 0;
my %dirs = ('東京' => '左', '新潟' => '左', '京都' => '右', '中山' => '右', '阪神' => '右', '中京' => '左', '福島' => '右', '小倉' => '右', '札幌' => '右', '函館' => '右');
my $dir = $straight ? '直' : ($dirs{$place // ''} // '');
my ($weight_rule) = $page =~ /(定量|別定|馬齢|ハンデ)/; $weight_rule //= '';
my ($cls) = $page =~ /(\d歳(?:以上|上)?(?:新馬|未勝利|\d勝クラス|オープン)|障害\S*?(?:未勝利|オープン))/; $cls //= '';
my $cond = join(' ', grep { $_ ne '' } $cls, $weight_rule);
my ($baba) = $page =~ /\| ?(良|稍重|重|不良) ?\|/;

# ---- 出走馬 ----
my $nm = sect('馬名等');
my %seen; my @names = grep { !$seen{$_}++ } ($nm =~ /data-hsnm="([^"]+)"/g);
my $n = @names; exit 2 if $n < 2 && !$RAW;
sub row { my $s = sect(shift); my @c = map { txt($_) } top_tds($s); return @c[-$n .. -1] if @c >= $n; return () }
my @umaban = row('馬番'); my @waku = row('枠番');
my @jockey = row('騎手'); my @kin = row('斤量'); my @odds = row('単勝'); my @bw = row('馬体重');
my @intv = row('間隔'); my @omega = row('Ω指数'); my @sexage = row('性·齢');
my @jc = row('騎手コース');
# 調教師×騎手の連対率: この行は後ろにコメントが付くので、見出し(th)で行を探す
my @tj; if ($h =~ /<tr[^>]*>((?:(?!<tr[\s>]).)*?<th>\s*調教師×)/s) { my @c = map { txt($_) } top_tds($1); @tj = @c[-$n .. -1] if @c >= $n }
# 騎手ごとの、脚質・性別で成績がはっきり変わる条件(過去3年。騎手の解説動画の要約で未検証。出典: 馬情報/騎手の得意・苦手.md)
#   コース・距離の得意不得意は「騎手のこのコース連対率」に入っているので、ここでは足さない
my %J_OIKOMI = ('西村淳' => -3, '丹内' => -3, 'ルメール' => -2, '坂井' => -2, '松山' => -2, '幸' => -2);   # 追込で勝つ割合がとても低い
my %J_HINBA = ('今村' => 2, '北村友' => -2);   # 牝馬で成績がはっきり上・下
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
    my ($ppace) = $cell =~ /<span class="bold (?:red|green|blue)">\s*([HMS])\s*</;   # 前走のペース(H・M・S)
    my ($ppop) = $cell =~ /<span>\s*(\d+)人\s*<\/span>/;   # 前走の人気
    my %circ; my @cc = split //, '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$cc[$_]} = $_ + 1 for 0 .. $#cc;
    my @pos = map { $circ{$_} } grep { exists $circ{$_} } split //, ($pass // '');
    push @{$zen[$i]}, { rank => $rank, heads => $hd, last => $pos[-1], first => $pos[0], umaban => $pu, surf => $psurf, dist => $pdist, going => $pgoing, place => $pplace, margin => $pmargin, pace => $ppace, pop => $ppop, race => $rn // '' };
  }
}
# 父(馬名等の欄で、馬名の後に母・父が並ぶ)
my %sire; { my $cur; while ($nm =~ /data-hsnm="([^"]+)"|class="chichi[^"]*"><span[^>]*>[^<]*<\/span>\s*([^<]*?)\s*</g) { if (defined $1) { $cur = $1 } elsif ($cur && !exists $sire{$cur}) { $sire{$cur} = $2 } } }
# 道悪(稍重〜不良)で産駒の成績がはっきり上がる(+1)・下がる(-1)種牡馬。過去3年の集計(YouTubeの動画、未検証)
my %SIRE_WET = (
  '芝' => { 'キズナ' => 1, 'モーリス' => 1, 'イスラボニータ' => 1, 'ファインニードル' => 1, 'シスキン' => 1,
            'キタサンブラック' => -1, 'レイデオロ' => -1, 'スワーヴリチャード' => -1, 'コントレイル' => -1 },
  'ダ' => { 'ナダル' => 1, 'パイロ' => 1, 'サンダースノー' => -1 });
# 国別タイプが米国型(本馬や産駒がアメリカのダートで実績)とはっきり言える種牡馬。仕上がりが早くダッシュ力があり、若駒のダート短距離に強い(亀谷敬正の動画、未検証)
# 種牡馬の国別タイプ(日本・米国・欧州)は 馬情報/種牡馬_国別タイプ.tsv から読む。確度が「?」の種牡馬は使わない
my %STYPE; { (my $dir = __FILE__) =~ s{[\\/][^\\/]*$}{}; $dir = '.' if $dir eq __FILE__; utf8::decode($dir);
  my $tf = "$dir/../../馬情報/種牡馬_国別タイプ.tsv"; utf8::encode($tf);
  local $/ = "\n"; if (open my $th, '<:encoding(UTF-8)', $tf) { <$th>; while (my $l = <$th>) { chomp $l; $l =~ s/\r$//; my ($s, $t, $sub, $cf) = split /\t/, $l; $STYPE{$s} = $t if $s && $t && $t ne '?' && ($cf // '') ne '?' } } }
my %SIRE_US = map { $_ => 1 } grep { $STYPE{$_} eq '米国' } keys %STYPE;
# 騎手の連対率の表(jockey_table.pl が全期間のデータから作る)。JRA公式・スポーツナビには騎手のコース連対率が無いので、これで騎手の点を作る
my (%JT, %JCT, $JG); { (my $dir = __FILE__) =~ s{[\\/][^\\/]*$}{}; $dir = '.' if $dir eq __FILE__; utf8::decode($dir);
  my $tf = "$dir/jockey.tsv"; utf8::encode($tf);
  local $/ = "\n"; if (open my $th, '<:encoding(UTF-8)', $tf) { while (my $l = <$th>) { chomp $l; $l =~ s/\r$//; my @c = split /\t/, $l;
    if ($c[0] eq 'G') { $JG = $c[1] } elsif ($c[0] eq 'J') { $JT{$c[1]} = [@c[2, 3]] } elsif ($c[0] eq 'C') { $JCT{$c[1]}{$c[2]} = [@c[3, 4]] } } } }
# ベイズ推定: 騎手の前の365日の連対率を全騎手の平均へ K=10回ぶん寄せ、そのコースの前の3年の連対率をその値へ k=200回ぶん寄せる。点は logit の差×18
#   (YouTube「はじめての統計学」のベイズ推定の回。2017〜2021で当てはめ、2022〜2026/3 の21万頭で、オッズ無しの勝ち馬の当たり方が
#    今の「コースの率をそのまま」の1.8倍。オッズがあるときの上乗せは0 = 騎手は市場に織り込み済み。自動実行/検証/jockey_eb.pl、馬情報/的中率を上げるための検証.md の18)
sub jockey_eb { my ($jk, $ck) = @_; return undef unless $JG; $jk =~ s/[\s▲△☆◇★]//g; $jk =~ s/^[A-Za-zＡ-Ｚａ-ｚ][.．]//;
  my $key = exists $JT{$jk} ? $jk : undef;
  unless ($key) { my @m = grep { index($_, $jk) == 0 || index($jk, $_) == 0 } keys %JT; $key = $m[0] if @m == 1 }
  my ($N, $W) = $key ? @{$JT{$key}} : (0, 0); my ($n, $w) = $key && $JCT{$key}{$ck} ? @{$JCT{$key}{$ck}} : (0, 0);
  my $m = ($W + 10 * $JG) / ($N + 10); my $r = ($w + 200 * $m) / ($n + 200);
  my $lg = sub { log($_[0] / (1 - $_[0])) }; return clamp(int(69 + 18 * ($lg->($r) - $lg->($JG)) + 0.5), 50, 95) }
# 母父(馬名の後に並ぶ「(母父)」)
my %damsire; { my $cur; while ($nm =~ /data-hsnm="([^"]+)"|class="tategaki hahachichi[^"]*">\s*(.*?)\s*<\/p>/sg) { if (defined $1) { $cur = $1 } elsif ($cur && !exists $damsire{$cur}) { (my $d = txt($2)) =~ s/[()（）]//g; $d =~ s/’/'/g; $damsire{$cur} = $d } } }
# 脚質マーク(逃・先・差・追の順に▲が付く)
my @legs; while ($nm =~ /<ul class="dbrunstyle2 legs">(.*?)<\/ul>/sg) { push @legs, [map { txt($_) } ($1 =~ /<li[^>]*>(.*?)<\/li>/sg)] }
# スポーツナビの素データ: 馬柱から読む値をそのまま入れる(Ω指数・騎手のコース連対率・調教師×騎手・前走の馬場とペースは無い)
if ($RAW) {
  ($rname, $date, $place, $no, $surf, $dist, $time, $weight_rule, $cls, $baba) = map { $RAW->{$_} // '' } qw(name date place no surface dist time weightRule cls baba);
  $baba = undef if $baba eq '';
  ($y, $mo, $d) = map { $_ + 0 } split /-/, $date; $straight = $RAW->{straight} ? 1 : 0; $dir = $straight ? '直' : ($dirs{$place} // '');
  $cond = join(' ', grep { $_ ne '' } $cls, $weight_rule);
  my @H = @{$RAW->{horses} || []}; $n = @H; exit 2 if $n < 2;
  my $col = sub { my $k = shift; map { $_->{$k} // '' } @H };
  @names = $col->('name'); @umaban = $col->('umaban'); @waku = $col->('waku'); @jockey = $col->('jockey'); @kin = $col->('kin');
  @odds = $col->('odds'); @bw = $col->('bw'); @intv = $col->('intv'); @omega = $col->('omega'); @sexage = $col->('sexage');
  @jc = map { '' } @H; @tj = ();
  @rdist = map { $_->{rdist} } @H; @rcourse = map { $_->{rcourse} } @H; @rgoing = map { undef } @H;
  @zen = map { $_->{zen} || [] } @H; @legs = ();
  %sire = map { ($_->{name} => $_->{sire}) } grep { $_->{sire} } @H; %damsire = map { ($_->{name} => $_->{damsire}) } grep { $_->{damsire} } @H;
}

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
    # 先読み競馬「着順でなくタイム差を見る(大敗でも差が小さい馬はなめられる)」: 2026年4〜10月の平場で前走6〜9着・0.6〜1.0秒差は市場の1.16倍(前半1.09・後半1.25、2,096頭)。1.1秒以上は0.83〜0.91倍、10着以下はぶれる
    elsif ($r >= 6 && $r <= 9 && $zm >= 0.6 && $zm <= 1.0) { $choshi += 1; $mnote = "前走${r}着でも勝ち馬と${zm}秒差(+1)" }
    elsif ($r >= 2 && $r <= 3 && $zm >= 1.0) { $choshi -= 4; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-4)" }
    elsif ($r >= 2 && $r <= 3 && $zm >= 0.6) { $choshi -= 2; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-2)" }
  }
  my $iv = $intv[$i] // ''; my ($wk) = $iv =~ /中(\d+)週/;
  $choshi -= 6 if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
  $choshi -= 3 if defined $wk && $wk >= 26;   # 半年以上の休み明けは、人気でも勝ち切れないことが多い
  # 中1週は疲れが残りやすい(バフェットの動画。2017〜2026/3の5.5万頭でも市場の0.94倍)。中3〜5週の +1 は2017年以降で1.00倍だったので外した(holdout_eval.pl)
  if (defined $wk) { $choshi -= 1 if $wk == 1 }
  my ($jr, $jn) = ($jc[$i] // '') =~ /([\d.]+)%\s*\[(\d+)\]/;
  my $kishu = (defined $jn && $jn >= 5) ? clamp(int(58 + 0.8 * $jr + 0.5), 55, 92) : 66;
  $kishu = jockey_eb($jockey[$i] // '', "$place$surf$dist") // $kishu if !defined $jn;
  # 脚質: 前走の4角位置の平均。無ければ脚質マーク
  my @ratios = map { $_->{last} / $_->{heads} } grep { $_->{last} && $_->{heads} } @$z;
  my $style;
  if (@ratios) { my $m = 0; $m += $_ for @ratios; $m /= @ratios; $style = $m <= 0.12 ? '逃げ' : $m <= 0.35 ? '先行' : $m <= 0.7 ? '差し' : '追込' }
  elsif ($legs[$i]) { for my $k (0 .. 3) { if (($legs[$i][$k] // '') eq '▲') { $style = $STY[$k]; last } } }
  $style //= '差し';
  # 騎手の補正(合計±5まで): 調教師×騎手の連対率(陣営が勝負馬を任せるコンビか)、騎手×脚質、騎手×性別
  my ($ja, @jw) = (0);
  my ($tr, $tn) = ($tj[$i] // '') =~ /([\d.]+)%\s*\[(\d+)\]/;
  if (defined $tn && $tn >= 10) {
    if ($tr >= 40) { $ja += 3; push @jw, "調教師×騎手の連対率${tr}%(+3)" }
    elsif ($tr >= 30) { $ja += 2; push @jw, "調教師×騎手の連対率${tr}%(+2)" }
    elsif ($tr <= 5 && $tn >= 15) { $ja -= 2; push @jw, "調教師×騎手の連対率${tr}%(-2)" }
  }
  my $jk = $jockey[$i] // ''; $jk =~ s/^[A-Za-z]\.//;
  for my $k (keys %J_OIKOMI) { if ($style eq '追込' && index($jk, $k) == 0) { $ja += $J_OIKOMI{$k}; push @jw, "${k}騎手は追込が苦手($J_OIKOMI{$k})" } }
  for my $k (keys %J_HINBA) { if (($sexage[$i] // '') =~ /^牝/ && index($jk, $k) == 0) { $ja += $J_HINBA{$k}; push @jw, "${k}騎手は牝馬" . ($J_HINBA{$k} > 0 ? "が得意(+" : "が苦手(") . "$J_HINBA{$k})" } }
  # 騎手×馬場・枠・馬格・産駒(出典: 馬情報/騎手の得意・苦手.md「7人の癖」。コースの連対率には入らない条件だけ)
  my $u0 = ($umaban[$i] // '') =~ /^(\d+)$/ ? $1 : 0;
  my $outer = $u0 && $n >= 10 && $u0 > $n * 0.7; my $inner = $u0 && $n >= 10 && $u0 <= $n * 0.3;
  my ($bw0) = ($bw[$i] // '') =~ /^(\d{3})/;
  # 2017〜2026/3 で確かめ直した(holdout_eval.pl): 川田の芝の道悪は0.87倍で弱く残る(-2→-1)。ルメールの道悪0.97・戸崎のダート外枠1.05・坂井の差し1.00・坂井の500kg以上1.04・
  #   松山の外枠の差し1.12(逆)はオッズ以上の差がなく外した(元のコードは 削除したもの/race_json_確かめ直し前_2026-10-27.pl)
  if (index($jk, '川田') == 0 && $surf eq '芝' && defined $baba && $baba ne '良') { $ja -= 1; push @jw, "川田騎手は芝の道悪が苦手(-1)" }
  if (index($jk, '戸崎') == 0 && $inner && $style !~ /逃げ|先行/) { $ja -= 1; push @jw, "戸崎騎手は内枠で包まれるのが苦手(-1)" }
  if (index($jk, '西村淳') == 0 && ($sire{$name} // '') eq 'ロードカナロア') { $ja += 2; push @jw, "西村淳騎手はロードカナロア産駒と手が合う(+2)" }
  $kishu = clamp($kishu + clamp($ja, -5, 5), 50, 95) if $ja;
  my $heavy = 0; my $g = $rgoing[$i]; my $wruns = 0;
  if ($g) { my ($w, $p, $runs) = (0, 0, 0); for my $k (keys %$g) { next unless $k =~ /稍|重|不/; my ($a, $b, $c, $o) = map { $_ // 0 } @{$g->{$k}}; $w += $a; $p += $a + $b + $c; $runs += $a + $b + $c + $o }
    $heavy = $w >= 1 ? 2 : ($runs >= 1 && $p / $runs >= 0.4) ? 1 : ($runs >= 2 && $p == 0) ? -1 : 0; $wruns = $runs }
  # 道悪の経験が少ない(2戦以下)馬は、父の産駒の道悪成績で ±1(出典: 馬情報/種牡馬の道悪適性.md)
  my $sire = $sire{$name} // ''; my $sadj = $SIRE_WET{$surf}{$sire} // 0; my $snote = '';
  if ($sadj && $wruns <= 2) { $heavy = clamp($heavy + $sadj, -2, 2); $snote = "父${sire}は道悪" . ($sadj > 0 ? '得意' : '苦手') }
  # 2・3歳限定の新馬・未勝利・1勝クラスのダート1400m以下は、父が米国型なら +2(出典: 馬情報/血統の系統と国別タイプ.md)
  my $unote = '';
  if ($SIRE_US{$sire} && $surf eq 'ダ' && $dist <= 1400 && $cls =~ /^[23]歳(?:新馬|未勝利|1勝クラス)/) { $course = clamp($course + 2, 50, 92); $unote = "父${sire}は米国型(若駒のダート短距離 +2)" }
  # 古馬混合の芝2200m以上は、父か母父が欧州型なら道悪で +1(道悪の経験2戦以下、父の道悪適性で補正した馬は除く)
  my $dsire = $damsire{$name} // ''; my $enote = '';
  if (!$sadj && $wruns <= 2 && $surf eq '芝' && $dist >= 2200 && $cls =~ /以上|上/ && grep { ($STYPE{$_} // '') eq '欧州' } $sire, $dsire) {
    $heavy = clamp($heavy + 1, -2, 2); $enote = (($STYPE{$sire} // '') eq '欧州' ? "父${sire}" : "母父${dsire}") . 'が欧州型(古馬の芝長距離の道悪 +1)' }
  my $od =($odds[$i] // '') =~ /^([\d.]+)/ ? $1 + 0 : undef;
  my @notes = (($RAW ? "近走の指数(" . $SRCN . "の着差から) " : "Ω指数 ") . (($omega[$i] // '') =~ /^\d+$/ ? $omega[$i] : 'なし'));
  push @notes, "前走 $z->[0]{race} $z->[0]{rank}着" if @$z && $z->[0]{rank};
  # 3連勝以上(近5走で前走から続く1着の数)。能力値は変えず、シミュレーターの1番人気の不安材料と★の判定に使う(コタの動画、未検証)
  { my $w = 0; for (@$z) { last unless ($_->{rank} // 0) == 1; $w++ } push @notes, "${w}連勝中" if $w >= 3 }
  push @notes, $mnote if $mnote;
  push @notes, "初出走" unless @$z;
  # トラック替わり(前走と今回で芝・ダートが違う)。能力値は変えず、大穴の軸候補の材料として出す(コタの動画、未検証)
  push @notes, ($surf eq '芝' ? 'ダートから芝替わり' : '芝からダート替わり') if @$z && $surf =~ /^(芝|ダ)$/ && ($z->[0]{surf} // '') =~ /^(芝|ダ)$/ && $z->[0]{surf} ne $surf;
  # 替わり2戦目: 前走が芝・ダートの替わり初戦で3着以内、今回も同じ馬場(コタの単勝の動画「替わって1回走った馬は続けて走る」。2026年の平場で227頭・市場の勝率の1.2倍だが、期間で差が大きいので能力値は変えない)
  push @notes, ($surf eq '芝' ? '芝' : 'ダート') . '替わり2戦目(前走好走)' if @$z >= 2 && $surf =~ /^(芝|ダ)$/ && ($z->[0]{surf} // '') eq $surf && ($z->[1]{surf} // '') =~ /^(芝|ダ)$/ && $z->[1]{surf} ne $surf && ($z->[0]{rank} // 99) <= 3;
  # 善戦型: 近5走(着順のある4走以上)で勝ちがなく2・3着が3回以上。勝率は市場どおりだが3着以内率が高く、単勝より2・3着付けやワイド・3連複の軸向き(コタの単勝の動画。2026年の平場の1〜5番人気で複勝率52%、全体44%)
  { my @k = grep { $_->{rank} } @$z; my $p23 = grep { $_->{rank} == 2 || $_->{rank} == 3 } @k;
    push @notes, "善戦型(近" . scalar(@k) . "走で2・3着${p23}回・勝ちなし)" if @k >= 4 && $p23 >= 3 && !grep { $_->{rank} == 1 } @k }
  # 人気になったときに勝ち切れない材料(飯野先生の「飛ぶ1番人気」。2026年の平場で1番人気の勝率が市場の 前走1着×3勝クラス以上0.82倍・前走2着0.3秒以上負け0.86倍・初距離0.92倍、前半・後半とも1倍未満。
  # 3着以内率は平常どおりなので能力値・★は変えず、simulator の favRisks の表示だけに使う)
  if (@$z && $z->[0]{rank}) {
    push @notes, '前走1着で3勝クラス以上' if $z->[0]{rank} == 1 && $cls =~ /3勝|オープン/;
    push @notes, "前走2着でも${zm}秒差" if $z->[0]{rank} == 2 && defined $zm && $zm >= 0.3;
    push @notes, '初距離(近走にこの距離なし)' if $dist && !grep { ($_->{dist} // 0) == $dist } @$z;
  }
  push @notes, "休み明け($iv)" if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
  push @notes, '中1週(-1)' if defined $wk && $wk == 1;
  push @notes, "騎手のこのコース連対率 $jr%" if defined $jn && $jn >= 5;
  push @notes, @jw;
  push @notes, $snote if $snote;
  push @notes, $unote if $unote;
  push @notes, $enote if $enote;
  my %hh = (name => $name, jockey => ($jockey[$i] // '未定'), style => $style,
    jisseki => $jisseki, kyori => $kyori, course => $course, choshi => clamp($choshi, 40, 95), kishu => $kishu, heavy => $heavy,
    note => join('・', @notes) . '(自動計算)');
  my $u = ($umaban[$i] // '') =~ /^(\d+)$/ ? $1 + 0 : undef; $hh{umaban} = $u;
  # 血統の国別タイプ(当日バイアスの「日本型が走る馬場か」の判定に使う)
  $hh{sire} = $sire if $sire; $hh{damsire} = $dsire if $dsire;
  $hh{sireType} = $STYPE{$sire} if $STYPE{$sire}; $hh{damsireType} = $STYPE{$dsire} if $STYPE{$dsire};
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
    # 芝2200m以上は付けない(スポナビ競馬「短距離は大型・長距離はコンパクトな馬」。2026年4〜10月の平場の芝2200m以上で 500kg以上は市場の0.75倍(前半0.78・後半0.72、226頭)、
    #   420kg未満は1.84倍(55頭)と全体の傾向と逆。1400m以下の500kg以上は1.10倍で今のまま。ダートは距離で差なし。出典: 馬情報/スポナビ競馬_動画まとめ.md)
    $sz = 0 if $surf eq '芝' && $dist >= 2200;
    # 2歳牝馬の芝の460kg以上 +2(先読み競馬。2026年の平場で1.34倍)は、2017〜2026/3 の2,878頭で1.00倍だったので外した(holdout_eval.pl)
    if ($sz) { $hh{jisseki} = clamp($hh{jisseki} + $sz, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・馬体重${wt}kg(${\($sz > 0 ? '+' : '')}$sz)$1/ }
  }
  # 展開の材料: 近3走で2回以上1角先頭なら「逃げにこだわる馬」、前走より200m以上の延長で逃げ・先行なら「短い距離からの延長組」(前半が速くなりやすい)
  if (@$z) {
    my @r3 = @{$z}[0 .. ($#$z < 2 ? $#$z : 2)];
    $hh{mustLead} = JSON::PP::true if (grep { ($_->{first} // 0) == 1 } @r3) >= 2;
    $hh{fromShort} = JSON::PP::true if $z->[0]{dist} && $dist - $z->[0]{dist} >= 200 && $style =~ /逃げ|先行/;
    # 前走の最初のコーナーで3番手以内か(コタ: この頭数の割合で延長馬の有利・不利が分かれる。下の「距離延長」とシミュレーターの「展開と隊列」で使う)。通過順が無ければ出さない
    $hh{prevFront} = $z->[0]{first} <= 3 ? JSON::PP::true : JSON::PP::false if $z->[0]{first};
  }
  # 危険な人気馬の条件(前走の好走が条件に恵まれたもの)と、その逆の巻き返し
  # 2026-10-27: どれも2026年4〜10月の平場で見つけた条件なので、使っていない 2017〜2026/3 の約3万レースで確かめ直した(自動実行/検証/holdout_eval.pl、
  #   Stanford の講義「交差検証の正しいやり方」「多重検定」から。馬情報/的中率を上げるための検証.md の17)。多重検定の補正(Benjamini-Hochberg q=0.1)を通ったものは元の点、
  #   向きは合うが弱いもの(片側 p<0.1)は点を半分、オッズ以上の差がないか逆のものは外した。外した条件のコードは 削除したもの/race_json_確かめ直し前_2026-10-27.pl
  if (@$z && $z->[0]{rank}) {
    my $p = $z->[0]; my $r = $p->{rank}; my @why; my $adj = 0;
    # 前走逃げて好走: 同じ形を再現できるとは限らない(同型がいればさらに不利。下でまとめて引く)。2017年以降0.97倍で弱い(-2→-1)
    if (($p->{first} // 0) == 1 && $r <= 3) { $adj -= 1; push @why, '前走逃げて好走'; $hh{_prevLead} = 1 }
    # 前走2着: 「次こそ勝つ」と人気しすぎる(コタの単勝の動画で1〜5番人気の単勝回収率72%が最低。2026年の平場1,593レースでも勝率が市場の0.88倍で、前半・後半とも同じ)
    if ($r == 2) { $adj -= 2; push @why, '前走2着(人気しすぎ)' }
    # 前走の人気と着順: 2・3番人気で4着以下の馬は人気を落として巻き返す(飯野先生の「5番人気以内で凡走した次走を狙え」。2026年の平場で1.18倍、2017年以降は1.03倍で弱い(+2→+1))
    # 前走1番人気で4着以下の -2 は2017年以降1.00倍(今回1番人気に限っても1.03倍)で外した
    if (defined $p->{pop} && $r >= 4 && $p->{pop} >= 2 && $p->{pop} <= 3) { $adj += 1; push @why, "前走$p->{pop}番人気で${r}着(人気を落として巻き返し)" }
    # 前走の道悪で好走 → 今回良馬場(2017年以降0.93倍) / 前走の道悪で凡走 → 今回良馬場(1.07倍で弱い、+2→+1)
    if (defined $baba && $baba eq '良' && ($p->{going} // '') =~ /^(重|不)$/) {
      if ($r <= 3) { $adj -= 3; push @why, '前走は道悪で好走・今回は良' } elsif ($r >= 6) { $adj += 1; push @why, '前走は道悪で凡走・今回は良' }
    }
    # 枠の替わり: 芝は内→外が不利、ダートは外→内が不利(砂をかぶる)。逆は巻き返し
    my $u = $hh{umaban};
    # 新潟の直線1000m(千直)は外ラチ沿いの外枠が有利で、芝の「内が有利」と逆なので上の替わりには入れない。
    # 前走千直の外枠で好走した馬は枠の恩恵が大きく、千直以外では割り引く(コタのレース映像の見方の動画。2026年の平場では該当9頭で検証できず)
    my $psen = ($p->{place} // '') eq '新潟' && ($p->{surf} // '') eq '芝' && ($p->{dist} // 0) == 1000;
    if ($psen && !$straight && $p->{umaban} && $p->{heads} && $p->{umaban} > $p->{heads} * 0.7 && $r <= 3) { $adj -= 2; push @why, '前走は千直の外枠の恩恵で好走' }
    if (defined $u && $p->{umaban} && $p->{heads} && ($p->{surf} // '') eq $surf && $surf ne '障' && !$psen && !$straight) {
      my $pin = $p->{umaban} <= $p->{heads} * 0.3; my $pout = $p->{umaban} > $p->{heads} * 0.7;
      my $nin = $u <= $n * 0.3; my $nout = $u > $n * 0.7;
      # 前走が有利な枠で凡走して今回は逆の枠(2017年以降1.07倍)。逆の「有利な枠で好走して今回は不利な枠」の -3 は0.98倍で外した
      my ($bad_from, $bad_to) = $surf eq '芝' ? ($pout, $nin) : ($pin, $nout);
      if ($bad_from && $bad_to && $r >= 4) { $adj += 2; push @why, $surf eq '芝' ? '前走外枠で凡走・今回内枠' : '前走内枠で凡走・今回外枠' }
    }
    # 芝→ダートの外枠の先行馬: 外枠なら砂をかぶらずに前へ行け、そのまま内に入れる(コタの動画。2026年4〜10月の平場で23頭・単回収153%。2017年以降567頭で1.28倍だが頭数が少なく +2→+1)
    if ($surf eq 'ダ' && defined $u && $n >= 10 && $u > $n * 0.7 && ($p->{surf} // '') eq '芝'
        && grep { ($_->{surf} // '') eq 'ダ' && ($_->{first} // 99) <= 4 && ($_->{rank} // 99) <= 3 } @$z) { $adj += 1; push @why, '芝からダートの外枠・ダートで先行して好走歴' }
    # 距離ローテ: 東京芝1400・東京ダ1600・京都芝1400(外回り)・京都芝2200は前走からの短縮が好成績(2017年以降まとめて1.07倍で弱い、+2→+1)。
    # 東京芝1400・ダ1600の1200m以下からの延長 -2 は0.99倍で外した
    my $pd = $p->{dist};
    if ($pd && (($place eq '東京' && $surf eq '芝' && $dist == 1400 && $pd >= 1600) || ($place eq '東京' && $surf eq 'ダ' && $dist == 1600 && $pd >= 1700)
        || ($place eq '京都' && $surf eq '芝' && !$straight && (($dist == 1400 && $pd >= 1600) || ($dist == 2200 && $pd >= 2400))))) { $adj += 1; push @why, "前走${pd}mから短縮" }
    # 距離短縮で初めての短距離(1400m以下): この距離の経験がなく、近走が全部今回より200m以上長い馬。相手のレベルが下がり、馬も楽に感じる。
    # 短距離の実績がないので人気になりにくい(上昇の動画、未検証)。東京・京都の芝1400の短縮(上)とは重ねない
    if ($dist <= 1400 && $surf ne '障' && $rdist[$i] && !$dn && !grep { /から短縮/ } @why) {
      my @d = grep { $_ } map { $_->{dist} } @$z;
      if (@d >= 2 && !grep { $_ < $dist + 200 } @d) { $adj += 2; push @why, "距離短縮で初めての${dist}m" }
    }
    # 休み明け(中10〜19週)で前走より400m以上の距離短縮: 立て直して短い距離から使い出す形で、人気になりにくい(ウマザワの「休み明けで初めての距離など、前走からの変化が大きい馬は穴になる」を検証。
    # 2026年4〜10月の平場363頭で勝率が市場の1.52倍(前半1.57・後半1.47)・複勝回収107%。芝1.60(1.37・1.83)、ダートは1.33だが前半2.14・後半0.69でぶれるので +1。
    # 中20週以上は上の休み明けの減点どおり、延長や200〜399mの短縮は差なし。上の場別の短縮(東京・京都の芝1400など)と重なる24頭は0.72倍なので重ねない)
    if (defined $wk && $wk >= 10 && $wk <= 19 && $p->{dist} && $p->{dist} - $dist >= 400 && $surf ne '障' && !grep { /短縮/ } @why) {
      my $sa = $surf eq '芝' ? 2 : 1; $adj += $sa; push @why, "休み明けで前走$p->{dist}mから短縮" }
    # 小回り4場のダ1700で前走ダ1400: 短い距離のスピードで楽に前へ行ける(丞相の函館・小倉・福島の動画)。
    # 2026年4〜10月の平場143頭で勝率が市場の1.80倍(前半1.62・後半2.33、4場とも1倍超)。ダ1600やダ1800への同じ延長は0.68〜0.77で効かない。
    # 「から延長」と書くので、下の「距離延長・前に行く馬の数」の補正とは重ねない
    if ($surf eq 'ダ' && $dist == 1700 && $place =~ /^(函館|札幌|福島|小倉)$/ && ($p->{surf} // '') eq 'ダ' && ($p->{dist} // 0) == 1400) {
      $adj += 2; push @why, '前走ダ1400mから延長(小回りのダ1700)' }
    # 競馬場のタイプ替わり(直線の坂・コースの広さ): 急坂で凡走して今回平坦(2017年以降1.04倍)、小回りで好走して今回大箱(0.97倍)だけ残す。
    # 初めての芝・ダート(丞相)、前走阪神の坂で失速→京都、平坦で好走→急坂、東京↔中山(コタ)は2017年以降オッズ以上の差がなく外した
    my $pp = $p->{place} // '';
    if ($pp && $pp ne $place && ($p->{surf} // '') eq $surf && $surf ne '障') {
      my %steep = map { $_ => 1 } qw(中山 阪神 中京); my %flat = map { $_ => 1 } qw(京都 新潟 小倉 函館 札幌 福島);
      my %big = map { $_ => 1 } qw(東京 阪神 京都 新潟); my %small = map { $_ => 1 } qw(中山 中京 福島 小倉 函館 札幌);
      if ($r >= 4 && $r <= 9 && $steep{$pp} && $flat{$place}) { $adj += 1; push @why, "前走は急坂の${pp}で凡走・今回は平坦" }
      if ($r <= 3 && $small{$pp} && $big{$place}) { $adj -= 1; push @why, "前走は小回りの${pp}で好走・今回は大箱" }
    }
    # 前崩れのレースで先行して粘った馬: 上級条件(2勝クラス以上)で前走がハイペース、1角・4角とも3番手以内で4〜10着(コタの動画。2026年4〜10月の平場で単回収128%。
    # 2017年以降は1.08倍で弱い(+2→+1。ペースはハロンタイムから作った近似))
    if (($p->{pace} // '') eq 'H' && $cls =~ /[23２３]勝|オープン/ && ($p->{surf} // '') eq $surf
        && ($p->{first} // 99) <= 3 && ($p->{last} // 99) <= 3 && $r >= 4 && $r <= 10) { $adj += 1; push @why, '前走ハイペースを先行して粘った' }
    # 前走1着の中身: 展開に逆らって勝った馬(1角3番手以内でハイペース・4番手以下でスロー)は「強い勝ち方」として人気しすぎる(あおきの動画を検証。2026年の平場で0.76倍、
    # 2017年以降は0.96倍で弱い、-2→-1)。「展開が向いて勝った +1」は2017年以降1.01倍で外した
    if ($r == 1 && ($p->{surf} // '') eq $surf && $surf ne '障' && $p->{first} && ($p->{pace} // '') =~ /^[HS]$/ && ($p->{first} <= 3) == ($p->{pace} eq 'H')) {
      $adj -= 1; push @why, '前走は展開に逆らって勝った(人気しすぎ)' }
    # 専用機の巻き返し(カチウマ博士)・ラップの型(丞相)・1角まで長い距離の差しは、2017年以降 0.91・1.01・0.77倍(逆か差なし)で外した
    $adj = clamp($adj, -5, 5);   # いくつ重なっても補正は±5まで
    if ($adj) { $hh{choshi} = clamp($hh{choshi} + $adj, 40, 95); my $w = join('・', @why); $hh{note} =~ s/(\(自動計算\))$/・${w}(${\($adj > 0 ? '+' : '')}$adj)$1/ }
  }
  # ダートの砂かぶり(内枠から馬群の中を通った走りの好走・凡走で ±2)は、2017年以降 0.95倍・1.04倍(どちらも逆)で外した
  # 減量騎手: 定量・馬齢戦で同じ性別・年齢の馬より3kg以上軽い(女性騎手4kg・見習3kg減)。斤量が軽い分ゲートを出て前で運べる
  #   (義英真の「夏の小回りは3kg減の騎手を穴で拾う」を検証。2026年4〜10月の平場で勝率が市場の ダート1500m以上 小回り4場2.15倍・ほかの場1.28倍。
  #    2017年以降は小回り4場1.10倍(2,914頭)・ほかの場1.03倍に縮んだので、小回り4場だけ +4→+2。出典: 馬情報/義英真_動画まとめ.md)
  if ($surf eq 'ダ' && $dist >= 1500 && $weight_rule =~ /定量|馬齢/ && $place =~ /^(函館|札幌|福島|小倉)$/) {
    my $key = sub { my ($s, $g) = ($sexage[$_[0]] // '') =~ /^(\D+)(\d+)/; defined $g ? "$s$g" : '' };
    my $kg = sub { (($kin[$_[0]] // '') =~ /([\d.]+)/)[0] };
    my ($me, $mk) = ($key->($i), $kg->($i));
    my ($mx) = sort { $b <=> $a } grep { defined } map { $kg->($_) } grep { $key->($_) eq $me } 0 .. $n - 1;
    if ($me ne '' && defined $mk && defined $mx && $mx - $mk >= 3) {
      my $ka = 2; my $d = $mx - $mk;
      $hh{choshi} = clamp($hh{choshi} + $ka, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・減量${d}kg(ダート中距離)(+$ka)$1/ }
  }
  # 牡馬混合の芝2400m以上の牝馬 -2(スポナビ競馬)は、2026年の平場の0.42倍が2017年以降2,462頭で0.98倍になり外した
  # 軸馬の減点チェック(上昇のチェックリスト、点数は動画のまま・未検証)。能力値には足さず、シミュレーターが1〜3番人気の比較に表示する
  if (@$z && $surf ne '障') {
    my $p = $z->[0]; my @ax; my $add = sub { push @ax, [$_[0], $_[1]] };
    my ($sex) = ($sexage[$i] // '') =~ /^(牡|牝|セ|騸)/; $sex //= '';
    $add->('前走逃げて好走', -5) if ($p->{first} // 0) == 1 && ($p->{rank} // 99) <= 3;
    $add->($surf eq '芝' ? '近走に芝の経験なし' : '近走にダートの経験なし', -5) unless grep { ($_->{surf} // '') eq $surf } @$z;
    $add->("距離延長(前走$p->{dist}m)", -5) if $p->{dist} && $dist - $p->{dist} >= 200;
    $add->('ダートで前走牝馬限定・今回牡馬混合', -5) if $surf eq 'ダ' && $sex eq '牝' && ($p->{race} // '') =~ /牝/ && $cls !~ /牝/;
    # 昇級初戦: 条件戦(1〜3勝クラス)に前走1着の馬がいれば、勝ってクラスが上がった馬(オープン・重賞は前走のクラスが分からないので見ない)
    $add->('昇級初戦(前走1着)', -4) if ($p->{rank} // 0) == 1 && $cls =~ /[123１２３]勝/;
    $add->('前走は道悪で好走・今回は良', -4) if ($hh{note} // '') =~ /前走は道悪で好走/;
    $add->("前走ローカル(${\($p->{place} // '')})で好走・今回主要場", -4) if ($p->{place} // '') =~ /^(福島|新潟|小倉|函館|札幌)$/ && $place =~ /^(東京|中山|阪神|京都)$/ && ($p->{rank} // 99) <= 3;
    $add->('6か月以上の休み明け', -3) if (defined $wk && $wk >= 26) || $iv =~ /半年|年|([6-9]|1\d)ヶ月/;
    if (defined $hh{umaban}) {
      $add->('芝の外枠(16頭以上の13番より外)', -3) if $surf eq '芝' && $n >= 16 && $hh{umaban} >= 13;
      $add->('ダートの内枠', -3) if $surf eq 'ダ' && $n >= 10 && $hh{umaban} <= 3;
    }
    if ($weight_rule eq 'ハンデ') { my @kk = map { /([\d.]+)/ ? $1 : 0 } @kin; my ($mx) = sort { $b <=> $a } @kk; my ($k) = ($kin[$i] // '') =~ /([\d.]+)/;
      $add->("ハンデ戦のトップハンデ(${k}kg)", -3) if $k && $mx && $k >= $mx }
    my %steep = map { $_ => 1 } qw(中山 阪神 中京);
    $add->('急坂のコースで好走歴なし(近走)', -2) if $steep{$place} && !grep { $steep{$_->{place} // ''} && ($_->{rank} // 99) <= 3 && ($_->{surf} // '') eq $surf } @$z;
    $add->("馬体重$hh{weightDiff}kg", -2) if defined $hh{weightDiff} && abs($hh{weightDiff}) >= 15;
    $add->("${dir}回りの経験なし(近走)", -1) if $dir =~ /^(左|右)$/ && !grep { ($dirs{$_->{place} // ''} // '') eq $dir } @$z;
    $add->('冬の牝馬', -1) if $sex eq '牝' && ($mo == 12 || $mo <= 2);
    $add->('夏の牡馬', -1) if $sex eq '牡' && $mo >= 6 && $mo <= 8;
    # 追込は前が止まらないと届かず展開任せ(テスラ: 追込の勝率は逃げの約10分の1。点数は独自)
    $add->('追込(展開待ち)', -3) if $style eq '追込';
    $hh{axisCheck} = [map { { why => $_->[0], pt => $_->[1] } } @ax] if @ax;
  }
  push @horses, \%hh;
}
# 前走逃げて好走した馬は、ほかに逃げ馬がいるとマークされ、ペースも厳しくなりやすい(2017年以降0.92倍で弱い、-2→-1)
my $leaders = grep { $_->{style} eq '逃げ' } @horses;
for my $x (@horses) {
  next unless delete $x->{_prevLead};
  if ($leaders >= 2) { $x->{choshi} = clamp($x->{choshi} - 1, 40, 95); $x->{note} =~ s/(\(自動計算\))$/・逃げ馬がほかにもいる(-1)$1/ }
}
# 距離延長 × 前走1角3番手以内の馬の割合(コタ。+1/-2)は、2017年以降 1.01倍・1.00倍で差がなく外した。prevFront はシミュレーターの「展開と隊列」の表示に使う
# 仮オッズ: オッズがまだ無い馬は、能力値から人気を想定して付ける(1/オッズの合計は実際の平均の約1.26)
# exp(点数/8): 2026年4〜10月の平場1,868レースで、実際の単勝オッズの勝率に一番近い温度(以前の /4 は1番手の馬を強く見すぎ)
my %W = (jisseki => .28, kyori => .17, course => .055, choshi => .245, kishu => .25);
my @score = map { my $x = $_; my $s = 0; $s += $W{$_} * $x->{$_} for keys %W; $s } @horses;
my @e = map { exp($_ / 8) } @score; my $sum = 0; $sum += $_ for @e;
for my $i (0 .. $#horses) { next if defined $horses[$i]{odds}; my $p = $e[$i] / $sum * 1.26; $horses[$i]{odds} = clamp(int(1 / $p * 10 + 0.5) / 10, 1.2, 300) }
@horses = sort { ($a->{umaban} // 99) <=> ($b->{umaban} // 99) } @horses;

# 波乱度(乱数の大きさ): 2026年4〜10月の平場1,868レースで、オッズが出る前(能力値だけ)の1〜3着が一番当たる値。オッズを混ぜた後の3着以内率はほとんど変わらない
my $chaos = 16; $chaos = 20 if $cls =~ /2歳|新馬/ || $weight_rule eq 'ハンデ'; $chaos = 12 if $surf eq "障";
my $nowj = do { my @t = gmtime(time + 9 * 3600); sprintf('%04d-%02d-%02dT%02d:%02d:00+09:00', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]) };
my %doc = (id => "k$kid", name => $rname, grade => '', date => $date, place => $place, no => $no + 0, time => $time,
  surface => $surf, dist => $dist + 0, dir => $dir, courseNote => ($straight ? '直線' : ''), cond => $cond,
  stage => ((grep { defined $_->{umaban} } @horses) ? '枠順確定' : '出走確定'), chaos => $chaos,
  weather => ($RAW ? $RAW->{weather} // '' : ''), going => (defined $baba ? {'良' => 0, '稍重' => 1, '重' => 2, '不良' => 3}->{$baba} : undef),
  updatedAt => $nowj, source => ($RAW ? "$SRCN(能力値は自動計算)" : '競馬ラボ(能力値は自動計算)'),
  memo => ($RAW ? "全レース自動追加。${SRCN}の出馬表と近走から計算(Ω指数の代わりに近走の着差、騎手のコース連対率なし)" : '全レース自動追加。能力値はΩ指数・距離/コース成績・前走・騎手のコース連対率から自動で計算'),
  auto => JSON::PP::true, keibalabId => "$kid", horses => \@horses);
# スポーツナビの素データは残しておき、次の実行では馬ページを取り直さずに使う(yahoo.pl raw の「前回のdbのデータ」)
$doc{yahooRaw} = $RAW if $RAW;
print JSON::PP->new->canonical->pretty->encode(\%doc);
