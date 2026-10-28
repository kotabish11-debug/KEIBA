# 馬DB(馬情報/馬DB/)を馬名で引く。競走馬・種牡馬・繁殖牝馬のどれでも(重賞の判断材料や出走馬ファイルを作るときに使う)
# 使い方: perl 自動実行/馬DB/find.pl <馬名> [近走の数(既定10)]
#   同じ名前が無ければ、名前の一部が合う馬を出す。出走履歴(PCだけにある)が無ければ近走は出さない
use utf8; use strict; use warnings;
use File::Basename qw(dirname); use File::Spec; use File::Glob (); use Encode ();
binmode STDOUT, ':utf8';
my $HERE = Encode::decode('UTF-8', dirname(File::Spec->rel2abs(__FILE__))); my $DB = "$HERE/../../馬情報/馬DB";
my $q = Encode::decode('UTF-8', shift // die "使い方: perl find.pl <馬名> [近走の数]\n"); my $nrun = shift // 10;
sub files { File::Glob::bsd_glob(Encode::encode('UTF-8', shift)) }
sub rtsv { my $f = shift; my @r; open my $h, '<:utf8', $f or return ([], []); my $hd = <$h> // ''; chomp $hd; $hd =~ s/\r$//;
  while (<$h>) { chomp; s/\r$//; push @r, [split /\t/, $_, -1] } return ([split /\t/, $hd], \@r) }
sub show { my ($cols, $r, @skip) = @_; my %s = map { $_ => 1 } @skip;
  print join('', map { ($r->[$_] // '') ne '' && !$s{$cols->[$_]} ? "- $cols->[$_]: $r->[$_]\n" : '' } 0 .. $#$cols) }
my $hit = 0;

# JRA-VAN で補った全部入り(PCだけ。jv.pl が作る)。あれば、馬DB に無い馬をここから引き、種牡馬・繁殖牝馬もこちらを使う
my $JVD = "$HERE/../../馬情報/JRA-VAN/馬DB"; my $hasjv = () = files("$JVD/競走馬/*.tsv");

# 競走馬(馬DB に無ければ JRA-VAN から)
my (@exact, @part, $pc, %src, %seen);
for my $d ($DB, $hasjv ? $JVD : ()) {
  for my $f (files("$d/競走馬/*.tsv")) { my ($c, $rows) = rtsv($f); $pc = $c; for (@$rows) { next if $seen{$_->[0]}++; $src{$_->[0]} = $d;
    if ($_->[1] eq $q) { push @exact, $_ } elsif (index($_->[1], $q) >= 0) { push @part, $_ } } }
}
my @h = @exact ? @exact : @part[0 .. ($#part < 19 ? $#part : 19)];
for my $r (grep { defined } @h) {
  my $d = $src{$r->[0]}; $hit++; print "## 競走馬 $r->[1]($r->[0]" . ($d eq $DB ? '' : '。JRA-VAN') . ")\n"; show($pc, $r, qw(id 馬名 cname 母産駒cname));
  my ($rc, $runs) = rtsv(Encode::decode('UTF-8', (files("$d/出走履歴/" . substr($r->[0], 0, 4) . '年生.tsv'))[0] // '') || '/nonexistent');
  my @mine = grep { $_->[0] eq $r->[0] } @$runs;
  if (@mine) { print "\n| 年月日 | 場 | レース | 距離 | 馬場 | 頭数 | 人気 | 着順 | 騎手 | 斤量 | 馬体重 | タイム | 1着馬(2着馬) |\n|" . ('---|' x 13) . "\n";
    for my $x (@mine[0 .. ($#mine < $nrun - 1 ? $#mine : $nrun - 1)]) { print '| ' . join(' | ', $x->[1], $x->[2], $x->[3] . ($x->[4] ? "($x->[4])" : ''), "$x->[6]$x->[7]", @$x[8 .. 15], $x->[17]) . " |\n" } }
  print "\n";
}
if (!@exact && @part > 20) { print "(名前の一部が合う馬はほかに " . (@part - 20) . " 頭)\n\n" }

# 種牡馬・母の父として
my $SUM = $hasjv && -e Encode::encode('UTF-8', "$JVD/種牡馬.tsv") ? $JVD : $DB;
my ($sc, $srows) = rtsv("$SUM/種牡馬.tsv");
for my $r (grep { $_->[0] eq $q } @$srows) { $hit++; print "## 種牡馬 $r->[0](産駒の成績はJRAのレースだけ)\n"; show($sc, $r, '種牡馬'); print "\n" }
# 繁殖牝馬
my ($dc, $drows) = rtsv("$SUM/繁殖牝馬.tsv");
for my $r (grep { $_->[0] eq $q } @$drows) { $hit++; print "## 繁殖牝馬 $r->[0]\n"; show($dc, $r, '繁殖牝馬'); print "\n" }
# 繁殖馬(JRA-VAN の繁殖馬マスタ。外国の種牡馬・繁殖牝馬も。産駒数は地方の馬も入れた国内の血統登録の数)
if ($hasjv) { my ($bc, $brows) = rtsv("$JVD/繁殖馬.tsv");
  for my $r (grep { $_->[2] eq $q || lc $_->[3] eq lc $q } @$brows) { $hit++; print "## 繁殖馬 $r->[2](JRA-VAN)\n"; show($bc, $r, '馬名'); print "\n" } }
# 登録されたばかりでまだ走っていない馬
my ($gc, $grows) = rtsv("$DB/登録.tsv");
for my $r (grep { $_->[1] eq $q } @$grows) { next if @exact; $hit++; print "## 競走馬登録 $r->[1]\n"; show($gc, $r, '馬名'); print "\n" }
my ($mc, $mrows) = rtsv("$DB/抹消.tsv");
for my $r (grep { $_->[1] eq $q } @$mrows) { $hit++; print "## 登録抹消 $r->[1]\n"; show($mc, $r, '馬名'); print "\n" }
print "見つからない: $q(馬DBにまだ入っていない。update.pl が少しずつ集めている)\n" unless $hit;
