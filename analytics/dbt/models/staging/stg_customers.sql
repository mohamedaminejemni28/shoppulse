select
    customer_id,
    customer_key,
    lower(trim(email)) as email,
    trim(first_name) as first_name,
    trim(last_name) as last_name,
    trim(first_name || ' ' || last_name) as full_name,
    upper(country_code) as country_code,
    acquisition_channel,
    customer_status,
    signup_at,
    updated_at
from {{ source('shop', 'customers') }}
