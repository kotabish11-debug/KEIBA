# 競馬ラボ(keibalab.jp)が必要な情報収集をPCで行う(タスクスケジューラ「競馬_PC収集」から呼ばれる)
# クラウドのルーティンは競馬ラボにつながらないため、全レースの競馬ラボ版・重賞の判断材料・学習データ・種牡馬リーディングはここで集める
# 指示は prompt.md。Claude Code を無人(-p)で動かし、許可の確認なしで実行する
$root = "C:\Users\murakawa kota\Desktop\競馬"
$here = Join-Path $root "自動実行\PC収集"
$logDir = Join-Path $root "自動実行\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
Set-Location $root
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Users\murakawa kota\.local\bin"
$env:CLAUDE_CODE_GIT_BASH_PATH = "C:\Program Files\Git\bin\bash.exe"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$log = Join-Path $logDir ("{0}_pc.log" -f (Get-Date -Format "yyyyMMdd_HHmm"))
function Log($m) { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] $m" | Out-File -Append -Encoding utf8 $log }

# 二重起動を防ぐ
$lock = Join-Path $here ".lock"
if ((Test-Path $lock) -and ((Get-Item $lock).LastWriteTime -gt (Get-Date).AddHours(-2))) { Log "前回の実行中のため見送り"; exit 0 }
New-Item -ItemType File -Force $lock | Out-Null
try {
  Log "start"
  git pull --rebase --autostash -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log

  $prompt = Get-Content -Raw -Encoding UTF8 (Join-Path $here "prompt.md")
  $tools = "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,ToolSearch,ArtifactData"
  $prompt | claude -p --model sonnet --allowedTools $tools --permission-mode acceptEdits 2>&1 | Out-File -Append -Encoding utf8 $log
  Log ("claude 終了コード " + $LASTEXITCODE)

  # 学習データ(週1回。Claudeを使わずスクリプトだけで集める)
  & "C:\Program Files\Git\bin\bash.exe" (Join-Path $here "backfill_weekly.sh") 2>&1 | Out-File -Append -Encoding utf8 $log
  git add "馬情報/過去レースデータ" "自動実行/PC収集/backfill_last.txt" "馬情報/複勝の買い方_成績.md" 2>&1 | Out-Null
  git diff --cached --quiet
  if ($LASTEXITCODE -ne 0) {
    git commit -q -m ("PC収集 {0} 学習データ" -f (Get-Date -Format "yyyy-MM-dd HH:mm")) 2>&1 | Out-File -Append -Encoding utf8 $log
    git pull --rebase --autostash -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log
    if ($LASTEXITCODE -ne 0) { git rebase --abort 2>&1 | Out-Null; Log "pull失敗" } else { git push -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log }
  }
  Log ("end: " + (git log -1 --format="%h %s"))
} finally {
  Remove-Item -Force $lock -ErrorAction SilentlyContinue
}
