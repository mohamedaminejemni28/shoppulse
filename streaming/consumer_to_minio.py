import io
import json
import os
import time
import uuid
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from kafka import KafkaConsumer


BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
TOPIC = os.getenv("KAFKA_TOPIC", "shoppulse.events")
GROUP_ID = os.getenv("KAFKA_CONSUMER_GROUP", "shoppulse-datalake-writer-v1")
BUCKET = os.getenv("MINIO_BUCKET", "shoppulse")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "25"))
FLUSH_SECONDS = int(os.getenv("FLUSH_SECONDS", "10"))


def s3_client():
    return boto3.client(
        "s3",
        endpoint_url=os.getenv("MINIO_ENDPOINT", "http://minio:9000"),
        aws_access_key_id=os.getenv("MINIO_ACCESS_KEY"),
        aws_secret_access_key=os.getenv("MINIO_SECRET_KEY"),
        region_name="us-east-1",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def ensure_bucket(client) -> None:
    try:
        client.head_bucket(Bucket=BUCKET)
    except Exception:
        client.create_bucket(Bucket=BUCKET)


def flush(client, records: list[dict]) -> None:
    if not records:
        return
    now = datetime.now(timezone.utc)
    key = (
        "raw/streaming/events/"
        f"date={now:%Y-%m-%d}/hour={now:%H}/"
        f"events_{now:%H-%M-%S}_{uuid.uuid4().hex[:8]}.jsonl"
    )
    payload = "\n".join(json.dumps(record, ensure_ascii=False) for record in records) + "\n"
    client.upload_fileobj(
        io.BytesIO(payload.encode("utf-8")),
        BUCKET,
        key,
        ExtraArgs={"ContentType": "application/x-ndjson"},
    )
    print(f"{len(records)} événements archivés dans s3://{BUCKET}/{key}", flush=True)


def main() -> None:
    client = s3_client()
    for attempt in range(30):
        try:
            ensure_bucket(client)
            break
        except Exception as exc:
            if attempt == 29:
                raise
            print(f"MinIO indisponible ({exc}), nouvelle tentative...", flush=True)
            time.sleep(2)

    consumer = KafkaConsumer(
        TOPIC,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id=GROUP_ID,
        auto_offset_reset="earliest",
        enable_auto_commit=False,
        value_deserializer=lambda value: json.loads(value.decode("utf-8")),
    )
    records: list[dict] = []
    last_flush = time.monotonic()
    while True:
        messages = consumer.poll(timeout_ms=1000, max_records=BATCH_SIZE)
        for partition_messages in messages.values():
            records.extend(message.value for message in partition_messages)
        if records and (len(records) >= BATCH_SIZE or time.monotonic() - last_flush >= FLUSH_SECONDS):
            flush(client, records)
            consumer.commit()
            records.clear()
            last_flush = time.monotonic()


if __name__ == "__main__":
    main()
