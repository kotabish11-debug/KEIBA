#!/usr/bin/env bash
# YouTubeの動画を取って静止画に切り出す(字幕に出ない画面の表・印・パドックなどを Claude が画像で見るため。2026-10-26〜)
# 使い方: bash 自動実行/YouTube/frames.sh <URL> [何秒おき 5] [範囲 例 "*1:00-3:30"(省略で全部)]
# 出力: 自動実行/YouTube/映像/<動画ID>/ に 動画と f_001.jpg …(横1280px)。著作物なのでコミットしない(.gitignore)。見終わったら 削除したもの/ に移す
#   ユーザーが指定した動画だけに使う(登録チャンネルを丸ごと取らない)。メンバー限定などは取らない
#   yt-dlp・ffmpeg・Deno は winget で入れたもの(WinGet\Packages の実体を探す)
set -euo pipefail
P="$LOCALAPPDATA/Microsoft/WinGet/Packages"
YT=$(command -v yt-dlp || ls "$P"/yt-dlp.yt-dlp_*/yt-dlp.exe 2>/dev/null | head -1)
FF=$(command -v ffmpeg || ls "$P"/yt-dlp.FFmpeg_*/*/bin/ffmpeg.exe "$P"/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe 2>/dev/null | head -1)
DENO=$(ls "$P"/DenoLand.Deno_*/deno.exe 2>/dev/null | head -1); [ -n "$DENO" ] && export PATH="$(dirname "$DENO"):$PATH"
[ -n "$YT" ] && [ -n "$FF" ] || { echo "yt-dlp か ffmpeg が無い(winget install yt-dlp.yt-dlp)"; exit 1; }
URL="$1"; SEC="${2:-5}"; RANGE="${3:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ID=$("$YT" --no-warnings --get-id "$URL" | head -1); O="$ROOT/自動実行/YouTube/映像/$ID"; mkdir -p "$O"
"$YT" -q --no-warnings --ffmpeg-location "$(dirname "$FF")" -f "bv*[height<=1080]+ba/b[height<=1080]" ${RANGE:+--download-sections "$RANGE"} -o "$O/video.%(ext)s" "$URL"
V=$(ls "$O"/video.* | head -1)
"$FF" -loglevel error -i "$V" -vf "fps=1/$SEC,scale=1280:-2" -q:v 3 -y "$O/f_%03d.jpg"
echo "$(ls "$O"/f_*.jpg | wc -l) 枚 → $O"
