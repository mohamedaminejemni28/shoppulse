param(
    [Parameter(Position = 0)]
    [ValidateSet("debug", "build", "run", "test", "docs")]
    [string]$Action = "build"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectRoot

$dockerCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\resources\bin\docker.exe"),
    "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
)

$dockerExecutable = $dockerCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not $dockerExecutable) {
    throw "Docker est introuvable. Installez et démarrez Docker Desktop."
}

switch ($Action) {
    "debug" { & $dockerExecutable compose --profile analytics run --rm dbt debug }
    "build" { & $dockerExecutable compose --profile analytics run --rm dbt build }
    "run"   { & $dockerExecutable compose --profile analytics run --rm dbt run }
    "test"  { & $dockerExecutable compose --profile analytics run --rm dbt test }
    "docs"  { & $dockerExecutable compose --profile analytics run --rm dbt docs generate }
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
