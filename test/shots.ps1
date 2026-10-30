# Screenshot regression: renders key states of the reference games into test/shots/<name>.png
# Usage (from ugc-platform):  pwsh test/shots.ps1 [-Server http://10.0.4.94:5300]
# Requires the platform server (for AI assets). Compare the PNGs visually or with test/diff_shots.mjs.
# -Project <id> renders edit/play/win of any project as proj_<id>_*.png instead of the reference set.
param([string]$Server = "http://10.0.4.94:5300", [string]$Fox = "d7b950c42f", [string]$Penguin = "cd6a1667bb", [string]$Project = "")
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { $c = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"; if (Test-Path $c) { $c } else { Join-Path $root "..\Godot_v4.7.2-stable_win64_console.exe" } }
$rt = Join-Path $root "runtime"
$out = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force $out | Out-Null

function Get-SpecFile($id) {
  $p = Invoke-RestMethod "$Server/api/projects/$id"
  $as = @{}
  foreach ($k in $p.game.assets.PSObject.Properties) {
    $a = $k.Value; $u = $a.url
    if ($u -and $u.StartsWith('/')) { $u = "$Server$u" }
    $as[$k.Name] = @{ kind = $a.kind; state = $a.state; url = $u }
  }
  $f = Join-Path $env:TEMP "ugc_shot_$id.json"
  @{ spec = $p.game; assets = $as } | ConvertTo-Json -Depth 40 | Set-Content -Encoding utf8 $f
  return $f
}

$cases = @(
  @{ name = "2d_edit";  id = $Fox;     args = @();                          secs = 10 },
  @{ name = "2d_play";  id = $Fox;     args = @("--play");                  secs = 8 },
  @{ name = "2d_start"; id = $Fox;     args = @("--play", "--start-card");  secs = 5 },
  @{ name = "2d_win";   id = $Fox;     args = @("--play", "--simulate=win");  secs = 5 },
  @{ name = "2d_lose";  id = $Fox;     args = @("--play", "--simulate=lose"); secs = 5 },
  @{ name = "2d_pause"; id = $Fox;     args = @("--play", "--simulate=pause"); secs = 4 },
  @{ name = "3d_edit";  id = $Penguin; args = @();                          secs = 30 },
  @{ name = "3d_play";  id = $Penguin; args = @("--play");                  secs = 30 }
)
if ($Project) {
  $cases = @(
    @{ name = "proj_${Project}_edit"; id = $Project; args = @();                    secs = 25 },
    @{ name = "proj_${Project}_play"; id = $Project; args = @("--play");            secs = 25 },
    @{ name = "proj_${Project}_win";  id = $Project; args = @("--play", "--simulate=win"); secs = 25 }
  )
}
$specs = @{}
$fail = 0
foreach ($c in $cases) {
  if (-not $specs[$c.id]) { $specs[$c.id] = Get-SpecFile $c.id }
  $png = Join-Path $out "$($c.name).png"
  Remove-Item $png -ErrorAction SilentlyContinue
  $ErrorActionPreference = "Continue"
  $log = & $godot --path $rt --resolution 1280x720 -- "--spec=$($specs[$c.id])" @($c.args) "--shot=$png" "--shot-secs=$($c.secs)" 2>&1 | ForEach-Object { "$_" }
  $ErrorActionPreference = "Stop"
  $errs = $log | Select-String "SCRIPT ERROR|^ERROR" | Where-Object { $_ -notmatch "Reading less data|leaked at exit|in use at exit|at exit in PagedAllocator|never freed|leaked \d+ bytes" }
  $ok = (Test-Path $png) -and -not $errs
  if (-not $ok) { $fail++ }
  "{0,-10} {1}" -f $c.name, ($(if ($ok) { "ok" } else { "FAIL" }))
  $errs | Select-Object -First 5 | ForEach-Object { "    $_" }
}
if ($fail) { exit 1 }
