# JRA-VAN Data Lab の全データ(馬情報/JRA-VAN/全データ)から、競走馬・出走履歴・繁殖馬を馬DBと同じ形の表にする(2026-10-29 ユーザー指示「取り込んで」)
#   JRA-VAN のデータは再配布できないので、GitHub に送る 馬情報/馬DB には混ぜず、PCだけの 馬情報/JRA-VAN/馬DB/ に置く
#   ・競走馬/<生年>年生.tsv   競走馬マスタ(UM)の全馬。列は馬DBの競走馬と同じ(馬名意味・取引市場・レーティング・地方/海外賞金・cname は空)
#   ・出走履歴/<生年>年生.tsv レース(RACE の RA・SE。1986年〜)。中央のレースと、中央の馬が出た地方・海外のレース。Rt は空
#   ・繁殖馬.tsv              繁殖馬マスタ(HN)の全馬(国内外の種牡馬・繁殖牝馬)。産駒の数は産駒マスタ(SK = 国内で血統登録された全部の馬。地方の馬も入る)から
#   まとめ(種牡馬・繁殖牝馬・概要)は最後に update.pl full が作る(馬DB の JRA公式のページを先に使い、無い馬をここから補う)
# 使い方: perl 自動実行/馬DB/jv.pl [force]   (元のデータが前回から変わっていなければ、まとめだけ作り直す。JRA-VAN の update.sh のあとに呼ぶ)
use utf8; use strict; use warnings;
use Encode qw(decode encode); use File::Basename qw(dirname); use File::Spec; use File::Path qw(make_path); use File::Glob (); use POSIX qw(strftime);
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
my $HERE = decode('UTF-8', dirname(File::Spec->rel2abs(__FILE__))); my $ROOT = "$HERE/../..";
my $SRC = "$ROOT/馬情報/JRA-VAN/全データ"; my $OUT = "$ROOT/馬情報/JRA-VAN/馬DB"; my $DB = "$ROOT/馬情報/馬DB"; my $CACHE = "$OUT/.レース";
make_path("$OUT/競走馬", "$OUT/出走履歴", $CACHE);
my $TODAY = strftime('%Y-%m-%d', gmtime(time + 9 * 3600)); my $TODAY8 = $TODAY =~ s/-//gr;
sub logm { print strftime('[%H:%M:%S] ', gmtime(time + 9 * 3600)), @_, "\n" }
sub files { map { decode('UTF-8', $_) } File::Glob::bsd_glob(encode('UTF-8', shift)) }
sub stamp { my @s = stat(encode('UTF-8', shift)); @s ? "$s[7] $s[9]" : '' }
sub wtsv { my ($f, $cols, $rows) = @_; open my $h, '>:utf8', "$f.tmp" or die "$f: $!"; print $h join("\t", @$cols), "\n";
  print $h join("\t", map { my $v = $_ // ''; $v =~ s/[\t\r\n]/ /g; $v } @$_), "\n" for @$rows; close $h; rename "$f.tmp", $f or die "$f: $!" }
sub rlines { my $f = shift; open my $h, '<:utf8', $f or return (); map { s/\r?\n$//r } <$h> }

my @PCOL = qw(id 馬名 欧字名 性 生年月日 毛色 父 父ID 母 母ID 母の父 母の父ID 母の母 母の母ID 馬主 調教師 所属 生産牧場 産地 馬名意味 取引市場 レーティング
  総賞金 地方賞金 海外賞金 収得賞金 収得賞金障害 成績 芝 ダ 障 出走数 最終出走日 最終レース 最終着順 抹消日 母産駒cname 取得日 cname 印);
my @RCOL = qw(id 年月日 場 レース名 格 レースID 芝ダ 距離 馬場 頭数 人気 着順 騎手 斤量 馬体重 タイム Rt 1着馬(2着馬));

# 元のデータが前回と同じなら、表は作り直さない
my @src = ("$SRC/DIFN.txt", "$SRC/BLDN.txt", files("$SRC/RACE/[12][0-9][0-9][0-9].txt"));
my $now = join "\n", map { "$_ " . stamp($_) } @src;
sub summary { system('perl', encode('UTF-8', "$HERE/update.pl"), 'full') == 0 or die "update.pl full が失敗\n" }
if (($ARGV[0] // '') ne 'force' && join("\n", rlines("$OUT/.元のデータ")) eq $now) { logm('JRA-VAN: 元のデータが前回と同じ'); summary(); exit 0 }

# ---- 固定長(Shift-JIS)のレコードから取り出す。位置は JV-Data 仕様書(1から数える) ----
sub f { my ($l, $p, $n) = @_; my $s = decode('cp932', substr($l, $p - 1, $n)); $s =~ s/^[ \x{3000}]+|[ \x{3000}]+$//g; $s }
# 名前を馬DB(JRA公式)の書き方に: 全角の空白・英数字は半角、株式会社 → (株)
sub nm { my $s = shift // ''; $s =~ tr/\x{3000}Ａ-Ｚａ-ｚ０-９/ A-Za-z0-9/; $s =~ s/\s*株式会社\s*/(株)/g; $s =~ s/\s*有限会社\s*/(有)/g; $s =~ s/\s*合同会社\s*/(同)/g; $s =~ s/\s+/ /g; $s =~ s/^ | $//g; $s }
sub ymd { my $d = shift; $d =~ /^(\d{4})(\d\d)(\d\d)$/ && $d ne '00000000' ? "$1-$2-$3" : '' }
my %SEX = (1 => '牡', 2 => '牝', 3 => 'せん');
my %COLOR = ('01' => '栗毛', '02' => '栃栗毛', '03' => '鹿毛', '04' => '黒鹿毛', '05' => '青鹿毛', '06' => '青毛', '07' => '芦毛', '08' => '栗粕毛', '09' => '鹿粕毛', '10' => '青粕毛', '11' => '白毛');
# 馬記号(馬DB の「印」の書き方。馬DB と JRA-VAN の両方にいる馬で確かめた)
my %MARK = ('01' => 'マルチュウ', '02' => 'カクチュウ', '03' => 'マルチチ', '04' => 'マルイチ', '05' => 'マルチ', '06' => 'マルガイ', '07' => 'マルチチマルチュウ', '08' => 'マルチチマルイチ',
  '09' => 'マルチチマルチ', '10' => 'マルイチマルチ', '11' => 'マルガイマルチ', '12' => 'マルチチマルイチマルチ', '15' => 'マルショウ', '21' => 'カクチ', '22' => 'マルガイカクチ',
  '23' => 'マルチチカクチ', '24' => 'マルイチカクチ', '25' => 'マルチチマルイチカクチ', '26' => 'カクガイ');
my %BELONG = (1 => '美浦', 2 => '栗東');
my %MOCHI = (0 => '内国産', 1 => '持込', 2 => '輸入内国産扱い', 3 => '輸入', 9 => 'その他');
my %PLACE = ('01' => '札幌', '02' => '函館', '03' => '福島', '04' => '新潟', '05' => '東京', '06' => '中山', '07' => '中京', '08' => '京都', '09' => '阪神', '10' => '小倉',
  30 => '門別', 31 => '北見', 32 => '岩見', 33 => '帯広', 34 => '旭川', 35 => '盛岡', 36 => '水沢', 37 => '上山', 38 => '三条', 39 => '足利', 40 => '宇都', 41 => '高崎', 42 => '浦和',
  43 => '船橋', 44 => '大井', 45 => '川崎', 46 => '金沢', 47 => '笠松', 48 => '名古', 49 => '紀三', 50 => '園田', 51 => '姫路', 52 => '益田', 53 => '福山', 54 => '高知', 55 => '佐賀',
  56 => '荒尾', 57 => '中津', 58 => '札幌', 59 => '函館', 60 => '新潟', 61 => '中京');
my %GRADE = (A => 'G1', B => 'G2', C => 'G3', F => 'J.G1', G => 'J.G2', H => 'J.G3', L => 'L');
my %GOING = (1 => '良', 2 => '稍重', 3 => '重', 4 => '不良');
my %AGE = (11 => [2, ''], 12 => [3, ''], 13 => [3, '上'], 14 => [4, '上'], 18 => [3, '上', '障害'], 19 => [4, '上', '障害'], 21 => [2, '', 'アラ'], 22 => [3, '', 'アラ'], 23 => [3, '上', 'アラ'], 24 => [4, '上', 'アラ']);
my %ABN = (1 => '取消', 2 => '除外', 3 => '除外', 4 => '中止', 5 => '失格');

# ---- マスタ(DIFN): 騎手・調教師・馬主・競走馬。同じ馬が何度も出てくるときは作成日が新しいもの ----
my (%KS, %CH, %BN, %UM, %umd);
open my $h, '<:raw', encode('UTF-8', "$SRC/DIFN.txt") or die "DIFN.txt: $!";
while (my $l = <$h>) {
  my $t = substr($l, 0, 2);
  if ($t eq 'KS') { $KS{substr($l, 11, 5)} = nm(f($l, 42, 34)) } elsif ($t eq 'CH') { $CH{substr($l, 11, 5)} = nm(f($l, 42, 34)) }
  elsif ($t eq 'BN') { $BN{substr($l, 11, 6)} = nm(f($l, 18, 64)) }
  elsif ($t eq 'UM') { my $id = substr($l, 11, 10); my $d = substr($l, 3, 8); next if ($umd{$id} // '') gt $d; $umd{$id} = $d;
    if (substr($l, 2, 1) eq '0') { delete $UM{$id}; next }   # データ区分0 = 提供ミスで削除
    my @c = map { substr($l, 1142 + 3 * $_, 3) + 0 } 0 .. 41;   # 芝(直・右・左)・ダ(直・右・左)・障害の着回数(1〜5着・着外)
    my @sf = map { my $g = $_; my @x = (0) x 4; for my $i (@$g) { $x[$_ < 3 ? $_ : 3] += $c[$i * 6 + $_] for 0 .. 5 } join '-', @x } [0, 1, 2], [3, 4, 5], [6];
    my @tot = map { substr($l, 1106 + 3 * $_, 3) + 0 } 0 .. 5; my @pr = map { substr($l, 1052 + 9 * $_, 9) + 0 } 0 .. 5;
    $UM{$id} = { d => $d, massho => substr($l, 21, 1) eq '1' ? ymd(substr($l, 30, 8)) : '', birth => ymd(substr($l, 38, 8)), name => f($l, 47, 36), en => f($l, 119, 60),
      mark => $MARK{substr($l, 198, 2)} // '', sex => $SEX{substr($l, 200, 1)} // '', color => $COLOR{substr($l, 202, 2)} // '',
      ped => [map { [substr($l, 204 + 46 * $_, 10), f($l, 215 + 46 * $_, 36)] } 0 .. 13],
      belong => $BELONG{substr($l, 848, 1)} // '', trainer => $CH{substr($l, 849, 5)} // '', trainerS => nm(f($l, 855, 8)), breeder => nm(f($l, 891, 72)), origin => nm(f($l, 963, 20)),
      ownerC => substr($l, 982, 6), ownerS => nm(f($l, 989, 64)),
      prize => ($pr[0] + $pr[1] + $pr[2] + $pr[3]) * 100, shutoku => $pr[4] * 100, shutokuJ => $pr[5] * 100,
      rec => join('-', @tot[0 .. 2], $tot[3] + $tot[4] + $tot[5]), nrec => $tot[0] + $tot[1] + $tot[2] + $tot[3] + $tot[4] + $tot[5], sf => \@sf };
  }
}
close $h; $_->{trainer} ||= $_->{trainerS} for values %UM;   # 調教師マスタに無い(古い)ときは略称
logm('JRA-VAN: 競走馬マスタ ' . scalar(keys %UM) . ' 頭・騎手 ' . scalar(keys %KS) . '・調教師 ' . scalar(keys %CH) . '・馬主 ' . scalar(keys %BN));

# ---- 繁殖馬(HN)・産駒(SK)(BLDN) ----
my (%HN, %hnd, %SK, %skd);
open $h, '<:raw', encode('UTF-8', "$SRC/BLDN.txt") or die "BLDN.txt: $!";
while (my $l = <$h>) {
  my $t = substr($l, 0, 2); my $d = substr($l, 3, 8);
  if ($t eq 'HN') { my $k = substr($l, 11, 10); next if ($hnd{$k} // '') gt $d; $hnd{$k} = $d; if (substr($l, 2, 1) eq '0') { delete $HN{$k}; next }
    my $id = substr($l, 29, 10); $HN{$k} = { id => $id =~ /^0+$/ ? '' : $id, name => f($l, 41, 36), en => f($l, 117, 80), year => substr($l, 196, 4) =~ s/^0000$//r, sex => $SEX{substr($l, 200, 1)} // '',
      color => $COLOR{substr($l, 202, 2)} // '', mochi => $MOCHI{substr($l, 204, 1)} // '', imp => substr($l, 205, 4) =~ s/^0000$//r, origin => nm(f($l, 210, 20)), f => substr($l, 229, 10), m => substr($l, 239, 10) } }
  elsif ($t eq 'SK') { my $id = substr($l, 11, 10); next if ($skd{$id} // '') gt $d; $skd{$id} = $d; if (substr($l, 2, 1) eq '0') { delete $SK{$id}; next }
    $SK{$id} = [substr($l, 21, 4), substr($l, 66, 10), substr($l, 76, 10)] }   # 生年・父・母(繁殖登録番号)
}
close $h; undef %hnd; undef %skd;
logm('JRA-VAN: 繁殖馬 ' . scalar(keys %HN) . ' 頭・産駒 ' . scalar(keys %SK) . ' 頭');
my %idname = map { ($_ => $HN{$_}{name}) } keys %HN;   # 繁殖登録番号 → 馬名(UM に名前が無い古い祖先用)

# ---- レース(RACE/<年>.txt の RA・SE)→ 年ごとの出走の表(.レース/<年>.tsv)。元のファイルが変わった年だけ作り直す ----
sub racename { my ($r) = @_; return $r->{title} if $r->{title} ne '';
  my $ag = $AGE{$r->{kind}} or return ''; my $age = $ag->[0] + ($r->{date} lt '20010101' ? 1 : 0);   # 2000年までは数え年(旧表記)
  my $c = $r->{cond}; my $cn = $c eq '701' ? '新馬' : $c eq '702' ? '未出走' : $c eq '703' ? '未勝利' : $c eq '999' ? 'オープン' : $c =~ /^0\d\d$/ && $c > 0 ?
    ($r->{date} ge '20190601' && $c =~ /^0(05|10|16)$/ ? { '05' => 1, 10 => 2, 16 => 3 }->{$1} . '勝クラス' : ($c * 100) . '万下') : '';
  ($ag->[2] // '') . "${age}歳$ag->[1]$cn" }
for my $src (files("$SRC/RACE/[12][0-9][0-9][0-9].txt")) {
  my ($y) = $src =~ /(\d{4})\.txt$/; my $cf = "$CACHE/$y.tsv"; my $st = stamp($src);
  next if -e encode('UTF-8', $cf) && ((rlines("$cf.元"))[0] // '') eq $st;
  my (%RA, %SE); open my $g, '-|', 'grep', '-a', '-E', '^(RA|SE)', encode('UTF-8', $src) or die "$src: $!";
  while (my $l = <$g>) {
    my $t = substr($l, 0, 2); my $k = substr($l, 11, 16); my $d = substr($l, 3, 8); my $kbn = substr($l, 2, 1);
    if ($t eq 'RA') { next if $RA{$k} && $RA{$k}{d} gt $d; if ($kbn eq '0') { delete $RA{$k}; next }
      my $tr = substr($l, 705, 2); my $sf = $tr >= 10 && $tr <= 22 ? '芝' : $tr >= 23 && $tr <= 29 ? 'ダ' : $tr >= 51 && $tr <= 59 ? '障' : '';
      my $pc = substr($l, 19, 2); my $gr = substr($l, 614, 1);
      $RA{$k} = { d => $d, date => substr($l, 11, 8), place => $PLACE{$pc} // ($pc =~ /^[A-Z]/ ? '海外' : ''), r => substr($l, 25, 2), pc => $pc, title => nm(f($l, 33, 60)), kind => substr($l, 616, 2), cond => substr($l, 634, 3),
        grade => $kbn eq 'A' && $gr =~ /^[ABC]$/ ? 'jpn' . (ord($gr) - 64) : $GRADE{$gr} // '', dist => substr($l, 697, 4) + 0, sf => $sf,
        going => $GOING{substr($l, $sf eq 'ダ' ? 889 : 888, 1)} // '', heads => substr($l, 883, 2) + 0 } }
    else { my $kk = $k . substr($l, 28, 2); next if $SE{$kk} && $SE{$kk}[0] gt $d; $kbn eq '0' ? delete $SE{$kk} : ($SE{$kk} = [$d, $l]) }
  }
  close $g; my @rows;
  for my $kk (keys %SE) {
    my $l = $SE{$kk}[1]; my $r = $RA{substr($kk, 0, 16)} or next; next unless $r->{date} lt $TODAY8;
    my $ab = substr($l, 331, 1); my $rank = substr($l, 334, 2) + 0; next unless $rank || $ab;   # まだ走っていない(出馬表だけ)
    my $rk = $ABN{$ab} // ($ab eq '7' ? "$rank (降着)" : $rank || '');
    my $tm = substr($l, 338, 4); $tm = $tm =~ /^(\d)(\d\d)(\d)$/ && $tm > 0 ? ($1 ? "$1:$2.$3" : ($2 + 0) . ".$3") : '';
    my $bw = substr($l, 324, 3); my $pop = substr($l, 363, 2) + 0; my $jk = substr($l, 296, 5); my $op = nm(f($l, 404, 36));
    push @rows, [substr($l, 30, 10), ymd($r->{date}), $r->{place}, racename($r), $r->{grade}, $r->{date} . ($r->{pc} =~ /^\d+$/ ? $r->{pc} : '00') . $r->{r}, $r->{sf}, $r->{dist}, $r->{going}, $r->{heads},
      $pop || '', $rk, $KS{$jk} // nm(f($l, 307, 8)), sprintf('%.1f', substr($l, 288, 3) / 10), $bw =~ /^\d+$/ && $bw > 0 && $bw < 999 ? $bw + 0 : '', $tm, '', $rank == 1 ? "($op)" : $op];
  }
  wtsv($cf, \@RCOL, \@rows); open my $o, '>:utf8', "$cf.元" or die; print $o "$st\n"; close $o;
  logm("JRA-VAN: $y 年のレース " . scalar(keys %RA) . ' 件・出走 ' . scalar(@rows) . ' 頭');
}

# ---- 出走履歴(生年ごと)と、競走馬の最終出走 ----
# レース名・格は、馬DB(JRA公式)に同じレースがあればそちらの書き方にそろえる
my %rname; for my $f (files("$DB/出走履歴/*.tsv")) { open my $g, '<:utf8', $f or next; <$g>; while (<$g>) { my @c = split /\t/; $rname{$c[5]} //= [$c[3], $c[4]] if $c[5] } }
my (%runs, %last, %nrun);
for my $cf (sort { $a cmp $b } files("$CACHE/[12][0-9][0-9][0-9].tsv")) {
  open my $g, '<:utf8', $cf or next; <$g>;
  while (my $l = <$g>) { chomp $l; my @c = split /\t/, $l, -1; next unless $UM{$c[0]};
    if (my $n = $rname{$c[5]}) { @c[3, 4] = @$n }
    push @{$runs{substr($c[0], 0, 4)}}, \@c; $nrun{$c[0]}++;
    $last{$c[0]} = \@c if !$last{$c[0]} || $c[1] ge $last{$c[0]}[1] }
}
undef %rname;
for my $y (keys %runs) { wtsv("$OUT/出走履歴/${y}年生.tsv", \@RCOL, [sort { $a->[0] cmp $b->[0] || $b->[1] cmp $a->[1] } @{$runs{$y}}]) }
my $nr = 0; $nr += @{$runs{$_}} for keys %runs; undef %runs;

# ---- 競走馬(生年ごと) ----
my %prof;
for my $id (keys %UM) {
  my $u = $UM{$id}; my @p = map { my ($k, $n) = @{$u->{ped}[$_]}; [$n || $idname{$k} // '', $HN{$k} ? $HN{$k}{id} : ''] } 0, 1, 4, 5;   # 父・母・母の父・母の母
  my $ls = $last{$id}; my $nrn = $nrun{$id} // 0;
  push @{$prof{substr($id, 0, 4)}}, [$id, $u->{name}, $u->{en}, $u->{sex}, $u->{birth}, $u->{color}, map({ @$_ } @p), $BN{$u->{ownerC}} // $u->{ownerS}, $u->{trainer}, $u->{belong}, $u->{breeder}, $u->{origin},
    '', '', '', $u->{prize}, '', '', $u->{shutoku}, $u->{shutokuJ}, $u->{rec}, @{$u->{sf}}, $nrn > $u->{nrec} ? $nrn : $u->{nrec},
    $ls ? ($ls->[1], $ls->[3] . ($ls->[4] ? "($ls->[4])" : ''), $ls->[11]) : ('', '', ''), $u->{massho}, '', ymd($u->{d}), '', $u->{mark}];
}
for my $y (keys %prof) { wtsv("$OUT/競走馬/${y}年生.tsv", \@PCOL, [sort { $a->[0] cmp $b->[0] } @{$prof{$y}}]) }
undef %prof;

# ---- 繁殖馬(国内外の種牡馬・繁殖牝馬) ----
my (%kids, %kidy, %jra); my %kb = map { ($_ => [$UM{$_}{name}, $UM{$_}{prize}]) } keys %UM;
for my $id (keys %SK) { my ($y, $fa, $mo) = @{$SK{$id}};
  for my $k ($fa, $mo) { next if $k =~ /^0+$/; $kids{$k}++; my $r = $kidy{$k} //= [$y, $y]; $r->[0] = $y if $y lt $r->[0]; $r->[1] = $y if $y gt $r->[1];
    if (my $u = $kb{$id}) { my $j = $jra{$k} //= [0, 0, '', 0]; $j->[0]++; $j->[1] += $u->[1]; @$j[2, 3] = ($u->[0], $u->[1]) if $u->[1] > $j->[3] } } }
my @hrows;
for my $k (keys %HN) { my $x = $HN{$k}; my $fa = $HN{$x->{f}}; my $j = $jra{$k} // [0, 0, '', 0];
  push @hrows, ["0$k", $x->{id}, $x->{name}, $x->{en}, $x->{year}, $x->{sex}, $x->{color}, $x->{mochi}, $x->{imp}, $x->{origin},
    $fa ? $fa->{name} : '', $HN{$x->{m}} ? $HN{$x->{m}}{name} : '', $HN{$x->{m}} && $HN{$HN{$x->{m}}{f}} ? $HN{$HN{$x->{m}}{f}}{name} : '',
    $kids{$k} // 0, $kidy{$k} ? "$kidy{$k}[0]-$kidy{$k}[1]" : '', $j->[0], $j->[1], $j->[3] ? "$j->[2]($j->[3]円)" : '' ] }
wtsv("$OUT/繁殖馬.tsv", [qw(繁殖key 血統登録番号 馬名 欧字名 生年 性 毛色 持込 輸入年 産地 父 母 母の父 産駒数(国内の血統登録) 産駒の生年 中央に登録された産駒 産駒総賞金(中央) 一番稼いだ産駒)],
  [sort { $b->[16] <=> $a->[16] || $a->[0] cmp $b->[0] } @hrows]);
logm('JRA-VAN: 表を作った: 競走馬 ' . scalar(keys %UM) . " 頭・出走 $nr 件・繁殖馬 " . scalar(@hrows) . ' 頭');
open my $o, '>:utf8', "$OUT/.元のデータ" or die; print $o "$now\n"; close $o;
summary();
