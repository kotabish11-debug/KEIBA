#!/usr/bin/env bash
# JRA公式YouTubeの【調教動画】(重賞ごとの追い切り映像。馬ごとに日付・コース・調教タイムが字幕で出る)を取って、Claudeが読む一覧画像にする(2026-10-26〜)
# 使い方: bash 自動実行/YouTube/jra_chokyo.sh list              … チャンネルの調教動画の一覧を 馬情報/JRA公式_調教動画一覧.tsv に作り直す(ID・年・レース名・長さ)
#         bash 自動実行/YouTube/jra_chokyo.sh get <動画ID>       … 動画を取り、4秒おきの静止画を 4×5 の一覧画像(sheet_N.jpg)にする
#         bash 自動実行/YouTube/jra_chokyo.sh next [新しい|古い]  … 書き起こしが済んでいない(調教動画済み.txt に無い)動画を1本 get する。新しい = 今週の重賞、古い = 過去分の書き起こし
# 出力: 自動実行/YouTube/映像/調教_<動画ID>/sheet_*.jpg(コミットしない)。書き起こしの手順は 自動実行/YouTube/調教動画の手順.md
set -uo pipefail
P="$LOCALAPPDATA/Microsoft/WinGet/Packages"
YT=$(command -v yt-dlp || ls "$P"/yt-dlp.yt-dlp_*/yt-dlp.exe 2>/dev/null | head -1)
FF=$(ls "$P"/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe "$P"/yt-dlp.FFmpeg_*/*/bin/ffmpeg.exe 2>/dev/null | head -1)
DENO=$(ls "$P"/DenoLand.Deno_*/deno.exe 2>/dev/null | head -1); [ -n "$DENO" ] && export PATH="$(dirname "$DENO"):$PATH"
[ -n "$YT" ] && [ -n "$FF" ] || { echo "yt-dlp か ffmpeg が無い(winget install yt-dlp.yt-dlp)"; exit 1; }
export PYTHONIOENCODING=utf-8
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
LIST="$ROOT/馬情報/JRA公式_調教動画一覧.tsv"; DONE="$HERE/調教動画済み.txt"; touch "$DONE"
cmd="${1:-}"
if [ "$cmd" = list ]; then
  "$YT" --no-warnings --encoding utf-8 --flat-playlist --print "%(id)s	%(duration)s	%(title)s" "https://www.youtube.com/@jraofficial/videos" > "$LIST.tmp" || exit 1
  { printf 'id\t年\tレース\t秒\n'; grep '【調教動画】' "$LIST.tmp" | perl -CSD -Mutf8 -F'\t' -lane 'my ($y, $r) = $F[2] =~ /(\d{4})年\s*(.+?)\s*[｜|]/; print join "\t", $F[0], $y // "", $r // $F[2], $F[1]'; } > "$LIST"
  rm -f "$LIST.tmp"; echo "調教動画 $(($(wc -l < "$LIST") - 1)) 本 → $LIST"; exit 0
fi
if [ "$cmd" = next ]; then
  [ -s "$LIST" ] || bash "$0" list >/dev/null
  order=${2:-新しい}
  ID=$(tail -n +2 "$LIST" | { [ "$order" = 古い ] && tac || cat; } | cut -f1 | grep -vxF -f "$DONE" | head -1)
  [ -n "$ID" ] || { echo "書き起こしの済んでいない調教動画は無い"; exit 0; }
  grep "^$ID	" "$LIST"; set -- get "$ID"; cmd=get
fi
if [ "$cmd" = get ]; then
  ID="$2"; O="$HERE/映像/調教_$ID"; mkdir -p "$O"
  ls "$O"/video.* >/dev/null 2>&1 || "$YT" -q --no-warnings --ffmpeg-location "$(dirname "$FF")" -f "bv*[height<=1080]+ba/b[height<=1080]" -o "$O/video.%(ext)s" "https://www.youtube.com/watch?v=$ID" || exit 1
  V=$(ls "$O"/video.* | head -1)
  rm -f "$O"/f_*.jpg "$O"/sheet_*.jpg
  "$FF" -loglevel error -i "$V" -vf "fps=1/4,scale=640:-2" -q:v 3 -y "$O/f_%03d.jpg"
  "$FF" -loglevel error -framerate 1 -i "$O/f_%03d.jpg" -vf "tile=4x5" -q:v 3 -y "$O/sheet_%02d.jpg"
  echo "$(ls "$O"/sheet_*.jpg | wc -l) 枚の一覧画像 → $O"; exit 0
fi
echo "使い方: bash jra_chokyo.sh list | get <動画ID> | next [新しい|古い]"; exit 1
