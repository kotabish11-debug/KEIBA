#!/usr/bin/perl
# 調教の表(chokyo.tsv)を作る。race_json.pl が「調教の点」(本数がふだんより多い・坂路の終いが速い・2週間に0本)の補正に使う
# 使い方: perl 自動実行/全レース/chokyo_table.pl [馬情報/JRA-VAN] > 自動実行/全レース/chokyo.tsv
#   JRA-VAN のデータはPCにしか無く再配布できないので、PCの run.sh が1日1回作り直し、表はコミットしない(.gitignore)。クラウドでは補正なし
# 中身: 1行目「#最終 <調教の最後の日>」、そのあと 馬名 <TAB> ふだんの本数 <TAB> この21日の調教(日付:種類0坂路1ウッド:4F:終い1F:その前の1F をセミコロン区切り、時計は0.1秒)
#   ふだんの本数 = 2年以内のJRAの平地の出走(新馬を除く)ごとの「その前14日の本数」の平均(2走以上あるときだけ)。自動実行/検証/jv_chokyo_eval.pl と同じ作り方
# 出典: 馬情報/的中率を上げるための検証.md の22・25
use strict; use warnings; use utf8; use Encode qw(encode decode_utf8);
binmode STDOUT, ':utf8';
sub fn { encode('UTF-8', $_[0]) }
my $D = @ARGV ? decode_utf8(shift) : '馬情報/JRA-VAN';
sub days { my ($y, $m, $d) = $_[0] =~ /^(\d{4})-?(\d\d)-?(\d\d)/ or return 0; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }
my %JRA = map { $_ => 1 } qw(札幌 函館 福島 新潟 東京 中山 中京 京都 阪神 小倉);

# 1. 現役馬(抹消日が空)
my %name;
for my $f (glob(fn("$D/馬DB/競走馬/") . '*.tsv')) { open my $t, '<:utf8', $f or next; my $hd = <$t>; chomp $hd; my %i; my @c = split /\t/, $hd; @i{@c} = 0 .. $#c;
  while (<$t>) { chomp; my @x = split /\t/; $name{$x[0]} = $x[$i{'馬名'}] if ($x[$i{'抹消日'}] // '') eq '' && $x[$i{'馬名'}] } }
die "$D/馬DB/競走馬 がありません\n" unless %name;

# 2. 調教(坂路・ウッド。今年と前の2年)
my (%W, %dup, $last); my $Y = (localtime)[5] + 1900;
for my $k (0, 1) { for my $y ($Y - 2 .. $Y) { my $f = fn("$D/全データ/" . ($k ? 'WOOD' : 'SLOP') . "/$y.txt"); open my $h, '<', $f or next;
  while (my $l = <$h>) { my $hid = substr($l, 24, 10); next unless $name{$hid}; next if $dup{$k . substr($l, 11, 23)}++;
    my ($t4, $l2, $l1) = $k ? (substr($l, 79, 4), substr($l, 97, 3), substr($l, 100, 3)) : (substr($l, 34, 4), substr($l, 52, 3), substr($l, 55, 3));
    $_ = /^\d+$/ ? $_ + 0 : 0 for $t4, $l2, $l1; my $d = substr($l, 12, 8);
    $d = join('-', substr($d, 0, 4), substr($d, 4, 2), substr($d, 6, 2));
    push @{$W{$hid}}, [days($d), $k, $t4, $l1, $l2, $d]; $last = $d if !$last || $d gt $last } } }
die "調教のデータがありません\n" unless $last;
my $L = days($last);

# 3. 2年以内の出走(JRAの平地・新馬を除く)ごとの、その前14日の本数
my %runs;
for my $f (glob(fn("$D/馬DB/出走履歴/") . '*.tsv')) { open my $t, '<:utf8', $f or next; my $hd = <$t>; chomp $hd; my %i; my @c = split /\t/, $hd; @i{@c} = 0 .. $#c;
  while (<$t>) { chomp; my @x = split /\t/; next unless $name{$x[0]} && $JRA{$x[$i{'場'}] // ''};
    next if ($x[$i{'芝ダ'}] // '') =~ /障/ || ($x[$i{'レース名'}] // '') =~ /新馬/; my $d = days($x[$i{'年月日'}]); push @{$runs{$x[0]}}, $d if $d >= $L - 730 && $d <= $L } }

print "#最終\t$last\n";
for my $hid (sort { $name{$a} cmp $name{$b} } grep { $W{$_} || $runs{$_} } keys %name) {
  my @w = @{$W{$hid} || []}; my %rd = map { $_ => 1 } @{$runs{$hid} || []}; my @r = keys %rd;
  my $base = ''; if (@r >= 2) { my $s = 0; for my $d (@r) { $s += grep { $_->[0] < $d && $_->[0] >= $d - 14 } @w } $base = sprintf('%.2f', $s / @r) }
  my @recent = map { join(':', "$_->[5]", @{$_}[1 .. 4]) } sort { $a->[0] <=> $b->[0] } grep { $_->[0] > $L - 21 } @w;
  print "$name{$hid}\t$base\t", join(';', @recent), "\n";
}
