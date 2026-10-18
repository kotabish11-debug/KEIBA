# 競馬ラボの結果ページ(raceresult.html)から着順をJSONにする
# 使い方: perl result_json.pl <raceresult.html> > result.json   結果がまだ無ければ終了コード 2
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;
my $file = shift;
open my $fh, '<:utf8', $file or die "cannot open $file";
local $/; my $h = <$fh>;
sub txt { my $t = shift // ''; $t =~ s/<[^>]*>//g; $t =~ s/&nbsp;/ /g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
my %circ; my @cc = split //, '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱'; $circ{$cc[$_]} = $_ + 1 for 0 .. $#cc;
my @order;
while ($h =~ /<tr[^>]*>(.*?)<\/tr>/sg) {
  my @c = map { txt($_) } ($1 =~ /<td[^>]*>(.*?)<\/td>/sg);
  next if @c < 14;
  shift @c if $c[0] !~ /^\d+$|^(取消|除外|中止|失格)$/;
  # 着順・枠・馬番・馬名・性齢・斤量・騎手・人気・単勝・タイム・着差・通過・上り
  my ($rank, $waku, $ban, $name, $sa, $kin, $jk, $pop, $odds, $time, $diff, $pass, $f3) = @c;
  next unless defined $name && $ban =~ /^\d+$/;
  # (外)(地)(父)(市)(抽) などの印を外して、予想の馬名と合わせる
  $name =~ s/^(?:[\(（\[［][^\)）\]］]{1,2}[\)）\]］]|[□○◇☆▲△])+//; $name =~ s/\s+//g;
  my @pos = map { $circ{$_} } grep { exists $circ{$_} } split //, ($pass // '');
  push @order, { rank => ($rank =~ /^\d+$/ ? $rank + 0 : $rank), umaban => $ban + 0, name => $name, jockey => $jk,
    pop => ($pop =~ /^\d+$/ ? $pop + 0 : undef), odds => ($odds =~ /^[\d.]+$/ ? $odds + 0 : undef),
    pass => $pass, last4 => $pos[-1], f3 => $f3, time => $time };
}
exit 2 unless grep { ($_->{rank} // '') =~ /^\d+$/ } @order;
my $heads = scalar @order;
print JSON::PP->new->canonical->pretty->encode({ heads => $heads, order => \@order });
