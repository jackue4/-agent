param([string]$ListenAddress = '10.0.4.94', [switch]$Tunnel)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logDir = Join-Path $root 'artifacts\lan-services'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
if (-not (Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -eq $ListenAddress)) {
    throw "This computer does not own IPv4 address $ListenAddress. Pass -ListenAddress with its current LAN address."
}
$node = (Get-Command node.exe).Source
$previousHost = $env:HOST
$previousPort = $env:PORT
$previousData = $env:UGC_DATA_DIR
try {
    $env:HOST = $ListenAddress
    $env:PORT = '5300'
    $env:UGC_DATA_DIR = Join-Path $root 'data'
    $services = @(
        @{ Name = 'platform'; Port = 5300; Dir = 'server'; Entry = 'server.mjs' },
        @{ Name = 'sword-rogue'; Port = 5178; Dir = 'sword-rogue'; Entry = 'node_modules/vite/bin/vite.js' }
    )
    foreach ($service in $services) {
        $url = "http://${ListenAddress}:$($service.Port)/"
        $listener = Get-NetTCPConnection -State Listen -LocalPort $service.Port -ErrorAction SilentlyContinue
        if (-not $listener) {
            Start-Process -FilePath $node -ArgumentList $service.Entry -WorkingDirectory (Join-Path $root $service.Dir) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir "$($service.Name).out.log") -RedirectStandardError (Join-Path $logDir "$($service.Name).err.log") | Out-Null
        }
        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 2
                if ($response.StatusCode -eq 200) { $ready = $true; break }
            } catch { Start-Sleep -Milliseconds 300 }
        }
        if (-not $ready) { throw "Service unavailable: $url. Check port ownership and logs in $logDir." }
        Write-Output "$($service.Name): $url"
    }
    if ($Tunnel) {
        $tunnelExe = Join-Path $root 'tools\cloudflared\cloudflared.exe'
        $target = "http://${ListenAddress}:5300"
        $existing = Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" | Where-Object { $_.ExecutablePath -eq $tunnelExe -and $_.CommandLine.Contains($target) }
        if (-not $existing) {
            Start-Process -FilePath $tunnelExe -ArgumentList @('tunnel', '--url', $target) -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'tunnel.out.log') -RedirectStandardError (Join-Path $logDir 'tunnel.err.log') | Out-Null
        }
        Write-Output "Tunnel origin: $target (public URL in $logDir\tunnel.err.log)"
    }
} finally {
    $env:HOST = $previousHost
    $env:PORT = $previousPort
    $env:UGC_DATA_DIR = $previousData
}
