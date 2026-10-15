select
    oi.order_item_id as sale_id,
    o.order_id,
    o.order_number,
    o.ordered_at::date as order_date,
    o.customer_id,
    c.full_name as customer_name,
    c.country_code,
    p.product_id,
    p.sku,
    p.product_name,
    p.category_name,
    o.order_status,
    o.source_channel,
    o.currency,
    oi.quantity,
    oi.unit_price,
    oi.unit_cost,
    oi.discount_amount,
    oi.gross_amount,
    oi.line_total as net_amount,
    oi.gross_margin
from {{ ref('stg_order_items') }} as oi
join {{ ref('stg_orders') }} as o on o.order_id = oi.order_id
join {{ ref('stg_customers') }} as c on c.customer_id = o.customer_id
join {{ ref('stg_products') }} as p on p.product_id = oi.product_id
