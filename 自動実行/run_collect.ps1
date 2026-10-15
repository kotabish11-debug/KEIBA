# 重賞の情報収集を claude -p で実行する(タスクスケジューラから呼ばれる)
$root = "C:\Users\murakawa kota\Desktop\競馬"
$claude = "C:\Users\murakawa kota\.local\bin\claude.exe"
$logDir = Join-Path $root "自動実行\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
Set-Location $root
# claude の出力(UTF-8)をログに正しく書くため
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$now = Get-Date -Format "yyyy-MM-dd HH:mm (ddd)"
$prompt = "現在時刻は $now です。$root\情報収集の手順.md の手順に従って、重賞の情報収集を実行してください。終わったら、新しく分かったことを3行以内で報告してください。"
$log = Join-Path $logDir ("{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmm"))

"[$now] start" | Out-File -Encoding utf8 $log
& $claude -p $prompt --allowedTools "WebFetch,WebSearch,Read,Write,Edit,Glob,Grep" --output-format text 2>&1 | Out-File -Append -Encoding utf8 $log
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] end (exit $LASTEXITCODE)" | Out-File -Append -Encoding utf8 $log
