# 学習データ(平場_*.jsonl.gz)を、過去レースでシミュレーターを動かす harness.html 用の data.js にする(計算に要る項目だけ)
# 使い方: perl make_data.pl <出力 data.js> <平場_*.jsonl.gz>...
use utf8; use strict; use warnings;
use JSON::PP; use IO::Uncompress::Gunzip;
my ($out, @gz) = @ARGV;
my $J = JSON::PP->new->utf8->canonical; my (@all, %seen);
my @HK = qw(name umaban style jisseki kyori course choshi kishu heavy odds rank pop mustLead fromShort sireType damsireType weight);
for my $g (@gz) { my $z = IO::Uncompress::Gunzip->new($g) or die;
  while (my $l = $z->getline) { my $r = eval { $J->decode($l) } or next; next if $seen{$r->{id}}++;
    my @hs = map { my $h = $_; +{ map { exists $h->{$_} ? ($_ => $h->{$_}) : () } @HK } } @{$r->{horses}};
    push @all, { (map { $_ => $r->{$_} } qw(id date place no surface dist cond cls going heads)), horses => \@hs } } }
@all = sort { $a->{id} cmp $b->{id} } @all;
open my $o, '>:raw', $out or die; print $o "const DATA = ", $J->encode(\@all), ";\n"; close $o;
print scalar(@all), " races\n";
