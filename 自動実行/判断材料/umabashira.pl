use utf8; use strict; binmode STDOUT,':utf8';
local $/; open my $fh,'<:utf8',$ARGV[0] or die; my $h=<$fh>;
sub sect { my ($name)=@_; return $1 if $h=~/<!-- \Q$name\E -->(.*?)<!-- /s; return '' }
sub txt { my $t=shift; $t=~s/<[^>]*>//g; $t=~s/&nbsp;/ /g; $t=~s/\s+/ /g; $t=~s/^ | $//g; $t }
my $nm=sect('馬名等'); my @names = $nm=~/data-hsnm="([^"]+)"/g; my $n=@names;
my @sire = map {txt($_)} ($nm=~/<dd class="chichi[^"]*">(.*?)<\/dd>/sg);
my @damsire = map {my $x=txt($_); $x=~s/[()]//g; $x} ($nm=~/<p class="tategaki hahachichi[^"]*">(.*?)<\/p>/sg);
my $ow=sect('馬主'); my @own; my @brd;
while($ow=~/<dl class="ownerDl">(.*?)<\/dl>/sg){ my $b=$1; my @a=map{txt($_)} ($b=~/<a [^>]*>(.*?)<\/a>/sg); push @own,$a[0]//''; push @brd,$a[1]//'' }
my %pct;
for my $k ('騎手コース','馬番×コース','種牡馬×コース連対率','調教師×騎手連対率'){ my $s=sect($k); my @v; while($s=~/([\d.]+)%\s*(?:<[^>]*>\s*)*\[(\d+)\]/sg){ push @v,"$1%($2)" } $pct{$k}=\@v }
my %rec;
for my $k ('距離','コース','馬場状態'){ my $s=sect($k); my @v;
  while($s=~/<table class="ResultBox[^"]*">(.*?)<\/table>/sg){ my $t=$1; my @hd=map{txt($_)} ($t=~/<th>(.*?)<\/th>/sg); my @rows; while($t=~/<tr>\s*(<td>.*?)<\/tr>/sg){ push @rows,[map{txt($_)} ($1=~/<td>(.*?)<\/td>/sg)] }
    my @out; for my $c (0..$#hd){ push @out, "$hd[$c]:".join('-',map{$_->[$c]//'?'} @rows) } push @v, join(' ',@out) }
  $rec{$k}=\@v }
print "馬名\t父\t母父\t馬主\t生産者\t騎手コース連対\t馬番×コース連対\t種牡馬×コース連対\t調教師×騎手連対\t距離成績\tコース成績\t馬場成績\n";
for my $i (0..$n-1){ print join("\t",$names[$i],$sire[$i]//'',$damsire[$i]//'',$own[$i]//'',$brd[$i]//'', map({$pct{$_}[$i]//''} '騎手コース','馬番×コース','種牡馬×コース連対率','調教師×騎手連対率'), map({$rec{$_}[$i]//''} '距離','コース','馬場状態')),"\n" }
my $tail=$h; $tail=~s/<script.*?<\/script>//sg; my $tt=txt($tail);
for my $k ('このコースが得意な騎手','このコースで有利な枠','このコースで有利な脚質','このコースが得意な調教師','このコースが得意な種牡馬'){ if($tt=~/\Q$k\E (.{0,60})/){ my $v=$1; $v=~s/ この.*//; $v=~s/ <!--.*//; print "# $k: $v\n" } }
