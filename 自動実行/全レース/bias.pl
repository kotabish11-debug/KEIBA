#!/usr/bin/perl
# その日の同じ競馬場・同じ馬場(芝/ダ)で終わったレースから、トラックバイアス(内外・前後の有利不利)を推定する
# 人気馬の好走は能力で説明できるので使わず、6番人気以下で3着以内に来た馬の枠と4角の位置だけを見る
# 使い方: perl bias.pl <当日バイアス.tsv> <日付 YYYY-MM-DD> <場所> <芝|ダ>
# 出力: {"draw":…, "front":…, "n":…, "races":…, "note":"…"}(根拠が足りなければ何も出さない)
use strict; use warnings; use utf8; use JSON::PP;
my ($file, $date, $place, $surf) = @ARGV;
exit 0 unless $file && $surf;
utf8::decode($_) for ($place, $surf);
open my $h, '<:encoding(UTF-8)', $file or exit 0;
my (%races, @x);
while (my $line = <$h>) {
  chomp $line; $line =~ s/\r$//;
  my ($d, $p, $s, $id, $u, $hd, $l4, $rk, $pop) = split /\t/, $line;
  next unless defined $pop && $d eq $date && $p eq $place && $s eq $surf;
  $races{$id} = 1;
  next unless $pop =~ /^\d+$/ && $pop >= 6 && $rk =~ /^\d+$/ && $rk <= 3 && $hd =~ /^\d+$/ && $hd > 0 && $u =~ /^\d+$/;
  push @x, [$u / $hd, ($l4 =~ /^\d+$/ ? $l4 / $hd : undef)];
}
my $nr = keys %races;
exit 0 if $nr < 2 || @x < 2;
my ($in, $front, $nf) = (0, 0, 0);
for (@x) {
  my ($u, $l) = @$_;
  $in += $u <= 0.35 ? 1 : $u > 0.65 ? -1 : 0;
  if (defined $l) { $front += $l <= 0.35 ? 1 : $l > 0.6 ? -1 : 0; $nf++ }
}
my $shrink = @x / (@x + 2);   # 頭数が少ないうちは弱めに
my $draw = sprintf('%.2f', 0.6 * ($in / @x) * $shrink) + 0;
my $fr = sprintf('%.2f', 1.5 * ($nf ? $front / $nf : 0) * $shrink) + 0;
exit 0 if abs($draw) < 0.1 && abs($fr) < 0.3;
my @w;
push @w, $draw > 0 ? '内枠' : '外枠' if abs($draw) >= 0.1;
push @w, $fr > 0 ? '前に行った馬' : '後ろから差した馬' if abs($fr) >= 0.3;
my $note = "当日の${place}${surf}: ${nr}レースで6番人気以下の3着以内" . scalar(@x) . '頭は' . join('・', @w) . 'が中心(当日バイアスとして補正)';
print JSON::PP->new->utf8->canonical->encode({ draw => $draw, front => $fr, n => scalar(@x), races => $nr, note => $note });
