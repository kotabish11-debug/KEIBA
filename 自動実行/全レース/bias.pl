#!/usr/bin/perl
# その日の同じ競馬場・同じ馬場(芝/ダ)で終わったレースから、トラックバイアス(内外・前後の有利不利)を推定する
# 人気馬の好走は能力で説明できるので使わず、6番人気以下で3着以内に来た馬の枠と4角の位置だけを見る
# 芝はさらに「日本型(サンデー系)の父の馬が走る馬場か」を見る(出典: 馬情報/血統の系統と国別タイプ.md)
#   出走馬に占める日本型の割合と、3着以内に占める割合を比べる。日本型が来ない日は欧州型・米国型が恵まれる
# 使い方: perl bias.pl <当日バイアス.tsv> <日付 YYYY-MM-DD> <場所> <芝|ダ>
# 出力: {"draw":…, "front":…, "jp":…, "n":…, "races":…, "note":"…"}(根拠が足りなければ何も出さない)
use strict; use warnings; use utf8; use JSON::PP;
my ($file, $date, $place, $surf) = @ARGV;
exit 0 unless $file && $surf;
utf8::decode($_) for ($place, $surf);
open my $h, '<:encoding(UTF-8)', $file or exit 0;
my (%races, @x, %jr);
my ($fj, $fk, $tj, $tk) = (0, 0, 0, 0);   # 出走馬・3着以内の、日本型の頭数とタイプが分かる頭数
while (my $line = <$h>) {
  chomp $line; $line =~ s/\r$//;
  my ($d, $p, $s, $id, $u, $hd, $l4, $rk, $pop, $st) = split /\t/, $line;
  next unless defined $pop && $d eq $date && $p eq $place && $s eq $surf;
  $races{$id} = 1;
  if (defined $st && $st ne '' && $rk =~ /^\d+$/) {
    my $j = $st eq '日本' ? 1 : 0; $fk++; $fj += $j; $jr{$id} = 1;
    if ($rk <= 3) { $tk++; $tj += $j }
  }
  next unless $pop =~ /^\d+$/ && $pop >= 6 && $rk =~ /^\d+$/ && $rk <= 3 && $hd =~ /^\d+$/ && $hd > 0 && $u =~ /^\d+$/;
  push @x, [$u / $hd, ($l4 =~ /^\d+$/ ? $l4 / $hd : undef)];
}
my $nr = keys %races;
exit 0 if $nr < 2;
my ($draw, $fr) = (0, 0);
if (@x >= 2) {
  my ($in, $front, $nf) = (0, 0, 0);
  for (@x) {
    my ($u, $l) = @$_;
    $in += $u <= 0.35 ? 1 : $u > 0.65 ? -1 : 0;
    if (defined $l) { $front += $l <= 0.35 ? 1 : $l > 0.6 ? -1 : 0; $nf++ }
  }
  my $shrink = @x / (@x + 2);   # 頭数が少ないうちは弱めに
  $draw = sprintf('%.2f', 0.6 * ($in / @x) * $shrink) + 0;
  $fr = sprintf('%.2f', 1.5 * ($nf ? $front / $nf : 0) * $shrink) + 0;
}
# 日本型が走る馬場か(芝だけ。3レース以上・3着以内でタイプの分かる馬が6頭以上)
my $jp = 0; my ($fs, $ts);
if ($surf eq '芝' && keys(%jr) >= 3 && $tk >= 6 && $fk) {
  ($fs, $ts) = ($fj / $fk, $tj / $tk);
  my $v = 2 * ($ts - $fs) * $tk / ($tk + 6);   # 3着以内の頭数が少ないうちは弱めに
  $v = $v > 1 ? 1 : $v < -1 ? -1 : $v;
  $jp = abs($v) >= 0.3 ? sprintf('%.2f', $v) + 0 : 0;
}
my ($bd, $bf) = (abs($draw) >= 0.1, abs($fr) >= 0.3);
($draw, $fr) = (0, 0) unless $bd || $bf;
exit 0 unless $bd || $bf || $jp;
my @w;
push @w, $draw > 0 ? '内枠' : '外枠' if $bd;
push @w, $fr > 0 ? '前に行った馬' : '後ろから差した馬' if $bf;
my @notes;
push @notes, "${nr}レースで6番人気以下の3着以内" . scalar(@x) . '頭は' . join('・', @w) . 'が中心' if @w;
push @notes, sprintf('父が日本型(サンデー系)の馬は出走の%d%%・3着以内の%d%%(%s)', 100 * $fs + 0.5, 100 * $ts + 0.5, $jp > 0 ? '主流の馬場' : '反主流の馬場で欧州型・米国型が恵まれる') if $jp;
my $note = "当日の${place}${surf}: " . join('。', @notes) . '(当日バイアスとして補正)';
print JSON::PP->new->utf8->canonical->encode({ draw => $draw, front => $fr, jp => $jp, n => scalar(@x), races => $nr, note => $note });
