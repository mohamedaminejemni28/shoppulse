import json
import os
import random
import time
import uuid
from datetime import datetime, timezone

from kafka import KafkaProducer


BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
TOPIC = os.getenv("KAFKA_TOPIC", "shoppulse.events")
EVENT_COUNT = int(os.getenv("EVENT_COUNT", "100"))
DELAY_SECONDS = float(os.getenv("EVENT_DELAY_SECONDS", "0.05"))

EVENT_TYPES = ["page_view", "add_to_cart", "order_created", "payment_succeeded"]
WEIGHTS = [0.60, 0.22, 0.12, 0.06]


def build_event() -> dict:
    event_type = random.choices(EVENT_TYPES, weights=WEIGHTS, k=1)[0]
    customer_id = random.randint(1, 100)
    product_id = random.randint(1, 30)
    event = {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "customer_id": customer_id,
        "session_id": str(uuid.uuid4()),
        "product_id": product_id,
        "channel": random.choice(["web", "mobile", "email", "social"]),
        "device": random.choice(["desktop", "mobile", "tablet"]),
    }
    if event_type in {"order_created", "payment_succeeded"}:
        event["order_id"] = random.randint(1, 500)
        event["amount"] = round(random.uniform(10, 750), 2)
    return event


def main() -> None:
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        value_serializer=lambda value: json.dumps(value).encode("utf-8"),
        key_serializer=lambda value: value.encode("utf-8"),
        acks="all",
        retries=10,
    )
    for number in range(1, EVENT_COUNT + 1):
        event = build_event()
        producer.send(TOPIC, key=event["customer_id"].__str__(), value=event)
        print(f"[{number}/{EVENT_COUNT}] {event['event_type']} -> {TOPIC}", flush=True)
        time.sleep(DELAY_SECONDS)
    producer.flush()
    producer.close()
    print(f"Production terminée : {EVENT_COUNT} événements publiés.", flush=True)


if __name__ == "__main__":
    main()
