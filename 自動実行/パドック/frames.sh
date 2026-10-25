#!/usr/bin/env bash
# パドック・返し馬の動画を静止画に切り出す(Claudeは動画を直接見られないので、画像で馬ごとに見る。2026-10-26〜)
# 使い方: bash 自動実行/パドック/frames.sh <動画ファイル> [何秒おき 1]
# 出力: 馬情報/パドック/画像/<動画の名前>/f_001.jpg …(横1280px)。動画は 馬情報/パドック/動画/ に置く。動画と画像はGitHubに送らない(.gitignore)
#   判断は結果が出る前に 馬情報/パドック/判断の記録.csv に書き、たまったらオッズより当たったかを確かめる
set -euo pipefail
FF=$(command -v ffmpeg || ls "$LOCALAPPDATA"/Microsoft/WinGet/Packages/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe 2>/dev/null | head -1)
[ -n "$FF" ] || { echo "ffmpeg が見つからない(winget install Gyan.FFmpeg)"; exit 1; }
V="$1"; SEC="${2:-1}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
O="$ROOT/馬情報/パドック/画像/$(basename "${V%.*}")"; mkdir -p "$O"
"$FF" -loglevel error -i "$V" -vf "fps=1/$SEC,scale=1280:-2" -q:v 3 -y "$O/f_%03d.jpg"
echo "$(ls "$O" | wc -l) 枚 → $O"
