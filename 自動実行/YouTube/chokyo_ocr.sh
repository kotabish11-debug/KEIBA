#!/usr/bin/env bash
# 調教動画の字幕を文字認識で自動で読み、馬ごとの追い切りを1行ずつ出す(全部の過去分を読むため。2026-10-26〜)
# 使い方: bash 自動実行/YouTube/chokyo_ocr.sh <動画ID> <年> <レース名>   → 標準出力に chokyo_parse.pl の行
#   動画は 自動実行/YouTube/映像/調教_<ID>/video.*(無ければ取る)。2秒おきに字幕のある下の部分を切り出し、白い文字だけを3倍にして Windows の日本語OCR(ocr.ps1)で読む
#   読んだ文字は 映像/調教_<ID>/ocr.tsv に残す(コミットしない)
set -uo pipefail
ID="$1"; YEAR="$2"; RACE="$3"
P="$LOCALAPPDATA/Microsoft/WinGet/Packages"
YT=$(command -v yt-dlp || ls "$P"/yt-dlp.yt-dlp_*/yt-dlp.exe 2>/dev/null | head -1)
FF=$(ls "$P"/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe "$P"/yt-dlp.FFmpeg_*/*/bin/ffmpeg.exe 2>/dev/null | head -1)
DENO=$(ls "$P"/DenoLand.Deno_*/deno.exe 2>/dev/null | head -1); [ -n "$DENO" ] && export PATH="$(dirname "$DENO"):$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"; O="$HERE/映像/調教_$ID"; mkdir -p "$O"
ls "$O"/video.* >/dev/null 2>&1 || "$YT" -q --no-warnings --ffmpeg-location "$(dirname "$FF")" -f "bv*[height<=1080]/b[height<=1080]" -o "$O/video.%(ext)s" "https://www.youtube.com/watch?v=$ID" >&2 || exit 1
if [ ! -s "$O/ocr.tsv" ]; then
  C=$(mktemp -d); V=$(ls "$O"/video.* | head -1)
  "$FF" -loglevel error -i "$V" -vf "fps=1/2,scale=1920:-2,crop=iw*0.75:ih*0.32:0:ih*0.68,format=gray,lut=y='if(gt(val\,200)\,0\,255)',scale=iw*2:-2:flags=neighbor,pad=iw+80:ih+80:40:40:white" -y "$C/c_%04d.png"
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/ocr.ps1")" "$(cygpath -w "$C")" "$(cygpath -w "$O/ocr.tsv")"
  rm -rf "$C"
fi
perl "$HERE/chokyo_parse.pl" "$O/ocr.tsv" "$ID" "$YEAR" "$RACE"
