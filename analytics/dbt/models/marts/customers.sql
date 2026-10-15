with sales_by_customer as (
    select
        customer_id,
        count(distinct order_id) as order_count,
        sum(net_amount) as lifetime_revenue,
        sum(gross_margin) as lifetime_margin,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date
    from {{ ref('sales') }}
    where order_status in ('paid', 'processing', 'shipped', 'completed', 'refunded')
    group by customer_id
),
events_by_customer as (
    select
        customer_id,
        count(*) as event_count,
        max(event_time) as last_event_at
    from {{ ref('stg_events') }}
    where customer_id is not null
    group by customer_id
)
select
    c.customer_id,
    c.email,
    c.full_name,
    c.country_code,
    c.acquisition_channel,
    c.customer_status,
    c.signup_at,
    coalesce(s.order_count, 0) as order_count,
    coalesce(s.lifetime_revenue, 0) as lifetime_revenue,
    coalesce(s.lifetime_margin, 0) as lifetime_margin,
    s.first_order_date,
    s.last_order_date,
    coalesce(e.event_count, 0) as event_count,
    e.last_event_at,
    case
        when coalesce(s.order_count, 0) >= 5 then 'loyal'
        when coalesce(s.order_count, 0) >= 2 then 'repeat'
        when coalesce(s.order_count, 0) = 1 then 'one_time'
        else 'prospect'
    end as customer_segment
from {{ ref('stg_customers') }} as c
left join sales_by_customer as s on s.customer_id = c.customer_id
left join events_by_customer as e on e.customer_id = c.customer_id
