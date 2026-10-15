select
    p.product_id,
    p.product_key,
    p.category_id,
    c.category_name,
    upper(trim(p.sku)) as sku,
    trim(p.product_name) as product_name,
    p.unit_price,
    p.unit_cost,
    p.unit_price - p.unit_cost as unit_margin,
    upper(p.currency) as currency,
    p.is_active,
    p.updated_at
from {{ source('shop', 'products') }} as p
join {{ source('shop', 'categories') }} as c
    on c.category_id = p.category_id
