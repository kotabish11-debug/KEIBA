#!/usr/bin/env bash
# 馬DBを続けて集め、1回(BUDGET秒)取り込むたびに 馬情報/馬DB をコミットして送る(2026-10-28 ユーザー指示「できるだけやって」「取り込みおわったたびにコミット」)
# 使い方: bash loop.sh(裏で動かす)。止めるときは 馬情報/馬DB/state/stop を作る(次の区切りで止まる)
# PCタスクの update.sh とは state/.lock で二重に動かない。ログは 自動実行/logs/<日時>_umadb_loop.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
ST="$ROOT/馬情報/馬DB/state"; STOP="$ST/stop"
LOG="$ROOT/自動実行/logs/$(date +%Y%m%d_%H%M)_umadb_loop.log"
export BUDGET="${BUDGET:-3000}"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

commit() {
  cd "$ROOT" || return
  git add "馬情報/馬DB" >> "$LOG" 2>&1 || { log "git add 失敗(次の回にまた試す)"; return; }
  if git diff --cached --quiet -- "馬情報/馬DB"; then log "変わったものなし"; return; fi
  # 馬DB だけをコミットする(ほかの人・タスクが変えたファイルは入れない)
  git commit -q -m "馬DB $(date '+%Y-%m-%d %H:%M') 取り込み" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "馬情報/馬DB" >> "$LOG" 2>&1 || { log "コミット失敗"; return; }
  git pull --rebase --autostash -q origin main >> "$LOG" 2>&1
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    git rebase --abort >> "$LOG" 2>&1; log "pull が競合で止まったので取り消した(コミットは手元に残る)"; return
  fi
  if git push -q origin main >> "$LOG" 2>&1; then log "コミットして送った: $(git log -1 --format='%h %s')"; else log "push 失敗(次の回にまた送る)"; fi
}

log "start BUDGET=$BUDGET"
while [ ! -e "$STOP" ]; do
  t0=$(date +%s)
  out="$(bash "$HERE/update.sh" 2>&1)"; echo "$out" >> "$LOG"
  if echo "$out" | grep -q "見送り"; then sleep 600; continue; fi
  commit
  # やることがなくなって早く終わったときは1時間待つ(新しい出走・登録を待つ)
  [ $(( $(date +%s) - t0 )) -lt 600 ] && sleep 3600
done
rm -f "$STOP"; log "stop ファイルがあったので終了"
