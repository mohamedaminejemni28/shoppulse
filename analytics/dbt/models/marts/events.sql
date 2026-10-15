select
    event_time::date as event_date,
    event_type,
    device_type,
    source_channel,
    count(*) as event_count,
    count(distinct session_id) as session_count,
    count(distinct customer_id) as identified_customers,
    count(distinct product_id) as products_affected,
    count(distinct order_id) as orders_affected,
    max(ingested_at) as latest_ingested_at
from {{ ref('stg_events') }}
group by event_time::date, event_type, device_type, source_channel
