param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "status", "stop", "logs")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

switch ($Action) {
    "start" {
        docker compose --profile tools --profile orchestration --profile datalake --profile streaming --profile app up -d `
            postgres pgadmin kestra-postgres kestra minio kafka kafka-to-minio backend frontend
    }
    "status" {
        docker compose --profile tools --profile orchestration --profile datalake --profile streaming --profile app ps
    }
    "logs" {
        docker compose --profile orchestration --profile streaming --profile app logs --tail 100 backend frontend kestra kafka-to-minio
    }
    "stop" {
        docker compose --profile tools --profile orchestration --profile datalake --profile streaming --profile app stop
    }
}
