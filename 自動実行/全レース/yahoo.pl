# スポーツナビ競馬(sports.yahoo.co.jp/keiba)のページを読む。競馬ラボ(keibalab.jp)に接続できないときの代わり(run.sh が使う)
# 使い方:
#   perl yahoo.pl list   <日程ページ.html> <YYYY-MM-DD> <場コード2桁>      … その日・その場の開催ID(8桁: 年2+場2+回2+日2)。無ければ終了コード 2
#   perl yahoo.pl horses <出馬表.html>                                     … 出走馬の馬ID(1行に1頭)
#   perl yahoo.pl raw    <出馬表.html> <馬ページのフォルダー> <競馬ラボ形式のレースID> [前回のdbのデータ.json] > raw.json
#        … race_json.pl に渡す素データ。馬ページは <フォルダー>/<馬ID>.html。重賞は終了コード 3、出走馬が出ていなければ 2
#          前回のdbのデータに素データ(yahooRaw)があれば、その馬の近走はそれを使い、馬ページを取り直さない(馬番・オッズ・馬体重などは出馬表から取り直す)
#   perl yahoo.pl need   <出馬表.html> [前回のdbのデータ.json]                … 馬ページを取る必要がある馬ID(前回の素データに無い馬)
#   perl yahoo.pl result <結果ページ.html>                                 … result_json.pl と同じ形の着順。結果がまだ無ければ終了コード 2
#   perl yahoo.pl fuku   <オッズページ(race/odds/tfw).html>                    … {"<馬番>":[単勝,複勝の下限,複勝の上限]}。オッズが無ければ終了コード 2
#   perl yahoo.pl wide   <オッズページ(race/odds/wide).html>                   … {"<馬番>-<馬番>":[下限,上限]}。オッズが無ければ終了コード 2
# スポーツナビには Ω指数・騎手のコース連対率・調教師×騎手・前走の馬場とペースが無い。
# Ω指数の代わりに、近走の着差(勝ち馬との差)と格(G1〜G3)から「近走の指数」を作る(検証はしていない目安)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;

my $cmd = shift // '';
sub slurp { my $f = shift; open my $fh, '<:utf8', $f or return ''; local $/; my $s = <$fh>; $s // '' }
sub txt { my $t = shift // ''; $t =~ s/<[^>]*>/ /g; $t =~ s/&nbsp;/ /g; $t =~ s/&amp;/&/g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub clamp { my ($v, $lo, $hi) = @_; $v < $lo ? $lo : $v > $hi ? $hi : $v }
my %VENUE = ('01' => '札幌', '02' => '函館', '03' => '福島', '04' => '新潟', '05' => '東京', '06' => '中山', '07' => '中京', '08' => '京都', '09' => '阪神', '10' => '小倉');
my %JRA = map { $_ => 1 } values %VENUE;

if ($cmd eq 'list') {
  my ($file, $date, $v) = @ARGV; my $h = slurp($file);
  my ($dd) = $date =~ /-(\d{2})$/; $dd += 0;
  # 日付の見出し(「24日（土）」)の後に、その日の各場のレース一覧へのリンクが並ぶ
  my $cur = 0;
  while ($h =~ /(\d{1,2})日（.）|\/keiba\/race\/list\/(\d{8})/g) {
    if (defined $1) { $cur = $1 + 0; next }
    my $id = $2; next unless substr($id, 2, 2) eq $v;
    if ($cur == $dd) { print "$id\n"; exit 0 }
  }
  exit 2;
}

# 出馬表の各行
sub denma_rows {
  my $h = shift; my @rows;
  while ($h =~ /<tr class="hr-table__row">(.*?)<\/tr>/sg) {
    my $r = $1; my ($hid, $name) = $r =~ /\/keiba\/directory\/horse\/(\d+)\/"[^>]*_cl_link:horse;">([^<]+)<\/a>/ or next;
    my @num = map { txt($_) } ($r =~ /hr-table__data--number">(.*?)<\/td>/sg);
    my ($sexage) = $r =~ /_cl_link:horse;">[^<]+<\/a>\s*<p>([^<\/]+)/;
    my ($jk, $kin) = $r =~ /_cl_link:jockey;">([^<]+)<\/a><p>(?:<span[^>]*><\/span>)?\s*([^<]*)<\/p>/;
    my ($sire) = $r =~ /父：(?:<a[^>]*>)?([^<\n]+?)\s*(?:<\/a>|\n|<\/p>)/;
    my ($dsire) = $r =~ /\(母父：(?:<a[^>]*>)?([^<)]+?)\s*(?:<\/a>)?\)/;
    my @nm = $r =~ /hr-table__data--name"><p>([^<]*)<\/p>/g;
    my ($oddc) = $r =~ /hr-table__data--odds">(.*?)<\/td>/s; $oddc //= '';
    my ($pop) = $oddc =~ /^\s*(\d+)\s*\(/; my ($odds) = $oddc =~ /<span>\s*([\d.]+)\s*<\/span>/;
    my $scr = $r =~ /取消|除外/ ? 1 : 0;
    $jk //= ''; $jk =~ s/\s+//g; $kin //= ''; $kin =~ s/\s+//g;
    $sire //= ''; $sire =~ s/\s+$//; $dsire //= ''; $dsire =~ s/’/'/g;
    push @rows, { id => $hid, name => $name, waku => ($num[0] // '') =~ /^(\d+)$/ ? $1 : '', umaban => ($num[1] // '') =~ /^(\d+)$/ ? $1 : '',
      sexage => (($sexage // '') =~ /^(\S+?\d+)/ ? $1 : ''), jockey => $jk, kin => $kin, sire => $sire, damsire => $dsire,
      bw => ($nm[-1] // '') =~ /^\d{3}/ ? $nm[-1] : '', odds => $odds // '', pop => $pop, scr => $scr };
  }
  return @rows;
}

if ($cmd eq 'horses') { my $h = slurp(shift); print "$_->{id}\n" for denma_rows($h); exit 0 }
# 前回のdbのデータに残した素データ(馬ID → 近走など)
sub prev_raw {
  my $f = shift; return {} unless $f && -f $f; my $s = slurp($f); my $d = eval { JSON::PP->new->decode($s) } or return {};
  $d = $d->{data} if ref $d->{data} eq 'HASH'; my $r = $d->{yahooRaw}; return {} unless ref $r eq 'HASH';
  return { map { ($_->{id} => $_) } grep { $_->{id} } @{$r->{horses} || []} };
}
if ($cmd eq 'need') { my $h = slurp(shift); my $pv = prev_raw(shift); print "$_->{id}\n" for grep { !$pv->{$_->{id}} } denma_rows($h); exit 0 }

if ($cmd eq 'raw') {
  my ($file, $hdir, $kid, $prevf) = @ARGV; my $h = slurp($file); my $pv = prev_raw($prevf);
  my ($title) = $h =~ /<title>([^<]*)/; $title //= '';
  exit 2 unless $title =~ /出馬表/;
  exit 3 if $h =~ /class="hr-label hr-label--j?g\d/;   # 重賞は Claude が能力値を付ける
  my $info = txt($h =~ /(\d{4}年\d{1,2}月\d{1,2}日（.）.*?)(?:<table|hr-table)/s ? $1 : '');
  my ($y, $mo, $d, $kai, $place) = $info =~ /(\d{4})年(\d{1,2})月(\d{1,2})日（.）\s*(\d+)回(\D+?)\d+日/ or exit 2;
  my ($time) = $info =~ /(\d{1,2}:\d{2})発走/;
  my ($sf, $dir, $dist) = $info =~ /(芝|ダート|障害)・?(\S*?)\s*(\d{3,4})m/; $sf //= '芝';
  my $surf = { '芝' => '芝', 'ダート' => 'ダ', '障害' => '障' }->{$sf};
  my ($baba) = $info =~ /馬場：\s*(良|稍重|重|不良)/;
  my ($wr) = $info =~ /(定量|別定|馬齢|ハンデ)/;
  my ($age) = $info =~ /\s(\d歳(?:以上)?)\s/; my ($c) = $info =~ /\s(新馬|未勝利|\d勝クラス|オープン)\b/;
  $c = $1 if !$c && $info =~ /(新馬|未勝利|\d勝クラス|オープン)/;
  my $cls = $surf eq '障' ? '障害' . ($c // '') : (($age // '') . ($c // ''));
  my ($rname) = $title =~ /\d{4}年(.*?)\s*出馬表/; $rname //= ''; $rname =~ s/^サラ系//;
  my ($no) = substr($kid, -2) + 0;
  my $date = sprintf('%04d-%02d-%02d', $y, $mo, $d);
  my @rows = grep { !$_->{scr} } denma_rows($h);
  exit 2 if @rows < 2;
  my @H;
  for my $r (@rows) {
    my %x = map { $_ => $r->{$_} } qw(id name umaban waku jockey kin sexage sire damsire bw odds);
    if (my $p = $pv->{$r->{id}}) { $x{$_} = $p->{$_} for grep { exists $p->{$_} } qw(rdist rcourse zen intv omega); push @H, \%x; next }
    my $hp = "$hdir/$r->{id}.html"; exit 4 unless -s $hp;   # 馬ページが取れていない(次の実行に回す)
    my @runs = past_runs(slurp($hp), $date);
    # 距離・コースの成績: [1着, 2着, 3着, 着外]
    my (%rd, %rc);
    for my $p (grep { $_->{rank} =~ /^\d+$/ && $_->{jra} } @runs) {
      my $k = $p->{rank} <= 3 ? $p->{rank} - 1 : 3;
      if ($p->{surf} eq $surf && $p->{dist} == $dist) { $rd{'当該'}[$_] //= 0 for 0 .. 3; $rd{'当該'}[$k]++ }
      if ($p->{surf} eq $surf && $p->{place} eq $place) { my $ck = "$place$surf"; $rc{$ck}[$_] //= 0 for 0 .. 3; $rc{$ck}[$k]++ }
    }
    $x{rdist} = %rd ? \%rd : {}; $x{rcourse} = %rc ? \%rc : {};
    my @z = grep { $_->{rank} =~ /^\d+$/ } @runs[0 .. ($#runs < 4 ? $#runs : 4)];
    $x{zen} = [map { my $p = $_; +{ (map { $_ => $p->{$_} } qw(heads last first umaban surf dist place margin race pop)), rank => $p->{rank} + 0 } } @z];
    if (@runs && $runs[0]{days}) { my $wk = int($runs[0]{days} / 7) - 1; $x{intv} = $wk >= 1 ? "中${wk}週" : '連闘' }
    # 近走の指数(Ω指数の代わり): 勝ち馬との差が小さいほど高く、重賞は格の分を足す。地方・海外は割り引く
    my @perf = map { 80 - 8 * clamp($_->{msigned}, -0.5, 2.5) + $_->{gbonus} - ($_->{jra} ? 0 : 6) } grep { defined $_->{msigned} } @runs[0 .. ($#runs < 4 ? $#runs : 4)];
    if (@perf) {
      my ($best) = sort { $b <=> $a } @perf; my @r3 = @perf[0 .. ($#perf < 2 ? $#perf : 2)]; my $avg = 0; $avg += $_ for @r3; $avg /= @r3;
      $x{omega} = int(0.5 * $best + 0.5 * $avg + 4 + 0.5);
    }
    push @H, \%x;
  }
  print JSON::PP->new->canonical->pretty->encode({ name => $rname, date => $date, place => $place, no => $no, surface => $surf, dist => ($dist // 0) + 0,
    time => $time // '', straight => (($dir // '') =~ /直/ ? 1 : 0), weightRule => $wr // '', cls => $cls, baba => $baba // '', horses => \@H });
  exit 0;
}

# 馬ページの「出走レース」(新しい順)
sub past_runs {
  my ($h, $today) = @_; my @runs;
  my ($ty, $tm, $td) = split /-/, $today; my $tday = days($ty, $tm, $td);
  while ($h =~ /<tr class="hr-table__row">\s*<td class="hr-table__data hr-table__data--date">(\d{4})\/(\d{2})\/(\d{2})<\/td>(.*?)<\/tr>/sg) {
    my ($py, $pm, $pd, $r) = ($1, $2, $3, $4);
    my $pday = days($py, $pm, $pd); next if $pday >= $tday;
    my ($rc) = $r =~ /hr-table__data--race">(.*?)<\/td>/s; $rc //= '';
    my ($race) = $rc =~ /_cl_link:race">([^<]*)</; my ($g) = $rc =~ /hr-label--j?g(\d)/;
    my ($pl, $ps, $pdist, $hd) = txt($rc =~ /<p>(.*?)<\/p>/s ? $1 : '') =~ /^(\S+)\s+(芝|ダ|障)\D*?(\d{3,4})m\s+(\d+)頭/ or next;
    my @num = map { txt($_) } ($r =~ /hr-table__data--number[^"]*">(.*?)<\/td>/sg);
    my ($tm2) = $r =~ /hr-table__data--time">(.*?)<\/td>/s; my ($ms) = ($tm2 // '') =~ /\(\s*([+\-]?[\d.]+)\s*\)/;
    my ($ord) = $r =~ /hr-table__data--order">([\d\-]+)/; my @pos = grep { /^\d+$/ } split /-/, ($ord // '');
    my ($ppop) = $r =~ /hr-table__data--odds">\s*(\d+)/;   # 人気(その下の括弧がオッズ)
    push @runs, { rank => $num[0] // '', umaban => ($num[1] // '') =~ /^(\d+)$/ ? $1 + 0 : undef, heads => $hd + 0, surf => $ps, dist => $pdist + 0, pop => (defined $ppop ? $ppop + 0 : undef),
      place => $pl, jra => $JRA{$pl} ? 1 : 0, race => $race // '', days => $tday - $pday,
      msigned => (defined $ms ? $ms + 0 : undef), margin => (defined $ms ? abs($ms) + 0 : undef),
      gbonus => ($g ? { 1 => 8, 2 => 6, 3 => 4 }->{$g} // 0 : 0), first => (@pos ? $pos[0] + 0 : undef), last => (@pos ? $pos[-1] + 0 : undef) };
  }
  return @runs;
}
sub days { my ($y, $m, $d) = @_; ($m, $y) = ($m + 12, $y - 1) if $m < 3; return int(365.25 * $y) + int(30.6001 * ($m + 1)) + $d }

# 単勝・複勝オッズのページ(行: 枠番|馬番|馬名|単勝|複勝の下限 - 上限)から、馬番ごとの [単勝, 複勝の下限, 複勝の上限] を取り出す
if ($cmd eq 'fuku') {
  my $h = slurp(shift); my %o;
  while ($h =~ /<tr[^>]*>(.*?)<\/tr>/sg) {
    my @c = map { txt($_) } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
    next unless @c >= 5 && $c[1] =~ /^\d+$/;
    my ($lo, $hi) = $c[4] =~ /^([\d.]+)\s*-\s*([\d.]+)$/ or next;
    $o{$c[1]} = [($c[3] =~ /^[\d.]+$/ ? $c[3] + 0 : undef), $lo + 0, $hi + 0];
  }
  exit 2 unless %o; print encode_json(\%o), "\n"; exit 0;
}

# ワイドのオッズページ(race/odds/wide。1頭目ごとの表に、相手の馬番と「下限 - 上限」が並ぶ。終わったレースは確定オッズ)から {"<小さい馬番>-<大きい馬番>":[下限,上限]}
if ($cmd eq 'wide') {
  my $h = slurp(shift); my %o;
  while ($h =~ /<table[^>]*hr-tableLeftTop--oddsW[^>]*>(.*?)<\/table>/sg) {
    my $t = $1; my ($u1) = $t =~ /<thead>.*?<th[^>]*>\s*(\d+)\s*<\/th>/s or next;
    while ($t =~ /<th[^>]*scope="row">\s*(\d+)\s*<\/th>\s*<td[^>]*>(.*?)<\/td>/sg) {
      my $u2 = $1; my ($lo, $hi) = txt($2) =~ /^([\d.]+)\s*-\s*([\d.]+)$/ or next;
      $o{join '-', sort { $a <=> $b } $u1 + 0, $u2 + 0} = [$lo + 0, $hi + 0];
    }
  }
  exit 2 unless %o; print JSON::PP->new->canonical->encode(\%o), "\n"; exit 0;
}

if ($cmd eq 'result') {
  my $h = slurp(shift); my @order;
  while ($h =~ /<tr[^>]*>(.*?)<\/tr>/sg) {
    my @c = map { txt($_) } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
    next if @c < 8;
    # 着順・枠・馬番・馬名 性齢/馬体重・タイム 着差・通過 上がり・騎手 斤量・人気 (オッズ)
    my ($rank, $waku, $ban, $nm, $tm, $pass, $jk, $po) = @c;
    next unless defined $ban && $ban =~ /^\d+$/ && $rank =~ /^\d+$|^(取消|除外|中止|失格)$/;
    my ($name) = $nm =~ /^(\S+)/; $name =~ s/^(?:[\(（\[［][^\)）\]］]{1,2}[\)）\]］]|[□○◇☆▲△])+//;
    # 通過順の欄: 「3-2 37.4」(通過順と上がり)。2026-10 からは上がりだけ「37.4」のことがあり、それを通過順と読まない
    my @pos = grep { /^\d+$/ } split /-/, (($pass // '') =~ /^(\d+(?:-\d+)*)(?:\s|$)/ ? $1 : '');
    my ($f3) = ($pass // '') =~ /(?:^|\s)(\d{2}\.\d)$/;
    # 人気の欄: 「1 (2.3)」。人気が「-」でオッズだけのことがあり、そのときは下でオッズの順から人気を付ける
    my ($pop) = ($po // '') =~ /^(\d+)\s*\(/; my ($odds) = ($po // '') =~ /\(\s*([\d.]+)\s*\)/;
    my ($time) = ($tm // '') =~ /^(\d+:\d{2}\.\d)/; (my $j = $jk // '') =~ s/\s*[▲△☆◇★]?[\d.]+$//; $j =~ s/\s+//g;
    push @order, { rank => ($rank =~ /^\d+$/ ? $rank + 0 : $rank), umaban => $ban + 0, name => $name, jockey => $j,
      pop => (defined $pop ? $pop + 0 : undef), odds => (defined $odds ? $odds + 0 : undef),
      pass => join('-', @pos), last4 => (@pos ? $pos[-1] + 0 : undef), f3 => $f3, time => $time };
  }
  exit 2 unless grep { ($_->{rank} // '') =~ /^\d+$/ } @order;
  unless (grep { defined $_->{pop} } @order) { my $i = 0; $_->{pop} = ++$i for sort { $a->{odds} <=> $b->{odds} } grep { $_->{odds} } @order }
  print JSON::PP->new->canonical->pretty->encode({ heads => scalar(@order), order => \@order });
  exit 0;
}

die "使い方: perl yahoo.pl list|horses|raw|result ...\n";
