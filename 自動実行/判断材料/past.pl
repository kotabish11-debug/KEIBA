use utf8; use strict; binmode STDOUT,':utf8';
local $/; open my $F,'<:utf8',$ARGV[0] or die; my $h=<$F>;
print "年\t着\t馬番\t馬名\t性齢\t人気\t騎手\t斤量\t厩舎\t上がり\t通過\t父\t母父\t前走\t前走間隔\t前走条件\t前走人気\t前走着\n";
my $yr='';
while($h=~/<tr[^>]*>(.*?)<\/tr>/sg){
  my @c=map{my $t=$_; $t=~s/<[^>]*>//g; $t=~s/&nbsp;/ /g; $t=~s/\s+/ /g; $t=~s/^ | $//g; $t} ($1=~/<td[^>]*>(.*?)<\/td>/sg);
  next if @c<20;
  if($c[0]=~/^\d+\/\d+ /){ shift @c; $yr = $yr eq '' ? 2025 : $yr-1 }
  next unless $c[0]=~/^\d+$/;
  my ($rank,$ban,$name,$sa,$pop,$jk,$kin,$tr,$diff,$f3,$wt,$pass,$sire,$sl,$ds,$dsl,$dam,$pd,$pr,$int,$pc,$ppass,$pkin,$ppop,$prank)=@c;
  print join("\t",$yr,$rank,$ban,$name,$sa,$pop,$jk,$kin,$tr,$f3,$pass,$sire,$ds,$pr,$int,$pc,$ppop//'',$prank//''),"\n";
}
