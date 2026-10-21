# 競馬ラボの馬柱ページから、馬ごとの生のデータ(能力値にする前の数字)を取り出す。過去のレースを集めて、何が当たりに効くかを調べるのに使う
# 使い方: perl features.pl <umabashira.html> > features.json
# 出力: { heads, horses: [ { name, umaban, waku, omega, kin, sex, age, weight, weightDiff, intvWeeks, jcRate, jcRuns, tjRate, tjRuns,
#          scRate, scRuns, odds, runs: [ { rank, pop, heads, umaban, agari, agariRank, pace, margin, first, last, surf, dist, going, place, kin } ... 最大5走 ] } ] }
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;

my ($file) = @ARGV;
open my $fh, '<:utf8', $file or die "cannot open $file";
local $/; my $h = <$fh>;

sub txt { my $t = shift // ''; $t =~ s/<[^>]*>//g; $t =~ s/&nbsp;/ /g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub sect { my $n = shift; return $1 if $h =~ /<!-- \Q$n\E -->(.*?)<!-- /s; '' }
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
my $nm = sect('馬名等');
my %seen; my @names = grep { !$seen{$_}++ } ($nm =~ /data-hsnm="([^"]+)"/g);
my $n = @names; exit 2 if $n < 2;
sub row { my $s = sect(shift); my @c = map { txt($_) } top_tds($s); return @c[-$n .. -1] if @c >= $n; return () }
# 見出し(th)で行を探す(後ろにコメントが付く行)
sub row_th { my $t = shift; my @c; if ($h =~ /<tr[^>]*>((?:(?!<tr[\s>]).)*?<th>\s*\Q$t\E)/s) { @c = map { txt($_) } top_tds($1); return @c[-$n .. -1] if @c >= $n } return () }
my @umaban = row('馬番'); my @waku = row('枠番'); my @kin = row('斤量'); my @odds = row('単勝'); my @bw = row('馬体重');
my @intv = row('間隔'); my @omega = row('Ω指数'); my @sexage = row('性·齢'); my @jc = row('騎手コース');
my @tj = row_th('調教師×'); my @sc = row_th('種牡馬×');

my %circ; my @cc = split //, '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$cc[$_]} = $_ + 1 for 0 .. $#cc;
my @runs = map { [] } 1 .. $n;
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
    my ($pdate) = $cell =~ /<li>\s*(\d\d\/\d\d)\s*<\/li>/;
    my ($pop) = $cell =~ /<span>\s*(\d+)人\s*<\/span>/;
    my ($ar, $ag) = $cell =~ /class="bgRise_(\d+)">\s*([\d.]+)/;
    ($ag) = $cell =~ /<br \/>\s*<span class="std11">\s*([\d.]+)/ unless defined $ag;
    my ($pace) = $cell =~ /<span class="bold (?:red|green|blue)">\s*([HMS])\s*</;
    my ($pmargin) = $cell =~ /class="std11">\s*[^<\d(]+\(\s*(-?\d+(?:\.\d+)?)\s*\)\s*<\/td>/;
    my ($pkin) = $cell =~ /<span>[^<\d]+<\/span><span>([\d.]+)<\/span>/;
    my ($pass) = $cell =~ /class="zensou std11"><span[^>]*>\s*(.*?)\s*<\/span>/s;
    my ($rn) = $cell =~ /class="zensoname">\s*([^<]*?)\s*</s;
    my @pos = map { $circ{$_} } grep { exists $circ{$_} } split //, ($pass // '');
    push @{$runs[$i]}, { k => $k, rank => $rank, pop => $pop, heads => $hd, umaban => $pu, agari => $ag, agariRank => $ar, pace => $pace,
      margin => $pmargin, first => $pos[0], last => $pos[-1], surf => $psurf, dist => $pdist, going => $pgoing, place => $pplace,
      date => $pdate, kin => $pkin, race => $rn // '' };
  }
}
my @out;
for my $i (0 .. $n - 1) {
  my %x = (name => $names[$i]);
  $x{umaban} = $1 + 0 if ($umaban[$i] // '') =~ /^(\d+)$/;
  $x{waku} = $1 + 0 if ($waku[$i] // '') =~ /^(\d+)$/;
  $x{omega} = $1 + 0 if ($omega[$i] // '') =~ /^(\d+)$/;
  $x{kin} = $1 + 0 if ($kin[$i] // '') =~ /([\d.]+)/;
  if (($sexage[$i] // '') =~ /^(\S)\D*(\d+)/) { $x{sex} = $1; $x{age} = $2 + 0 }
  if (($bw[$i] // '') =~ /^(\d{3})\s*\(\s*([＋－+\-]?)\s*(\d+)\s*\)/) { $x{weight} = $1 + 0; $x{weightDiff} = (($2 eq '－' || $2 eq '-') ? -1 : 1) * $3 }
  my $iv = $intv[$i] // '';
  if ($iv =~ /連闘/) { $x{intvWeeks} = 1 } elsif ($iv =~ /中(\d+)週/) { $x{intvWeeks} = $1 + 1 } elsif ($iv =~ /(\d+)ヶ月/) { $x{intvWeeks} = int($1 * 4.3) } elsif ($iv =~ /半年/) { $x{intvWeeks} = 26 } elsif ($iv =~ /年/) { $x{intvWeeks} = 52 }
  for ([\@jc, 'jc'], [\@tj, 'tj'], [\@sc, 'sc']) { my ($a, $p) = @$_; if (($a->[$i] // '') =~ /([\d.]+)%\s*\[(\d+)\]/) { $x{"${p}Rate"} = $1 + 0; $x{"${p}Runs"} = $2 + 0 } }
  $x{odds} = $1 + 0 if ($odds[$i] // '') =~ /^([\d.]+)/;
  $x{runs} = $runs[$i];
  push @out, \%x;
}
print JSON::PP->new->utf8(0)->canonical->encode({ heads => $n, horses => \@out });
