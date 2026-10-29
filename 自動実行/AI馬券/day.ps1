# AI馬券の1日(タスクスケジューラ「競馬_AI馬券」が毎朝 8:30 に呼ぶ。中央競馬の無い日はすぐ終わる)
#   朝の準備(morning.sh)→ 各レースの発走4分前に判断・購入(live.py、最終レースまで)→ 結果を埋めて(settle.py)記録をコミット
#   買うかどうか・金額は 自動実行/AI馬券/config.json(mode: dry = 記録だけ / browser = 即PATで購入の手前まで / live = 本当に買う)
$root = "C:\Users\murakawa kota\Desktop\AIの作業場\競馬"
$logDir = Join-Path $root "自動実行\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
Set-Location $root
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
$env:PYTHONIOENCODING = "utf-8"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$bash = "C:\Program Files\Git\bin\bash.exe"
$py = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
$day = Get-Date -Format "yyyyMMdd"
$log = Join-Path $logDir ("{0}_ai.log" -f (Get-Date -Format "yyyyMMdd_HHmm"))
function Log($m) { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] $m" | Out-File -Append -Encoding utf8 $log }

Log "start"
& $bash "自動実行/AI馬券/morning.sh" $day 2>&1 | Out-File -Append -Encoding utf8 $log
$rc = $LASTEXITCODE
if ($rc -eq 3) { Log "中央競馬なし"; Remove-Item $log; exit 0 }
if ($rc -ne 0) { Log "朝の準備に失敗 ($rc)"; exit 1 }

$w = "馬情報\JRA-VAN\AI馬券\work"
& $py "自動実行\AI馬券\live.py" "$w\today_$day.pkl" "$w\entries_$day.jsonl" 2>&1 | Out-File -Append -Encoding utf8 $log

# 最終レースの確定を待ってから結果を埋める(JRA-VAN の成績は確定から少しあとに入る)
Start-Sleep -Seconds 1800
& $bash "自動実行/JRA-VAN/update.sh" 2>&1 | Out-File -Append -Encoding utf8 $log
& $py "自動実行\AI馬券\settle.py" 2>&1 | Out-File -Append -Encoding utf8 $log

git add "馬情報/AI馬券/記録.csv" "馬情報/AI馬券/成績.md" 2>&1 | Out-Null
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -q -m ("AI馬券 {0} の記録" -f (Get-Date -Format "yyyy-MM-dd")) 2>&1 | Out-File -Append -Encoding utf8 $log
  git pull --rebase --autostash -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log
  if ($LASTEXITCODE -ne 0) { git rebase --abort 2>&1 | Out-Null; Log "pull失敗" } else { git push -q origin main 2>&1 | Out-File -Append -Encoding utf8 $log }
}
Log "end"
