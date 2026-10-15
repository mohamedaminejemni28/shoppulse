select
    order_id,
    order_key,
    order_number,
    customer_id,
    order_status,
    upper(currency) as currency,
    subtotal_amount,
    discount_amount,
    shipping_amount,
    tax_amount,
    total_amount,
    source_channel,
    ordered_at,
    updated_at
from {{ source('shop', 'orders') }}
