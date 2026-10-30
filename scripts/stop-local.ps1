param([switch]$KeepDatabase)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$expectedPython = Join-Path $projectRoot '.tools\python\python.exe'
if (Test-Path -LiteralPath '.runtime/app-processes.json') {
    $records = Get-Content -Raw -LiteralPath '.runtime/app-processes.json' | ConvertFrom-Json
    foreach ($record in $records) {
        $process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if ($null -ne $process -and $process.Path -eq $expectedPython -and $process.StartTime.ToUniversalTime().Ticks -eq $record.start_ticks) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
        }
    }
    Remove-Item -LiteralPath '.runtime/app-processes.json'
}
if (-not $KeepDatabase -and (Test-Path -LiteralPath '.runtime/mysql-admin.json')) {
    & $expectedPython 'scripts/stop_mysql.py'
    if ($LASTEXITCODE -ne 0) { throw 'Database shutdown failed; see the local logs.' }
}
Write-Output 'Owned project processes stopped. MySQL data has been preserved.'
