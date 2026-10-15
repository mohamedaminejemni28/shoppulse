\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS warehouse;

COMMENT ON SCHEMA warehouse IS 'Data Warehouse en étoile de ShopPulse.';

CREATE TABLE IF NOT EXISTS warehouse.dim_date (
    date_key integer PRIMARY KEY,
    full_date date NOT NULL UNIQUE,
    day_of_month smallint NOT NULL,
    day_name text NOT NULL,
    week_of_year smallint NOT NULL,
    month_number smallint NOT NULL,
    month_name text NOT NULL,
    quarter_number smallint NOT NULL,
    year_number smallint NOT NULL,
    is_weekend boolean NOT NULL
);

CREATE TABLE IF NOT EXISTS warehouse.dim_customer (
    customer_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id bigint NOT NULL UNIQUE,
    customer_uuid uuid NOT NULL,
    email text NOT NULL,
    full_name text NOT NULL,
    country_code char(2) NOT NULL,
    acquisition_channel text NOT NULL,
    customer_status text NOT NULL,
    signup_at timestamptz NOT NULL,
    customer_segment text NOT NULL,
    source_updated_at timestamptz NOT NULL,
    warehouse_updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.dim_product (
    product_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL UNIQUE,
    product_uuid uuid NOT NULL,
    sku text NOT NULL,
    product_name text NOT NULL,
    category_name text NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    unit_cost numeric(12, 2) NOT NULL,
    currency char(3) NOT NULL,
    is_active boolean NOT NULL,
    source_updated_at timestamptz NOT NULL,
    warehouse_updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.fact_sales (
    order_item_id bigint PRIMARY KEY,
    order_id bigint NOT NULL,
    order_number text NOT NULL,
    date_key integer NOT NULL REFERENCES warehouse.dim_date(date_key),
    customer_sk bigint NOT NULL REFERENCES warehouse.dim_customer(customer_sk),
    product_sk bigint NOT NULL REFERENCES warehouse.dim_product(product_sk),
    order_status text NOT NULL,
    source_channel text NOT NULL,
    currency char(3) NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    unit_cost numeric(12, 2) NOT NULL,
    discount_amount numeric(12, 2) NOT NULL,
    gross_amount numeric(14, 2) NOT NULL,
    net_amount numeric(14, 2) NOT NULL,
    gross_margin numeric(14, 2) NOT NULL,
    ordered_at timestamptz NOT NULL,
    warehouse_loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.fact_events (
    event_id uuid PRIMARY KEY,
    date_key integer NOT NULL REFERENCES warehouse.dim_date(date_key),
    customer_sk bigint REFERENCES warehouse.dim_customer(customer_sk),
    product_sk bigint REFERENCES warehouse.dim_product(product_sk),
    session_id uuid NOT NULL,
    order_id bigint,
    event_type text NOT NULL,
    device_type text NOT NULL,
    source_channel text NOT NULL,
    campaign_name text,
    event_time timestamptz NOT NULL,
    ingested_at timestamptz NOT NULL,
    warehouse_loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.etl_runs (
    etl_run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_name text NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz NOT NULL,
    dim_customers bigint NOT NULL,
    dim_products bigint NOT NULL,
    fact_sales bigint NOT NULL,
    fact_events bigint NOT NULL,
    status text NOT NULL CHECK (status IN ('succeeded', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_fact_sales_date ON warehouse.fact_sales(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer ON warehouse.fact_sales(customer_sk);
CREATE INDEX IF NOT EXISTS idx_fact_sales_product ON warehouse.fact_sales(product_sk);
CREATE INDEX IF NOT EXISTS idx_fact_events_date_type ON warehouse.fact_events(date_key, event_type);
CREATE INDEX IF NOT EXISTS idx_fact_events_customer ON warehouse.fact_events(customer_sk) WHERE customer_sk IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fact_events_product ON warehouse.fact_events(product_sk) WHERE product_sk IS NOT NULL;

CREATE OR REPLACE FUNCTION warehouse.refresh()
RETURNS TABLE (
    dim_customers bigint,
    dim_products bigint,
    fact_sales bigint,
    fact_events bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_started_at timestamptz := clock_timestamp();
BEGIN
    INSERT INTO warehouse.dim_date (
        date_key, full_date, day_of_month, day_name, week_of_year,
        month_number, month_name, quarter_number, year_number, is_weekend
    )
    SELECT
        to_char(d, 'YYYYMMDD')::integer,
        d,
        extract(day FROM d)::smallint,
        trim(to_char(d, 'Day')),
        extract(week FROM d)::smallint,
        extract(month FROM d)::smallint,
        trim(to_char(d, 'Month')),
        extract(quarter FROM d)::smallint,
        extract(year FROM d)::smallint,
        extract(isodow FROM d) IN (6, 7)
    FROM generate_series(
        LEAST(
            coalesce((SELECT min(ordered_at)::date FROM shop.orders), current_date),
            coalesce((SELECT min(event_time)::date FROM shop.events), current_date)
        ),
        GREATEST(
            coalesce((SELECT max(ordered_at)::date FROM shop.orders), current_date),
            coalesce((SELECT max(event_time)::date FROM shop.events), current_date),
            current_date
        ),
        interval '1 day'
    ) AS dates(d)
    ON CONFLICT (date_key) DO NOTHING;

    INSERT INTO warehouse.dim_customer (
        customer_id, customer_uuid, email, full_name, country_code,
        acquisition_channel, customer_status, signup_at, customer_segment,
        source_updated_at
    )
    SELECT
        c.customer_id,
        c.customer_key,
        lower(c.email),
        trim(c.first_name || ' ' || c.last_name),
        c.country_code,
        c.acquisition_channel,
        c.customer_status,
        c.signup_at,
        a.customer_segment,
        c.updated_at
    FROM shop.customers AS c
    JOIN analytics.v_customer_summary AS a ON a.customer_id = c.customer_id
    ON CONFLICT (customer_id) DO UPDATE SET
        customer_uuid = EXCLUDED.customer_uuid,
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name,
        country_code = EXCLUDED.country_code,
        acquisition_channel = EXCLUDED.acquisition_channel,
        customer_status = EXCLUDED.customer_status,
        signup_at = EXCLUDED.signup_at,
        customer_segment = EXCLUDED.customer_segment,
        source_updated_at = EXCLUDED.source_updated_at,
        warehouse_updated_at = now();

    INSERT INTO warehouse.dim_product (
        product_id, product_uuid, sku, product_name, category_name,
        unit_price, unit_cost, currency, is_active, source_updated_at
    )
    SELECT
        p.product_id,
        p.product_key,
        p.sku,
        trim(p.product_name),
        c.category_name,
        p.unit_price,
        p.unit_cost,
        p.currency,
        p.is_active,
        p.updated_at
    FROM shop.products AS p
    JOIN shop.categories AS c ON c.category_id = p.category_id
    ON CONFLICT (product_id) DO UPDATE SET
        product_uuid = EXCLUDED.product_uuid,
        sku = EXCLUDED.sku,
        product_name = EXCLUDED.product_name,
        category_name = EXCLUDED.category_name,
        unit_price = EXCLUDED.unit_price,
        unit_cost = EXCLUDED.unit_cost,
        currency = EXCLUDED.currency,
        is_active = EXCLUDED.is_active,
        source_updated_at = EXCLUDED.source_updated_at,
        warehouse_updated_at = now();

    INSERT INTO warehouse.fact_sales (
        order_item_id, order_id, order_number, date_key, customer_sk,
        product_sk, order_status, source_channel, currency, quantity,
        unit_price, unit_cost, discount_amount, gross_amount, net_amount,
        gross_margin, ordered_at
    )
    SELECT
        oi.order_item_id,
        o.order_id,
        o.order_number,
        to_char(o.ordered_at, 'YYYYMMDD')::integer,
        dc.customer_sk,
        dp.product_sk,
        o.order_status,
        o.source_channel,
        o.currency,
        oi.quantity,
        oi.unit_price,
        oi.unit_cost,
        oi.discount_amount,
        round(oi.unit_price * oi.quantity, 2),
        oi.line_total,
        round((oi.unit_price - oi.unit_cost) * oi.quantity - oi.discount_amount, 2),
        o.ordered_at
    FROM shop.order_items AS oi
    JOIN shop.orders AS o ON o.order_id = oi.order_id
    JOIN warehouse.dim_customer AS dc ON dc.customer_id = o.customer_id
    JOIN warehouse.dim_product AS dp ON dp.product_id = oi.product_id
    ON CONFLICT (order_item_id) DO UPDATE SET
        order_status = EXCLUDED.order_status,
        source_channel = EXCLUDED.source_channel,
        quantity = EXCLUDED.quantity,
        unit_price = EXCLUDED.unit_price,
        unit_cost = EXCLUDED.unit_cost,
        discount_amount = EXCLUDED.discount_amount,
        gross_amount = EXCLUDED.gross_amount,
        net_amount = EXCLUDED.net_amount,
        gross_margin = EXCLUDED.gross_margin,
        warehouse_loaded_at = now();

    INSERT INTO warehouse.fact_events (
        event_id, date_key, customer_sk, product_sk, session_id, order_id,
        event_type, device_type, source_channel, campaign_name,
        event_time, ingested_at
    )
    SELECT
        e.event_id,
        to_char(e.event_time, 'YYYYMMDD')::integer,
        dc.customer_sk,
        dp.product_sk,
        e.session_id,
        e.order_id,
        e.event_type,
        ws.device_type,
        ws.source_channel,
        ws.campaign_name,
        e.event_time,
        e.ingested_at
    FROM shop.events AS e
    JOIN shop.web_sessions AS ws ON ws.session_id = e.session_id
    LEFT JOIN warehouse.dim_customer AS dc ON dc.customer_id = e.customer_id
    LEFT JOIN warehouse.dim_product AS dp ON dp.product_id = e.product_id
    ON CONFLICT (event_id) DO UPDATE SET
        customer_sk = EXCLUDED.customer_sk,
        product_sk = EXCLUDED.product_sk,
        order_id = EXCLUDED.order_id,
        event_type = EXCLUDED.event_type,
        device_type = EXCLUDED.device_type,
        source_channel = EXCLUDED.source_channel,
        campaign_name = EXCLUDED.campaign_name,
        event_time = EXCLUDED.event_time,
        ingested_at = EXCLUDED.ingested_at,
        warehouse_loaded_at = now();

    SELECT count(*) INTO dim_customers FROM warehouse.dim_customer;
    SELECT count(*) INTO dim_products FROM warehouse.dim_product;
    SELECT count(*) INTO fact_sales FROM warehouse.fact_sales;
    SELECT count(*) INTO fact_events FROM warehouse.fact_events;

    INSERT INTO warehouse.etl_runs (
        pipeline_name, started_at, finished_at, dim_customers,
        dim_products, fact_sales, fact_events, status
    ) VALUES (
        'warehouse.refresh', v_started_at, clock_timestamp(), dim_customers,
        dim_products, fact_sales, fact_events, 'succeeded'
    );

    RETURN NEXT;
END;
$$;

CREATE OR REPLACE VIEW warehouse.v_sales_dashboard AS
SELECT
    d.full_date,
    p.category_name,
    s.source_channel,
    count(DISTINCT s.order_id) AS orders,
    sum(s.quantity) AS units_sold,
    round(sum(s.net_amount), 2) AS item_revenue,
    round(sum(s.gross_margin), 2) AS gross_margin
FROM warehouse.fact_sales AS s
JOIN warehouse.dim_date AS d ON d.date_key = s.date_key
JOIN warehouse.dim_product AS p ON p.product_sk = s.product_sk
WHERE s.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')
GROUP BY d.full_date, p.category_name, s.source_channel;

COMMIT;
