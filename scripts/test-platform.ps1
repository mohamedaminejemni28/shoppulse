$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Test-Endpoint([string]$Name, [string]$Url) {
    $response = Invoke-RestMethod -Uri $Url -TimeoutSec 15
    Write-Host "[OK] $Name" -ForegroundColor Green
    return $response
}

Write-Host "1/7 Validation de la configuration Docker"
docker compose --profile tools --profile orchestration --profile datalake --profile streaming --profile app --profile analytics --profile batch config --quiet

Write-Host "2/7 Démarrage de la plateforme"
& "$PSScriptRoot\platform.ps1" start

Write-Host "3/7 Tests PostgreSQL"
& "$PSScriptRoot\db.ps1" test
if ($LASTEXITCODE -ne 0) { throw "Les tests PostgreSQL ont échoué" }

Write-Host "4/7 Tests dbt et Data Warehouse"
& "$PSScriptRoot\dbt.ps1" build
if ($LASTEXITCODE -ne 0) { throw "Le build dbt a échoué" }

Write-Host "5/7 Tests API"
$health = Test-Endpoint "API /health" "http://127.0.0.1:8000/health"
$dashboard = Test-Endpoint "API /dashboard" "http://127.0.0.1:8000/dashboard"
$null = Test-Endpoint "API /analytics/products" "http://127.0.0.1:8000/analytics/products?limit=3"
$null = Test-Endpoint "API /events/recent" "http://127.0.0.1:8000/events/recent?limit=3"
$supervision = Test-Endpoint "API /supervision" "http://127.0.0.1:8000/supervision"

Write-Host "6/7 Test du frontend"
$frontend = Invoke-WebRequest -Uri "http://127.0.0.1:3000" -TimeoutSec 15 -UseBasicParsing
if ($frontend.StatusCode -ne 200 -or $frontend.Content -notmatch "ShopPulse") { throw "Frontend invalide" }
Write-Host "[OK] Dashboard frontend" -ForegroundColor Green

Write-Host "7/7 Contrôle des services"
docker compose --profile tools --profile orchestration --profile datalake --profile streaming --profile app ps

Write-Host ""
Write-Host "PLATEFORME SHOPPULSE VALIDÉE" -ForegroundColor Green
Write-Host "Commandes : $($dashboard.summary.orders) | CA : $($dashboard.summary.revenue) | Conversion : $($dashboard.summary.conversion_rate)%"
