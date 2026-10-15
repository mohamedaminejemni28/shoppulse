$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Read-Env([string]$Name) {
    $line = Get-Content .env | Where-Object { $_ -match "^$([regex]::Escape($Name))=" } | Select-Object -Last 1
    if (-not $line) { throw "$Name est absent de .env" }
    return ($line -split "=", 2)[1]
}

$apiKey = Read-Env "SHOPPULSE_API_KEY"
$kestraUser = Read-Env "KESTRA_ADMIN_EMAIL"
$kestraPassword = Read-Env "KESTRA_ADMIN_PASSWORD"
$kestraToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${kestraUser}:${kestraPassword}"))
$kestraHeaders = @{ Authorization = "Basic $kestraToken" }

Write-Host "1/5 Création d'une nouvelle commande ShopPulse"
$body = @{
    customer_id = 1
    source_channel = "web"
    shipping_amount = 5
    items = @(
        @{ product_id = 1; quantity = 1; discount_amount = 0 },
        @{ product_id = 2; quantity = 2; discount_amount = 0 }
    )
} | ConvertTo-Json -Depth 5
$order = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/orders" `
    -Headers @{ "X-ShopPulse-API-Key" = $apiKey } -ContentType "application/json" -Body $body
Write-Host "Commande créée : $($order.order_number), total $($order.total_amount)"

Write-Host "2/5 Export PostgreSQL vers MinIO avec Kestra"
$export = Invoke-RestMethod -Method Post `
    -Uri "http://127.0.0.1:8080/api/v1/main/executions/shoppulse.datalake/export_shoppulse_to_datalake" `
    -Headers $kestraHeaders -ContentType "multipart/form-data"
Write-Host "Exécution Kestra : $($export.id)"

Write-Host "3/5 Actualisation du Data Warehouse avec Kestra"
$warehouse = Invoke-RestMethod -Method Post `
    -Uri "http://127.0.0.1:8080/api/v1/main/executions/shoppulse.warehouse/refresh_warehouse" `
    -Headers $kestraHeaders -ContentType "multipart/form-data"
Write-Host "Exécution Warehouse : $($warehouse.id)"

Write-Host "4/5 Actualisation des modèles dbt"
& "$PSScriptRoot\dbt.ps1" run

Write-Host "5/5 Vérification dans l'API et le dashboard"
$visible = Invoke-RestMethod -Uri "http://127.0.0.1:8000/orders/$($order.order_id)"
Write-Host "Commande visible dans l'API : $($visible.order_number)"
Write-Host "Ouvrez http://127.0.0.1:3000 puis cliquez sur Actualiser."
Write-Host "Dans MinIO, vérifiez raw/orders/date=... après la fin du flow Kestra."
