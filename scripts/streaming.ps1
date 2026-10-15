param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "produce", "status", "logs", "stop", "test")]
    [string]$Action = "status",

    [Parameter(Position = 1)]
    [ValidateRange(1, 100000)]
    [int]$Count = 100
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

switch ($Action) {
    "start" {
        docker compose --profile datalake --profile streaming up -d minio kafka kafka-to-minio
    }
    "produce" {
        $env:KAFKA_EVENT_COUNT = $Count
        try {
            docker compose --profile streaming run --rm kafka-producer
        }
        finally {
            Remove-Item Env:KAFKA_EVENT_COUNT -ErrorAction SilentlyContinue
        }
    }
    "status" {
        docker compose --profile datalake --profile streaming ps minio kafka kafka-to-minio
    }
    "logs" {
        docker compose --profile streaming logs --tail 100 kafka kafka-to-minio
    }
    "test" {
        docker compose --profile streaming exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:29092 --describe --topic shoppulse.events
        docker compose --profile streaming logs --tail 30 kafka-to-minio
    }
    "stop" {
        docker compose --profile streaming stop kafka-producer kafka-to-minio kafka
    }
}
