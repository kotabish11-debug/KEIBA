# simulator.html から、計算に使う関数と定数だけを抜き出して1つのJSにする(過去レースでシミュレーターと同じ計算を動かすため)
# 使い方: perl extract.pl <simulator.html> > sim_core.js [名前...](名前を指定するとそれだけ抜き出す)
# 画面(DOM)に触る部分は抜き出さない。足りない名前があれば @NAMES に足す
use utf8; use strict; use warnings;
binmode STDOUT, ':utf8';
my $f = shift;
open my $h, '<:raw', $f or die; local $/; my $html = <$h>; utf8::decode($html);
my @NAMES = @ARGV ? map { utf8::decode(my $x = $_); $x } @ARGV : qw(WEIGHTS FACTORS STYLES_RUN PACE_ADJ MUST_LEAD_ADJ DRAW_SHOCK PACE_BIG_PLACES MIN_RUNS FLB_GAMMA
  STYLES_BET PAYBACK SHRINK TURF_START_DIRT FIRST_CORNER_SHORT FIRST_CORNER_LONG COURSE_PRESET SIRE_WET
  clone clampNum baseScore autoPaceProbs paceProbs mulberry32 marketWin canBlend blendWeight simulate runSim
  sireWetAdj euroWetAdj dayBloodAdj baseFixed oddsOf marketProbs estOdds buildCandidates pickBets allocate hits
  defaultBias raceFromDoc defaultSettings);
for my $n (@NAMES) {
  my $re = qr/^  (?:function \Q$n\E\s*\(|const \Q$n\E\s*=)/m;
  pos($html) = 0; $html =~ /$re/g or die "not found: $n\n";
  my $start = $-[0]; my $i = $+[0]; $i-- if substr($html, $i - 1, 1) eq "(";
  # 次の行頭(2文字インデント)の宣言かコメントまで、括弧の対応を見ながら進む
  my $depth = 0; my $len = length $html; my ($q, $seen) = ('', 0);
  for (; $i < $len; $i++) {
    my $c = substr($html, $i, 1);
    if ($q) { if ($c eq '\\') { $i++; next } $q = '' if $c eq $q; next }
    if ($c eq '"' || $c eq "'" || $c eq '`') { $q = $c; next }
    if ($c eq '/' && substr($html, $i + 1, 1) eq '/') { $i = index($html, "\n", $i); next }
    if ($c eq '{' || $c eq '(' || $c eq '[') { $depth++; $seen = 1 }
    elsif ($c eq '}' || $c eq ')' || $c eq ']') { $depth-- }
    if ($depth == 0 && $seen && ($c eq '}' || $c eq ';' || $c eq ']')) {
      # 関数は } で終わり、const は ; で終わる
      my $rest = substr($html, $i + 1, 2);
      last if $c eq ';' || $rest =~ /^;?\s/;
    }
    last if $depth == 0 && !$seen && $c eq ';';
  }
  my $code = substr($html, $start, $i - $start + 1);
  $code .= ';' unless $code =~ /[;}]\s*$/;
  print "$code\n";
}
