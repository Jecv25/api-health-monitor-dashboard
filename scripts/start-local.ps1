param([switch]$SkipBuild, [switch]$NoWorker)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$pythonExe = Join-Path $projectRoot '.tools\python\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) { throw 'Run .\scripts\setup-local.ps1 first.' }
New-Item -ItemType Directory -Force -Path '.runtime' | Out-Null
if (Test-Path -LiteralPath '.runtime/app-processes.json') {
    $previous = Get-Content -Raw -LiteralPath '.runtime/app-processes.json' | ConvertFrom-Json
    $running = @($previous | Where-Object { Get-Process -Id $_.pid -ErrorAction SilentlyContinue })
    if ($running.Count -gt 0) { throw 'This project already has running processes. Use .\scripts\stop-local.ps1 before restarting.' }
}
foreach ($port in @(8000,8080,9001)) {
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    try { $probe.Start() }
    catch { throw "Port $port is already in use. Stop the existing project or resolve the conflict before startup." }
    finally { $probe.Stop() }
}
& $pythonExe 'scripts/provision_mysql.py'
if ($LASTEXITCODE -ne 0) { throw 'Database startup failed.' }
if (-not $SkipBuild -or -not (Test-Path -LiteralPath 'frontend/build/web/index.html')) {
    Push-Location -LiteralPath 'frontend'
    try {
        flutter build web --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
    } finally { Pop-Location }
}
$records = [System.Collections.Generic.List[object]]::new()
function Start-ProjectProcess([string]$name, [string[]]$arguments, [string]$directory) {
    $stdoutPath = Join-Path $projectRoot ".runtime/$name.stdout.log"
    $stderrPath = Join-Path $projectRoot ".runtime/$name.stderr.log"
    $process = Start-Process -FilePath $pythonExe -ArgumentList $arguments -WorkingDirectory $directory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $records.Add(@{ name = $name; pid = $process.Id; start_ticks = $process.StartTime.ToUniversalTime().Ticks })
    ConvertTo-Json -InputObject @($records.ToArray()) | Set-Content -LiteralPath '.runtime/app-processes.json'
}
Start-ProjectProcess -name 'api' -arguments @('-m','uvicorn','app.main:app','--host','127.0.0.1','--port','8000') -directory (Join-Path $projectRoot 'backend')
Start-ProjectProcess -name 'demo' -arguments @('-m','uvicorn','app.demo_service:app','--host','127.0.0.1','--port','9001') -directory (Join-Path $projectRoot 'backend')
if (-not $NoWorker) { Start-ProjectProcess -name 'worker' -arguments @('-m','app.worker') -directory (Join-Path $projectRoot 'backend') }
Start-ProjectProcess -name 'frontend' -arguments @('scripts/serve_frontend.py') -directory $projectRoot
$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $apiState = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/healthz' -TimeoutSec 2
        $uiState = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8080' -TimeoutSec 2
        $demoState = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9001/health/healthy' -TimeoutSec 2
        if ($apiState.status -eq 'ok' -and $uiState.StatusCode -eq 200 -and $demoState.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $ready) { throw 'Startup did not complete. See .runtime/*.stderr.log, then run stop-local.ps1.' }
Write-Output 'Dashboard: http://localhost:8080'
Write-Output 'API documentation: http://127.0.0.1:8000/docs'
Write-Output 'Copy operator key: .\scripts\copy-operator-key.ps1'
