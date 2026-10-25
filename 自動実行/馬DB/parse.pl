# JRA公式(www.jra.go.jp/JRADB)の競走馬のページを読む。馬DB(馬情報/馬DB/)を作る update.pl が使う
# ページは Shift_JIS(CP932)のまま保存して渡す。cname の末尾の2桁はチェック用の値なので自分で作らず、ページのリンクから拾う
# 使い方(update.pl からは require して関数を使う。単体でも動作確認できる):
#   perl parse.pl horse  <馬ページ.html>        … プロフィールと出走レース(JSON)
#   perl parse.pl sanku  <産駒一覧.html>        … 繁殖牝馬と産駒(JSON)
#   perl parse.pl reg    <競走馬登録.html>      … 新しく登録された馬(JSON)
#   perl parse.pl massho <抹消一覧.html>        … 登録を抹消された馬(JSON)
#   perl parse.pl ids    <ページ.html>          … ページ内の馬ページのリンク(「馬ID<TAB>cname」)
use utf8; use strict; use warnings;
use JSON::PP; use Encode ();

sub slurp { my $f = shift; open my $fh, '<:raw', $f or return ''; local $/; my $s = <$fh> // '';
  return $s =~ /charset="?Shift_JIS/i ? Encode::decode('cp932', $s) : Encode::decode('UTF-8', $s) }
sub txt { my $t = shift // ''; $t =~ s/<br\s*\/?>/ /g; $t =~ s/<[^>]*>/ /g; $t =~ s/&nbsp;/ /g; $t =~ s/&amp;/&/g; $t =~ s/&#8544;/Ⅰ/g; $t =~ s/&#8545;/Ⅱ/g; $t =~ s/&#8546;/Ⅲ/g;
  $t =~ s/[’]/'/g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub z2h { my $t = shift // ''; $t =~ tr/０-９．/0-9./; $t }
sub ymd { my $t = shift // ''; $t =~ /(\d{4})年(\d{1,2})月(\d{1,2})日/ ? sprintf('%04d-%02d-%02d', $1, $2, $3) : '' }
sub yen { my $t = txt(shift); $t =~ s/[,円\s]//g; $t =~ /^(\d+)/ ? $1 + 0 : '' }
my %GRADE = (g1 => 'G1', g2 => 'G2', g3 => 'G3', jg1 => 'J.G1', jg2 => 'J.G2', jg3 => 'J.G3', listed => 'L');

# ページ内の馬ページのリンク: [[馬ID, cname], ...](同じ馬は1回)
sub horse_links {
  my $h = shift; my (%seen, @r);
  while ($h =~ /(pw01dud\d\d(\d{10})\/[0-9A-F]{2})/g) { push @r, [$2, $1] unless $seen{$2}++ }
  return @r;
}

# 馬ページ: プロフィール・賞金・出走レース
sub horse_page {
  my $h = shift; return undef unless $h =~ /<span class="opt">競走馬情報<\/span>((?:<span class="horse_icon">.*?<\/span>)*)([^<]+)/s;
  my %p = (name => txt($2)); my $ic = $1; $p{mark} = join '', $ic =~ /alt="([^"]+)"/g;   # 印(マル外・マル地など)
  my ($en) = $h =~ /<span class="name_en">(.*?)<\/span>\s*<\/span>/s; $p{en} = txt($en);
  ($p{massho}) = map { ymd($_) } $h =~ /抹消年月日\s*([^<]+)/; $p{massho} //= '';
  while ($h =~ /<dt>([^<]+)<\/dt>\s*<dd>(.*?)<\/dd>/sg) {
    my ($k, $v) = ($1, $2);
    if ($k =~ /^(父|母|母の父|母の母)$/) {
      my $key = { '父' => 'sire', '母' => 'dam', '母の父' => 'bms', '母の母' => 'damdam' }->{$k};
      my ($cn, $id) = $v =~ /CNAME=(pw01dud\d\d(\d{10})\/[0-9A-F]{2})/;
      my ($sk) = $v =~ /'(pj01snk1\d+\/[0-9A-F]{2})'/;
      (my $nm = $v) =~ s/<span class="sanku">.*//s;
      $p{$key} = txt($nm); $p{"${key}Id"} = $id // ''; $p{"${key}Cname"} = $cn // ''; $p{"${key}Sanku"} = $sk // '';
    }
    elsif ($k eq '性別') { $p{sex} = txt($v) }
    elsif ($k eq '馬齢') { ($p{age}) = txt($v) =~ /(\d+)/ }
    elsif ($k eq '生年月日') { $p{birth} = ymd($v) }
    elsif ($k eq '毛色') { $p{color} = txt($v) }
    elsif ($k eq '馬主名') { $p{owner} = txt($v) }
    elsif ($k eq '調教師名') { my $t = txt($v); ($p{trainer}, $p{belong}) = $t =~ /^(.*?)\s*（(.+?)）\s*$/ ? ($1, $2) : ($t, '') }
    elsif ($k eq '生産牧場') { $p{breeder} = txt($v) }
    elsif ($k eq '産地') { $p{origin} = txt($v) }
    elsif ($k eq '馬名意味') { $p{meaning} = txt($v) }
    elsif ($k eq '取引市場') { $p{market} = txt($v) }
    elsif ($k =~ /^レーティング/) { $p{rating} = txt($v); my ($y) = $k =~ /(\d{4})/; $p{rating} = "$p{rating}($y)" if $y && $p{rating} ne '' }
    elsif ($k eq '総賞金') { $p{prize} = yen($v) }
    elsif ($k eq '内地方賞金') { $p{prizeNar} = yen($v) }
    elsif ($k eq '内海外賞金') { $p{prizeAbroad} = yen($v) }
    elsif ($k eq '収得賞金（平地）') { $p{shutoku} = yen($v) }
    elsif ($k eq '収得賞金（障害）') { $p{shutokuJ} = yen($v) }
  }
  my @runs;
  if ($h =~ /<div class="main">出走レース<\/div>.*?<tbody>(.*?)<\/tbody>/s) {
    for my $r (split /<\/tr>/, $1) {
      my @c = ($r =~ /<td[^>]*>(.*?)<\/td>/sg); next if @c < 14;
      my $date = ymd($c[0]) or next;
      my ($rc) = $c[2] =~ /CNAME=pw01sde10(\d\d)\d{4}\d\d\d\d(\d\d)(\d{8})\//;
      my $rid = defined $rc ? "$3$1$2" : '';
      my ($g) = $c[2] =~ /icon_grade_s_(\w+?)\.png/; my $grade = $g ? $GRADE{$g} // $g : '';
      (my $race = $c[2]) =~ s/<span class="grade_icon">.*//s;
      my ($sf, $dist) = txt($c[3]) =~ /^(芝|ダ|障)\D*?(\d{3,4})/;
      push @runs, { date => $date, place => txt($c[1]), race => txt($race), grade => $grade, raceId => $rid, surf => $sf // txt($c[3]), dist => $dist // '',
        going => txt($c[4]), heads => txt($c[5]), pop => txt($c[6]), rank => z2h(txt($c[7])), jockey => txt($c[8]), kin => txt($c[9]), bw => txt($c[10]),
        time => txt($c[11]), rt => txt($c[12]), winner => txt($c[13]) };
    }
  }
  $p{runs} = \@runs;
  return \%p;
}

# 産駒一覧: 繁殖牝馬(母)の名前・生年・血統と、産駒の一覧
sub sanku_page {
  my $h = shift; return undef unless $h =~ /<span class="opt">産駒一覧<\/span>(.*?)<\/h1>/s;
  my $hd = $1; my ($nm) = $hd =~ /^([^<]+)/; my ($en) = $hd =~ /<span class="name_en">(.*?)<\/span>\s*<\/span>/s;
  my %d = (name => txt($nm), en => txt($en), birth => ymd($hd));
  while ($h =~ /<dt>(父|母の父|母|母の母)<\/dt>\s*<dd>(.*?)<\/dd>/sg) { $d{{ '父' => 'sire', '母の父' => 'bms', '母' => 'dam', '母の母' => 'damdam' }->{$1}} = txt($2) }
  my @kids;
  if ($h =~ /<th scope="col" class="name">馬名<\/th>.*?<tbody>(.*?)<\/tbody>/s) {
    for my $r (split /<\/tr>/, $1) {
      my ($th) = $r =~ /<th scope="row">(.*?)<\/th>/s or next;
      my ($id) = $th =~ /pw01dud\d\d(\d{10})\//; my ($cn) = $th =~ /CNAME=(pw01dud\d+\/[0-9A-F]{2})/;
      my @c = ($r =~ /<td[^>]*>(.*?)<\/td>/sg);
      my $massho = $th =~ /title="抹消馬"/ ? 1 : 0; my $jg = $th =~ /<strong|<b>|class="[^"]*bold/ ? 1 : 0;
      (my $kn = $th) =~ s/<span class="icon"[^>]*>.*?<\/span>//s; my $tr = txt($c[3] // '');
      my ($trn, $bel) = $tr =~ /^(.*?)\s*（(.+?)）\s*$/ ? ($1, $2) : ($tr, '');
      push @kids, { name => txt($kn), id => $id // '', cname => $cn // '', sire => txt($c[0] // ''), sex => txt($c[1] // ''), birth => ymd($c[2] // ''),
        trainer => $trn, belong => $bel, prize => yen($c[4] // ''), massho => $massho, graded => $jg };
    }
  }
  $d{kids} = \@kids;
  return \%d;
}

# 競走馬登録(毎週): 新しく登録された馬
sub reg_page {
  my $h = shift; my ($day) = map { ymd($_) } $h =~ /競走馬登録\s*(\d{4}年\d{1,2}月\d{1,2}日)登録分/ or return undef; my @r;
  my ($tb) = $h =~ /<tbody>(.*?)<\/tbody>/s or return { date => $day, horses => [] };
  for my $r (split /<\/tr>/, $tb) {
    my ($th) = $r =~ /<th scope="row">(.*?)<\/th>/s or next; my $mg = $th =~ /alt="(マル[^"]*)"/ ? $1 : '';
    my ($dt) = $r =~ /<td class="data">(.*?)<\/td>/s; my ($sx, $col) = (split /<br>/, $dt // '')[0] =~ /^\s*(\S+?)・(\S+)/;
    my ($st) = $r =~ /<td class="stable">(.*?)<\/td>/s; my @s = map { txt($_) } split /<br>/, $st // '';
    my ($bel, $trn) = ($s[0] // '') =~ /^（(.+?)）\s*(.*)$/; my ($org, $brd) = ($s[1] // '') =~ /^(\S+)\s+(.*)$/;
    my ($pa) = $r =~ /<div class="parent">(.*?)<\/div>/s; my @pa = map { txt($_) } ($pa // '') =~ /<span>(.*?)<\/span>/sg;
    my ($gp) = $r =~ /<div class="grandparent">(.*?)<\/div>/s; my @gp = map { txt($_) } ($gp // '') =~ /<span>(.*?)<\/span>/sg;
    push @r, { name => txt($th), mark => $mg, sex => $sx // '', color => $col // '', birth => ymd($dt), belong => $bel // '', trainer => $trn // '', origin => $org // ($s[1] // ''),
      breeder => $brd // '', owner => $s[2] // '', sire => $pa[0] // '', dam => $pa[1] // '', bms => $gp[0] // '', damdam => $gp[1] // '' };
  }
  return { date => $day, horses => \@r };
}

# 抹消一覧: 登録を抹消された馬
sub massho_page {
  my $h = shift; my ($day) = map { ymd($_) } $h =~ /抹消一覧\s*(\d{4}年\d{1,2}月\d{1,2}日)抹消分/ or return undef; my @r;
  my ($tb) = $h =~ /<tbody>(.*?)<\/tbody>/s or return { date => $day, horses => [] };
  for my $r (split /<\/tr>/, $tb) {
    my ($th) = $r =~ /<th scope="row">(.*?)<\/th>/s or next; my @c = ($r =~ /<td[^>]*>(.*?)<\/td>/sg);
    my ($pa) = ($c[2] // '') =~ /<div class="parent">(.*?)<\/div>/s; my ($s, $d) = map { txt($_) } split /<br>/, $pa // '';
    push @r, { name => txt($th), trainer => txt($c[0] // ''), lastRace => txt($c[1] // ''), sire => $s // '', dam => $d // '',
      shutoku => txt($c[3] // ''), nyuchaku => txt($c[4] // '') };
  }
  return { date => $day, horses => \@r };
}

unless (caller) {
  binmode STDOUT, ':utf8';
  my ($cmd, $f) = @ARGV; my $h = slurp($f // '');
  my $js = JSON::PP->new->canonical->pretty;
  if ($cmd eq 'ids') { print "$_->[0]\t$_->[1]\n" for horse_links($h); exit 0 }
  my $r = $cmd eq 'horse' ? horse_page($h) : $cmd eq 'sanku' ? sanku_page($h) : $cmd eq 'reg' ? reg_page($h) : $cmd eq 'massho' ? massho_page($h)
    : die "使い方: perl parse.pl horse|sanku|reg|massho|ids <ページ.html>\n";
  exit 2 unless $r; print $js->encode($r);
}
1;
