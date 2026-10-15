param(
    [Parameter(Position = 0)]
    [ValidateSet("run", "build")]
    [string]$Action = "run"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

switch ($Action) {
    "build" {
        docker compose --profile batch build spark-batch
    }
    "run" {
        docker compose --profile datalake up -d minio
        docker compose --profile batch run --rm spark-batch
    }
}
