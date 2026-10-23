#!/bin/bash
# 登録したYouTubeチャンネル(channels.tsv)の新しい動画を探し、自動字幕(文字起こし)を 未処理/<動画ID>.txt に保存する
# 使い方: bash 自動実行/YouTube/new_videos.sh   → 新しく保存した本数を表示。処理済みの動画IDは seen.txt
# - 各チャンネルの「動画」「ショート」「ライブ」タブの最初のページ(新しい順に約30本)だけを見る
# - 字幕は innertube の player API を iOS クライアントで呼ぶと取れる(WEB の timedtext は PO トークンが要り取れない)
# - メンバー限定の動画は取れないので seen.txt に入れて飛ばす(回避はしない)
# - 文字起こしは著作物なのでコミットしない(未処理/・処理済み/ は .gitignore)。要約して 馬情報/ の資料に書くのは Claude の仕事
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
mkdir -p 未処理 処理済み; touch seen.txt
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"
IUA="com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
T=$(mktemp -d); n=0
grep -v '^#' channels.tsv | while IFS=$'\t' read -r handle name doc; do
  [ -z "$handle" ] && continue
  for tab in videos shorts streams; do
    curl -s -m 30 -A "$UA" -H "Accept-Language: ja" "https://www.youtube.com/@$handle/$tab" -o "$T/page.html" || continue
    perl -ne 'while (/"(?:videoId|contentId)":"([\w-]{11})"/g) { print "$1\n" }' "$T/page.html"
  done | awk '!s[$0]++' | while read -r id; do
    grep -qxF -- "$id" seen.txt && continue
    curl -s -m 30 -A "$IUA" -H 'Content-Type: application/json' "https://www.youtube.com/youtubei/v1/player?prettyPrint=false" \
      -d "{\"context\":{\"client\":{\"clientName\":\"IOS\",\"clientVersion\":\"20.10.4\",\"hl\":\"ja\",\"deviceMake\":\"Apple\",\"deviceModel\":\"iPhone16,2\"}},\"videoId\":\"$id\"}" -o "$T/p.json"
    # 他チャンネルの動画(おすすめ欄など)が混じったら飛ばす
    grep -q "\"channelId\"" "$T/p.json" || continue
    title=$(perl -ne 'if (/"videoDetails":\{.*?"title":"((?:[^"\\]|\\.)*)"/) { print $1; exit }' "$T/p.json")
    author=$(perl -ne 'if (/"videoDetails":\{.*?"author":"((?:[^"\\]|\\.)*)"/) { print $1; exit }' "$T/p.json")
    [ "$author" != "$name" ] && [ -n "$author" ] && case "$name" in *"$author"*) ;; *) continue;; esac
    url=$(grep -o '"captionTracks":\[{"baseUrl":"[^"]*"' "$T/p.json" | head -1 | sed 's/.*"baseUrl":"//;s/"$//;s/\\u0026/\&/g')
    echo "$id" >> seen.txt
    [ -z "$url" ] && continue   # メンバー限定・字幕なし
    curl -s -m 60 -A "$IUA" "$url&fmt=json3" -o "$T/j.json"
    { printf '# %s\n# チャンネル: %s / https://www.youtube.com/watch?v=%s / 資料: %s\n\n' "$title" "$name" "$id" "$doc"
      perl -e 'local $/; my $t = <>; my $o = ""; while ($t =~ /"utf8":\s*"((?:[^"\\]|\\.)*)"/g) { my $s = $1; $s =~ s/\\n/ /g; $s =~ s/\\"/"/g; $o .= $s } $o =~ s/\s+/ /g; print "$o\n"' "$T/j.json"; } > "未処理/$id.txt"
    echo "new $id $title"
  done
done
rm -rf "$T"
echo "未処理: $(ls 未処理 | wc -l) 本"
