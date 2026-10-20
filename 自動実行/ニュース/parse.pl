#!/usr/bin/env perl
# ニュース一覧のHTMLから見出しを取り出し、TSV(id 取得元 日時 分類 見出し URL)で出す
# 使い方: perl parse.pl <yahoo|jra|keibalab> <HTMLファイル> [年月 例: 202610(jraのみ)]
use strict; use warnings; use utf8;
use Digest::MD5 qw(md5_hex);
use Encode qw(decode encode_utf8);
binmode STDOUT, ':utf8';
my ($kind, $file, $ym) = @ARGV;
open my $fh, '<:raw', $file or die "$file: $!";
my $html = decode('UTF-8', do { local $/; <$fh> });
close $fh;

sub clean { my $s = shift // ''; $s =~ s/<[^>]*>//g; $s =~ s/&amp;/&/g; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g; $s =~ s/&#39;/'/g; $s =~ s/&#(\d+);/chr($1)/ge; $s =~ s/&#x([0-9a-fA-F]+);/chr(hex $1)/ge;$s =~ s/[\t\r\n]+/ /g; $s =~ s/\x{3000}/ /g; $s =~ s/^\s+|\s+$//g; return $s; }
sub out { my ($src, $at, $cat, $title, $url) = @_; return unless $title && $url; print join("\t", 'n' . substr(md5_hex(encode_utf8($url)), 0, 12), $src, $at, $cat, $title, $url), "\n"; }

if ($kind eq 'yahoo') {
  # スポーツナビ 競馬ニュース: <a class="cm-timeLine__itemArticleLink" href=...> 見出し・配信元・時刻
  while ($html =~ m{<a class="cm-timeLine__itemArticleLink" href="([^"]+)">(.*?)</a>}gs) {
    my ($url, $b) = ($1, $2);
    my ($t) = $b =~ m{cm-timeLine__itemTitle">(.*?)</p>}s;
    my ($c) = $b =~ m{cm-timeLine__itemCredit">(.*?)</small>}s;
    my ($tm) = $b =~ m{cm-timeLine__itemTime">(.*?)</time>}s;
    $tm = clean($tm); $tm =~ s{/}{-}g;
    out('スポーツナビ', $tm, clean($c), clean($t), $url);
  }
} elsif ($kind eq 'jra') {
  # JRAニュース: <div class="news_unit" id="date_20"> の下に <a href="/news/..."> 分類・見出し
  my $y = substr($ym // '', 0, 4); my $m = substr($ym // '', 4, 2);
  for my $unit (split /<div class="news_unit"/, $html) {
    my ($d) = $unit =~ m{^\s*id="date_(\d+)"} or next;
    while ($unit =~ m{<a href="(/news/\d{6}/\d+\.html)">\s*<div class="icon"><p>(.*?)</p></div>\s*<div class="txt">(.*?)</div>}gs) {
      out('JRA', sprintf('%s-%s-%02d', $y, $m, $d), clean($2), clean($3), "https://www.jra.go.jp$1");
    }
  }
} elsif ($kind eq 'keibalab') {
  # 競馬ラボ トピックス: <a href="/topics/12345/"> 見出し・日付
  my %seen;
  while ($html =~ m{<a href="(/topics/\d+/)">(.*?)</a>}gs) {
    my ($path, $b) = ($1, $2);
    my ($t) = $b =~ m{class="mediaTitle">(.*?)</h3>}s or next;
    my ($tag) = $b =~ m{class="mediaTag">(.*?)</p>}s;
    my ($dt) = $b =~ m{class="mediaDate">(.*?)</time>}s;
    next if $seen{$path}++;
    $dt = clean($dt); $dt =~ s{/}{-}g;
    # 今年の記事は「10/19」のように年が付かない
    if ($dt =~ /^\d{1,2}-\d{1,2}$/) { my @t = gmtime(time + 9 * 3600); $dt = sprintf('%04d-%s', $t[5] + 1900, $dt); }
    out('競馬ラボ', $dt, clean($tag), clean($t), "https://www.keibalab.jp$path");
  }
} else { die "kind: yahoo|jra|keibalab\n"; }
