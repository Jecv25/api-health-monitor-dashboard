$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Force -Path '.tools','.runtime' | Out-Null
$pythonExe = Join-Path $projectRoot '.tools\python\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' -OutFile '.tools/python.zip'
    Expand-Archive -LiteralPath '.tools/python.zip' -DestinationPath '.tools/python' -Force
    Set-Content -LiteralPath '.tools/python/python312._pth' -Value @('python312.zip','.','Lib/site-packages','../../backend','import site')
    Invoke-WebRequest -UseBasicParsing -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '.tools/get-pip.py'
    & $pythonExe '.tools/get-pip.py' --no-warn-script-location
    if ($LASTEXITCODE -ne 0) { throw 'pip bootstrap failed.' }
}
$dependencies = if (Test-Path -LiteralPath 'backend/requirements.lock.txt') { 'backend/requirements.lock.txt' } else { 'backend/requirements.txt' }
& $pythonExe -m pip install -r $dependencies --no-warn-script-location
if ($LASTEXITCODE -ne 0) { throw 'Backend dependency installation failed.' }
if (-not (Test-Path -LiteralPath '.tools/mysql-8.4.8-winx64/bin/mysqld.exe')) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.8-winx64.zip' -OutFile '.tools/mysql.zip'
    Expand-Archive -LiteralPath '.tools/mysql.zip' -DestinationPath '.tools' -Force
}
& $pythonExe 'scripts/provision_mysql.py'
if ($LASTEXITCODE -ne 0) { throw 'Database provisioning failed.' }
Push-Location -LiteralPath 'frontend'
try { flutter pub get; if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed.' } }
finally { Pop-Location }
Write-Output 'Setup complete. Run .\scripts\start-local.ps1 next.'
