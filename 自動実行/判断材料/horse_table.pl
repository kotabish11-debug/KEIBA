use utf8; use strict; binmode STDOUT,':utf8';
my ($tsv,$csv,$surf)=@ARGV; my %sire;
open my $C,'<:utf8',$csv or die; <$C>; while(<$C>){ chomp; my @f=split /,/; $sire{$f[1]}={rank=>$f[0],turf=>$f[22],dirt=>$f[23],dt=>$f[19],dd=>$f[20]} }
open my $T,'<:utf8',$tsv or die; my $hd=<$T>;
print "| 馬名 | 父(2026中央順位・芝勝率・芝平均勝ち距離) | 生産者 | 騎手のこのコース連対率 | 父のこのコース連対率 | 距離成績(当該) | コース成績 | 道悪(稍重以下) |\n|---|---|---|---|---|---|---|---|\n";
my @rows;
while(<$T>){ chomp; next if /^#/; my @f=split /\t/;
  my ($nm,$s,$ds,$ow,$br,$jc,$bc,$sc,$tj,$dist,$course,$going)=@f;
  my $si=$sire{$s}; my $sinfo = $si ? "$si->{rank}位・".sprintf("%.1f%%",$si->{turf}*100)."・".int($si->{dt})."m" : "圏外";
  my ($cur)= $dist=~/当該:(\S+)/; $cur//= ($dist=~/^:(\S+)/)[0] // '';
  my @cc=split / /,$course; my $cs=join(" ",$cc[0],$cc[-1]); $cs=~s/:/ /g;
  my @g = ($going=~/(?:芝|ダ)(?:稍|重|不):(\d+)-(\d+)-(\d+)-(\d+)/g); my ($w,$p2,$p3,$o)=(0,0,0,0); while(@g){ $w+=shift @g; $p2+=shift @g; $p3+=shift @g; $o+=shift @g }
  my $gs = $going eq '' ? '-' : "$w-$p2-$p3-$o";
  push @rows, "| $nm | $s($sinfo) | $br | $jc | $sc | $cur | $cs | $gs |";
}
print "$_\n" for sort @rows;
