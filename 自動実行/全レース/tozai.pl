# 重賞の着順CSVを、開催地域(関東・関西・北海道)×調教師の所属(栗東・美浦)で集計し、人気から見た期待値と比べる
# 使い方: perl tozai.pl 馬情報/調教師の所属.tsv 馬情報/2026重賞_全着順.csv
# 所属表は競馬ラボの馬柱の「厩舎」欄(栗/美 と略称)から作ったもの。未対応の調教師は最後に出るので、所属表に足す
use utf8; use strict; use warnings; binmode STDOUT, ':utf8';
my ($abbrf, $csv) = @ARGV;
open my $a, '<:utf8', $abbrf or die; <$a>; my %ab; while (<$a>) { chomp; s///; my ($n, $t) = split /	/; $ab{$n} = $t }
open my $c, '<:encoding(UTF-8)', $csv or die; my $hd = <$c>;
my (%st, %miss, %tr);
while (<$c>) { chomp; s/^\x{FEFF}//; s///; my @f = map { s/^"|"$//gr } split /","/;
  my ($date, $race, $grade, $place, $rank, $trainer, $pop) = @f[0,1,2,3,4,16,17];
  next unless $rank =~ /^\d+$/;
  my ($sur, $giv) = split / /, $trainer, 2; $giv //= '';
  my $t = $tr{$trainer} //= do { my $r; for my $k (keys %ab) { if (index($k, $sur) == 0) { my $rest = substr($k, length $sur); if ($rest eq '' || index($giv, $rest) == 0) { $r = $ab{$k}; last } } } $r // '?' };
  if ($t eq '?') { $miss{$trainer}++; next }
  my $area = $place =~ /東京|中山|新潟|福島/ ? '関東' : $place =~ /京都|阪神|中京|小倉/ ? '関西' : '北海道';
  my $k = "$area\t$t"; $st{$k}{n}++; $st{$k}{w}++ if $rank == 1; $st{$k}{p}++ if $rank <= 3;
  # 人気から見た期待との差: 人気ごとの全体の勝率を後で引く
  $st{$k}{pops} .= "$pop,$rank;";
}
# 人気別の全体勝率・複勝率
my (%pw, %pp, %pn);
for my $k (keys %st) { for (split /;/, $st{$k}{pops}) { my ($p, $r) = split /,/; next unless $p =~ /^\d+$/; $pn{$p}++; $pw{$p}++ if $r == 1; $pp{$p}++ if $r <= 3 } }
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", qw(地域 所属 頭数 勝率 複勝率 人気から見た勝ち期待 人気から見た複勝期待);
for my $k (sort keys %st) { my $s = $st{$k}; my ($ew, $ep) = (0, 0);
  for (split /;/, $s->{pops}) { my ($p, $r) = split /,/; next unless $p =~ /^\d+$/; $ew += ($pw{$p} // 0) / $pn{$p}; $ep += ($pp{$p} // 0) / $pn{$p} }
  printf "%s\t%d\t%.1f%%\t%.1f%%\t実%d/期待%.1f\t実%d/期待%.1f\n", $k, $s->{n}, 100 * ($s->{w} // 0) / $s->{n}, 100 * ($s->{p} // 0) / $s->{n}, $s->{w} // 0, $ew, $s->{p} // 0, $ep }
print "未対応: ", join(' ', map { "$_($miss{$_})" } sort keys %miss), "\n";
