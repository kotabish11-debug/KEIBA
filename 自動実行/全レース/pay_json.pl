# 競馬ラボの結果ページ(raceresult.html)から全券種の払戻を取り出す
# 使い方: perl pay_json.pl <raceresult.html> <レースID>
# 出力(1行のJSON): {"id":..., "pay": {"単勝":[{"k":"8","yen":220}], "複勝":[...], "ワイド":[{"k":"5-8","yen":240},...], ...}}
#   k は馬番(馬連・ワイド・3連複は小さい順、馬単・3連単は着順)。yen は100円あたり。同着で複数あるときは配列に並ぶ
use utf8; use strict; use warnings;
use JSON::PP;
my ($f, $id) = @ARGV;
open my $h, '<:raw', $f or die; local $/; my $html = <$h>; utf8::decode($html);
my ($tbl) = $html =~ m{<div class="haraimodoshi">(.*?)</table>}s or exit 2;
my %pay;
while ($tbl =~ m{<td class="bg\w+">([^<]+)</td>\s*<td class="tC">(.*?)</td>\s*<td class="tR">(.*?)</td>}sg) {
  my ($type, $ks, $ys) = ($1, $2, $3); $type =~ s/\s+//g;
  my @k = map { s/\s+//gr } split m{<br\s*/?>}, $ks; my @y = map { s/[^\d]//gr } split m{<br\s*/?>}, $ys;
  for my $i (0 .. $#k) {
    next unless length $k[$i] && length($y[$i] // '');
    my $k = $k[$i]; $k =~ s/[→－ー]/-/g;
    $k = join '-', sort { $a <=> $b } split /-/, $k if $type =~ /^(馬連|ワイド|3連複|枠連)$/;
    push @{$pay{$type}}, { k => $k, yen => $y[$i] + 0 };
  }
}
exit 2 unless $pay{'単勝'};
print JSON::PP->new->utf8->canonical->encode({ id => $id, pay => \%pay }), "\n";
