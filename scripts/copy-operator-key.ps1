$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$environmentFile = Join-Path $projectRoot 'backend/.env'
if (-not (Test-Path -LiteralPath $environmentFile)) { throw 'Run setup-local.ps1 first.' }
$keyLine = Get-Content -LiteralPath $environmentFile | Where-Object { $_.StartsWith('OPERATOR_KEY=') } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($keyLine)) { throw 'The local operator key is not configured.' }
Set-Clipboard -Value $keyLine.Substring('OPERATOR_KEY='.Length)
Write-Output 'Local operator key copied. Paste it into Connect operator in the dashboard. Keep it out of submitted evidence.'
