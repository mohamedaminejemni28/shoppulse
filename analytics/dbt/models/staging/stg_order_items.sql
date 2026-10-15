select
    order_item_id,
    order_id,
    product_id,
    unit_price,
    unit_cost,
    quantity,
    discount_amount,
    line_total,
    round(unit_price * quantity, 2) as gross_amount,
    round((unit_price - unit_cost) * quantity - discount_amount, 2) as gross_margin,
    created_at
from {{ source('shop', 'order_items') }}
