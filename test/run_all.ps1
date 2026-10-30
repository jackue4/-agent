# Full verification: server unit tests, Godot headless tests, autoplay bot on every 2D reference
# game, and screenshot regression. Requires the platform server on -Server (for assets/specs).
# Usage (from ugc-platform): powershell -NoProfile -ExecutionPolicy Bypass -File test\run_all.ps1
param([string]$Server = "http://10.0.4.94:5300", [string[]]$BotGames = @("d7b950c42f", "c9a209a863"), [switch]$NoShots)
$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { $c = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"; if (Test-Path $c) { $c } else { Join-Path $root "..\Godot_v4.7.2-stable_win64_console.exe" } }
$results = [ordered]@{}

Push-Location (Join-Path $root "server")
cmd /c "npm test > %TEMP%\ugc_npm.log 2>&1"
$results["server unit tests"] = $LASTEXITCODE -eq 0
Get-Content $env:TEMP\ugc_npm.log -Encoding utf8 | Select-String '(pass|fail) \d' | ForEach-Object { "  $_" }
Pop-Location

$log = & $godot --headless --path (Join-Path $root "runtime") --script res://tests/run_tests.gd 2>&1 | ForEach-Object { "$_" }
$results["godot headless tests"] = $LASTEXITCODE -eq 0
$log | Select-String 'passed|FAIL' | Select-Object -Last 3 | ForEach-Object { "  $_" }

$env:UGC_BASE = $Server
foreach ($g in $BotGames) {
  $out = node (Join-Path $PSScriptRoot "bot_play.mjs") $g 2>&1
  $results["bot plays $g"] = $LASTEXITCODE -eq 0
  $out | ForEach-Object { "  $_" }
}

if (-not $NoShots) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "shots.ps1") -Server $Server | ForEach-Object { "  $_" }
  $results["screenshot regression"] = $LASTEXITCODE -eq 0
}

""
$fail = 0
foreach ($k in $results.Keys) { if (-not $results[$k]) { $fail++ }; "{0,-28} {1}" -f $k, $(if ($results[$k]) { "PASS" } else { "FAIL" }) }
exit $fail
