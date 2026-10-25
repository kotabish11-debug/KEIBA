#!/usr/bin/env bash
# YouTubeのライブ配信(JRA公式の「中央競馬全レース中継」など)を、今から指定した分だけ録って一覧画像にする(パドックが映るか・パドックの判断に使えるかを確かめるため。2026-10-26〜)
# 使い方: bash 自動実行/YouTube/live_rec.sh <URL> <分> <名前>   例: bash live_rec.sh https://www.youtube.com/watch?v=eKmAAki7N6c 40 20261031_1450
#   配信がまだ始まっていなければ、始まるまで最大30分待つ。720pまで
# 出力: 自動実行/YouTube/映像/ライブ_<名前>/ に live.ts と、10秒おきの静止画を 4×5 にまとめた sheet_*.jpg(コミットしない)。ログは 自動実行/logs/live_<名前>.log
set -uo pipefail
P="$LOCALAPPDATA/Microsoft/WinGet/Packages"
YT=$(command -v yt-dlp || ls "$P"/yt-dlp.yt-dlp_*/yt-dlp.exe 2>/dev/null | head -1)
FF=$(ls "$P"/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe "$P"/yt-dlp.FFmpeg_*/*/bin/ffmpeg.exe 2>/dev/null | head -1)
DENO=$(ls "$P"/DenoLand.Deno_*/deno.exe 2>/dev/null | head -1); [ -n "$DENO" ] && export PATH="$(dirname "$DENO"):$PATH"
URL="$1"; MIN="$2"; NAME="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
O="$HERE/映像/ライブ_$NAME"; mkdir -p "$O" "$ROOT/自動実行/logs"; LOG="$ROOT/自動実行/logs/live_$NAME.log"
exec >> "$LOG" 2>&1
echo "[$(date '+%F %T')] 開始 $URL $MIN 分"
END=$(( $(date +%s) + 1800 )); M3U=""
while [ -z "$M3U" ] && [ "$(date +%s)" -lt "$END" ]; do
  M3U=$("$YT" --no-warnings -g -f "bv*[height<=720]/b[height<=720]/best" "$URL" 2>/dev/null | head -1)
  [ -z "$M3U" ] && { echo "配信がまだ取れない。1分待つ"; sleep 60; }
done
[ -n "$M3U" ] || { echo "配信が取れなかった"; exit 1; }
"$FF" -loglevel error -i "$M3U" -t $((MIN * 60)) -c copy -y "$O/live.ts"
"$FF" -loglevel error -i "$O/live.ts" -vf "fps=1/10,scale=640:-2" -q:v 3 -y "$O/f_%03d.jpg"
"$FF" -loglevel error -framerate 1 -i "$O/f_%03d.jpg" -vf "tile=4x5" -q:v 3 -y "$O/sheet_%02d.jpg"
echo "[$(date '+%F %T')] 終了 $(ls "$O"/sheet_*.jpg 2>/dev/null | wc -l) 枚の一覧画像 → $O"
