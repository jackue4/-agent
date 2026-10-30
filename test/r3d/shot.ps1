param([string]$spec, [string]$out, [double]$secs = 3, [switch]$play)
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rt = Join-Path $root "runtime"
$exe = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { $c = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"; if (Test-Path $c) { $c } else { Join-Path (Split-Path $root -Parent) "Godot_v4.7.2-stable_win64_console.exe" } }
$a = @("--path", $rt, "--resolution", "1280x720", "--", "--spec=$spec", "--shot=$out", "--shot-secs=$secs")
if ($play) { $a += "--play" }
$o = & $exe @a 2>&1 | Out-String
$lines = $o -split "\r?\n" | Where-Object { $_ -match "ERROR|WARNING|error|at:|GDScript" -and $_ -notmatch "ugc\]" }
$lines | Select-Object -First 40
"--- done: " + (Test-Path $out)
