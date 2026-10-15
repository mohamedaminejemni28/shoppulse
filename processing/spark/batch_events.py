import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.config import Config
from pyspark.sql import SparkSession
from pyspark.sql import functions as F


BUCKET = os.getenv("MINIO_BUCKET", "shoppulse")
RAW_PREFIX = "raw/streaming/events/"


def s3_client():
    return boto3.client(
        "s3",
        endpoint_url=os.getenv("MINIO_ENDPOINT", "http://minio:9000"),
        aws_access_key_id=os.getenv("MINIO_ACCESS_KEY"),
        aws_secret_access_key=os.getenv("MINIO_SECRET_KEY"),
        region_name="us-east-1",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def download_raw_files(client, target: Path) -> int:
    paginator = client.get_paginator("list_objects_v2")
    count = 0
    for page in paginator.paginate(Bucket=BUCKET, Prefix=RAW_PREFIX):
        for item in page.get("Contents", []):
            if not item["Key"].endswith(".jsonl"):
                continue
            destination = target / f"part-{count:05d}.jsonl"
            client.download_file(BUCKET, item["Key"], str(destination))
            count += 1
    return count


def upload_directory(client, source: Path, prefix: str) -> int:
    count = 0
    for file in source.rglob("*.parquet"):
        key = f"{prefix}/{file.name}"
        client.upload_file(str(file), BUCKET, key)
        count += 1
    return count


def main() -> None:
    client = s3_client()
    workspace = Path(tempfile.mkdtemp(prefix="shoppulse-spark-"))
    raw_dir = workspace / "raw"
    output_dir = workspace / "output"
    raw_dir.mkdir(parents=True)
    try:
        file_count = download_raw_files(client, raw_dir)
        if file_count == 0:
            raise RuntimeError("Aucun événement Kafka trouvé dans MinIO. Lancez d'abord le producteur.")

        spark = (
            SparkSession.builder
            .appName("ShopPulseStreamingBatch")
            .master(os.getenv("SPARK_MASTER", "local[*]"))
            .getOrCreate()
        )
        spark.sparkContext.setLogLevel("WARN")
        events = spark.read.json(str(raw_dir / "*.jsonl"))
        enriched = events.withColumn("event_date", F.to_date(F.to_timestamp("occurred_at")))
        aggregates = (
            enriched.groupBy("event_date", "event_type", "channel", "device")
            .agg(
                F.count("event_id").alias("event_count"),
                F.countDistinct("customer_id").alias("unique_customers"),
                F.round(F.sum(F.coalesce(F.col("amount"), F.lit(0.0))), 2).alias("total_amount"),
            )
            .orderBy("event_date", "event_type", "channel", "device")
        )
        aggregates.show(50, truncate=False)
        aggregates.coalesce(1).write.mode("overwrite").parquet(str(output_dir))
        spark.stop()

        now = datetime.now(timezone.utc)
        prefix = f"analytics/streaming_event_summary/date={now:%Y-%m-%d}/run={now:%H-%M-%S}"
        uploaded = upload_directory(client, output_dir, prefix)
        print(
            f"Spark a traité {file_count} fichier(s) et publié {uploaded} fichier(s) "
            f"dans s3://{BUCKET}/{prefix}/",
            flush=True,
        )
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    main()
