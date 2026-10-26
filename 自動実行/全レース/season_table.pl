#!/usr/bin/perl
# 1年前の好走の表(season.tsv)を作る。race_json.pl が「1年前の同じ時期に3着以内・近5走は4着以下(得意な季節)」の補正に使う
# 使い方: perl 自動実行/全レース/season_table.pl 馬情報/過去レースデータ/全期間 > 自動実行/全レース/season.tsv
#   (全期間のデータはPCにしか無いので、PCの run.sh が1日1回作り直し、PC収集がコミットする。クラウドはコミットされた表を使う)
# 中身: 馬名 <TAB> 3着以内に入ったJRAの平地のレースの日付(カンマ区切り)。最後のレースの日から430日前まで
# 出典: YouTube「競馬予想で始めるデータ分析」の「馬の得意な季節を競馬AIに学習させる」。2017〜2026/3 の 13,997頭で勝率が市場の1.15倍
#   (前半1.16・後半1.14、2026/4〜10 は1.19)。自動実行/検証/holdout_eval.pl、馬情報/的中率を上げるための検証.md の19
use strict; use warnings; use utf8; use JSON::PP; use Encode qw(encode);
binmode STDOUT, ':utf8';
my $DIR = shift or die "使い方: perl season_table.pl <全期間のフォルダー>\n";
sub days { my ($y, $m, $d) = split /-/, shift; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }
my @yd = grep { -d $_ && /\/(\d{4})$/ } sort glob("$DIR/*"); @yd = @yd[-2 .. -1] if @yd > 2;
my (@R, %seen, $last);
for my $yd (@yd) { open my $f, '<', "$yd/" . encode('UTF-8', 'JRA詳細.jsonl') or next;
  while (<$f>) { my $r = eval { decode_json($_) } or next; next if $seen{$r->{id}}++; push @R, $r; $last = $r->{date} if !$last || $r->{date} gt $last } }
die "JRA詳細.jsonl がありません\n" unless $last;
my $L = days($last); my %T;
for my $r (@R) {
  next if days($r->{date}) < $L - 430;
  my $R = $r->{race} || {}; next if ($R->{course} // '') =~ /障|→/ || ($R->{surface} // '') =~ /障/;
  for my $h (@{$r->{horses} || []}) { next unless ($h->{rank} // '') =~ /^\d+$/ && $h->{rank} <= 3 && $h->{name}; $T{$h->{name}}{$r->{date}} = 1 }
}
print "$_\t", join(',', sort keys %{$T{$_}}), "\n" for sort keys %T;
