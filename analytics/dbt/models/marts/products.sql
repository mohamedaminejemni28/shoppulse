with sales_by_product as (
    select
        product_id,
        count(distinct order_id) as order_count,
        sum(quantity) as units_sold,
        sum(net_amount) as revenue,
        sum(gross_margin) as gross_margin
    from {{ ref('sales') }}
    where order_status in ('paid', 'processing', 'shipped', 'completed', 'refunded')
    group by product_id
),
views_by_product as (
    select
        product_id,
        count(*) filter (where event_type = 'product_viewed') as product_views,
        count(distinct session_id) filter (where event_type = 'product_viewed') as viewing_sessions
    from {{ ref('stg_events') }}
    where product_id is not null
    group by product_id
)
select
    p.product_id,
    p.sku,
    p.product_name,
    p.category_name,
    p.unit_price,
    p.unit_cost,
    p.unit_margin,
    p.currency,
    p.is_active,
    coalesce(s.order_count, 0) as order_count,
    coalesce(s.units_sold, 0) as units_sold,
    coalesce(s.revenue, 0) as revenue,
    coalesce(s.gross_margin, 0) as gross_margin,
    coalesce(v.product_views, 0) as product_views,
    coalesce(v.viewing_sessions, 0) as viewing_sessions,
    round(100.0 * coalesce(s.order_count, 0) / nullif(v.viewing_sessions, 0), 2) as view_to_order_rate_pct
from {{ ref('stg_products') }} as p
left join sales_by_product as s on s.product_id = p.product_id
left join views_by_product as v on v.product_id = p.product_id
