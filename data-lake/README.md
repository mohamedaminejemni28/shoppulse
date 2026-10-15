# Data Lake ShopPulse

Le bucket MinIO `shoppulse` est organisé en trois zones.

## `raw`

Copies fidèles des tables PostgreSQL. Elles servent d'historique et ne sont pas modifiées après leur création.

```text
raw/
  customers/date=AAAA-MM-JJ/customers_HH-mm-ss.csv
  products/date=AAAA-MM-JJ/products_HH-mm-ss.csv
  orders/date=AAAA-MM-JJ/orders_HH-mm-ss.csv
  order_items/date=AAAA-MM-JJ/order_items_HH-mm-ss.csv
  events/date=AAAA-MM-JJ/events_HH-mm-ss.csv
```

## `processed`

Données nettoyées et enrichies, prêtes pour les transformations suivantes.

```text
processed/
  orders/date=AAAA-MM-JJ/orders_enriched_HH-mm-ss.csv
  products/date=AAAA-MM-JJ/products_inventory_HH-mm-ss.csv
  events/date=AAAA-MM-JJ/events_enriched_HH-mm-ss.csv
```

## `analytics`

Indicateurs métier prêts à être consommés par une API ou un tableau de bord.

```text
analytics/
  daily_sales/date=AAAA-MM-JJ/daily_sales_HH-mm-ss.csv
  product_performance/date=AAAA-MM-JJ/product_performance_HH-mm-ss.csv
  customer_summary/date=AAAA-MM-JJ/customer_summary_HH-mm-ss.csv
  conversion_funnel/date=AAAA-MM-JJ/conversion_funnel_HH-mm-ss.csv
```

Le flow Kestra `shoppulse.datalake.export_shoppulse_to_datalake` construit les trois zones tous les jours à 02:00 dans le fuseau `Africa/Lagos`.

## Événements Kafka et traitement Spark

Les événements temps réel sont archivés automatiquement par le service `kafka-to-minio` :

```text
raw/streaming/events/date=AAAA-MM-JJ/hour=HH/events_HH-MM-SS_ID.jsonl
```

Le job Spark lit l'ensemble de ces fichiers, calcule les volumes d'événements, les clients uniques et les montants par date, type, canal et appareil, puis écrit :

```text
analytics/streaming_event_summary/date=AAAA-MM-JJ/run=HH-MM-SS/*.parquet
```
