select
    e.event_id,
    e.session_id,
    e.customer_id,
    e.product_id,
    e.order_id,
    e.event_type,
    e.event_time,
    e.ingested_at,
    e.schema_version,
    ws.device_type,
    ws.source_channel,
    ws.campaign_name
from {{ source('shop', 'events') }} as e
join {{ source('shop', 'web_sessions') }} as ws
    on ws.session_id = e.session_id
