#!/usr/bin/perl
# 調教の表(chokyo.tsv)が無いところ(クラウドのルーティン)で作り直したレースに、db にある前回の「調教の点」を引き継ぐ
# 使い方: perl chokyo_keep.pl <作り直したレース.json> <db のレース.json> > 出力.json
#   調教の点は JRA-VAN のデータがある PC だけが付ける(chokyo_table.pl・race_json.pl)。クラウドが作り直すたびに消えないよう、
#   db の各馬の note にある「調教2週間に…(+N)」を探し、同じ馬名の choshi に N を足して note に戻す(2026-10-29〜)
use strict; use warnings; use utf8; use JSON::PP;
my ($nf, $df) = @ARGV;
my $J = JSON::PP->new->utf8->canonical;
sub rd { open my $h, '<:raw', $_[0] or return; local $/; my $d = eval { $J->decode(<$h>) } or return; ref $d->{data} eq 'HASH' ? $d->{data} : $d }
my $new = rd($nf) or die "読めません: $nf\n"; my $db = rd($df);
my %pt;
for my $h (@{($db || {})->{horses} || []}) { $pt{$h->{name}} = [$1, $2] if ($h->{note} // '') =~ /(調教2週間に.*?\(([+-]\d)\))/ }
for my $h (@{$new->{horses} || []}) {
  my $p = $pt{$h->{name}} or next; next if ($h->{note} // '') =~ /調教2週間に/;
  my $c = ($h->{choshi} // 65) + $p->[1]; $h->{choshi} = $c < 40 ? 40 : $c > 95 ? 95 : $c;
  my $nt = $h->{note} // ''; $h->{note} = $nt =~ s/(\(自動計算\))$/・$p->[0]$1/ ? $nt : "$nt・$p->[0]";
}
print $J->encode($new);
