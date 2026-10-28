# GitHub(クラウドの情報収集の保存先)と、PCの「競馬」フォルダーを同期する(タスクスケジューラから呼ばれる)
# 情報収集そのものはクラウドのルーティンが行う。PCが止まっていた間の分は、次に起動したときにここで取り込まれる
param([int]$WaitMinutes = 30)

$root = "C:\Users\murakawa kota\Desktop\AIの作業場\競馬"
$logDir = Join-Path $root "自動実行\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
Set-Location $root
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$log = Join-Path $logDir ("{0}_sync.log" -f (Get-Date -Format "yyyyMMdd_HHmm"))
function Log($m) { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] $m" | Out-File -Append -Encoding utf8 $log }

# クラウドの情報収集(定刻に開始)が終わるのを待ってから取り込む
Log "start (wait $WaitMinutes min)"
Start-Sleep -Seconds ($WaitMinutes * 60)

# PCで変更したもの(シミュレーターの自動更新など)を先にコミットする
git add -A 2>&1 | Out-Null
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -q -m ("PCでの変更 {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm")) 2>&1 | Out-File -Append -Encoding utf8 $log
}

git pull --rebase -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log
if ($LASTEXITCODE -ne 0) {
  git rebase --abort 2>&1 | Out-Null
  Log "pull失敗(同じファイルが両方で変更された可能性)。手動で確認が必要"
  exit 1
}
git push -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log
Log ("end: " + (git log -1 --format="%h %s"))
