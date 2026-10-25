# 調教動画の字幕の文字認識の結果(ocr.ps1 の出力)から、馬ごとの追い切り(日付・コース・併せ・タイム)を取り出す(2026-10-26〜)
# 使い方: perl chokyo_parse.pl <ocr.tsv> <動画ID> <年> <レース名>   → 1行1頭のTSV(調教タイム_JRA動画.tsv と同じ列。メモ欄に読めた枚数)
#   字幕は「10/21(水)」「栗東・CW 21 ロブチェン(外)」の行と、「ロブチェン(外)」「6F 5F 4F 3F 1F」「84.5 67.8 52.5 37.3 11.5」の行が出る
#   静止画を時間の順に見て、馬名が前の馬と似ていなければ次の馬とする。馬名・日付・コース・併せ・各タイムは、その馬の静止画の多数決(項目ごと)
#   数字の行は空白を詰めて「2桁.1桁」を拾い、範囲(6F 75〜95・5F 60〜75・4F 47〜60・3F 33〜47・2F 22〜31・1F 10.5〜15.5)と大小の順で項目に当てる
#   坂路は 800m・600m・400m・200m を 4F・3F・2F・1F に入れる(4F は 47〜70)。馬名は文字認識のままなので、結果と合わせるときに出走馬の名前に寄せる
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
my ($f, $vid, $year, $race) = @ARGV; utf8::decode($race);
open my $h, '<:encoding(UTF-8)', $f or die "$f";
my %frame;
while (<$h>) { s/^\x{FEFF}//; chomp; s/\r//; my ($img, $t) = split /\t/, $_, 2; next unless defined $t; push @{$frame{$img}}, $t }
sub norm { my $s = shift; $s =~ s/\s+//g; $s =~ tr/（）．ＷＣＰ/().WCP/; $s =~ s/[。、,，]/・/g; $s }
sub lcs { my ($a, $b) = @_; my @a = split //, $a; my @b = split //, $b; my @p = (0) x (@b + 1);
  for my $x (@a) { my @c = (0); for my $j (1 .. @b) { push @c, $x eq $b[$j - 1] ? $p[$j - 1] + 1 : ($p[$j] > $c[-1] ? $p[$j] : $c[-1]) } @p = @c } $p[-1] }
sub sim { my ($a, $b) = @_; return 0 unless length $a && length $b; 2 * lcs($a, $b) / (length($a) + length($b)) }
# コースは「栗東・CW」の、番号(数字)より前だけを見る(馬名の「ダ」などを拾わないため)。文字認識は w を小文字で返すことが多い
sub course { my $s = shift; my ($c, $rest) = $s =~ /(栗東|美浦)(\D{0,5})/ or return '';
  my $t = $rest =~ /坂/ ? '坂路' : $rest =~ /cw/i ? 'CW' : $rest =~ /dp/i ? 'DP' : $rest =~ /w|vv|ⅳ|ウ/i ? 'W' : $rest =~ /p|ポ/i ? 'P' : $rest =~ /芝/ ? '芝' : $rest =~ /ダ/ ? 'ダ' : '?'; "$c$t" }
my (@seg, $cur);
for my $img (sort keys %frame) {
  my @L = map { norm($_) } @{$frame{$img}};
  my ($date) = map { /(\d{1,2})\/(\d{1,2})\(/ ? sprintf('%d/%d', $1, $2) : () } @L;
  my ($cl) = grep { /栗東|美浦/ } @L;
  my ($hn, $hp) = $cl ? $cl =~ /([ァ-ヶー]{3,})(?:\((内|中|外))?/ : ();
  my ($ln, $lp) = map { /^[ー・]*([ァ-ヶ][ァ-ヶー]{2,})(?:\((内|中|外)\)?)?$/ ? ($1, $2) : () } @L;
  my $name = $hn // $ln;
  if ($name && (!$cur || sim($name, $cur->{last}) < 0.5)) { $cur = { n => {}, date => {}, course => {}, pos => {}, v => {}, reads => 0 }; push @seg, $cur }
  next unless $cur;
  if ($name) { $cur->{n}{$name}++; $cur->{last} = $name }
  $cur->{date}{$date}++ if $date && $cl;
  $cur->{course}{course($cl)}++ if $cl && course($cl);
  my $pos = $hp // $lp; $cur->{pos}{$pos}++ if $pos;
  $cur->{hasHdr}++ if $cl;
  my %got; for my $num (grep { /\d.*\d.*\d.*\d/ && !/\/|[ァ-ヶ]{2}/ } @L) { my %g = nums($num, (top($cur->{course}) // '') =~ /坂路/); %got = %g if keys %g > keys %got }
  next unless keys %got >= 2;
  $cur->{reads}++; $cur->{v}{$_}{$got{$_}}++ for keys %got;
}
sub top { my $hh = shift || {}; (sort { $hh->{$b} <=> $hh->{$a} || $a cmp $b } keys %$hh)[0] }
# 数字の行 → {6F => 84.5, …}。この字幕の字体では「7.」と「1.」がどちらも「れ」と読まれるので、両方を試して
# 範囲・大小の順・1ハロンあたりの差(10〜18.5秒)に一番多く合う読みを選ぶ
sub nums { my ($line, $sak) = @_;
  my %r = $sak ? ('4F' => [47, 70], '3F' => [33, 50], '2F' => [22, 33], '1F' => [10.5, 16]) : ('6F' => [75, 95], '5F' => [60, 75], '4F' => [47, 60], '3F' => [33, 47], '2F' => [22, 31], '1F' => [10.5, 15.5]);
  my %d = ('6F' => 6, '5F' => 5, '4F' => 4, '3F' => 3, '2F' => 2, '1F' => 1);
  my @F = $sak ? qw(4F 3F 2F 1F) : qw(6F 5F 4F 3F 2F 1F);
  (my $s = $line) =~ s/[^\d.れ]//g; my @cand = ('');
  for my $ch (split //, $s) { @cand = map { my $c = $_; $ch eq 'れ' ? ("${c}7.", "${c}1.") : ("$c$ch") } @cand; last if @cand > 64 }
  my ($best, $bn) = ({}, 0);
  for my $c (@cand) { $c =~ s/\.\././g; my @v = $c =~ /(\d{2}\.\d)/g; my %got; my $prev;
    for my $val (@v) { for my $k (@F) { next if exists $got{$k}; next if $prev && ($d{$k} >= $d{$prev} || $val >= $got{$prev}); my ($lo, $hi) = @{$r{$k}}; next unless $val >= $lo && $val < $hi;
        if ($prev) { my $per = ($got{$prev} - $val) / ($d{$prev} - $d{$k}); $per = $got{$prev} - $val if $k eq '1F' && $d{$prev} == 2; next unless ($k eq '1F' ? ($got{$prev} - $val) / ($d{$prev} - 1) : $per) >= 10 && $per <= 18.5 }
        $got{$k} = $val; $prev = $k; last } }
    ($best, $bn) = (\%got, scalar keys %got) if keys %got > $bn }
  %$best }
for my $x (@seg) { next unless $x->{reads} && $x->{hasHdr};
  my @t = map { my $k = $_; my $v = $x->{v}{$k} || {}; my $b = top($v); defined $b && $v->{$b} >= ($x->{reads} >= 4 ? 2 : 1) ? $b : '' } qw(6F 5F 4F 3F 2F 1F);
  print join("\t", $vid, $year, $race, top($x->{n}) // '', top($x->{date}) // '', top($x->{course}) // '', '', top($x->{pos}) // '単走', @t, "読めた枚数$x->{reads}"), "\n" }
