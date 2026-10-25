# JRA公式(www.jra.go.jp/JRADB)のページを読む。全レースの主な取得元(run.sh が使う)。つながらなければスポーツナビ(yahoo.pl)
# JRAのページは Shift_JIS(CP932)のまま保存して渡す。ページの場所は cname(例 pw01dde0105202604081120261024/2B)で、末尾の2桁は
# チェック用の値なので自分で作らず、一覧ページのリンクから拾う(run.sh の jlink)
# 使い方:
#   perl jra.pl link   <ページ.html> <cnameの正規表現>                     … 最初に当てはまる cname
#   perl jra.pl need   <出馬表.html> [前回のdbのデータ.json]                 … 馬ページを取る必要がある馬(「馬ID<TAB>cname」1行に1頭)
#   perl jra.pl raw    <出馬表.html> <馬ページのフォルダー> <競馬ラボ形式のレースID> [前回のdbのデータ.json] [単勝・複勝オッズ.html] > raw.json
#        … race_json.pl に渡す素データ(yahoo.pl raw と同じ形)。馬ページは <フォルダー>/<馬ID>.html。重賞は終了コード 3、出走馬が出ていなければ 2、
#          馬ページが取れていなければ 4。オッズのページを渡すと、単勝オッズと馬体重はそちらを使う
#   perl jra.pl result <結果.html>                                          … result_json.pl と同じ形の着順。結果がまだ無ければ終了コード 2
#   perl jra.pl fuku   <単勝・複勝オッズ.html>                              … {"<馬番>":[単勝,複勝の下限,複勝の上限]}。オッズが無ければ終了コード 2
#   perl jra.pl wide   <ワイドオッズ.html(pw155)>                           … {"<馬番>-<馬番>":[下限,上限]}。オッズが無ければ終了コード 2
# JRAには Ω指数・騎手のコース連対率・調教師×騎手・前走のペースが無い。Ω指数の代わりに、出馬表の近4走の着差(勝ち馬との差)と格から
# 「近走の指数」を作る(yahoo.pl と同じ式。検証はしていない目安)。距離・コースの成績と間隔は馬ページの全成績から数える
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use Encode ();

my $cmd = shift // '';
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return ''; local $/; my $s = <$fh> // '';
  return $s =~ /charset="?Shift_JIS/i ? Encode::decode('cp932', $s) : Encode::decode('UTF-8', $s) }
sub txt { my $t = shift // ''; $t =~ s/<[^>]*>/ /g; $t =~ s/&nbsp;/ /g; $t =~ s/&amp;/&/g; $t =~ s/&#8546;/Ⅲ/g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub clamp { my ($v, $lo, $hi) = @_; $v < $lo ? $lo : $v > $hi ? $hi : $v }
sub z2h { my $t = shift // ''; $t =~ tr/０-９．/0-9./; $t }
my %JRA = map { $_ => 1 } qw(札幌 函館 福島 新潟 東京 中山 中京 京都 阪神 小倉);
my %SURF = ('芝' => '芝', 'ダート' => 'ダ', 'ダ' => 'ダ', '障害' => '障', '障' => '障');

if ($cmd eq 'link') {
  my ($file, $re) = @ARGV; my $h = slurp($file);
  while ($h =~ /(pw[0-9a-zA-Z]+\/[0-9A-F]{2})/g) { my $c = $1; if ($c =~ /^$re$/) { print "$c\n"; exit 0 } }
  exit 2;
}

# 出馬表の各行(馬番・枠は枠順確定前は空)
sub denma_rows {
  my $h = shift; my @rows;
  my ($tb) = $h =~ /<tbody>(.*?)<\/tbody>/s or return ();
  for my $r (split /<\/tr>/, $tb) {
    my ($cn, $hid, $name) = $r =~ /accessU\.html\?CNAME=(pw01dud\d\d(\d{10})\/[0-9A-F]{2})">([^<]+)<\/a>/ or next;
    my ($waku) = $r =~ /<td class="waku">.*?alt="枠(\d)/s; my ($ban) = $r =~ /<td class="num">\s*(\d+)\s*</;
    my ($hc) = $r =~ /<td class="horse">(.*?)<\/td>/s; $hc //= '';
    my ($odds) = $hc =~ /class="odds_line"><span class="num"><strong[^>]*>([\d.]+)</; my ($pop) = $hc =~ /class="pop_rank">\((\d+)/;
    my ($sire) = $hc =~ /<li class="sire"><span>父：<\/span>([^<]+)/; my ($dsire) = $hc =~ /\(母の父：([^)<]+)\)/;
    my ($jc) = $r =~ /<td class="jockey">(.*?)<\/td>/s; $jc //= '';
    my ($sexage) = $jc =~ /<p class="age">([^<\/]+)/; my ($kin) = $jc =~ /<p class="weight">\s*([\d.]+)/;
    my ($jk) = $jc =~ /<p class="jockey">(.*?)<\/p>/s; $jk = txt($jk); $jk =~ s/[\s▲△☆◇★]//g;
    my ($bw) = $jc =~ /<p class="h_weight">\s*(\d{3}(?:\s*<span>\([+\-]?\d+\)<\/span>)?)/; $bw = txt($bw) if defined $bw; $bw =~ s/\s+// if defined $bw;
    my $scr = $r =~ /取消|除外/ ? 1 : 0;
    my @past; while ($r =~ /<td class="past p\d[^"]*"[^>]*>(.*?)<\/td>/sg) { my $p = past_cell($1); push @past, $p if $p }
    $dsire //= ''; $dsire =~ s/’/'/g; $sire //= ''; $sire =~ s/\s+$//;
    push @rows, { id => $hid, cname => $cn, name => $name, waku => $waku // '', umaban => $ban // '', sexage => $sexage // '', jockey => $jk,
      kin => $kin // '', sire => $sire, damsire => $dsire, bw => $bw // '', odds => $odds // '', pop => $pop, scr => $scr, past => \@past };
  }
  return @rows;
}
# 出馬表の近走の欄(1走ぶん)
sub past_cell {
  my $c = shift; return undef unless $c =~ /class="date">(\d{4})年(\d{1,2})月(\d{1,2})日/;
  my ($y, $m, $d) = ($1, $2, $3);
  my ($pl) = $c =~ /<div class="rc">\s*([^<\s]+)/; my ($race) = $c =~ /<div class="name">(?:<a[^>]*>)?([^<]*)/;
  my ($g) = $c =~ /grade_icon[^"]*\bj?g(\d)|icon_grade_j?g(\d)/; $g //= $2 if defined $2;
  my ($rank) = $c =~ /<div class="place">\s*([^<\s]+)/; $rank = z2h($rank // '');
  my ($hd) = $c =~ /class="max">(\d+)/; my ($ban) = $c =~ /class="gate">(\d+)/; my ($pop) = $c =~ /class="pop">(\d+)/;
  my ($dist, $sf) = $c =~ /class="dist">(\d+)(芝|ダ|障)/;
  my @pos = $c =~ /<li title="\dコーナー通過順位">(\d+)<\/li>/g;
  my ($ms) = $c =~ /<p class="fin">.*?<span class="time">\(([\d.]+)\)/s;
  my $ms2 = defined $ms ? (($rank eq '1') ? -$ms : $ms) : undef;
  return { date => sprintf('%04d-%02d-%02d', $y, $m, $d), place => $pl // '', jra => $JRA{$pl // ''} ? 1 : 0, race => $race // '', rank => $rank,
    heads => ($hd // 0) + 0, umaban => (defined $ban ? $ban + 0 : undef), pop => (defined $pop ? $pop + 0 : undef), surf => $sf // '', dist => ($dist // 0) + 0,
    first => (@pos ? $pos[0] + 0 : undef), last => (@pos ? $pos[-1] + 0 : undef), msigned => (defined $ms2 ? $ms2 + 0 : undef),
    margin => (defined $ms ? $ms + 0 : undef), gbonus => ($g ? { 1 => 8, 2 => 6, 3 => 4 }->{$g} // 0 : 0) };
}

# 前回のdbのデータに残した素データ(馬ID → 近走など)
sub prev_raw {
  my $f = shift; return {} unless $f && -f $f; open my $fh, '<:raw', $f or return {}; local $/; my $s = <$fh>;
  my $d = eval { JSON::PP->new->utf8->decode($s) } or return {};
  $d = $d->{data} if ref $d->{data} eq 'HASH'; my $r = $d->{yahooRaw}; return {} unless ref $r eq 'HASH' && ($r->{src} // '') eq 'jra';
  return { map { ($_->{id} => $_) } grep { $_->{id} } @{$r->{horses} || []} };
}
if ($cmd eq 'need') { my $h = slurp(shift); my $pv = prev_raw(shift); print "$_->{id}\t$_->{cname}\n" for grep { !$_->{scr} && !$pv->{$_->{id}} } denma_rows($h); exit 0 }

# 単勝・複勝オッズのページ: 馬番 → { tan, lo, hi, bw }
sub odds_rows {
  my $h = shift; my %o; my ($tb) = $h =~ /<tbody>(.*?)<\/tbody>/s or return {};
  for my $r (split /<\/tr>/, $tb) {
    my ($ban) = $r =~ /<td class="num">\s*(\d+)\s*</ or next;
    my ($tan) = $r =~ /<td class="odds_tan">\s*(?:<strong[^>]*>)?([\d.]+)/; my ($lo, $hi) = $r =~ /class="min">([\d.]+)<.*?class="max">([\d.]+)</s;
    my ($bw) = $r =~ /<td class="h_weight">\s*(\d{3}(?:\s*(?:<span>)?\([+\-]?\d+\)(?:<\/span>)?)?)/; $bw = txt($bw) if defined $bw; $bw =~ s/\s+//g if defined $bw;
    $o{$ban} = { tan => $tan, lo => $lo, hi => $hi, bw => $bw };
  }
  return \%o;
}
if ($cmd eq 'fuku') {
  my $o = odds_rows(slurp(shift)); my %f;
  for my $b (keys %$o) { my $x = $o->{$b}; next unless defined $x->{lo}; $f{$b} = [(defined $x->{tan} ? $x->{tan} + 0 : undef), $x->{lo} + 0, $x->{hi} + 0] }
  exit 2 unless %f; print encode_json(\%f), "\n"; exit 0;
}
# ワイドのオッズページ(pw155。1頭目ごとの表: caption が1頭目の馬番、行が相手の馬番と「下限 - 上限」)
if ($cmd eq 'wide') {
  my $h = slurp(shift); my %o;
  while ($h =~ /<table[^>]*class="[^"]*\bwide\b[^"]*"[^>]*>(.*?)<\/table>/sg) {
    my $t = $1; my ($u1) = $t =~ /<caption>\s*(\d+)\s*<\/caption>/ or next;
    while ($t =~ /<th scope="row">\s*(\d+)\s*<\/th>\s*<td[^>]*>(.*?)<\/td>/sg) {
      my $u2 = $1; my $c = $2; my ($lo) = $c =~ /class="min">\s*([\d.]+)/ or next; my ($hi) = $c =~ /class="max">\s*([\d.]+)/ or next;
      $o{join '-', sort { $a <=> $b } $u1 + 0, $u2 + 0} = [$lo + 0, $hi + 0];
    }
  }
  exit 2 unless %o; print JSON::PP->new->canonical->encode(\%o), "\n"; exit 0;
}

# 見出し(日付・発走時刻・天候・馬場・レース名・条件・距離)
sub header {
  my $h = shift; my ($hd) = $h =~ /<div class="race_header">(.*?)<ul class="prize">/s; $hd //= $h;
  my ($y, $mo, $d, $place) = $hd =~ /class="cell date">\s*(\d{4})年(\d{1,2})月(\d{1,2})日（.+?）\s*\d+回(\S+?)\d+日/ or return;
  my ($th, $tm) = $hd =~ /発走時刻：<strong>(\d{1,2})時(\d{2})分/;
  my ($weather) = $hd =~ /class="weather">.*?class="txt">([^<]+)/s;
  my ($baba) = $hd =~ /class="(?:turf|durt)">.*?class="txt">([^<]+)/s;
  my ($rn) = $hd =~ /class="race_name">(.*?)<\/span>\s*<\/span>/s; $rn = txt($rn // ''); $rn =~ s/\s*G[ⅠⅡⅢ]$//;
  my $grade = $hd =~ /icon_grade_(j?g\d)/ ? $1 : '';
  my ($cat) = $hd =~ /class="cell category">([^<]*)/; my ($cl) = $hd =~ /class="cell class">(.*?)<\/div>/s; my ($wr) = $hd =~ /class="cell weight">([^<]*)/;
  my ($co) = $hd =~ /class="cell course">(.*?)<\/div>/s; $co = txt($co // '');
  my ($dist) = $co =~ /([\d,]+)\s*メートル/; $dist =~ s/,//g if defined $dist; my ($det) = $co =~ /（(.*?)）/; $det //= '';
  my ($sf) = $det =~ /^(芝|ダート|障害)/; $sf //= ($cat // '') =~ /障害/ ? '障害' : '芝';
  $sf = '障害' if ($cat // '') =~ /障害/ || $rn =~ /障害|ジャンプ/;
  return { date => sprintf('%04d-%02d-%02d', $y, $mo, $d), place => $place, time => (defined $th ? sprintf('%02d:%s', $th, $tm) : ''),
    weather => $weather // '', baba => $baba // '', name => $rn, grade => $grade, cat => txt($cat), cls => txt($cl), wr => txt($wr),
    dist => ($dist // 0) + 0, surf => $SURF{$sf}, straight => ($det =~ /直線/ ? 1 : 0) };
}

if ($cmd eq 'raw') {
  my ($file, $hdir, $kid, $prevf, $oddsf) = @ARGV; my $h = slurp($file); my $pv = prev_raw($prevf);
  exit 2 unless $h =~ /<title>出馬表/;
  my $hd = header($h) or exit 2;
  exit 3 if $hd->{grade};   # 重賞は Claude が能力値を付ける
  my ($place, $surf, $dist, $date) = @$hd{qw(place surf dist date)};
  (my $cat = $hd->{cat}) =~ s/障害//; my $cls = $surf eq '障' ? '障害' . $hd->{cls} : $cat . $hd->{cls};
  my $od = $oddsf && -s $oddsf ? odds_rows(slurp($oddsf)) : {};
  my @rows = grep { !$_->{scr} } denma_rows($h);
  exit 2 if @rows < 2;
  my @H;
  for my $r (@rows) {
    my %x = map { $_ => $r->{$_} } qw(id name umaban waku jockey kin sexage sire damsire bw odds);
    if (my $o = $od->{$r->{umaban}}) { $x{odds} = $o->{tan} if defined $o->{tan}; $x{bw} = $o->{bw} if $o->{bw} }
    $x{sexage} =~ s/\/.*//;
    if (my $p = $pv->{$r->{id}}) { $x{$_} = $p->{$_} for grep { exists $p->{$_} } qw(rdist rcourse zen intv omega); push @H, \%x; next }
    my $hp = "$hdir/$r->{id}.html"; exit 4 unless -s $hp;   # 馬ページが取れていない(次の実行に回す)
    my @runs = horse_runs(slurp($hp), $date);
    # 距離・コースの成績: [1着, 2着, 3着, 着外]
    my (%rd, %rc);
    for my $p (grep { $_->{rank} =~ /^\d+$/ && $_->{jra} } @runs) {
      my $k = $p->{rank} <= 3 ? $p->{rank} - 1 : 3;
      if ($p->{surf} eq $surf && $p->{dist} == $dist) { $rd{'当該'}[$_] //= 0 for 0 .. 3; $rd{'当該'}[$k]++ }
      if ($p->{surf} eq $surf && $p->{place} eq $place) { my $ck = "$place$surf"; $rc{$ck}[$_] //= 0 for 0 .. 3; $rc{$ck}[$k]++ }
    }
    $x{rdist} = %rd ? \%rd : {}; $x{rcourse} = %rc ? \%rc : {};
    my @past = grep { $_->{date} lt $date } @{$r->{past}};
    my @z = grep { $_->{rank} =~ /^\d+$/ } @past;
    $x{zen} = [map { my $p = $_; +{ (map { $_ => $p->{$_} } qw(heads last first umaban surf dist place margin race pop)), rank => $p->{rank} + 0 } } @z];
    if (@runs && $runs[0]{days}) { my $wk = int($runs[0]{days} / 7) - 1; $x{intv} = $wk >= 1 ? "中${wk}週" : '連闘' }
    # 近走の指数(Ω指数の代わり): 勝ち馬との差が小さいほど高く、重賞は格の分を足す。地方・海外は割り引く
    my @perf = map { 80 - 8 * clamp($_->{msigned}, -0.5, 2.5) + $_->{gbonus} - ($_->{jra} ? 0 : 6) } grep { defined $_->{msigned} } @past;
    if (@perf) {
      my ($best) = sort { $b <=> $a } @perf; my @r3 = @perf[0 .. ($#perf < 2 ? $#perf : 2)]; my $avg = 0; $avg += $_ for @r3; $avg /= @r3;
      $x{omega} = int(0.5 * $best + 0.5 * $avg + 4 + 0.5);
    }
    push @H, \%x;
  }
  my ($no) = substr($kid, -2) + 0;
  print JSON::PP->new->canonical->pretty->encode({ src => 'jra', name => $hd->{name}, date => $date, place => $place, no => $no, surface => $surf, dist => $dist,
    time => $hd->{time}, straight => $hd->{straight}, weightRule => $hd->{wr}, cls => $cls, baba => $hd->{baba}, weather => $hd->{weather}, horses => \@H });
  exit 0;
}

# 馬ページの「出走レース」(新しい順)
sub horse_runs {
  my ($h, $today) = @_; my @runs; my $tday = days(split /-/, $today);
  my ($tb) = $h =~ /<div class="main">出走レース<\/div>.*?<tbody>(.*?)<\/tbody>/s or return ();
  for my $r (split /<\/tr>/, $tb) {
    my @c = map { txt($_) } ($r =~ /<td[^>]*>(.*?)<\/td>/sg); next if @c < 8;
    my ($py, $pm, $pd) = $c[0] =~ /(\d{4})年(\d{1,2})月(\d{1,2})日/ or next;
    my $pday = days($py, $pm, $pd); next if $pday >= $tday;
    my ($sf, $pdist) = $c[3] =~ /^(芝|ダ|障)\D*?(\d{3,4})/ or next;
    push @runs, { place => $c[1], jra => $JRA{$c[1]} ? 1 : 0, surf => $sf, dist => $pdist + 0, rank => z2h($c[7]), days => $tday - $pday };
  }
  return @runs;
}
sub days { my ($y, $m, $d) = @_; ($m, $y) = ($m + 12, $y - 1) if $m < 3; return int(365.25 * $y) + int(30.6001 * ($m + 1)) + $d }

if ($cmd eq 'result') {
  my $h = slurp(shift); my @order;
  my ($tb) = $h =~ /<tbody>(.*?)<\/tbody>/s or exit 2;
  # 単勝の払戻(勝ち馬のオッズ)
  my %win; if ($h =~ /<li class="win">(.*?)<\/li>/s) { my $w = $1; while ($w =~ /<div class="num">(\d+)<\/div>\s*<div class="yen">([\d,]+)/g) { (my $y = $2) =~ s/,//g; $win{$1} = $y / 100 } }
  # 複勝の払戻(100円あたりの円。1日のまとめで買い目の成績に使う)
  my %fuku; if ($h =~ /<li class="place">(.*?)<\/li>/s) { my $w = $1; while ($w =~ /<div class="num">(\d+)<\/div>\s*<div class="yen">([\d,]+)/g) { (my $y = $2) =~ s/,//g; $fuku{$1} = $y + 0 } }
  # 全券種の払戻 { 券種 => { 組番 => 円(100円あたり) } }。組番は馬単・3連単だけ着順どおり、ほかはページの表記どおり
  my %pay; while ($h =~ /<li class="\w+">\s*<dl>\s*<dt>([^<]+)<\/dt>(.*?)<\/dl>/sg) { my ($t, $b) = ($1, $2); $t =~ s/\s+//g;
    while ($b =~ /<div class="num">([\d\-]+)<\/div>\s*<div class="yen">([\d,]+)/g) { my ($k, $y) = ($1, $2); $y =~ s/,//g; $pay{$t}{$k} = $y + 0 } }
  for my $r (split /<\/tr>/, $tb) {
    my ($rank) = $r =~ /<td class="place">\s*([^<]*?)\s*</ or next; $rank = z2h($rank);
    my ($ban) = $r =~ /<td class="num">\s*(\d+)/ or next;
    my ($name) = $r =~ /<td class="horse">.*?>([^<]+)<\/a>/s or next; $name =~ s/^\s+|\s+$//g;
    my ($jk) = $r =~ /<td class="jockey">(.*?)<\/td>/s; $jk = txt($jk); $jk =~ s/[\s▲△☆◇★]//g;
    my @pos = $r =~ /<li title="\dコーナー通過順位">(\d+)<\/li>/g;
    my ($f3) = $r =~ /<td class="f_time">\s*([\d.]+)/; my ($time) = $r =~ /<td class="time">\s*(\d+:\d{2}\.\d)/; my ($pop) = $r =~ /<td class="pop">\s*(\d+)/;
    my ($mg) = $r =~ /<td class="margin">(.*?)<\/td>/s; $mg = z2h(txt($mg)); my ($bw, $bwd) = $r =~ /<td class="h_weight">\s*(\d+)\s*<span>\(([+\-]?\d+)\)/;
    $rank = $1 if $rank =~ /(取消|除外|中止|失格)/;
    next unless $rank =~ /^\d+$|^(取消|除外|中止|失格)$/;
    push @order, { rank => ($rank =~ /^\d+$/ ? $rank + 0 : $rank), umaban => $ban + 0, name => $name, jockey => $jk,
      pop => (defined $pop ? $pop + 0 : undef), odds => $win{$ban}, pass => join('-', @pos), last4 => (@pos ? $pos[-1] + 0 : undef), f3 => $f3, time => $time,
      margin => $mg, bw => (defined $bw ? $bw + 0 : undef), bwDiff => (defined $bwd ? $bwd + 0 : undef) };
  }
  exit 2 unless grep { ($_->{rank} // '') =~ /^\d+$/ } @order;
  # レースの細部: ハロンタイム・上り3F・競走中の出来事(出遅れ・不利など)
  my ($lap) = $h =~ /ハロンタイム<\/th>\s*<td>([^<]+)/; my @laps = map { $_ + 0 } ($lap // '') =~ /([\d.]+)/g;
  my ($up) = $h =~ /上り<\/th>\s*<td>([^<]+)/; my ($up3) = ($up // '') =~ /3F\s*([\d.]+)/;
  my @ev; if ($h =~ /競走中の出来事等<\/h3>(.*?)<\/ul>/s) { my $e = $1; push @ev, map { txt($_) } $e =~ /<span class="txt">(.*?)<\/span>/sg }
  print JSON::PP->new->canonical->pretty->encode({ heads => scalar(@order), order => \@order,
    (@laps ? (laps => \@laps) : ()), ($up3 ? (last3f => $up3 + 0) : ()), (@ev ? (events => \@ev) : ()), (%fuku ? (fuku => \%fuku) : ()), (%pay ? (pay => \%pay) : ()) });
  exit 0;
}

die "使い方: perl jra.pl link|need|raw|result|fuku ...\n";
