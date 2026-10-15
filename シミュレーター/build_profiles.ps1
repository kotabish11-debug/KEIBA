# 「馬情報」フォルダーの出走馬ファイル(*出走馬*.md)から、シミュレーターの馬カード用データ(data/profiles.json)を作る
# 使い方: powershell -ExecutionPolicy Bypass -File シミュレーター\build_profiles.ps1
# 読むもの: 一覧の表(性齢・調教師・父・母・母父など)と「## 戦績」の各馬の行
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root "馬情報"
$outDir = Join-Path $PSScriptRoot "data"
New-Item -ItemType Directory -Force $outDir | Out-Null

$PLACES = "札幌|函館|福島|新潟|東京|中山|中京|京都|阪神|小倉"
$COLS = @{ "馬名" = "name"; "性齢" = "sexage"; "騎手" = "jockey"; "斤量" = "kinryo"; "調教師" = "trainer"; "父" = "sire"; "母" = "dam"; "母父" = "damsire";
  "生年月日" = "birth"; "馬主" = "owner"; "生産者" = "breeder"; "本賞金" = "prize"; "馬ID" = "horseId" }

function Cells($line) { ($line.Trim().Trim("|") -split "\|") | ForEach-Object { $_.Trim() } }
function NumOrNull($s) { if ($s -match "^-?\d+(\.\d+)?$") { [double]$s } else { $null } }

# 戦績の1行を項目に分ける。分けられない部分は text に残す
function ParseRun($body, [ref]$year) {
  $r = [ordered]@{}
  $m = [regex]::Match($body, "^(?:(\d{4})/)?(\d{1,2})/(\d{1,2})\s+(.*)$")
  if (-not $m.Success) { return $null }
  if ($m.Groups[1].Success) { $year.Value = [int]$m.Groups[1].Value }
  $r.date = "{0}-{1:D2}-{2:D2}" -f $year.Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value
  $rest = $m.Groups[4].Value
  $note = ""
  $i = $rest.IndexOf("※")
  if ($i -ge 0) { $note = $rest.Substring($i + 1).Trim(); $rest = $rest.Substring(0, $i).Trim() }
  $cm = [regex]::Match($rest, "^(.+?)\s+($PLACES)(芝|ダ|障)(\d+)\s*(.*)$")
  if (-not $cm.Success) { $r.text = $rest; if ($note) { $r.note = $note }; return $r }
  $name = $cm.Groups[1].Value.Trim()
  $gm = [regex]::Match($name, "^(.*)\(([^)]+)\)$")
  if ($gm.Success) { $r.race = $gm.Groups[1].Value; $r.grade = $gm.Groups[2].Value } else { $r.race = $name }
  $r.place = $cm.Groups[2].Value; $r.surface = $cm.Groups[3].Value; $r.dist = [int]$cm.Groups[4].Value
  $tokens = @($cm.Groups[5].Value -split "\s+" | Where-Object { $_ -ne "" })
  $left = @()
  foreach ($t in $tokens) {
    if (-not $r.Contains("rank") -and $t -match "^(\d+|取消|中止|除外|失格)(?:/(\d+))?$") {
      $rk = $Matches[1]; $hd = $Matches[2]
      if ($rk -match "^\d+$") { $r.rank = [int]$rk } else { $r.rank = $null; $r.result = $rk }
      if ($hd) { $r.heads = [int]$hd }
    }
    elseif (-not $r.Contains("rank") -and $t -match "^(\d+)着$") { $r.rank = [int]$Matches[1] }
    elseif ($t -match "^(\d+)人(?:\(([\d.]+)\))?$") { $r.pop = [int]$Matches[1]; if ($Matches[2]) { $r.odds = [double]$Matches[2] } }
    elseif ($t -match "^(\d{3})(?:\(([+-]?\d+)\))?$") { $r.weight = [int]$Matches[1]; if ($Matches[2]) { $r.weightDiff = [int]$Matches[2] } }
    elseif ($t -match "^\d:\d{2}\.\d$") { $r.time = $t }
    elseif ($t -match "^\d+(-\d+)+$") { $r.pass = $t }
    elseif ($t -match "^\d{2}\.\d$") { $r.f3 = [double]$t }
    elseif ($t -eq "-") { }
    elseif (-not $r.Contains("jockey") -and $t -match "^([^\d(][^(]*?)(?:\(([^)]*)\))?$") {
      $r.jockey = $Matches[1]; if ($Matches[2]) { $r.kinryo = $Matches[2] }
    }
    else { $left += $t }
  }
  if ($left.Count) { $r.text = ($left -join " ") }
  if ($note) { $r.note = $note }
  return $r
}

$horses = [ordered]@{}
$files = Get-ChildItem $srcDir -Filter "*出走馬*.md" | Sort-Object LastWriteTime
foreach ($f in $files) {
  $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
  $baseYear = 2026
  if ($f.Name -match "^(\d{4})" -or $f.Name -match "(\d{4})") { $baseYear = [int]$Matches[1] }
  $raceLabel = ($lines[0] -replace "^#\s*", "" -replace "\s+—.*$", "")
  # 一覧の表
  $header = $null
  foreach ($ln in $lines) {
    if ($ln -match "^\|" -and $ln -match "\|\s*馬名\s*\|") { $header = Cells $ln; continue }
    if ($header -and $ln -match "^\|\s*-{3}") { continue }
    if ($header -and $ln -match "^\|") {
      $c = Cells $ln
      $p = [ordered]@{}
      for ($k = 0; $k -lt $header.Count; $k++) {
        $h = $header[$k]; $v = $c[$k]
        if (-not $v -or $v -eq "-") { continue }
        if ($COLS.ContainsKey($h)) { $p[$COLS[$h]] = $v }
        elseif ($h -match "通算") { $p.record = $v; $p.recordLabel = $h }
      }
      if (-not $p.sexage -and $f.Name -match "秋華賞") { $p.sexage = "牝3" }
      $p.raceLabel = $raceLabel
      $p.source = $f.Name
      $p.runs = @()
      $horses[$p.name] = $p
      continue
    }
    if ($header -and $ln -notmatch "^\|") { $header = $null }
  }
  # 戦績
  $inRuns = $false; $cur = $null; $year = $baseYear
  foreach ($ln in $lines) {
    if ($ln -match "^## ") { $inRuns = $ln -match "^## 戦績"; $cur = $null; continue }
    if (-not $inRuns) { continue }
    if ($ln -match "^### (.+)$") { $cur = $Matches[1].Trim(); $year = $baseYear; continue }
    if (-not $cur -or -not $horses.Contains($cur)) { continue }
    if ($ln -match "^- ※(.+)$") {
      $prev = $horses[$cur].comment
      $horses[$cur].comment = if ($prev) { "$prev / " + $Matches[1].Trim() } else { $Matches[1].Trim() }
      continue
    }
    if ($ln -match "^- (.+)$") {
      $yr = $year
      $run = ParseRun $Matches[1].Trim() ([ref]$yr)
      $year = $yr
      if ($run) { $horses[$cur].runs += , $run }
    }
  }
}

# 今年の重賞の全着順(騎手カードと、馬カードの重賞成績に使う)
function IsoOf($s) { if ($s -match "(\d+)月(\d+)日") { "2026-{0:D2}-{1:D2}" -f [int]$Matches[1], [int]$Matches[2] } else { "" } }
$raceInfo = @{}
foreach ($ln in [IO.File]::ReadAllLines((Join-Path $srcDir "2026年_重賞一覧.md"), [Text.Encoding]::UTF8)) {
  if ($ln -notmatch "^\|\s*\d+月\d+日") { continue }
  $c = Cells $ln
  $info = @{ surface = ""; dist = $null; going = ""; heads = $null }
  if ($c[4] -match "^(芝|ダ|障)([\d,]+)m") { $info.surface = $Matches[1]; $info.dist = [int]($Matches[2] -replace ",", "") }
  if ($c[7] -match ":(.+)$") { $info.going = $Matches[1] }
  if ($c[6] -match "^\d+$") { $info.heads = [int]$c[6] }
  $raceInfo[(IsoOf $c[0]) + "|" + $c[2]] = $info
}
# 1行 = [日付, レース, 格, 場, 芝ダ障, 距離, 馬場, 頭数, 着順, 枠, 馬番, 馬名, 性齢, 斤量, 騎手, タイム, 着差, 通過, 上3F, 馬体重, 調教師, 人気]
$results = @()
foreach ($r in (Import-Csv (Join-Path $srcDir "2026重賞_全着順.csv") -Encoding UTF8)) {
  $iso = IsoOf $r.date
  $info = $raceInfo["$iso|$($r.race)"]
  if (-not $info) { $info = @{ surface = ""; dist = $null; going = ""; heads = $null } }
  $results += , @($iso, $r.race, $r.grade, $r.place_jo, $info.surface, $info.dist, $info.going, $info.heads,
    $r.rank, $r.waku, $r.num, $r.horse, $r.sexage, $r.kinryo, $r.jockey, $r.time, $r.margin, $r.corners, $r.agari, $r.bodyweight, $r.trainer, $r.pop)
}

$out = [ordered]@{ generatedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"); horses = $horses; results = $results }
$json = $out | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $outDir "profiles.json"), $json, (New-Object Text.UTF8Encoding($false)))
"profiles.json: {0} 頭 / 重賞着順 {1} 行" -f $horses.Count, $results.Count

