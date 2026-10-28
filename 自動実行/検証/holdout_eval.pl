#!/usr/bin/perl
# race_json.pl の自動補正(YouTube の動画から入れたもの)を、条件を決めたときに使っていない期間で確かめ直す
# (Stanford の統計学習の講義「交差検証の正しいやり方」「多重検定・Benjamini-Hochberg」から。出典: 馬情報/スタンフォード大学_講義まとめ.md)
#
# 使い方: perl 自動実行/検証/holdout_eval.pl 馬情報/過去レースデータ/全期間 [見つけた期間の始まり 2026-04-01] [q 0.10] [補正ごとの一覧の出力.tsv]
#  - 各馬の過去走は JRA詳細.jsonl(2016年〜、馬IDで並べる)から作り、単勝オッズは レース.jsonl(競馬ラボ)を馬番で合わせる
#  - 補正ごとに「該当した馬の勝ち数 ÷ 市場の勝率(1/オッズを足して1に直したもの)の合計」= 市場比。1より大きければオッズより来る
#  - z = (勝ち数 − 市場の合計) ÷ √Σp(1−p)。補正の向き(+ なら来る、− なら来ない)の片側 p 値に直し、
#    確かめる期間(2017年〜見つけた期間の前)の全補正で Benjamini-Hochberg(誤発見率 q)をかける
#  - race_json.pl の条件を、この データにある項目で近づけたもの。違い: ペース(H/S)はハロンタイムの前後3Fの差で決める、
#    着差は走破タイムの差、「この距離の成績」は JRAの過去走だけ(地方は無い)、Ω指数・騎手のコース連対率・調教師×騎手は作れないので見ない
use strict; use warnings; use utf8; use JSON::PP; use Encode qw(encode);
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';
sub fn { encode('UTF-8', $_[0]) }   # 日本語のファイル名はバイト列で開く
my ($DIR, $FIND, $Q, $OUT) = @ARGV; $FIND //= '2026-04-01'; $Q //= 0.10;
die "使い方: perl holdout_eval.pl <全期間のフォルダー> [2026-04-01] [0.10] [出力.tsv]\n" unless $DIR && -d $DIR;
my $START = '2017-01-01';   # 2016年は JRA詳細 が年の途中からで、過去走がそろわない
my %PLACE = ('01' => '札幌', '02' => '函館', '03' => '福島', '04' => '新潟', '05' => '東京', '06' => '中山', '07' => '中京', '08' => '京都', '09' => '阪神', '10' => '小倉');
my %DIRS = (札幌 => '右', 函館 => '右', 福島 => '右', 新潟 => '左', 東京 => '左', 中山 => '右', 中京 => '左', 京都 => '右', 阪神 => '右', 小倉 => '右');
sub tsec { my $t = shift // ''; return $1 * 60 + $2 if $t =~ /^(\d+):(\d+(?:\.\d+)?)$/; return $1 + 0 if $t =~ /^(\d+(?:\.\d+)?)$/; undef }
sub days { my ($y, $m, $d) = split /-/, shift; my $a = int((14 - $m) / 12); my $yy = $y + 4800 - $a; my $mm = $m + 12 * $a - 3; $d + int((153 * $mm + 2) / 5) + 365 * $yy + int($yy / 4) - int($yy / 100) + int($yy / 400) }

# 1. 読み込み
my (%odds, %lab, @races);
for my $yd (sort glob("$DIR/*")) {
  next unless -d $yd && $yd =~ /\/(\d{4})$/;
  if (open my $f, '<', "$yd/" . fn('レース.jsonl')) { while (<$f>) { my $r = eval { decode_json($_) } or next; $lab{$r->{id}} = { cls => $r->{cls} // '', cond => $r->{cond} // '', grade => $r->{grade} // '' };
    $odds{$r->{id}}{$_->{umaban}} = $_->{odds} for grep { $_->{umaban} && $_->{odds} } @{$r->{horses} || []} } }
  if (open my $f, '<', "$yd/" . fn('JRA詳細.jsonl')) { while (<$f>) { my $r = eval { decode_json($_) } or next; push @races, $r } }
}
@races = sort { $a->{date} cmp $b->{date} || $a->{id} cmp $b->{id} } @races;
my %seen; @races = grep { !$seen{$_->{id}}++ } @races;
print STDERR scalar(@races), " レース\n";
# 父・母父(馬ID → [父, 母の父])。JRA-VAN で補った全部入りの馬DB(PCだけ)があればそれ、無ければ 馬情報/馬DB(2026-10-29〜)
my %PED; my $HJ = $DIR; utf8::decode($HJ); $HJ =~ s{[\\/]過去レースデータ[\\/]全期間[\\/]?$}{};
for my $db ("$HJ/JRA-VAN/馬DB", "$HJ/馬DB") { my @f = glob(fn("$db/競走馬/") . '*.tsv') or next;
  for my $p (@f) { open my $t, '<:utf8', $p or next; my $hd = <$t>; chomp $hd; my %i; my @c = split /\t/, $hd; @i{@c} = 0 .. $#c;
    while (<$t>) { chomp; my @x = split /\t/; $PED{$x[0]} = [$x[$i{'父'}] // '', $x[$i{'母の父'}] // ''] } }
  print STDERR "父・母父: $db(", scalar(keys %PED), " 頭)\n"; last }
# race_json.pl と同じ種牡馬の表(道悪の得意・苦手、国別タイプ)
my %SIRE_WET = ('芝' => { map({ $_ => 1 } qw(キズナ モーリス イスラボニータ ファインニードル シスキン)), map({ $_ => -1 } qw(キタサンブラック レイデオロ スワーヴリチャード コントレイル)) },
  'ダ' => { 'ナダル' => 1, 'パイロ' => 1, 'サンダースノー' => -1 });
my %STYPE; if (open my $t, '<:utf8', fn("$HJ/種牡馬_国別タイプ.tsv")) { <$t>; while (<$t>) { chomp; s/\r$//; my ($s, $ty, $sub, $cf) = split /\t/; $STYPE{$s} = $ty if $s && $ty && $ty ne '?' && ($cf // '') ne '?' } }

# 2. レースごとの共通の値(場・ペース・頭数・勝ち時計)と、各馬の1走ぶんの記録
my %hist;   # 馬ID → [ 過去走(古い順) ]
for my $r (@races) {
  my $R = $r->{race} || {}; my $place = $PLACE{substr($r->{id}, 8, 2)} // '';
  my $surf = $R->{surface} // ''; $surf = 'ダ' if $surf =~ /^ダ/; $surf = '障' if ($R->{course} // '') =~ /障|→/ || $surf =~ /障/;
  my @L = @{$r->{laps} || []}; my $pace = '';
  if (@L >= 6 && defined $r->{last3f}) { my $f3 = $L[0] + $L[1] + $L[2]; my $d = $f3 - $r->{last3f}; $pace = $d <= -1.0 ? 'H' : $d >= 1.0 ? 'S' : 'M' }
  my @H = grep { $_->{rank} && $_->{rank} =~ /^\d+$/ } @{$r->{horses} || []};
  my ($wt) = map { tsec($_->{time}) } grep { $_->{rank} == 1 } @H; my ($t2) = sort { $a <=> $b } grep { defined } map { tsec($_->{time}) } grep { $_->{rank} == 2 } @H;
  $r->{_place} = $place; $r->{_surf} = $surf; $r->{_pace} = $pace; $r->{_n} = scalar @{$r->{horses} || []};
  $r->{_straight} = ($R->{course} // '') =~ /直/ ? 1 : 0;
  for my $h (@{$r->{horses} || []}) {
    my ($first, $last) = ($h->{pass} // '') =~ /^(\d+)(?:-.*?(\d+))?$/; $last //= $h->{last4} // $first;
    my $t = tsec($h->{time}); my $mg;
    if ($h->{rank} && $h->{rank} =~ /^\d+$/) { if ($h->{rank} == 1) { $mg = defined $t2 && defined $wt ? $t2 - $wt : undef } elsif (defined $t && defined $wt) { $mg = $t - $wt } }
    $h->{_rec} = { date => $r->{date}, place => $place, surf => $surf, dist => $R->{dist} // 0, going => $R->{going} // '', rank => (($h->{rank} // '') =~ /^\d+$/ ? $h->{rank} + 0 : undef),
      heads => $r->{_n}, umaban => $h->{umaban}, first => $first, last => $last, margin => (defined $mg ? int($mg * 10 + 0.5) / 10 : undef), pace => $pace, pop => $h->{pop},
      straight => $r->{_straight}, race => $lab{$r->{id}}{cls} // $R->{cls} // '' };
  }
}

# 3. 補正の一覧(名前, 向き, 判定)。判定は (今回のレース, この馬, 前走たち(新しい順), 共通の値) を受け取り真偽を返す
my %steep = map { $_ => 1 } qw(中山 阪神 中京); my %flat = map { $_ => 1 } qw(京都 新潟 小倉 函館 札幌 福島);
my %big = map { $_ => 1 } qw(東京 阪神 京都 新潟); my %small = map { $_ => 1 } qw(中山 中京 福島 小倉 函館 札幌);
my $lapt = sub { my ($pl, $s, $d) = @_; return '' if ($s // '') ne '芝' || !$d || $d < 1600;
  return 'S' if $pl eq '東京' || ($pl eq '新潟' && ($d == 1600 || $d == 1800)) || ($pl eq '阪神' && $d =~ /^(1600|1800|2400|2600)$/);
  return 'J' if $pl =~ /^(函館|福島|小倉|札幌|中山)$/ || ($pl eq '阪神' && $d =~ /^(2000|2200|3000)$/); return '' };
my %longer = ('中山芝1800' => 2000, '中京芝2000' => 2200, '中京ダ1800' => 1900, '京都ダ1800' => 1900, '阪神ダ1800' => 2000, '阪神芝2000' => 2200);
my @F = (
  # [名前, 向き, 出典, 判定]
  ['前走1着・0.5秒以上の完勝', 2, '着差', sub { my ($c, $h, $z) = @_; $z->[0]{rank} == 1 && ($z->[0]{margin} // 0) >= 0.5 }],
  ['前走4着以下・0.3秒差以内', 4, '着差', sub { my ($c, $h, $z) = @_; $z->[0]{rank} >= 4 && defined $z->[0]{margin} && $z->[0]{margin} <= 0.3 }],
  ['前走4着以下・0.4〜0.5秒差', 2, '着差', sub { my ($c, $h, $z) = @_; $z->[0]{rank} >= 4 && defined $z->[0]{margin} && $z->[0]{margin} > 0.3 && $z->[0]{margin} <= 0.5 }],
  ['前走6〜9着・0.6〜1.0秒差', 1, '先読み競馬', sub { my ($c, $h, $z) = @_; $z->[0]{rank} >= 6 && $z->[0]{rank} <= 9 && defined $z->[0]{margin} && $z->[0]{margin} >= 0.6 && $z->[0]{margin} <= 1.0 }],
  ['前走2・3着でも1.0秒以上離された', -4, '着差', sub { my ($c, $h, $z) = @_; $z->[0]{rank} >= 2 && $z->[0]{rank} <= 3 && ($z->[0]{margin} // 0) >= 1.0 }],
  ['前走2・3着でも0.6〜0.9秒離された', -2, '着差', sub { my ($c, $h, $z) = @_; $z->[0]{rank} >= 2 && $z->[0]{rank} <= 3 && ($z->[0]{margin} // 0) >= 0.6 && $z->[0]{margin} < 1.0 }],
  ['中20週以上の休み明け', -6, '間隔', sub { defined $_[3]{wk} && $_[3]{wk} >= 20 }],
  ['中1週', -1, 'バフェット', sub { defined $_[3]{wk} && $_[3]{wk} == 1 }],
  ['中3〜5週', 1, 'バフェット', sub { defined $_[3]{wk} && $_[3]{wk} >= 3 && $_[3]{wk} <= 5 }],
  ['前走逃げて好走', -2, '前走', sub { my ($c, $h, $z) = @_; ($z->[0]{first} // 0) == 1 && $z->[0]{rank} <= 3 }],
  ['前走2着', -2, 'コタ', sub { $_[2][0]{rank} == 2 }],
  ['前走1番人気で4着以下', -2, '飯野先生', sub { my $p = $_[2][0]; ($p->{pop} // 0) == 1 && $p->{rank} >= 4 }],
  ['(star.pl)今回1番人気・前走1番人気で4着以下', -1, '飯野先生', sub { my $p = $_[2][0]; ($_[1]{pop} // 0) == 1 && ($p->{pop} // 0) == 1 && $p->{rank} >= 4 }],
  ['(star.pl)今回1番人気・前走逃げて好走', -1, '前走', sub { my $p = $_[2][0]; ($_[1]{pop} // 0) == 1 && ($p->{first} // 0) == 1 && $p->{rank} <= 3 }],
  ['(star.pl)今回1番人気(全部・比べる基準)', -1, '基準', sub { ($_[1]{pop} // 0) == 1 }],
  ['(star.pl)今回1番人気・馬体重420kg未満', -1, '馬格', sub { ($_[1]{pop} // 0) == 1 && ($_[1]{bw} // 999) < 420 }],
  ['(star.pl)今回1番人気・芝の重・不良', -1, '道悪', sub { ($_[1]{pop} // 0) == 1 && $_[0]{surf} eq '芝' && $_[0]{going} =~ /^(重|不良)$/ }],
  ['(star.pl)今回1番人気・追込', -1, '脚質', sub { ($_[1]{pop} // 0) == 1 && $_[3]{style} eq '追込' }],
  ['(star.pl)今回1番人気・勝ち切れない騎手(幸・三浦・今村・横山典・丹内・西村淳)', -1, '騎手', sub { ($_[1]{pop} // 0) == 1 && $_[1]{jockey} =~ /^(幸|三浦|今村|横山典|丹内|西村淳)/ }],
  ['(star.pl)今回1番人気・ルメール騎手で道悪', -1, '騎手', sub { ($_[1]{pop} // 0) == 1 && $_[1]{jockey} =~ /ルメール/ && $_[0]{going} ne '良' }],
  ['(star.pl)今回1番人気・川田騎手で芝の道悪', -1, '騎手', sub { ($_[1]{pop} // 0) == 1 && $_[1]{jockey} =~ /^川田/ && $_[0]{surf} eq '芝' && $_[0]{going} ne '良' }],
  ['前走2・3番人気で4着以下', 2, '飯野先生',sub { my $p = $_[2][0]; ($p->{pop} // 0) >= 2 && ($p->{pop} // 0) <= 3 && $p->{rank} >= 4 }],
  ['前走道悪で好走・今回良', -3, '道悪', sub { my ($c, $h, $z) = @_; $c->{going} eq '良' && $z->[0]{going} =~ /^(重|不良?)$/ && $z->[0]{rank} <= 3 }],
  ['前走道悪で凡走・今回良', 2, '道悪', sub { my ($c, $h, $z) = @_; $c->{going} eq '良' && $z->[0]{going} =~ /^(重|不良?)$/ && $z->[0]{rank} >= 6 }],
  ['枠替わりで不利(芝:内→外・ダ:外→内)の前走好走', -3, '枠', sub { my ($c, $h, $z) = @_; my $w = $c->{waku_sw} or return 0; $w eq 'good' && $z->[0]{rank} <= 3 }],
  ['枠替わりで有利(芝:外→内・ダ:内→外)の前走凡走', 2, '枠', sub { my ($c, $h, $z) = @_; my $w = $c->{waku_sw} or return 0; $w eq 'bad' && $z->[0]{rank} >= 4 }],
  ['芝→ダートの外枠・ダートで先行好走歴', 2, 'コタ', sub { my ($c, $h, $z) = @_; $c->{surf} eq 'ダ' && $c->{n} >= 10 && $h->{umaban} > $c->{n} * 0.7 && $z->[0]{surf} eq '芝' && grep { $_->{surf} eq 'ダ' && ($_->{first} // 99) <= 4 && ($_->{rank} // 99) <= 3 } @$z }],
  ['東京・京都の場別の距離短縮', 2, '競馬場', sub { my ($c, $h, $z) = @_; my $pd = $z->[0]{dist};
      ($c->{place} eq '東京' && $c->{surf} eq '芝' && $c->{dist} == 1400 && $pd >= 1600) || ($c->{place} eq '東京' && $c->{surf} eq 'ダ' && $c->{dist} == 1600 && $pd >= 1700)
      || ($c->{place} eq '京都' && $c->{surf} eq '芝' && !$c->{straight} && (($c->{dist} == 1400 && $pd >= 1600) || ($c->{dist} == 2200 && $pd >= 2400))) }],
  ['東京芝1400・ダ1600の1200m以下からの延長', -2, '競馬場', sub { my ($c, $h, $z) = @_; $c->{place} eq '東京' && (($c->{surf} eq '芝' && $c->{dist} == 1400) || ($c->{surf} eq 'ダ' && $c->{dist} == 1600)) && $z->[0]{dist} && $z->[0]{dist} <= 1200 }],
  ['距離短縮で初めての1400m以下', 2, '丞相', sub { my ($c, $h, $z) = @_; return 0 unless $c->{dist} <= 1400 && $c->{surf} ne '障' && !$c->{dist_seen}; my @d = grep { $_ } map { $_->{dist} } @$z; @d >= 2 && !grep { $_ < $c->{dist} + 200 } @d }],
  ['休み明け(中10〜19週)で400m以上の短縮', 2, 'ウマザワ', sub { my ($c, $h, $z, $v) = @_; defined $v->{wk} && $v->{wk} >= 10 && $v->{wk} <= 19 && $z->[0]{dist} && $z->[0]{dist} - $c->{dist} >= 400 }],
  ['小回り4場のダ1700・前走ダ1400', 2, '丞相', sub { my ($c, $h, $z) = @_; $c->{surf} eq 'ダ' && $c->{dist} == 1700 && $c->{place} =~ /^(函館|札幌|福島|小倉)$/ && $z->[0]{surf} eq 'ダ' && $z->[0]{dist} == 1400 }],
  ['初めての芝・ダート(3歳未勝利6月以降・1勝クラス)', 2, '丞相', sub { my ($c, $h, $z) = @_; $c->{surf} =~ /^(芝|ダ)$/ && !grep({ $_->{surf} eq $c->{surf} } @$z) && (($c->{cls} =~ /3歳未勝利/ && $c->{mo} >= 6) || $c->{cls} =~ /1勝/) }],
  ['初めての芝・ダート(2勝クラス以上)', -1, '丞相', sub { my ($c, $h, $z) = @_; $c->{surf} =~ /^(芝|ダ)$/ && !grep({ $_->{surf} eq $c->{surf} } @$z) && $c->{cls} =~ /[23]勝|オープン/ }],
  ['前走阪神で先行して失速・今回京都', 2, '競馬場', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $c->{place} eq '京都' && $p->{place} eq '阪神' && ($p->{first} // 99) <= 3 && $p->{rank} >= 4 && $p->{rank} <= 9 && $p->{surf} eq $c->{surf} }],
  ['平坦で好走・今回急坂', -2, '競馬場', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} ne $c->{place} && $p->{surf} eq $c->{surf} && $p->{rank} <= 3 && $flat{$p->{place}} && $steep{$c->{place}} }],
  ['急坂で凡走・今回平坦', 1, '競馬場', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} ne $c->{place} && $p->{surf} eq $c->{surf} && $p->{rank} >= 4 && $p->{rank} <= 9 && $steep{$p->{place}} && $flat{$c->{place}} }],
  ['小回りで好走・今回大箱', -1, '競馬場', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} ne $c->{place} && $p->{surf} eq $c->{surf} && $p->{rank} <= 3 && $small{$p->{place}} && $big{$c->{place}} }],
  ['東京で好走・今回中山', -2, 'コタ', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} eq '東京' && $c->{place} eq '中山' && $p->{surf} eq $c->{surf} && $p->{rank} <= 3 }],
  ['東京ダで6着以下・今回中山ダ', 1, 'コタ', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} eq '東京' && $c->{place} eq '中山' && $p->{surf} eq 'ダ' && $c->{surf} eq 'ダ' && $p->{rank} >= 6 }],
  ['前走ハイペースを先行して4〜10着(2勝クラス以上)', 2, 'コタ', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{pace} eq 'H' && $c->{cls} =~ /[23]勝|オープン/ && $p->{surf} eq $c->{surf} && ($p->{first} // 99) <= 3 && ($p->{last} // 99) <= 3 && $p->{rank} >= 4 && $p->{rank} <= 10 }],
  ['前走は展開に逆らって勝った', -2, 'あおき', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{rank} == 1 && $p->{surf} eq $c->{surf} && $p->{first} && $p->{pace} =~ /^[HS]$/ && (($p->{first} <= 3) == ($p->{pace} eq 'H')) }],
  ['前走は展開が向いて勝った', 1, 'あおき', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{rank} == 1 && $p->{surf} eq $c->{surf} && $p->{first} && $p->{pace} =~ /^[HS]$/ && (($p->{first} <= 3) != ($p->{pace} eq 'H')) }],
  ['専用機の巻き返し', 2, 'カチウマ博士', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; return 0 if $p->{rank} < 4 || ($p->{place} eq $c->{place} && $p->{surf} eq $c->{surf} && $p->{dist} == $c->{dist});
      (grep { $_->{place} eq $c->{place} && $_->{surf} eq $c->{surf} && $_->{dist} == $c->{dist} && ($_->{rank} // 99) <= 3 } @$z) >= 2 }],
  ['ラップの型が苦手な方', -2, '丞相', sub { my ($c, $h, $z) = @_; return 0 if $c->{straight}; my $ct = $lapt->($c->{place}, $c->{surf}, $c->{dist}) or return 0; my $ot = $ct eq 'S' ? 'J' : 'S'; my ($gO, $gT, $bT) = (0, 0, 0);
      for my $q (@$z) { my $t = $lapt->($q->{place}, $q->{surf}, $q->{dist}) or next; my $qr = $q->{rank} or next; if ($t eq $ot && $qr <= 3) { $gO++ } elsif ($t eq $ct && $qr <= 3) { $gT++ } elsif ($t eq $ct && $qr >= 6) { $bT++ } }
      $gO && $bT && !$gT }],
  ['同じ場の1角まで長い距離で差し', 2, 'コース', sub { my ($c, $h, $z) = @_; my $p = $z->[0]; $p->{place} eq $c->{place} && $p->{surf} eq $c->{surf} && $p->{last} && $p->{heads} && $p->{last} / $p->{heads} > 0.35 && $p->{rank} >= 2 && $p->{rank} <= 6 && ($longer{"$p->{place}$p->{surf}$p->{dist}"} // 0) == $c->{dist} }],
  ['ダートの砂かぶりに強い差し(3勝以上)', 2, 'ダートの見方', sub { $_[3]{sand} eq 'tough' }],
  ['ダートの砂かぶりで凡走・今回も内枠の差し', -2, 'ダートの見方', sub { $_[3]{sand} eq 'weak' }],
  ['減量3kg以上・ダ1500以上(小回り4場)', 4, '義英真', sub { $_[3]{genryo} && $_[0]{place} =~ /^(函館|札幌|福島|小倉)$/ }],
  ['減量3kg以上・ダ1500以上(ほかの場)', 1, '義英真', sub { $_[3]{genryo} && $_[0]{place} !~ /^(函館|札幌|福島|小倉)$/ }],
  ['牡馬混合の芝2400m以上の牝馬', -2, 'スポナビ競馬', sub { my ($c, $h) = @_; $c->{surf} eq '芝' && $c->{dist} >= 2400 && $c->{cond} !~ /牝/ && ($h->{sexAge} // '') =~ /^牝/ }],
  ['前走逃げて好走・ほかにも逃げ馬', -2, '前走', sub { $_[3]{prevLead} && $_[0]{leaders} >= 2 }],
  ['距離延長・前に行く馬が少ない', 1, 'コタ', sub { defined $_[0]{fr} && $_[3]{extend} && $_[0]{fr} < 0.3 }],
  ['距離延長・前に行く馬が多い', -2, 'コタ', sub { defined $_[0]{fr} && $_[3]{extend} && $_[0]{fr} >= 0.4 }],
  ['馬体重-20kg以上', -4, '馬体重', sub { defined $_[1]{bwDiff} && $_[1]{bwDiff} <= -20 }],
  ['2〜3歳で馬体重-10〜-19kg', -2, '馬体重', sub { my $h = $_[1]; defined $h->{bwDiff} && $h->{bwDiff} <= -10 && $h->{bwDiff} > -20 && ($h->{sexAge} // '') =~ /[23]$/ }],
  ['6歳以上で馬体重+10kg以上', -2, '馬体重', sub { my $h = $_[1]; my ($a) = ($h->{sexAge} // '') =~ /(\d+)$/; defined $h->{bwDiff} && $h->{bwDiff} >= 10 && ($a // 0) >= 6 }],
  ['馬体重420kg未満', -2, '馬格', sub { my ($c, $h) = @_; ($h->{bw} // 999) < 420 && !($c->{surf} eq '芝' && $c->{dist} >= 2200) }],
  ['馬体重500kg以上(芝2200m未満)', 1, '馬格', sub { my ($c, $h) = @_; ($h->{bw} // 0) >= 500 && !($c->{surf} eq '芝' && $c->{dist} >= 2200) }],
  ['2歳牝馬の芝で460kg以上', 2, '先読み競馬', sub { my ($c, $h) = @_; $c->{surf} eq '芝' && ($h->{sexAge} // '') =~ /^牝2$/ && ($h->{bw} // 0) >= 460 }],
  ['ルメール騎手の道悪', -2, '騎手', sub { $_[1]{jockey} =~ /ルメール/ && $_[0]{going} ne '良' }],
  ['川田騎手の芝の道悪', -2, '騎手', sub { $_[1]{jockey} =~ /^川田/ && $_[0]{surf} eq '芝' && $_[0]{going} ne '良' }],
  ['戸崎騎手のダートの外枠', 2, '騎手', sub { $_[1]{jockey} =~ /^戸崎/ && $_[0]{surf} eq 'ダ' && $_[3]{outer} }],
  ['坂井騎手の差し馬', -1, '騎手', sub { $_[1]{jockey} =~ /^坂井/ && $_[3]{style} eq '差し' }],
  ['坂井騎手の500kg以上', 1, '騎手', sub { $_[1]{jockey} =~ /^坂井/ && ($_[1]{bw} // 0) >= 500 }],
  ['松山騎手の外枠の差し・追込', -1, '騎手', sub { $_[1]{jockey} =~ /^松山/ && $_[3]{outer} && $_[3]{style} =~ /差し|追込/ }],
  # 季節(YouTube「競馬予想で始めるデータ分析」。2026-10-27 に2017〜2026/3で確かめて入れた。検証.md の19)
  [q(冬(12〜2月)の牝馬・牝馬限定戦以外), -2, q(データ分析), sub { my ($c, $h) = @_; ($c->{mo} == 12 || $c->{mo} <= 2) && $c->{cond} !~ /牝/ && ($h->{sexAge} // q()) =~ /^牝/ }],
  [q(夏(6〜8月)の牝馬・牝馬限定戦以外), 1, q(データ分析), sub { my ($c, $h) = @_; ($c->{mo} >= 6 && $c->{mo} <= 8) && $c->{cond} !~ /牝/ && ($h->{sexAge} // q()) =~ /^牝/ }],
  [q(1年前の同じ時期に3着以内・近5走は4着以下), 2, q(データ分析), sub { $_[3]{season} && !grep { ($_->{rank} // 99) <= 3 } @{$_[2]} }],
  # CiNii の論文(徳田 2020「日本競馬における前走2着のバイアス」中央大学。芝の古馬戦 2000〜2019年で、前走2着の0.0〜0.1秒差は単回収78%・0.8〜0.9秒差は155%)。2026-10-27 結果を見る前に決めた
  [q(前走2着・0.1秒差以内), -2, q(論文), sub { my $p = $_[2][0]; $p->{rank} == 2 && defined $p->{margin} && $p->{margin} <= 0.1 }],
  [q(前走2着・0.1秒差以内(芝の古馬戦)), -2, q(論文), sub { my ($c, $h, $z) = @_; $c->{surf} eq q(芝) && $c->{cond} =~ /歳上/ && $z->[0]{rank} == 2 && defined $z->[0]{margin} && $z->[0]{margin} <= 0.1 }],
  [q(前走2着・0.6〜1.0秒差(芝の古馬戦)), 2, q(論文), sub { my ($c, $h, $z) = @_; $c->{surf} eq q(芝) && $c->{cond} =~ /歳上/ && $z->[0]{rank} == 2 && defined $z->[0]{margin} && $z->[0]{margin} >= 0.6 && $z->[0]{margin} <= 1.0 }],
  # 血統と騎手の癖(race_json.pl にあるが、父が無くて確かめていなかったもの。2026-10-29 JRA-VAN の馬DBで父がそろった。検証.md の24)
  [q(父が道悪得意・道悪の経験2戦以下・今回道悪), 1, q(血統), sub { my ($c, $h, $z, $v) = @_; $c->{going} =~ /稍|重|不/ && $v->{wruns} <= 2 && ($SIRE_WET{$c->{surf}}{$v->{sire}} // 0) > 0 }],
  [q(父が道悪苦手・道悪の経験2戦以下・今回道悪), -1, q(血統), sub { my ($c, $h, $z, $v) = @_; $c->{going} =~ /稍|重|不/ && $v->{wruns} <= 2 && ($SIRE_WET{$c->{surf}}{$v->{sire}} // 0) < 0 }],
  [q(父が米国型・2〜3歳の未勝利・1勝のダ1400以下), 2, q(血統), sub { my ($c, $h, $z, $v) = @_; ($STYPE{$v->{sire}} // '') eq '米国' && $c->{surf} eq 'ダ' && $c->{dist} <= 1400 && $c->{cls} =~ /^[23]歳(?:未勝利|1勝)/ }],
  [q(父か母父が欧州型・古馬の芝2200以上の道悪・経験2戦以下), 1, q(血統), sub { my ($c, $h, $z, $v) = @_; $c->{surf} eq '芝' && $c->{dist} >= 2200 && $c->{cond} =~ /歳上/ && $c->{going} =~ /稍|重|不/
      && $v->{wruns} <= 2 && !($SIRE_WET{'芝'}{$v->{sire}} // 0) && grep { ($STYPE{$_} // '') eq '欧州' } $v->{sire}, $v->{dsire} }],
  [q(西村淳騎手×ロードカナロア産駒), 2, q(騎手), sub { $_[1]{jockey} =~ /^西村淳/ && $_[3]{sire} eq 'ロードカナロア' }],
  [q(追込が苦手な騎手(西村淳・丹内・ルメール・坂井・松山・幸)の追込), -2, q(騎手), sub { $_[3]{style} eq '追込' && $_[1]{jockey} =~ /^(?:[A-Z]\.)?(西村淳|丹内|ルメール|坂井|松山|幸)/ }],
  [q(今村騎手の牝馬), 2, q(騎手), sub { $_[1]{jockey} =~ /^今村/ && ($_[1]{sexAge} // '') =~ /^牝/ }],
  [q(北村友騎手の牝馬), -2, q(騎手), sub { $_[1]{jockey} =~ /^北村友/ && ($_[1]{sexAge} // '') =~ /^牝/ }],
  [q(戸崎騎手の内枠の差し・追込), -1, q(騎手), sub { $_[1]{jockey} =~ /^戸崎/ && $_[3]{inner} && $_[3]{style} !~ /逃げ|先行/ }],
);
# 新馬は過去走が無いので「新馬で馬体重」は別に見る
my @NF = (
  ['新馬ダートで500kg以上', 3, '新馬', sub { $_[0]{surf} eq 'ダ' && ($_[1]{bw} // 0) >= 500 }],
  ['新馬ダートで460kg未満', -3, '新馬', sub { $_[0]{surf} eq 'ダ' && ($_[1]{bw} // 999) < 460 }],
  ['新馬芝で460kg未満', -2, '新馬', sub { $_[0]{surf} eq '芝' && ($_[1]{bw} // 999) < 460 }],
  [q(父が米国型・新馬のダ1400以下), 2, q(血統), sub { ($STYPE{$_[3]{sire}} // '') eq '米国' && $_[0]{surf} eq 'ダ' && $_[0]{dist} <= 1400 }],
);

# 4. 時系列に回す(各馬の過去走は、そのレースより前のものだけ)
my %S;   # 名前 → 期間 → [頭数, 勝ち, 市場, 分散, 単勝の払戻]
my @PER = ('前半 2017-2020', '後半 2021-' . substr($FIND, 0, 7), '見つけた期間');
my $per = sub { my $d = shift; $d lt $START ? undef : $d lt '2021-01-01' ? 0 : $d lt $FIND ? 1 : 2 };
my $nr = 0;
for my $r (@races) {
  my $pi = $per->($r->{date}); my @hs = @{$r->{horses} || []};
  my $L = $lab{$r->{id}} || {}; my $ok = defined $pi && $r->{_surf} ne '障' && ($L->{grade} // '') eq '' && $odds{$r->{id}};
  if ($ok) {
    my $R = $r->{race}; my $n = $r->{_n}; my ($mo) = $r->{date} =~ /^\d+-(\d+)/;
    my $c = { place => $r->{_place}, surf => $r->{_surf}, dist => $R->{dist} // 0, going => $R->{going} // '', n => $n, mo => $mo + 0, straight => $r->{_straight},
      cls => $L->{cls} // '', cond => $L->{cond} // '', kin => $R->{kinType} // '' };
    my $od = $odds{$r->{id}}; my $si = 0; $si += 1 / $_ for grep { $_ } map { $od->{$_->{umaban} // 0} } @hs;
    my @rows;
    for my $h (@hs) {
      my $o = $od->{$h->{umaban} // 0} or next; next unless $si;
      my $z = [reverse @{$hist{$h->{horseId} // ''} || []}]; $z = [@{$z}[0 .. 4]] if @$z > 5; $z = [grep { defined } @$z];
      my $win = (($h->{rank} // '') =~ /^\d+$/ && $h->{rank} == 1) ? 1 : 0;
      my $dn = days($r->{date}); my $sea = grep { my $g = $dn - days($_->{date}); $g >= 320 && $g <= 410 && ($_->{rank} // 99) <= 3 } @{$hist{$h->{horseId} // q()} || []};
      my $wr = grep { $_->{surf} eq $r->{_surf} && $_->{going} =~ /稍|重|不/ } @{$hist{$h->{horseId} // q()} || []};
      push @rows, { h => $h, z => $z, sea => $sea, wr => $wr, p => (1 / $o) / $si, win => $win, odds => $o };
    }
    # レース全体で要る値: 逃げ馬の数・前走1角3番手以内の割合・減量
    my %v;
    for my $x (@rows) {
      my ($h, $z) = ($x->{h}, $x->{z}); my %w;
      my @ra = map { $_->{last} / $_->{heads} } grep { $_->{last} && $_->{heads} } @$z;
      if (@ra) { my $m = 0; $m += $_ for @ra; $m /= @ra; $w{style} = $m <= 0.12 ? '逃げ' : $m <= 0.35 ? '先行' : $m <= 0.7 ? '差し' : '追込' } else { $w{style} = '差し' }
      $w{outer} = $h->{umaban} && $n >= 10 && $h->{umaban} > $n * 0.7; $w{inner} = $h->{umaban} && $n >= 10 && $h->{umaban} <= $n * 0.3;
      if (@$z) { my $gap = days($r->{date}) - days($z->[0]{date}); $w{wk} = int($gap / 7 + 0.5) - 1;
        $w{prevLead} = ($z->[0]{first} // 0) == 1 && ($z->[0]{rank} // 99) <= 3; $w{extend} = $z->[0]{dist} && $c->{dist} - $z->[0]{dist} >= 200;
        $w{prevFront} = $z->[0]{first} ? ($z->[0]{first} <= 3 ? 1 : 0) : undef; }
      # 砂かぶり
      $w{sand} = '';
      if ($c->{surf} eq 'ダ' && $w{style} =~ /差し|追込/ && @$z) { my ($t, $wk) = (0, 0);
        for my $p (@$z) { next unless $p->{surf} eq 'ダ' && $p->{umaban} && $p->{heads} && $p->{last} && $p->{rank}; next unless $p->{umaban} <= $p->{heads} * 0.4 && $p->{last} > $p->{heads} * 0.3;
          if ($p->{rank} <= 3 || ($p->{margin} // 9) <= 0.3) { $t++ } elsif ($p->{rank} >= 6 && ($p->{margin} // 0) >= 0.6) { $wk++ } }
        $w{sand} = ($t && $c->{cls} =~ /3勝|オープン/) ? 'tough' : (!$t && $wk && $w{inner}) ? 'weak' : '' }
      $w{season} = $x->{sea}; $w{wruns} = $x->{wr}; @w{qw(sire dsire)} = @{$PED{$h->{horseId} // ''} || ['', '']}; $x->{v} = \%w;
    }
    $c->{leaders} = grep { $_->{v}{style} eq '逃げ' } @rows;
    my @pf = grep { defined $_->{v}{prevFront} } @rows; $c->{fr} = (@pf >= @rows * 0.7 && @rows >= 8) ? (grep { $_->{v}{prevFront} } @pf) / @pf : undef;
    if ($c->{surf} eq 'ダ' && $c->{dist} >= 1500 && $c->{kin} =~ /定量|馬齢/) {
      my %mx; for my $x (@rows) { my ($s, $a) = ($x->{h}{sexAge} // '') =~ /^(\D+)(\d+)/ or next; my $k = $x->{h}{kin} // next; $mx{"$s$a"} = $k if !defined $mx{"$s$a"} || $k > $mx{"$s$a"} }
      for my $x (@rows) { my ($s, $a) = ($x->{h}{sexAge} // '') =~ /^(\D+)(\d+)/ or next; my $k = $x->{h}{kin} // next; $x->{v}{genryo} = $mx{"$s$a"} - $k >= 3 }
    }
    for my $x (@rows) {
      my ($h, $z, $v) = ($x->{h}, $x->{z}, $x->{v});
      # 枠の替わり(前走と同じ芝ダ・千直を除く)
      $c->{waku_sw} = '';
      if (@$z && $z->[0]{umaban} && $z->[0]{heads} && $z->[0]{surf} eq $c->{surf} && !$z->[0]{straight} && !$c->{straight} && $h->{umaban}) {
        my $p = $z->[0]; my ($pin, $pout) = ($p->{umaban} <= $p->{heads} * 0.3, $p->{umaban} > $p->{heads} * 0.7); my ($nin, $nout) = ($h->{umaban} <= $n * 0.3, $h->{umaban} > $n * 0.7);
        my ($gf, $gt) = $c->{surf} eq '芝' ? ($pin, $nout) : ($pout, $nin); my ($bf, $bt) = $c->{surf} eq '芝' ? ($pout, $nin) : ($pin, $nout);
        $c->{waku_sw} = ($gf && $gt) ? 'good' : ($bf && $bt) ? 'bad' : '' }
      $c->{dist_seen} = grep { $_->{dist} == $c->{dist} && $_->{surf} eq $c->{surf} } @$z;
      my $list = $c->{cls} =~ /新馬/ ? \@NF : (@$z && $z->[0]{rank}) ? \@F : [grep { $_->[2] =~ /馬体重|馬格|騎手|義英真|スポナビ|先読み|血統/ && $_->[0] !~ /前走/ } @F];
      for my $f (@$list) {
        next unless eval { $f->[3]->($c, $h, $z, $v) };
        my $s = $S{$f->[0]}[$pi] //= [0, 0, 0, 0, 0, 0, 0];
        $s->[0]++; $s->[1] += $x->{win}; $s->[2] += $x->{p}; $s->[3] += $x->{p} * (1 - $x->{p}); $s->[4] += $x->{win} * $x->{odds};
        # ★(star.pl)は3着以内率の話なので、単勝オッズのHarville式の3着以内率とも比べる
        if ($f->[0] =~ /^\(star/) { my @q = map { $_->{p} } @rows; my $pi0 = $x->{p}; my $p3 = $pi0;
          for my $j (0 .. $#q) { next if $rows[$j] == $x; my $a = $q[$j] * $pi0 / (1 - $q[$j]); $p3 += $a;
            for my $k (0 .. $#q) { next if $k == $j || $rows[$k] == $x; $p3 += $q[$j] * $q[$k] / (1 - $q[$j]) * $pi0 / (1 - $q[$j] - $q[$k]) } }
          $s->[5] += (($x->{h}{rank} // '') =~ /^\d+$/ && $x->{h}{rank} <= 3) ? 1 : 0; $s->[6] += $p3 }
      }
      my $s = $S{'(全体)'}[$pi] //= [0, 0, 0, 0, 0]; $s->[0]++; $s->[1] += $x->{win}; $s->[2] += $x->{p}; $s->[3] += $x->{p} * (1 - $x->{p}); $s->[4] += $x->{win} * $x->{odds};
    }
    $nr++;
  }
  push @{$hist{$_->{horseId}}}, $_->{_rec} for grep { $_->{horseId} } @hs;
}
print STDERR "$nr レースを集計\n";

# 5. 結果: 確かめる期間(前半+後半)で片側 p 値 → Benjamini-Hochberg
sub erf { my $x = shift; my $t = 1 / (1 + 0.3275911 * abs($x)); my $y = 1 - ((((1.061405429 * $t - 1.453152027) * $t + 1.421413741) * $t - 0.284496736) * $t + 0.254829592) * $t * exp(-$x * $x); $x >= 0 ? $y : -$y }
sub pnorm { 0.5 * (1 + erf($_[0] / sqrt 2)) }
my @res;
for my $f (@F, @NF) {
  my ($nm, $dir, $src) = @$f; my @s = map { $S{$nm}[$_] // [0, 0, 0, 0, 0] } 0 .. 2;
  my @h = map { $s[0][$_] + $s[1][$_] } 0 .. 4;
  my $z = $h[3] > 0 ? ($h[1] - $h[2]) / sqrt($h[3]) : 0; my $pv = $dir > 0 ? 1 - pnorm($z) : pnorm($z);
  push @res, { nm => $nm, dir => $dir, src => $src, s => \@s, h => \@h, z => $z, p => $pv };
}
my @ord = sort { $a->{p} <=> $b->{p} } @res; my $m = @ord; my $L = 0;
for my $j (1 .. $m) { $L = $j if $ord[$j - 1]{p} <= $Q * $j / $m }
$ord[$_ - 1]{bh} = $_ <= $L ? 1 : 0 for 1 .. $m;
my $rt = sub { my $s = shift; $s->[2] > 0 ? sprintf('%.2f', $s->[1] / $s->[2]) : '-' };
my $roi = sub { my $s = shift; $s->[0] ? sprintf('%.0f%%', 100 * $s->[4] / $s->[0]) : '-' };
my $all = $S{'(全体)'};
printf "全体: 確かめる期間 %d 頭(市場比 %s・単回収 %s) / 見つけた期間 %d 頭(%s・%s)\n\n", $all->[0][0] + $all->[1][0], $rt->([map { $all->[0][$_] + $all->[1][$_] } 0 .. 4]), $roi->([map { $all->[0][$_] + $all->[1][$_] } 0 .. 4]), $all->[2][0], $rt->($all->[2]), $roi->($all->[2]);
print join("\t", '判定', '補正', '点', '出典', '確かめる期間の頭数', '市場比', 'z', '片側p', $PER[0], $PER[1], $PER[2] . '(頭数・市場比)', '単回収(確かめる期間)'), "\n";
my @lines;
for my $x (sort { ($b->{bh} <=> $a->{bh}) || ($a->{p} <=> $b->{p}) } @res) {
  my $same = $x->{dir} > 0 ? 1 : -1; my $ok0 = ($x->{s}[0][2] && ($x->{s}[0][1] / $x->{s}[0][2] - 1) * $same > 0); my $ok1 = ($x->{s}[1][2] && ($x->{s}[1][1] / $x->{s}[1][2] - 1) * $same > 0);
  my $j = $x->{bh} && $ok0 && $ok1 ? '再現' : ($x->{z} * $same <= -2) ? '逆' : $x->{bh} ? '再現(期間でぶれる)' : '再現せず';
  my $nm = $x->{nm}; if ($nm =~ /^\(star/) { my $t5 = 0; my $t6 = 0; $t5 += $x->{s}[$_][5] // 0 for 0, 1; $t6 += $x->{s}[$_][6] // 0 for 0, 1; $nm .= sprintf(' [3着以内 %.1f%%・Harville %.1f%%・%.2f倍]', 100 * $t5 / ($x->{h}[0] || 1), 100 * $t6 / ($x->{h}[0] || 1), $t6 ? $t5 / $t6 : 0) }
  my $l = join("\t", $j, $nm, ($x->{dir} > 0 ? '+' : '') . $x->{dir}, $x->{src}, $x->{h}[0], $rt->($x->{h}), sprintf('%+.1f', $x->{z}), sprintf('%.3f', $x->{p}),
    map({ "$x->{s}[$_][0]・" . $rt->($x->{s}[$_]) } 0 .. 2), $roi->($x->{h}));
  print "$l\n"; push @lines, $l;
}
printf "\n%d 個の補正で、誤発見率 q=%.2f の Benjamini-Hochberg を通ったのは %d 個\n", $m, $Q, $L;
if ($OUT) { open my $o, '>:utf8', $OUT or die; print $o join("\t", '判定', '補正', '点', '出典', '頭数', '市場比', 'z', 'p', @PER, '単回収'), "\n", map { "$_\n" } @lines }
