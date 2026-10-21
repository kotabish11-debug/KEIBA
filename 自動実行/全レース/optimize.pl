# 予想と結果の記録から、能力値の重み(実績・距離・コース・調子・騎手)と★の基準を調整する
# 使い方: perl optimize.pl <馬ごとの記録.csv> <レースごとの記録.csv> <今のmodel.json> > 新しいmodel.json
# - 重み: 勝ち馬が高い点数になるように(条件付きロジット)当てはめ、記録が少ないうちは今の重みに強く寄せる
# - ★の基準(◎の3着以内率がこれ以上なら★): ★を付けたレースの◎の3着以内率が83%を下回れば上げ、92%以上なら少し下げる
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
use JSON::PP;
my ($hf, $rf, $mf) = @ARGV;
my @K = qw(jisseki kyori course choshi kishu);
my %prior = (jisseki => .35, kyori => .15, course => .15, choshi => .20, kishu => .15);
my $model = { weights => {%prior}, starTop3 => 0.80 };
if ($mf && -e $mf) { open my $m, '<:raw', $mf; local $/; my $x = JSON::PP->new->utf8->decode(<$m>); $model = $x if ref $x eq 'HASH' }
my %cur = %{$model->{weights}};

sub read_csv { my $f = shift; my @rows; return @rows unless -e $f; open my $fh, '<:utf8', $f or return @rows; my $hd = <$fh>; chomp $hd; $hd =~ s/^\x{feff}//; my @h = split /,/, $hd;
  while (<$fh>) { chomp; s/\r$//; my @v = split /,/, $_, -1; my %r; @r{@h} = @v; push @rows, \%r } return @rows }
my @hr = read_csv($hf);
my %races; for my $r (@hr) { next unless ($r->{rank} // '') =~ /^\d+$/; push @{$races{$r->{raceId}}}, $r }
my @rids = grep { grep { $_->{rank} == 1 } @{$races{$_}} } keys %races;
my $N = scalar @rids;

my %w = %cur;
if ($N >= 10) {
  # パラメータ: θ_k(重み = softmax(θ))と尺度 λ。点数 s = λ Σ w_k x_k / 10
  my %th = map { $_ => log($cur{$_} || 0.01) } @K; my $lam = 1.0; my $lr = 0.05;
  for my $it (1 .. 400) {
    my $z = 0; $z += exp($th{$_}) for @K; my %wk = map { $_ => exp($th{$_}) / $z } @K;
    my (%gw, $gl) = (); $gw{$_} = 0 for @K; $gl = 0;
    for my $rid (@rids) {
      my @hs = @{$races{$rid}}; my @s; my $mx = -1e9;
      for my $h (@hs) { my $v = 0; $v += $wk{$_} * (($h->{$_} || 60) / 10) for @K; push @s, $v; $mx = $v if $lam * $v > $mx }
      my @e = map { exp($lam * $_ - $mx) } @s; my $sum = 0; $sum += $_ for @e;
      for my $i (0 .. $#hs) {
        my $p = $e[$i] / $sum; my $y = $hs[$i]{rank} == 1 ? 1 : 0;
        $gl += ($y - $p) * $s[$i];
        $gw{$_} += ($y - $p) * $lam * (($hs[$i]{$_} || 60) / 10) for @K;
      }
    }
    # w = softmax(θ) の連鎖律と、今の重みへの引き戻し(L2)
    my $dot = 0; $dot += $wk{$_} * $gw{$_} for @K;
    for my $k (@K) { my $g = $wk{$k} * ($gw{$k} - $dot) / $N - 0.5 * ($th{$k} - log($cur{$k} || 0.01)); $th{$k} += $lr * $g }
    $lam += $lr * ($gl / $N - 0.1 * ($lam - 1)); $lam = 0.1 if $lam < 0.1;
  }
  my $z = 0; $z += exp($th{$_}) for @K; my %fit = map { $_ => exp($th{$_}) / $z } @K;
  # 記録が少ないうちは今の重みに寄せる(50レースで半々)
  my $a = $N / ($N + 50);
  %w = map { $_ => $a * $fit{$_} + (1 - $a) * $cur{$_} } @K;
  # 1項目は 0.05〜0.6 の範囲にして合計1に
  $w{$_} = $w{$_} < 0.05 ? 0.05 : $w{$_} > 0.6 ? 0.6 : $w{$_} for @K; my $t = 0; $t += $w{$_} for @K; $w{$_} = int($w{$_} / $t * 1000 + 0.5) / 1000 for @K;
}

# ★の基準
my @rr = read_csv($rf);
my @stars = grep { ($_->{star} // '') eq '1' && ($_->{honmeiRank} // '') =~ /^\d+$/ } @rr;
my $sp = $model->{starTop3} || 0.80; my $shit = undef;
if (@stars >= 10) {
  my $ok = grep { $_->{honmeiRank} <= 3 } @stars; $shit = $ok / @stars;
  # 目標は★のレースで◎の3着以内が83%以上(過去1,871レースでは、基準80%で実際84%・基準85%でも85%で、9割には届かない。馬情報/的中率を上げるための検証.md)
  if ($shit < 0.83) { $sp += 0.02 } elsif ($shit >= 0.92) { $sp -= 0.01 }
  $sp = 0.95 if $sp > 0.95; $sp = 0.70 if $sp < 0.70;
}
my @all = grep { ($_->{honmeiRank} // '') =~ /^\d+$/ } @rr;
my %stat = (races => scalar @all,
  honmeiWin => (@all ? int(100 * (grep { $_->{honmeiRank} == 1 } @all) / @all + 0.5) : undef),
  honmeiTop3 => (@all ? int(100 * (grep { $_->{honmeiRank} <= 3 } @all) / @all + 0.5) : undef),
  starRaces => scalar @stars, starTop3 => (defined $shit ? int(100 * $shit + 0.5) : undef));
my @t = gmtime(time + 9 * 3600);
my %out = (weights => \%w, starTop3 => int($sp * 100 + 0.5) / 100, fittedRaces => $N + 0, stats => \%stat,
  updatedAt => sprintf('%04d-%02d-%02dT%02d:%02d:00+09:00', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1]),
  note => $N >= 10 ? "結果 ${N}レースから重みを調整" : "結果が10レース未満のため重みは初期値のまま");
print JSON::PP->new->canonical->pretty->encode(\%out);
