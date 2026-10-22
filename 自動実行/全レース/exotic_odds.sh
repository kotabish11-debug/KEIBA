#!/usr/bin/env bash
# 学習データのレースの、確定の馬連・馬単・3連複オッズを競馬ラボ(ipat-f.keibalab.jp のオッズAPI)から集める
# 本物のオッズで期待値を出したときに利益が出るかを確かめるため(ワイドは過去のオッズが残っていない)
# 使い方: bash 自動実行/全レース/exotic_odds.sh [学習データ.jsonl.gz ...]
# 出力: 馬情報/過去レースデータ/確定オッズ_馬連馬単3連複.jsonl.gz(1行1レース {"id","uren":{"1-2":12.3},"utan":{"1-2":..},"trio":{"1-2-3":..}})。取得済みは飛ばす
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OUTGZ="$ROOT/馬情報/過去レースデータ/確定オッズ_馬連馬単3連複.jsonl.gz"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
[ $# -eq 0 ] && set -- "$ROOT"/馬情報/過去レースデータ/平場_*.jsonl.gz
[ -s "$OUTGZ" ] && zcat "$OUTGZ" > "$W/have.jsonl" || : > "$W/have.jsonl"
grep -o '^{"id":"[0-9]*"' "$W/have.jsonl" | grep -o '[0-9]\{12\}' | sort -u > "$W/have.txt"
for g in "$@"; do zcat "$g" | grep -o '"id":"[0-9]\{12\}"' | grep -o '[0-9]\{12\}'; done | sort -u | comm -23 - "$W/have.txt" > "$W/todo.txt"
echo "確定オッズ: $(wc -l < "$W/todo.txt") レースを取得"
cp "$W/have.jsonl" "$W/new.jsonl"; mkdir -p "$W/h"
fetch() { local id="$1" d="$2"
  for k in uren utan trio; do
    curl -sSL -m 30 -A "Mozilla/5.0" -H "Referer: https://www.keibalab.jp/" -o "$d/${id}_$k.json" \
      "https://ipat-f.keibalab.jp/jquery/odds.html?kind=$k&opdt=${id:0:8}&rcoursecd=${id:8:2}&rno=${id:10:2}&device=pc"; sleep 0.7
  done; }
export -f fetch
split -l 60 "$W/todo.txt" "$W/part_"
for part in "$W"/part_*; do
  xargs -P 3 -I{} bash -c 'fetch {} "$1"' _ "$W/h" < "$part"
  while read -r ID; do
    perl -MJSON::PP -e 'my $id = shift; my %o = (id => $id);
      for my $k (qw(uren utan trio)) { open my $h, "<", "$ARGV[0]/${id}_$k.json" or exit 1; local $/; my $d = eval { decode_json(<$h>) } or exit 1; my $n = $d->{normal} or exit 1;
        for my $a (keys %$n) { for my $b (keys %{$n->{$a}}) { my $v = $n->{$a}{$b};
          if (ref $v) { for my $c (keys %$v) { $o{$k}{join "-", map { $_ + 0 } $a, $b, $c} = $v->{$c} + 0 if $v->{$c} > 0 } }
          else { $o{$k}{join "-", map { $_ + 0 } $a, $b} = $v + 0 if $v > 0 } } } }
      exit 1 unless $o{uren}; print JSON::PP->new->canonical->encode(\%o), "\n"' "$ID" "$W/h" >> "$W/new.jsonl"
    rm -f "$W/h/${ID}"_*.json
  done < "$part"
  gzip -c "$W/new.jsonl" > "$OUTGZ.tmp" && mv "$OUTGZ.tmp" "$OUTGZ"
done
echo "確定オッズ: 合計 $(zcat "$OUTGZ" | wc -l) レース"
