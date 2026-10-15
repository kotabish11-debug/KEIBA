use utf8; use strict; binmode STDOUT,':utf8'; binmode STDIN,':utf8';
my %circ; my @c=split //,'①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$c[$_]}=$_+1 for 0..$#c;
<STDIN>; my (%pop,%popw,%ban,%style,%stylew,%prev,%prevw,%sire,%prk,%jk,%int); my $n=0;
while(<STDIN>){ chomp; my @f=split /\t/;
  my ($y,$r,$b,$nm,$sa,$p,$j,$k,$tr,$f3,$pass,$s,$ds,$pr,$iv,$pc,$pp,$prr)=@f; $n++;
  my @pos = map{$circ{$_}} grep{exists $circ{$_}} split //,$pass; my $last=$pos[-1]//0;
  my $st = $last==0?'?':$last<=1?'逃げ':$last<=4?'先行':$last<=9?'差し':'追込';
  $pop{ $p<=1?'1番人気':$p<=3?'2-3番人気':$p<=6?'4-6番人気':'7番人気以下' }++; $popw{ $p<=1?'1番人気':$p<=3?'2-3番人気':$p<=6?'4-6番人気':'7番人気以下' }++ if $r==1;
  $ban{ $b<=4?'馬番1-4':$b<=8?'馬番5-8':$b<=12?'馬番9-12':'馬番13-' }++;
  $style{$st}++; $stylew{$st}++ if $r==1; $prev{$pr}++; $prevw{$pr}++ if $r==1; $sire{$s}++;
  $prk{ $prr eq ''?'?':$prr==1?'前走1着':$prr<=3?'前走2-3着':$prr<=5?'前走4-5着':'前走6着以下' }++; $jk{$j}++; $int{$iv}++;
}
sub show { my ($t,$h,$w)=@_; print "$t: ",join('、',map{"$_ ".$h->{$_}.($w?"(1着".($w->{$_}//0).")":'')} sort{$h->{$b}<=>$h->{$a}} keys %$h),"\n" }
print "対象: 過去10年の1〜3着 ${n}頭\n";
show('人気',\%pop,\%popw); show('馬番',\%ban); show('脚質(4角位置)',\%style,\%stylew); show('前走レース',\%prev,\%prevw); show('前走着順',\%prk); show('間隔',\%int);
my @top=grep{$sire{$_}>=2} keys %sire; show('父(2頭以上)',{map{$_=>$sire{$_}}@top}); my @tj=grep{$jk{$_}>=2} keys %jk; show('騎手(2回以上)',{map{$_=>$jk{$_}}@tj});
