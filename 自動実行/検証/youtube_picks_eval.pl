use strict; use warnings; use utf8; use JSON::PP; use Encode;
# equine315 の動画で名前が出た馬(消去・残り/推奨・追い切りA/S・本命・印・WIN5推奨)を、レース.jsonl の結果と照合する
# 使い方: perl 自動実行/検証/youtube_picks_eval.pl <字幕のフォルダー> 馬情報/過去レースデータ/全期間  → <字幕のフォルダー>/picks.tsv と役割ごとの集計
#  字幕のフォルダー: list_videos.txt・list_shorts.txt(ID<TAB>タイトル)、part_*.meta(ID<TAB>投稿日)、txt/<ID>.txt(字幕の本文)、subs/<ID>.description
#  出典: 馬情報/イクイネKEIBA_動画まとめ.md
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
my ($EQ, $ALL) = map { decode('UTF-8', $_) } @ARGV;
sub days { my ($y, $m, $d) = split /-/, shift; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }
sub rd { my $f = shift; open my $h, '<:utf8', encode('UTF-8', $f) or return ''; local $/; my $t = <$h>; $t }
my %byday;
for my $y (2023 .. 2026) {
  open my $h, '<:raw', encode('UTF-8', "$ALL/$y/レース.jsonl") or next;
  while (<$h>) { my $r = eval { decode_json($_) } or next; push @{ $byday{ days($r->{date}) } }, $r }
}
my (%title, %up);
for my $f ("$EQ/list_videos.txt", "$EQ/list_shorts.txt") { for (split /\r?\n/, rd($f)) { my @a = split /\t/; $title{$a[0]} = $a[1] } }
for my $f (glob "$EQ/part_*.meta") { for (split /\r?\n/, rd($f)) { my ($id, $d) = split /\t/; $up{$id} = "$1-$2-$3" if $d && $d =~ /^(\d{4})(\d\d)(\d\d)$/ } }
# 単勝オッズの Harville 式で3着以内の確率
sub harv3 { my @p = @_; my $s = 0; $s += $_ for @p; @p = map { $_ / $s } @p; my @r;
  for my $i (0 .. $#p) { my ($two, $three) = (0, 0);
    for my $a (0 .. $#p) { next if $a == $i; my $pa = $p[$a];
      $two += $pa * $p[$i] / (1 - $pa);
      for my $b (0 .. $#p) { next if $b == $i || $b == $a; $three += $pa * $p[$b] / (1 - $pa) * $p[$i] / (1 - $pa - $p[$b]) } }
    $r[$i] = $p[$i] + $two + $three } @r }
my $N = qr/(?:\d+|[一二三四五六七八九十])/;
open my $out, '>:utf8', "$EQ/picks.tsv";
print $out join("\t", qw(id kind up date race grade name role pop odds rank)), "\n";
my %agg;
for my $id (sort keys %title) {
  next unless $up{$id};
  (my $txt = rd("$EQ/txt/$id.txt")) =~ s/\s+//g; $txt =~ s/\[音楽\]//g;
  next unless length $txt;
  my $desc = rd("$EQ/subs/$id.description"); my @tags = $desc =~ /[#＃]([^\s#＃]+)/g;
  my $t = $title{$id};
  my $kind = $t =~ /WIN5/ ? 'win5' : $t =~ /消去|消し|追い切り|データ|推奨|予想/ ? 'shokyo' : 'other';
  next if $kind eq 'other';
  my $u = days($up{$id});
  my @cand;
  if ($kind eq 'win5' && $t =~ /(\d{4})年(\d+)月(\d+)日/) { @cand = @{ $byday{ days(sprintf '%04d-%02d-%02d', $1, $2, $3) } || [] } }
  else { @cand = grep { $_->{grade} } map { @{ $byday{$_} || [] } } ($u - 1) .. ($u + 8) }
  my $all = $txt . join(' ', '', @tags);
  my @hit;
  for my $r (@cand) { my @m = grep { length($_->{name}) >= 3 && index($all, $_->{name}) >= 0 } @{ $r->{horses} }; push @hit, [$r, \@m] if @m }
  @hit = sort { @{ $b->[1] } <=> @{ $a->[1] } } @hit; next unless @hit;
  my $top = @{ $hit[0][1] };
  @hit = $kind eq 'shokyo' ? grep { @{ $_->[1] } >= 3 && @{ $_->[1] } >= 0.3 * $top } @hit : grep { $_->[0]{no} >= 9 || $_->[0]{grade} } @hit;
  # 区間
  my (@el, @rem, @oi, @hon, @mk);
  while ($txt =~ /(?:該当した馬は|該当したのは|該当馬は|外交した馬は|該当する馬は|該当した馬が|外交したのは)(.{1,90}?)(?:の)?$N[頭等]/g) { push @el, $1 }
  while ($txt =~ /(?:残った馬は|残ったのは)(.{1,160}?)(?:の)?$N[頭等]/g) { push @rem, $1 }
  if ($txt =~ /.*推奨は(.{1,300}?)(?:でした|です|この動画)/s) { my $s = $1; my ($a, $b) = split /[SＳ]評価|エス評価|調教|長京|超京|調京|東京S|東京エス/, $s, 2; push @rem, $a; push @oi, $b if defined $b }
  while ($txt =~ /(?:[AＡSＳ]評価|エス評価)の?$N?(?:投目|頭目|等目|とう目)は(.{1,25})/g) { push @oi, $1 }
  while ($txt =~ /本命は(.{1,25})/g) { push @hon, $1 }
  while ($txt =~ /(?:対抗に|対抗は|単穴に|タン穴に|単穴は|丹穴に|連下に|レカに|連化に|穴に|穴は)(.{1,40})/g) { push @mk, $1 }
  for my $hr (@hit) {
    my ($r, $m) = @$hr;
    my @hs = grep { $_->{odds} } @{ $r->{horses} };
    my %p3; my @q3 = harv3(map { 1 / $_->{odds} } @hs); @p3{ map { $_->{umaban} } @hs } = @q3;
    my $sum = 0; $sum += 1 / $_->{odds} for @hs;
    for my $h (@$m) {
      next unless $h->{odds} && $h->{rank} && $h->{rank} =~ /^\d+$/;
      my $nm = $h->{name}; my $in = sub { scalar grep { index($_, $nm) >= 0 } @_ };
      my @roles;
      if ($kind eq 'win5') { @roles = ('WIN5推奨') }
      else {
        push @roles, '消去' if $in->(@el);
        push @roles, '追い切り評価' if $in->(@oi);
        push @roles, '残り・推奨' if $in->(@rem) && !$in->(@el);
        push @roles, '本命' if $in->(@hon);
        push @roles, '対抗以下の印' if $in->(@mk) && !$in->(@hon);
        push @roles, '消去で追い切り評価(復活)' if $in->(@el) && $in->(@oi);
        @roles = ('判定できず') unless @roles;
      }
      my $q = (1 / $h->{odds}) / $sum; my $q3 = $p3{ $h->{umaban} } // 0;
      print $out join("\t", $id, $kind, $up{$id}, $r->{date}, $r->{name}, $r->{grade} || '-', $nm, join('+', @roles), $h->{pop}, $h->{odds}, $h->{rank}), "\n";
      my $yr = substr($r->{date}, 0, 4) < 2026 ? '〜2025' : '2026';
      for my $role (@roles) { for my $k ($role, "$role/$yr", ($kind eq 'win5' ? "$role/" . ($r->{grade} ? '重賞' : '平場') : ())) {
        my $a = $agg{$k} ||= {};
        $a->{n}++; $a->{w}++ if $h->{rank} == 1; $a->{t3}++ if $h->{rank} <= 3; $a->{q} += $q; $a->{q3} += $q3; $a->{ret} += $h->{odds} if $h->{rank} == 1;
      } }
    }
  }
}
printf "%-28s %5s %4s %5s %8s %8s %7s %6s\n", qw(役割 頭数 勝 3着内 勝÷市場 3着÷市場 単回収 3着内率);
for my $k (sort keys %agg) { my $a = $agg{$k}; my $w = $a->{w} // 0; my $t3 = $a->{t3} // 0;
  my $z = ($t3 - $a->{q3}) / (sqrt($a->{q3} * (1 - $a->{q3} / $a->{n})) || 1);
  printf "%-28s %5d %4d %5d %8.2f %8.2f %6.0f%% %5.0f%%  z3=%+.1f\n", $k, $a->{n}, $w, $t3, $w / $a->{q}, $t3 / ($a->{q3} || 1), 100 * ($a->{ret} // 0) / $a->{n}, 100 * $t3 / $a->{n}, $z }
