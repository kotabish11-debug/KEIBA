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
    elsif ($r >= 2 && $r <= 3 && $zm >= 1.0) { $choshi -= 4; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-4)" }
    elsif ($r >= 2 && $r <= 3 && $zm >= 0.6) { $choshi -= 2; $mnote = "前走${r}着だが勝ち馬と${zm}秒差(-2)" }
  }
  my $iv = $intv[$i] // ''; my ($wk) = $iv =~ /中(\d+)週/;
  $choshi -= 6 if (defined $wk && $wk >= 20) || $iv =~ /ヶ月|半年|年/;
  $choshi -= 3 if defined $wk && $wk >= 26;   # 半年以上の休み明けは、人気でも勝ち切れないことが多い
  # 中1週は疲れが残りやすく、中3〜5週が一番走る(バフェットの動画。2026年の平場で勝率が市場の 中1週0.89倍・中3〜5週1.06〜1.12倍、前半・後半とも同じ向き)
  if (defined $wk) { $choshi -= 1 if $wk == 1; $choshi += 1 if $wk >= 3 && $wk <= 5 }
  my ($jr, $jn) = ($jc[$i] // '') =~ /([\d.]+)%\s*\[(\d+)\]/;
  my $kishu = (defined $jn && $jn >= 5) ? clamp(int(58 + 0.8 * $jr + 0.5), 55, 92) : 66;
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
  if (index($jk, 'ルメール') == 0 && defined $baba && $baba ne '良') { $ja -= 2; push @jw, "ルメール騎手は道悪が苦手(-2)" }
  if (index($jk, '川田') == 0 && $surf eq '芝' && defined $baba && $baba ne '良') { $ja -= 2; push @jw, "川田騎手は芝の道悪が苦手(-2)" }
  if (index($jk, '戸崎') == 0 && $surf eq 'ダ' && $outer) { $ja += 2; push @jw, "戸崎騎手はダートの外枠が得意(+2)" }
  if (index($jk, '戸崎') == 0 && $inner && $style !~ /逃げ|先行/) { $ja -= 1; push @jw, "戸崎騎手は内枠で包まれるのが苦手(-1)" }
  if (index($jk, '坂井') == 0 && $style eq '差し') { $ja -= 1; push @jw, "坂井騎手は差し馬が苦手(-1)" }
  if (index($jk, '坂井') == 0 && defined $bw0 && $bw0 >= 500) { $ja += 1; push @jw, "坂井騎手は500kg以上の大型馬が得意(+1)" }
  if (index($jk, '松山') == 0 && $outer && $style =~ /差し|追込/) { $ja -= 1; push @jw, "松山騎手は外枠の差し馬が苦手(-1)" }
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
  push @notes, $wk == 1 ? '中1週(-1)' : "中${wk}週(+1)" if defined $wk && ($wk == 1 || ($wk >= 3 && $wk <= 5));
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
    if ($sz) { $hh{jisseki} = clamp($hh{jisseki} + $sz, 40, 95); $hh{note} =~ s/(\(自動計算\))$/・馬体重${wt}kg(${\($sz > 0 ? '+' : '')}$sz)$1/ }
  }
  # 展開の材料: 近3走で2回以上1角先頭なら「逃げにこだわる馬」、前走より200m以上の延長で逃げ・先行なら「短い距離からの延長組」(前半が速くなりやすい)
  if (@$z) {
    my @r3 = @{$z}[0 .. ($#$z < 2 ? $#$z : 2)];
    $hh{mustLead} = JSON::PP::true if (grep { ($_->{first} // 0) == 1 } @r3) >= 2;
    $hh{fromShort} = JSON::PP::true if $z->[0]{dist} && $dist - $z->[0]{dist} >= 200 && $style =~ /逃げ|先行/;
    # 前走の最初のコーナーで3番手以内か(コタ: この頭数の割合で延長馬の有利・不利が分かれる。下の「距離延長」とシミュレーターの「展開と隊列」で使う)。通過順が無ければ出さない
    $hh{prevFront} = $z->[0]{first} <= 3 ? JSON::PP::true : JSON::PP::false if $z->[0]{first};
    $hh{_extend} = 1 if $z->[0]{dist} && $dist - $z->[0]{dist} >= 200;
  }
  # 危険な人気馬の条件(前走の好走が条件に恵まれたもの)と、その逆の巻き返し
  if (@$z && $z->[0]{rank}) {
    my $p = $z->[0]; my $r = $p->{rank}; my @why; my $adj = 0;
    # 前走逃げて好走: 同じ形を再現できるとは限らない(同型がいればさらに不利。下でまとめて引く)
    if (($p->{first} // 0) == 1 && $r <= 3) { $adj -= 2; push @why, '前走逃げて好走'; $hh{_prevLead} = 1 }
    # 前走2着: 「次こそ勝つ」と人気しすぎる(コタの単勝の動画で1〜5番人気の単勝回収率72%が最低。2026年の平場1,593レースでも勝率が市場の0.88倍で、前半・後半とも同じ)
    if ($r == 2) { $adj -= 2; push @why, '前走2着(人気しすぎ)' }
    # 前走の人気と着順: 1番人気で4着以下に負けた馬は次も人気が残って勝てない、2・3番人気で4着以下の馬は人気を落として巻き返す
    # (飯野先生の「5番人気以内で凡走した次走を狙え」を検証。2026年の平場で勝率が市場の 前走1番人気4着以下0.78倍(前半0.82・後半0.74、3着以内率も低い)・前走2〜3番人気4着以下1.18倍(1.19・1.16))
    if (defined $p->{pop} && $r >= 4) { if ($p->{pop} == 1) { $adj -= 2; push @why, '前走1番人気で4着以下(人気が残りやすい)' } elsif ($p->{pop} <= 3) { $adj += 2; push @why, "前走$p->{pop}番人気で${r}着(人気を落として巻き返し)" } }
    # 前走の道悪で好走 → 今回良馬場 / 前走の道悪で凡走 → 今回良馬場
    if (defined $baba && $baba eq '良' && ($p->{going} // '') =~ /^(重|不)$/) {
      if ($r <= 3) { $adj -= 3; push @why, '前走は道悪で好走・今回は良' } elsif ($r >= 6) { $adj += 2; push @why, '前走は道悪で凡走・今回は良' }
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
      my ($good_from, $good_to) = $surf eq '芝' ? ($pin, $nout) : ($pout, $nin);
      my ($bad_from, $bad_to) = $surf eq '芝' ? ($pout, $nin) : ($pin, $nout);
      if ($good_from && $good_to && $r <= 3) { $adj -= 3; push @why, $surf eq '芝' ? '前走内枠で好走・今回外枠' : '前走外枠で好走・今回内枠' }
      elsif ($bad_from && $bad_to && $r >= 4) { $adj += 2; push @why, $surf eq '芝' ? '前走外枠で凡走・今回内枠' : '前走内枠で凡走・今回外枠' }
    }
    # 芝→ダートの外枠の先行馬: 外枠なら砂をかぶらずに前へ行け、そのまま内に入れる(コタの動画。2026年4〜10月の平場で23頭・単回収153%、内・中枠の同じ条件は45%)
    if ($surf eq 'ダ' && defined $u && $n >= 10 && $u > $n * 0.7 && ($p->{surf} // '') eq '芝'
        && grep { ($_->{surf} // '') eq 'ダ' && ($_->{first} // 99) <= 4 && ($_->{rank} // 99) <= 3 } @$z) { $adj += 2; push @why, '芝からダートの外枠・ダートで先行して好走歴' }
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
    # 距離短縮で初めての短距離(1400m以下): この距離の経験がなく、近走が全部今回より200m以上長い馬。相手のレベルが下がり、馬も楽に感じる。
    # 短距離の実績がないので人気になりにくい(上昇の動画、未検証)。東京・京都の芝1400の短縮(上)とは重ねない
    if ($dist <= 1400 && $surf ne '障' && $rdist[$i] && !$dn && !grep { /から短縮/ } @why) {
      my @d = grep { $_ } map { $_->{dist} } @$z;
      if (@d >= 2 && !grep { $_ < $dist + 200 } @d) { $adj += 2; push @why, "距離短縮で初めての${dist}m" }
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
      # 東京と中山は求められる適性が逆(東京=切れ味・スピード、中山=器用さ・長く使う脚・スタミナ。ダートは中山が最も時計がかかる)。
      # 東京で好走して中山で人気になる馬は飛びやすく、東京で凡走した馬が中山のダートで巻き返す(コタの動画。2026年4〜10月の平場で
      # 東京好走→中山は40頭で勝率10%(オッズからの期待21%)、東京ダ6着以下→中山ダは89頭で勝率7.9%(期待5.4%)・単回収108%)
      if ($pp eq '東京' && $place eq '中山') {
        if ($r <= 3) { $adj -= 2; push @why, '前走は東京で好走・今回は中山(適性が逆)' }
        elsif ($r >= 6 && $surf eq 'ダ') { $adj += 1; push @why, '前走は東京ダートで凡走・今回は中山ダート' }
      }
    }
    # 前崩れのレースで先行して粘った馬: 上級条件(2勝クラス以上)で前走がハイペース、1角・4角とも3番手以内で4〜10着。
    # 展開が厳しかっただけで、次走で巻き返しやすい(コタの動画。2026年4〜10月の平場で173頭・勝率12.7%(期待7.8%)・単回収128%、
    # 1角3番手以内・4〜10着で前走スローは182頭・勝率9.3%(期待7.8%)・単回収66%)
    if (($p->{pace} // '') eq 'H' && $cls =~ /[23２３]勝|オープン/ && ($p->{surf} // '') eq $surf
        && ($p->{first} // 99) <= 3 && ($p->{last} // 99) <= 3 && $r >= 4 && $r <= 10) { $adj += 2; push @why, '前走ハイペースを先行して粘った' }
    # ラップの型(芝1600m以上): 直線の長いコースは瞬発力勝負(S)、直線の短いコースは持続力勝負(J)になりやすい。
    # 近走で一方の型だけ好走し、もう一方の型で6着以下があれば、今回その苦手な型のコースで -2(上昇のラップの動画、未検証)
    my $lapt = sub { my ($pl, $s, $d) = @_; return '' if ($s // '') ne '芝' || !$d || $d < 1600;
      return 'S' if $pl eq '東京' || ($pl eq '新潟' && ($d == 1600 || $d == 1800)) || ($pl eq '阪神' && $d =~ /^(1600|1800|2400|2600)$/);
      return 'J' if $pl =~ /^(函館|福島|小倉|札幌|中山)$/ || ($pl eq '阪神' && $d =~ /^(2000|2200|3000)$/); return '' };
    my $ct = $straight ? '' : $lapt->($place, $surf, $dist);
    if ($ct) {
      my $ot = $ct eq 'S' ? 'J' : 'S'; my ($gO, $gT, $bT) = (0, 0, 0);
      for my $q (@$z) { my $t = $lapt->($q->{place} // '', $q->{surf}, $q->{dist}) or next; my $qr = $q->{rank} or next;
        if ($t eq $ot && $qr <= 3) { $gO++ } elsif ($t eq $ct && $qr <= 3) { $gT++ } elsif ($t eq $ct && $qr >= 6) { $bT++ } }
      if ($gO && $bT && !$gT) { $adj -= 2; push @why, $ct eq 'S' ? '好走は持続力勝負のコースだけ・瞬発力勝負で凡走' : '好走は瞬発力勝負のコースだけ・持続力勝負で凡走' }
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
# 前走逃げて好走した馬は、ほかに逃げ馬がいるとマークされ、ペースも厳しくなりやすい
my $leaders = grep { $_->{style} eq '逃げ' } @horses;
for my $x (@horses) {
  next unless delete $x->{_prevLead};
  if ($leaders >= 2) { $x->{choshi} = clamp($x->{choshi} - 2, 40, 95); $x->{note} =~ s/(\(自動計算\))$/・逃げ馬がほかにもいる(-2)$1/ }
}
# 距離延長は、前走1角3番手以内の馬が30%未満(スロー見込み)なら +1、40%以上(先行争いが激しい)なら -2(コタの動画。2026年8月30日〜10月19日の平場328レースで、前走より200m以上延長の馬の3着以内率は人気からの期待より、30%未満のレース +2.0pt(695頭)・40%以上 -4.2pt(151頭))
{ my @pf = grep { exists $_->{prevFront} } @horses; my $fr = @pf >= @horses * 0.7 && @horses >= 8 ? scalar(grep { $_->{prevFront} } @pf) / @pf : undef;
  for my $x (@horses) {
    next unless delete $x->{_extend}; next unless defined $fr; next if $x->{note} =~ /から延長/;
    my $ad = $fr < 0.3 ? 1 : $fr >= 0.4 ? -2 : 0; next unless $ad;
    $x->{choshi} = clamp($x->{choshi} + $ad, 40, 95); my $w = $ad > 0 ? "距離延長・前に行く馬が少なく落ち着きそう(+1)" : "距離延長・前に行く馬が多く流れが速そう(-2)"; $x->{note} =~ s/(\(自動計算\))$/・$w$1/ } }
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
