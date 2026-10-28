# 馬DB(馬情報/馬DB/)を JRA公式から少しずつ集めて最新にする。PCのタスク「競馬_PC収集」が update.sh 経由で毎回呼ぶ(Claudeは使わない)
# 集めるもの: JRAで走った・登録された全部の競走馬(プロフィール・血統・賞金・全成績)、その父・母(種牡馬・繁殖牝馬)、母の産駒一覧、毎週の登録・抹消
# 1回の実行は BUDGET 秒(既定1500)まで。次の順に取り、時間が残れば過去の開催へ遡る(1986年まで。新しい月から)
#   1. 競走馬登録・抹消一覧(1日1回。登録は毎週月曜、抹消は月・木に出る)
#   2. 今月・先月の終わった開催の結果 → 走った馬のページを取り直す(走ったあとは成績が増えるので)
#   3. 出馬表(1日1回) → まだ無い馬のページ
#   4. 馬のページ → 父・母・母の母のページと、母・母の母の産駒一覧も取る
#   5. 遡り: 過去の月の開催の結果 → まだ無い馬
# 取ったものはすぐ state/ の記録(journal)に足すので、途中で止まっても次の実行で続きから入る
# 使い方: perl update.pl [build]   (build だけなら、まとめのファイル(種牡馬・繁殖牝馬・概要)を作り直すだけ)
use utf8; use strict; use warnings;
use File::Glob (); use JSON::PP; use File::Basename qw(dirname); use File::Path qw(make_path); use File::Temp qw(tempdir); use POSIX qw(strftime);
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
# フォルダー名に日本語があるので、パスは文字列(UTF-8を解いたもの)で持つ
my $HERE; BEGIN { require File::Spec; require Encode; $HERE = Encode::decode('UTF-8', dirname(File::Spec->rel2abs(__FILE__))) } do { my $f = Encode::encode("UTF-8", "$HERE/parse.pl"); require $f };
my $ROOT = "$HERE/../.."; my $DB = "$ROOT/馬情報/馬DB"; my $ST = "$DB/state"; my $PROFD = "$DB/競走馬"; my $RUND = "$DB/出走履歴";
make_path($ST, $PROFD, $RUND);
my $BUDGET = $ENV{BUDGET} // 1500; my $PAR = $ENV{PAR} // 3; my $T0 = time;
my $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
my $TODAY = strftime('%Y-%m-%d', gmtime(time + 9 * 3600)); my $TODAY8 = $TODAY =~ s/-//gr;
my $TMP = tempdir(CLEANUP => 1);
sub left { $BUDGET - (time - $T0) }
sub logm { print strftime('[%H:%M:%S] ', gmtime(time + 9 * 3600)), @_, "\n" }

# 表の列(ファイルの1行目)
my @PCOL = qw(id 馬名 欧字名 性 生年月日 毛色 父 父ID 母 母ID 母の父 母の父ID 母の母 母の母ID 馬主 調教師 所属 生産牧場 産地 馬名意味 取引市場 レーティング
  総賞金 地方賞金 海外賞金 収得賞金 収得賞金障害 成績 芝 ダ 障 出走数 最終出走日 最終レース 最終着順 抹消日 母産駒cname 取得日 cname 印);
my @RCOL = qw(id 年月日 場 レース名 格 レースID 芝ダ 距離 馬場 頭数 人気 着順 騎手 斤量 馬体重 タイム Rt 1着馬(2着馬));
my @KCOL = qw(繁殖key 繁殖牝馬 欧字名 生年月日 父 母の父 母 母の母 産駒 産駒ID 産駒の父 性 産駒生年月日 調教師 所属 総賞金 抹消 重賞勝ち 取得日 cname);
my @GCOL = qw(登録日 馬名 印 性 毛色 生年月日 所属 調教師 産地 生産牧場 馬主 父 母 母の父 母の母);
my @MCOL = qw(抹消日 馬名 調教師 最近のレース 父 母 収得賞金 入着賞金);
my %JRA = map { $_ => 1 } qw(札幌 函館 福島 新潟 東京 中山 中京 京都 阪神 小倉);

sub rtsv { my $f = shift; my @r; open my $h, '<:utf8', $f or return (); my $hd = <$h>; while (<$h>) { chomp; s/\r$//; next if $_ eq ''; push @r, [split /\t/, $_, -1] } return @r }
sub wtsv { my ($f, $cols, $rows) = @_; open my $h, '>:utf8', "$f.tmp" or die "$f: $!"; print $h join("\t", @$cols), "\n";
  print $h join("\t", map { my $v = $_ // ''; $v =~ s/[\t\r\n]/ /g; $v } @$_), "\n" for @$rows; close $h; rename "$f.tmp", $f or die "$f: $!" }
sub atsv { my ($f, $cols, $rows) = @_; my $new = !-s $f; open my $h, '>>:utf8', $f or die "$f: $!"; print $h join("\t", @$cols), "\n" if $new;
  print $h join("\t", map { my $v = $_ // ''; $v =~ s/[\t\r\n]/ /g; $v } @$_), "\n" for @$rows; close $h }
sub files { File::Glob::bsd_glob(Encode::encode('UTF-8', shift)) }   # glob は日本語のパスを文字列のままだと探せない
sub rlines { my $f = shift; open my $h, '<:utf8', $f or return (); my @l = map { s/\r?\n$//r } <$h>; grep { $_ ne '' } @l }

# JRAのページを取る(cname を POST。Shift_JISのまま保存)。jobs: [[保存先, access名, cname], ...]。並べて PAR 本ずつ
sub fetch {
  my @jobs = @_; return unless @jobs;
  my $lf = "$TMP/jobs.txt"; open my $h, '>', $lf or die; print $h "$_->[0] $_->[1] $_->[2]\n" for @jobs; close $h;
  system('sh', '-c', 'xargs -P "$1" -L 1 sh -c \'curl -sSL -m 30 -A "$0" -o "$1" -d "cname=$3" "https://www.jra.go.jp/JRADB/$2"; sleep 0.5\' "$2" < "$3"', '_', $PAR, $UA, $lf);
}
sub get1 { my ($acc, $cn) = @_; my $f = "$TMP/p_" . ($cn =~ s/\W/_/gr) . '.html'; fetch([$f, $acc, $cn]) unless -s $f; return slurp($f) }

# ---- 今あるデータ ----
my (%known, %lastrun, %byname, %qprio, %qcn, %qfail, %dams, %done_day, %reg_done, %tried);
for my $f (files("$PROFD/*.tsv")) { for my $r (rtsv($f)) { $known{$r->[0]} = $r->[37] // ''; $lastrun{$r->[0]} = $r->[32] // ''; push @{$byname{$r->[1]}}, [$r->[0], $r->[38]] } }
for my $l (rlines("$ST/journal_prof.tsv")) { my @c = split /\t/, $l, -1; if (@c > 37 && $c[0] =~ /^\d{10}$/) { $known{$c[0]} = $c[37] // ''; $lastrun{$c[0]} = $c[32] // '' } }
for my $l (rlines("$ST/queue.tsv")) { my ($p, $id, $cn, $fl) = split /\t/, $l; next unless $id; $qprio{$id} = $p; $qcn{$id} = $cn; $qfail{$id} = $fl // 0 }
# 繁殖牝馬(産駒一覧のページ): key → [cname, 取得日, 名前, 馬ID]
for my $l (rlines("$ST/dams.tsv")) { my ($k, $cn, $d, $nm, $id) = split /\t/, $l, -1; $dams{$k} = [$cn, $d // '', $nm // '', $id // ''] if $k }
$done_day{$_} = 1 for rlines("$ST/days_done.txt");
$reg_done{$_} = 1 for rlines("$ST/reg_done.txt");
sub save_state {
  open my $h, '>:utf8', "$ST/queue.tsv.tmp" or die; print $h "$qprio{$_}\t$_\t$qcn{$_}\t" . ($qfail{$_} // 0) . "\n" for sort keys %qprio; close $h; rename "$ST/queue.tsv.tmp", "$ST/queue.tsv";
  open $h, '>:utf8', "$ST/dams.tsv.tmp" or die; print $h join("\t", $_, @{$dams{$_}}), "\n" for sort keys %dams; close $h; rename "$ST/dams.tsv.tmp", "$ST/dams.tsv";
}
# 馬を取る予定に入れる(prio: 1=走った・出走する 2=遡りで見つけた 3=父母・産駒)。もう取ってあれば、$after より前に取ったものだけ取り直す
sub enqueue { my ($id, $cn, $prio, $after) = @_;
  return if exists $known{$id} && (!$after || ($known{$id} // '') ge $after);
  if (!exists $qprio{$id} || $prio < $qprio{$id}) { $qprio{$id} = $prio; $qcn{$id} = $cn } }
sub add_dam { my ($cn, $nm, $id) = @_; return unless $cn; my ($k) = $cn =~ /^pj01snk1(\d+)\//; return unless $k;
  $dams{$k} //= [$cn, '', $nm // '', $id // '']; $dams{$k}[2] ||= $nm // ''; $dams{$k}[3] ||= $id // '' }

# ---- 1. 競走馬登録・抹消一覧 ----
sub do_reglist {
  return if ((rlines("$ST/reglist_date.txt"))[0] // '') eq $TODAY;
  my $top = get1('accessV.html', 'pv156liH1/98'); return logm('登録・抹消一覧: 取れない') unless $top =~ /競走馬登録/;
  my ($ng, $nm) = (0, 0); my %seen;
  while ($top =~ /(pv1(5udj|6mdj)10(\d{8})\/[0-9A-F]{2})/g) {
    my ($cn, $kind, $d) = ($1, $2, $3); next if $reg_done{$cn} || $seen{$cn}++;
    my $h = get1('accessV.html', $cn);
    if ($kind eq '5udj') { my $r = reg_page($h) or next;
      atsv("$DB/登録.tsv", \@GCOL, [map { my $x = $_; [$r->{date}, @$x{qw(name mark sex color birth belong trainer origin breeder owner sire dam bms damdam)}] } @{$r->{horses}}]); $ng += @{$r->{horses}} }
    else { my $r = massho_page($h) or next;
      atsv("$DB/抹消.tsv", \@MCOL, [map { my $x = $_; [$r->{date}, @$x{qw(name trainer lastRace sire dam shutoku nyuchaku)}] } @{$r->{horses}}]); $nm += @{$r->{horses}};
      # 抹消された馬は、ページを取り直して抹消日を入れる
      for my $x (@{$r->{horses}}) { enqueue($_->[0], $_->[1], 2, $r->{date}) for @{$byname{$x->{name}} || []} } }
    $reg_done{$cn} = 1; open my $o, '>>:utf8', "$ST/reg_done.txt"; print $o "$cn\n"; close $o;
  }
  open my $o, '>:utf8', "$ST/reglist_date.txt"; print $o "$TODAY\n"; close $o;
  logm("登録・抹消一覧: 登録 $ng 頭・抹消 $nm 頭を追加");
}

# ---- 開催日(1日・1場)の全レースの結果から、走った馬を予定に入れる ----
# srl: pw01srl10<場2><年4><回2><日2><年月日8>/xx。終わった日だけ。全レース取れたら済みにする
sub do_day {
  my ($srl, $prio, $refresh) = @_; my ($key, $d8) = $srl =~ /^(pw01srl10\d{10}(\d{8}))\//; return 0 unless $key && $d8 lt $TODAY8;
  my $lst = get1('accessS.html', $srl); my %sde; $sde{$1} = 1 while $lst =~ /(pw01sde10\d{12}$d8\/[0-9A-F]{2})/g;
  return -1 unless %sde;
  my @jobs = map { ["$TMP/s_" . ($_ =~ s/\W/_/gr) . '.html', 'accessS.html', $_] } sort keys %sde; fetch(grep { !-s $_->[0] } @jobs);
  my $ok = 1; my $n = 0; my @ran; my $date = join '-', $d8 =~ /(\d{4})(\d\d)(\d\d)/;
  for my $j (@jobs) { my $h = slurp($j->[0]); unless ($h =~ /<tbody>/) { $ok = 0; next }
    for my $l (horse_links($h)) { my $b = exists $qprio{$l->[0]}; enqueue($l->[0], $l->[1], $prio, $refresh ? $date : ''); $n++ if !$b && exists $qprio{$l->[0]};
      push @ran, "$date\t$l->[0]\t$l->[1]" if $refresh } }
  # 走った馬を残す(馬のページはレースから数日おくれて成績が入るので、do_recent が入るまで取り直す)
  if (@ran) { open my $o, '>>:utf8', "$ST/ran_recent.tsv"; print $o "$_\n" for @ran; close $o }
  if ($ok) { $done_day{$key} = 1; open my $o, '>>:utf8', "$ST/days_done.txt"; print $o "$key\n"; close $o }
  return $ok ? $n : -1;
}
# 月の開催一覧のページ: (開催日の srl, ..., 前の月の cname)
sub month_page {
  my $h = shift; my %s; $s{$1} = 1 while $h =~ /(pw01srl10\d{18}\/[0-9A-F]{2})/g;
  my ($cur) = $h =~ /<div class="current"><span>(\d{4})年(\d{1,2})月/ ? sprintf('%04d%02d', $1, $2) : ''; my $prev;
  # 「前年」のリンクではなく「前月」(1か月前)を選ぶ
  if ($cur) { my ($y, $m) = $cur =~ /(\d{4})(\d\d)/; my $pm = $m == 1 ? sprintf('%04d12', $y - 1) : sprintf('%04d%02d', $y, $m - 1);
    ($prev) = $h =~ /'(pw01skl[01]0$pm\/[0-9A-F]{2})'/ }
  return ([sort { substr($b, 19, 8) cmp substr($a, 19, 8) } keys %s], $prev // '', $cur);
}

# ---- 2. 今月・先月の終わった開催 ----
sub do_recent {
  my $h = get1('accessS.html', 'pw01skl00999999/B3'); my ($days, $prev) = month_page($h); my @d = @$days;
  if ($prev) { my ($pd) = month_page(get1('accessS.html', $prev)); push @d, @$pd }
  my $lim = strftime('%Y%m%d', gmtime(time + 9 * 3600 - 45 * 86400)); my $n = 0; my $nd = 0;
  for my $s (@d) { my ($k, $d8) = $s =~ /^(pw01srl10\d{10}(\d{8}))\//; next if $done_day{$k} || $d8 lt $lim || $d8 ge $TODAY8; last if left() < 120; my $x = do_day($s, 1, 1); $n += $x if $x > 0; $nd++ }
  # 最近(14日)走った馬で、馬のページにまだそのレースが入っていない馬は、1日1回取り直す
  my $l14 = strftime('%Y-%m-%d', gmtime(time + 9 * 3600 - 14 * 86400)); my @keep; my $m = 0;
  for my $l (rlines("$ST/ran_recent.tsv")) { my ($d, $id, $cn) = split /\t/, $l; next unless $cn && $d ge $l14; push @keep, $l;
    next unless exists $known{$id} && ($lastrun{$id} // '') lt $d && ($known{$id} // '') lt $TODAY;
    my $b = exists $qprio{$id}; enqueue($id, $cn, 1, $TODAY); $m++ if !$b && exists $qprio{$id} }
  open my $o, '>:utf8', "$ST/ran_recent.tsv"; print $o "$_\n" for @keep; close $o;
  logm("最近の開催: $nd 日分を見て、取り直す馬 $n 頭。成績がまだ入っていない馬 $m 頭も取り直す");
}

# ---- 3. 出馬表(1日1回) ----
sub do_denma {
  return if ((rlines("$ST/denma_date.txt"))[0] // '') eq $TODAY;
  my $top = get1('accessD.html', 'pw01dli00/F3'); my %drl; $drl{$1} = 1 while $top =~ /(pw01drl00\d{18}\/[0-9A-F]{2})/g; my $n = 0;
  for my $c (sort keys %drl) { my $l = get1('accessD.html', $c); my %dde; $dde{$1} = 1 while $l =~ /(pw01dde01\d{20}\/[0-9A-F]{2})/g;
    my @jobs = map { ["$TMP/d_" . ($_ =~ s/\W/_/gr) . '.html', 'accessD.html', $_] } sort keys %dde; fetch(@jobs);
    for my $j (@jobs) { for my $x (horse_links(slurp($j->[0]))) { my $b = exists $qprio{$x->[0]}; enqueue($x->[0], $x->[1], 1); $n++ if !$b && exists $qprio{$x->[0]} } } }
  open my $o, '>:utf8', "$ST/denma_date.txt"; print $o "$TODAY\n"; close $o;
  logm('出馬表: ' . scalar(keys %drl) . " 開催を見て、新しい馬 $n 頭");
}

# ---- 4. 馬のページ ----
sub rec4 { my @r = @_; my @c = (0) x 4; for (@r) { next unless ($_->{rank} // '') =~ /^\d+$/; $c[$_->{rank} <= 3 ? $_->{rank} - 1 : 3]++ } join '-', @c }
sub horse_batch {
  my $n = shift; my @ids = (sort { $qprio{$a} <=> $qprio{$b} || $b cmp $a } keys %qprio)[0 .. $n - 1]; @ids = grep { defined } @ids; return 0 unless @ids;
  my @jobs = map { ["$TMP/h_$_.html", 'accessU.html', $qcn{$_}] } @ids; unlink map { $_->[0] } @jobs; fetch(@jobs);
  my (@prow, @rrow); my $ok = 0;
  for my $id (@ids) {
    my $p = horse_page(slurp("$TMP/h_$id.html"));
    unless ($p) { if (++$qfail{$id} >= 3) { delete $qprio{$id}; delete $qcn{$id}; delete $qfail{$id} } next }
    my @r = @{$p->{runs}}; my $last = $r[0] // {};
    push @prow, [$id, @$p{qw(name en sex birth color sire sireId dam damId bms bmsId damdam damdamId owner trainer belong breeder origin meaning market rating prize prizeNar prizeAbroad shutoku shutokuJ)},
      rec4(@r), rec4(grep { $_->{surf} eq '芝' } @r), rec4(grep { $_->{surf} eq 'ダ' } @r), rec4(grep { $_->{surf} eq '障' } @r), scalar(@r),
      $last->{date} // '', ($last->{race} // '') . ($last->{grade} ? "($last->{grade})" : ''), $last->{rank} // '', $p->{massho}, $p->{damSanku}, $TODAY, $qcn{$id}, $p->{mark}];
    push @rrow, [$id, @$_{qw(date place race grade raceId surf dist going heads pop rank jockey kin bw time rt winner)}] for @r;
    $known{$id} = $TODAY; $lastrun{$id} = $last->{date} // ''; delete $qprio{$id}; delete $qcn{$id}; delete $qfail{$id}; $ok++;
    for my $k (qw(sire dam bms damdam)) { enqueue($p->{"${k}Id"}, $p->{"${k}Cname"}, 3) if $p->{"${k}Id"} && $p->{"${k}Cname"} }
    add_dam($p->{damSanku}, $p->{dam}, $p->{damId}); add_dam($p->{damdamSanku}, $p->{damdam}, $p->{damdamId});
  }
  atsv("$ST/journal_prof.tsv", \@PCOL, \@prow) if @prow; atsv("$ST/journal_runs.tsv", \@RCOL, \@rrow) if @rrow;
  return $ok;
}
# 産駒一覧のページ(まだ取っていない母、60日より前に取った母)
sub dam_batch {
  my $n = shift; my $old = strftime('%Y-%m-%d', gmtime(time + 9 * 3600 - 60 * 86400));
  my @k = (sort { ($dams{$a}[1] cmp $dams{$b}[1]) || $b cmp $a } grep { $dams{$_}[1] lt $old } keys %dams)[0 .. $n - 1]; @k = grep { defined } @k; return 0 unless @k;
  my @jobs = map { ["$TMP/k_$_.html", 'accessU.html', $dams{$_}[0]] } @k; unlink map { $_->[0] } @jobs; fetch(@jobs);
  my @rows; my $ok = 0;
  for my $k (@k) {
    my $d = sanku_page(slurp("$TMP/k_$k.html")); unless ($d) { $dams{$k}[1] = $TODAY . '(失敗)' if ($dams{$k}[1] // '') eq ''; next }
    push @rows, [$k, @$d{qw(name en birth sire bms dam damdam)}, @$_{qw(name id sire sex birth trainer belong prize massho graded)}, $TODAY, $dams{$k}[0]] for @{$d->{kids}};
    push @rows, [$k, @$d{qw(name en birth sire bms dam damdam)}, ('') x 10, $TODAY, $dams{$k}[0]] unless @{$d->{kids}};
    $dams{$k}[1] = $TODAY; $dams{$k}[2] ||= $d->{name}; $ok++;
    enqueue($_->{id}, $_->{cname}, 3) for grep { $_->{id} && $_->{cname} } @{$d->{kids}};
  }
  atsv("$ST/journal_sanku.tsv", \@KCOL, \@rows) if @rows;
  return $ok;
}

# ---- 5. 遡り(1日・1場ずつ。新しい月から1986年1月まで) ----
sub backfill_one {
  my $cur = (rlines("$ST/cursor.txt"))[0] // 'pw01skl00999999/B3'; return 0 if $cur eq 'done';
  my $h = get1('accessS.html', $cur); my ($days, $prev, $ym) = month_page($h);
  return logm("遡り: 月のページが取れない($cur)") && 0 unless $ym;
  # 取れなかった日(-1)はこの実行では飛ばし、次の実行でやり直す
  for my $s (@$days) { my ($k, $d8) = $s =~ /^(pw01srl10\d{10}(\d{8}))\//; next if $done_day{$k} || $tried{$k}++ || $d8 ge $TODAY8; my $n = do_day($s, 2, 0); return [$d8, $n] }
  if (grep { my ($k, $d8) = /^(pw01srl10\d{10}(\d{8}))\//; !$done_day{$k} && $d8 lt $TODAY8 } @$days) { return 0 }   # この月にやり直す日が残っている
  my $next = ($ym le '198601' || !$prev) ? 'done' : $prev;
  open my $o, '>:utf8', "$ST/cursor.txt"; print $o "$next\n"; close $o; logm("遡り: $ym 月を終えた → " . ($next eq 'done' ? '完了' : $next));
  return 1;
}

# ---- journal を本体(生年ごとのファイル)に入れる ----
sub merge {
  my @jp = rlines("$ST/journal_prof.tsv"); my @jr = rlines("$ST/journal_runs.tsv"); my @jk = rlines("$ST/journal_sanku.tsv");
  shift @jp if @jp && $jp[0] =~ /^id\t/; shift @jr if @jr && $jr[0] =~ /^id\t/; shift @jk if @jk && $jk[0] =~ /^繁殖key\t/;
  my (%np, %nr);
  for (@jp) { my @c = split /\t/, $_, -1; next unless $c[0] =~ /^(\d{4})\d{6}$/; $np{$1}{$c[0]} = \@c; $nr{$1}{$c[0]} = {} }
  # 同じ馬を2回取っていれば出走レースが重なるので、年月日とレース名で1つにする
  for (@jr) { my @c = split /\t/, $_, -1; next unless $c[0] =~ /^(\d{4})\d{6}$/; $nr{$1}{$c[0]}{"$c[1]\t$c[3]"} = \@c if $nr{$1}{$c[0]} }
  for my $y (keys %np) {
    my $f = "$PROFD/${y}年生.tsv"; my %all = map { ($_->[0] => $_) } rtsv($f); $all{$_} = $np{$y}{$_} for keys %{$np{$y}};
    wtsv($f, \@PCOL, [map { $all{$_} } sort keys %all]);
    my $g = "$RUND/${y}年生.tsv"; my @keep = grep { !$nr{$y}{$_->[0]} } rtsv($g); push @keep, values %{$nr{$y}{$_}} for keys %{$nr{$y}};
    wtsv($g, \@RCOL, [sort { $a->[0] cmp $b->[0] || $b->[1] cmp $a->[1] } @keep]);
  }
  if (@jk) {
    my %nk; for (@jk) { my @c = split /\t/, $_, -1; $nk{$c[0]} //= []; push @{$nk{$c[0]}}, \@c }
    my $f = "$DB/産駒一覧.tsv"; my @keep = grep { !$nk{$_->[0]} } rtsv($f); push @keep, @{$nk{$_}} for keys %nk;
    wtsv($f, \@KCOL, [sort { $a->[0] cmp $b->[0] || ($a->[12] // '') cmp ($b->[12] // '') } @keep]);
  }
  unlink "$ST/journal_prof.tsv", "$ST/journal_runs.tsv", "$ST/journal_sanku.tsv";
  logm('本体に入れた: 競走馬 ' . scalar(@jp) . ' 頭・産駒一覧 ' . scalar(keys %{{ map { (split /\t/)[0] => 1 } @jk }}) . ' 頭の母');
}

# ---- まとめ: 種牡馬・繁殖牝馬・概要 ----
sub pct { my ($a, $b) = @_; $b ? sprintf('%.3f', $a / $b) : '' }
sub build {
  my %P; my %ci; @ci{@PCOL} = 0 .. $#PCOL;
  for my $f (files("$PROFD/*.tsv")) { for my $r (rtsv($f)) { $P{$r->[0]} = $r } }
  # 抹消一覧で抹消された馬(ページを取り直すまで抹消日が空のもの)
  my %mas; for my $r (rtsv("$DB/抹消.tsv")) { $mas{"$r->[1]\t$r->[4]\t$r->[5]"} = $r->[0] }
  my (%S, %B, %gw); my $y3 = (substr($TODAY, 0, 4) - 3) . substr($TODAY, 4);
  for my $f (files("$RUND/*.tsv")) {
    for my $r (rtsv($f)) {
      my $p = $P{$r->[0]} or next; next unless $JRA{$r->[2]} && $r->[11] =~ /^\d+$/;
      my ($rank, $sf, $dist, $go) = ($r->[11], $r->[6], $r->[7] || 0, $r->[8]);
      for my $t ([\%S, $p->[$ci{'父'}]], [\%B, $p->[$ci{'母の父'}]]) {
        my ($H, $nm) = @$t; next unless $nm; my $x = $H->{$nm} //= {};
        $x->{n}++; $x->{w}++ if $rank == 1; $x->{s2}++ if $rank <= 2; $x->{p}++ if $rank <= 3;
        next unless $H == \%S;
        $x->{"n$sf"}++; $x->{"w$sf"}++ if $rank == 1; $x->{"p$sf"}++ if $rank <= 3;
        my $db = $sf eq '障' ? '' : $dist <= 1400 ? 'd1' : $dist <= 1800 ? 'd2' : $dist <= 2200 ? 'd3' : 'd4';
        if ($db) { $x->{"n$db"}++; $x->{"p$db"}++ if $rank <= 3 }
        if ($go =~ /^(稍重|重|不良)$/) { $x->{nh}++; $x->{ph}++ if $rank <= 3 }
        if ($r->[1] ge $y3) { $x->{n3}++; $x->{w3}++ if $rank == 1; $x->{p3}++ if $rank <= 3 }
        if ($rank == 1 && $r->[4] =~ /^(J\.)?G\d$/) { $x->{gw}{$r->[0]} = 1; $gw{$r->[0]} = 1 }
        $x->{win}{$r->[0]} = 1 if $rank == 1;
      }
    }
  }
  # 種牡馬の国別タイプ・リーディング・種付料(既存の資料から)
  my %type = map { ($_->[0] => [$_->[1], $_->[4] // '']) } rtsv("$ROOT/馬情報/種牡馬_国別タイプ.tsv");
  my %lead; if (open my $h, '<:utf8', "$ROOT/馬情報/種牡馬リーディング_2026_中央.csv") { <$h>; while (<$h>) { chomp; my @c = split /,/; $lead{$c[1]} = $c[0] if @c > 1 } }
  my %fee; if (open my $h, '<:utf8', "$ROOT/馬情報/種牡馬一覧_アロースタッド_2026.csv") { <$h>; while (<$h>) { chomp; my @c = split /,/; $fee{$c[0]} = ($c[7] // '') . '万円(アロースタッド)' if @c > 7 } }
  my (%kids, %sireid);
  for my $p (values %P) { my $s = $p->[$ci{'父'}] or next; push @{$kids{$s}}, $p; $sireid{$s} ||= $p->[$ci{'父ID'}] }
  my @rows;
  for my $s (keys %kids) {
    my $k = $kids{$s}; my $x = $S{$s} // {}; my $bm = $B{$s} // {}; my $me = $sireid{$s} ? $P{$sireid{$s}} : undef;
    my @top = (sort { ($b->[$ci{'総賞金'}] || 0) <=> ($a->[$ci{'総賞金'}] || 0) } @$k)[0 .. 2]; my $sum = 0; $sum += ($_->[$ci{'総賞金'}] || 0) for @$k;
    push @rows, [$s, $sireid{$s} // '', $me ? ($me->[$ci{'生年月日'}], $me->[$ci{'父'}], $me->[$ci{'母の父'}]) : ('', '', ''), @{$type{$s} // ['', '']}, $lead{$s} // '', $fee{$s} // '',
      scalar(@$k), scalar(grep { $_->[$ci{'出走数'}] } @$k), scalar(keys %{$x->{win} // {}}), scalar(keys %{$x->{gw} // {}}),
      $x->{n} // 0, $x->{w} // 0, pct($x->{w} // 0, $x->{n}), pct($x->{s2} // 0, $x->{n}), pct($x->{p} // 0, $x->{n}),
      $x->{'n芝'} // 0, pct($x->{'w芝'} // 0, $x->{'n芝'}), pct($x->{'p芝'} // 0, $x->{'n芝'}), $x->{'nダ'} // 0, pct($x->{'wダ'} // 0, $x->{'nダ'}), pct($x->{'pダ'} // 0, $x->{'nダ'}),
      (map { pct($x->{"p$_"} // 0, $x->{"n$_"}) } qw(d1 d2 d3 d4)), pct($x->{ph} // 0, $x->{nh}), $x->{nh} // 0,
      $x->{n3} // 0, pct($x->{w3} // 0, $x->{n3}), pct($x->{p3} // 0, $x->{n3}), $sum,
      join('・', map { $_->[$ci{'馬名'}] } grep { defined && $_->[$ci{'総賞金'}] } @top), $bm->{n} // 0, pct($bm->{w} // 0, $bm->{n}), pct($bm->{p} // 0, $bm->{n})];
  }
  wtsv("$DB/種牡馬.tsv", [qw(種牡馬 種牡馬ID 生年月日 父 母の父 国別タイプ 系統 リーディング順位2026中央 種付料 産駒数 出走頭数 勝ち馬頭数 重賞勝ち馬頭数 出走回数 勝利数 勝率 連対率 複勝率
    芝出走 芝勝率 芝複勝率 ダ出走 ダ勝率 ダ複勝率 複勝率1400以下 複勝率1401-1800 複勝率1801-2200 複勝率2201以上 道悪複勝率 道悪出走 直近3年出走 直近3年勝率 直近3年複勝率 産駒総賞金 代表産駒
    母父として出走回数 母父として勝率 母父として複勝率)], [sort { $b->[33] <=> $a->[33] || $a->[0] cmp $b->[0] } @rows]);
  # 繁殖牝馬: 産駒一覧のページ(あれば)と、DBの競走馬の母から
  my %D;
  for my $r (rtsv("$DB/産駒一覧.tsv")) { my $d = $D{"$r->[1]\t$r->[3]"} //= { key => $r->[0], name => $r->[1], birth => $r->[3], info => [@$r[4 .. 7]], got => $r->[18], kids => {} };
    $d->{kids}{$r->[8]} = { name => $r->[8], id => $r->[9], sire => $r->[10], birth => $r->[12], prize => $r->[15], graded => $r->[17] } if $r->[8] ne '' }
  my %dkey = map { ($_->{name} => $_) } values %D;   # 名前だけで引く(産駒の母の名前)
  for my $p (values %P) { my $nm = $p->[$ci{'母'}] or next;
    my $d = $dkey{$nm} // do { my $x = { name => $nm, birth => '', info => [$p->[$ci{'母の父'}], '', $p->[$ci{'母の母'}], ''], kids => {} }; $D{"$nm\t"} = $x; $dkey{$nm} = $x };
    $d->{id} ||= $p->[$ci{'母ID'}]; $d->{kids}{$p->[1]} //= { name => $p->[1], id => $p->[0], sire => $p->[$ci{'父'}], birth => $p->[$ci{'生年月日'}], prize => $p->[$ci{'総賞金'}] } }
  my @dr;
  for my $d (values %D) {
    my @k = sort { ($a->{birth} // '') cmp ($b->{birth} // '') } values %{$d->{kids}}; my $me = $d->{id} ? $P{$d->{id}} : undef;
    my ($nr, $nw, $ng, $sum) = (0, 0, 0, 0);
    for my $c (@k) { my $q = $c->{id} ? $P{$c->{id}} : undef; $sum += $c->{prize} || 0;
      if ($q) { $nr++ if $q->[$ci{'出走数'}]; $nw++ if ($q->[$ci{'成績'}] // '') =~ /^[1-9]/ } $ng++ if $c->{graded} || ($c->{id} && $gw{$c->{id}}) }
    my ($best) = sort { ($b->{prize} || 0) <=> ($a->{prize} || 0) } @k;
    push @dr, [$d->{name}, $d->{id} // '', $d->{birth} || ($me ? $me->[$ci{'生年月日'}] : ''), $me ? ($me->[$ci{'父'}], $me->[$ci{'母の父'}], $me->[$ci{'母'}], $me->[$ci{'母の母'}]) : ($d->{info}[0], $d->{info}[1], $d->{info}[2], $d->{info}[3]),
      $me ? ($me->[$ci{'成績'}], $me->[$ci{'総賞金'}]) : ('', ''), scalar(@k), $nr, $nw, $ng, $sum, $best && $best->{prize} ? "$best->{name}($best->{prize}円)" : '',
      join('、', map { substr($_->{birth} // '', 0, 4) . ":$_->{name}(" . ($_->{sire} // '') . ')' } @k), $d->{got} // ''];
  }
  wtsv("$DB/繁殖牝馬.tsv", [qw(繁殖牝馬 繁殖牝馬ID 生年月日 父 母の父 母 母の母 自身の成績 自身の総賞金 産駒数 出走した産駒 勝ち上がった産駒 重賞勝ち産駒 産駒総賞金 一番稼いだ産駒 産駒(生年:馬名(父)) 産駒一覧の取得日)],
    [sort { $b->[13] <=> $a->[13] || $a->[0] cmp $b->[0] } @dr]);
  # 概要
  my (%cnt, $act, $ret); for my $p (values %P) { $cnt{substr($p->[0], 0, 4)}++; if ($p->[$ci{'抹消日'}] || $mas{"$p->[1]\t$p->[$ci{'父'}]\t$p->[$ci{'母'}]"}) { $ret++ } else { $act++ } }
  my $cur = (rlines("$ST/cursor.txt"))[0] // '(まだ)'; my ($cym) = $cur =~ /pw01skl[01]0(\d{6})/; $cur = $cym ? substr($cym, 0, 4) . '年' . (substr($cym, 4) + 0) . '月' : $cur;
  my $nreg = () = rtsv("$DB/登録.tsv"); my $nmas = () = rtsv("$DB/抹消.tsv"); my $ndam = grep { $dams{$_}[1] =~ /^\d/ } keys %dams;
  open my $o, '>:utf8', "$DB/概要.md" or die;
  print $o "# 馬DB の概要(自動で作り直す)\n\n" . strftime('%Y-%m-%d %H:%M', gmtime(time + 9 * 3600)) . " 時点。作り方・使い方は [説明.md](説明.md)\n\n";
  print $o "| 項目 | 数 |\n|---|---|\n| 競走馬 | " . scalar(keys %P) . " 頭(抹消 " . ($ret // 0) . "・現役 " . ($act // 0) . ")|\n| 種牡馬(産駒がDBにいる父) | " . scalar(@rows) . " 頭 |\n";
  print $o "| 繁殖牝馬(産駒がDBにいる母) | " . scalar(@dr) . " 頭(産駒一覧を取った母 $ndam)|\n| 競走馬登録の記録 | $nreg 頭 |\n| 抹消の記録 | $nmas 頭 |\n| これから取る馬 | " . scalar(keys %qprio) . " 頭 |\n| 遡り | $cur まで進行中(1986年1月まで) |\n\n";
  print $o "## 生年ごとの頭数\n\n| 生年 | 頭数 |\n|---|---|\n"; print $o "| $_ | $cnt{$_} |\n" for sort { $b cmp $a } keys %cnt;
  close $o;
  logm('まとめを作り直した: 競走馬 ' . scalar(keys %P) . '・種牡馬 ' . scalar(@rows) . '・繁殖牝馬 ' . scalar(@dr));
}

if (($ARGV[0] // '') eq 'build') { merge(); build(); exit 0 }
# 消えた分を取り直す予定に入れる(2026-10-27 の git の競合で、プロフィールの一部が消えたときに作った)
#   ・父・母・母の父・母の母がDBにいない馬 → その子のページを取り直す(子のページに父母のリンクがある。父母1頭につき子1頭)
#   ・出走履歴にいてプロフィールが無い馬 → 済んだ開催日を消して遡りを今月からやり直す(結果のページに馬のリンクがある)
#   ・産駒一覧を取ったことになっているのに 産駒一覧.tsv に無い母 → 取り直す
if (($ARGV[0] // '') eq 'repair') {
  merge(); my %cn; my %pc; my $np = 0;
  for my $f (files("$PROFD/*.tsv")) { for my $r (rtsv($f)) { $cn{$r->[0]} = $r->[38] } }
  for my $f (files("$PROFD/*.tsv")) { for my $r (rtsv($f)) { for my $i (7, 9, 11, 13) { my $p = $r->[$i] // ''; next if $p eq '' || $known{$p} || $pc{$p};
    $pc{$p} = 1; next unless $r->[38]; $known{$r->[0]} = '';   # 取得日を空にして、取り直す予定に入るようにする
    my $b = exists $qprio{$r->[0]}; enqueue($r->[0], $r->[38], 1, $TODAY); $np++ if !$b } } }
  my %ran; for my $f (files("$RUND/*.tsv")) { open my $h, '<:utf8', $f or next; <$h>; while (<$h>) { my ($id) = split /\t/; $ran{$id} = 1 unless $known{$id} || $cn{$id} } }
  my %kk; for my $r (rtsv("$DB/産駒一覧.tsv")) { $kk{$r->[0]} = 1 } my $nd = 0;
  for my $k (keys %dams) { if (($dams{$k}[1] // '') ne '' && !$kk{$k}) { $dams{$k}[1] = ''; $nd++ } }
  mkdir "$ST/backup_$TODAY8"; for my $f (qw(days_done.txt cursor.txt queue.tsv dams.tsv)) { system('cp', "$ST/$f", "$ST/backup_$TODAY8/$f") if -e "$ST/$f" }
  if (%ran) { open my $o, '>:utf8', "$ST/days_done.txt"; close $o; %done_day = (); open $o, '>:utf8', "$ST/cursor.txt"; print $o "pw01skl00999999/B3\n"; close $o }
  save_state();
  logm("取り直し: 父母がいない馬 " . scalar(keys %pc) . " 頭(子 $np 頭を取り直す)・プロフィールの無い出走馬 " . scalar(keys %ran) . " 頭(遡りを今月からやり直す)・産駒一覧の母 $nd 頭");
  exit 0;
}
merge();   # 前回止まったときの残り
do_reglist(); do_recent(); do_denma(); save_state();
my ($nh, $nk, $nb) = (0, 0, 0); my $lastsave = time;
while (left() > 180) {
  # 取る予定の馬が少なくなったら、過去の開催を1日ぶん遡る
  my $bf = keys(%qprio) < 600 ? backfill_one() : 0; $nb++ if ref $bf;
  my $a = horse_batch(60); $nh += $a;
  my $c = left() > 180 ? dam_batch(15) : 0; $nk += $c;
  last if !$a && !$c && !$bf;
  if (time - $lastsave > 120) { save_state(); $lastsave = time; logm("途中: 馬 $nh 頭・産駒一覧 $nk 頭の母・遡り $nb 日、残り " . scalar(keys %qprio) . ' 頭') }
}
save_state(); logm("取得: 馬 $nh 頭・産駒一覧 $nk 頭の母・遡り $nb 日。これから取る馬 " . scalar(keys %qprio) . ' 頭');
merge(); build();
