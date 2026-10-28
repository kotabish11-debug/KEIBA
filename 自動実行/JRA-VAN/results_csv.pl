# 全期間のレース結果を、odds_move.pl が読む形の馬ごとのCSVにする
#   着順・単勝オッズ = <年>/レース.jsonl、血統登録番号 = <年>/JRA詳細.jsonl(馬番でつなぐ。JRA詳細のオッズは1着馬だけ)
# 使い方: perl results_csv.pl [全期間のフォルダー] [始まりの年] > 結果_馬ごと.csv
#   列: raceId,date,umaban,rank,odds,horseId,cls,surface(障害・新馬は除く)
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP; use Encode qw(decode_utf8);
my ($dir, $from) = @ARGV; $dir ||= '馬情報/過去レースデータ/全期間'; $from ||= 2005;
my $J = JSON::PP->new->utf8;
print "raceId,date,umaban,rank,odds,horseId,cls,surface\n";
for my $yd (map { decode_utf8($_) } sort glob "$dir/[12][0-9][0-9][0-9]") {
  my ($y) = $yd =~ m{(\d{4})$}; next if $y < $from;
  my %hid;
  if (open my $h, '<', "$yd/JRA詳細.jsonl") {
    while (my $l = <$h>) { my $x = eval { $J->decode($l) } or next;
      $hid{$x->{id}}{$_->{umaban}} = $_->{horseId} for grep { $_->{horseId} } @{$x->{horses} || []} } }
  open my $h, '<', "$yd/レース.jsonl" or next;
  while (my $l = <$h>) {
    my $x = eval { $J->decode($l) } or next;
    my $cls = $x->{cls} // ''; my $sf = $x->{surface} // '';
    next if $cls =~ /新馬|障害/ || $sf =~ /障/;
    for my $m (@{$x->{horses} || []}) {
      next unless ($m->{rank} // '') =~ /^\d+$/ && ($m->{odds} // 0) >= 1;
      print join(',', $x->{id}, $x->{date}, $m->{umaban}, $m->{rank}, $m->{odds}, $hid{$x->{id}}{$m->{umaban}} // '', $cls, $sf), "\n";
    }
  }
}
