\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE VIEW analytics.v_daily_sales AS
WITH payment_summary AS (
    SELECT
        order_id,
        sum(amount) FILTER (WHERE payment_status IN ('succeeded', 'refunded')) AS paid_amount
    FROM shop.payments
    GROUP BY order_id
),
refund_summary AS (
    SELECT
        p.order_id,
        sum(r.amount) FILTER (WHERE r.refund_status = 'succeeded') AS refunded_amount
    FROM shop.refunds AS r
    JOIN shop.payments AS p ON p.payment_id = r.payment_id
    GROUP BY p.order_id
)
SELECT
    o.ordered_at::date AS order_date,
    o.currency,
    count(*) FILTER (WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')) AS orders_paid,
    count(*) FILTER (WHERE o.order_status = 'cancelled') AS orders_cancelled,
    count(DISTINCT o.customer_id) FILTER (WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')) AS purchasing_customers,
    round(sum(o.total_amount) FILTER (WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')), 2) AS gross_revenue,
    round(sum(coalesce(rs.refunded_amount, 0)), 2) AS refunded_amount,
    round(
        sum(o.total_amount) FILTER (WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded'))
        - sum(coalesce(rs.refunded_amount, 0)),
        2
    ) AS net_revenue,
    round(
        avg(o.total_amount) FILTER (WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')),
        2
    ) AS average_order_value,
    round(sum(coalesce(ps.paid_amount, 0)), 2) AS successful_payment_amount
FROM shop.orders AS o
LEFT JOIN payment_summary AS ps ON ps.order_id = o.order_id
LEFT JOIN refund_summary AS rs ON rs.order_id = o.order_id
GROUP BY o.ordered_at::date, o.currency;

CREATE OR REPLACE VIEW analytics.v_product_performance AS
WITH sales AS (
    SELECT
        oi.product_id,
        count(DISTINCT oi.order_id) AS order_count,
        sum(oi.quantity) AS units_sold,
        round(sum(oi.line_total), 2) AS item_revenue,
        round(sum((oi.unit_price - oi.unit_cost) * oi.quantity - oi.discount_amount), 2) AS gross_margin
    FROM shop.order_items AS oi
    JOIN shop.orders AS o ON o.order_id = oi.order_id
    WHERE o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')
    GROUP BY oi.product_id
),
views AS (
    SELECT
        product_id,
        count(*) AS product_views,
        count(DISTINCT session_id) AS viewing_sessions
    FROM shop.events
    WHERE event_type = 'product_viewed'
      AND product_id IS NOT NULL
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    c.category_name,
    p.unit_price,
    coalesce(v.product_views, 0) AS product_views,
    coalesce(v.viewing_sessions, 0) AS viewing_sessions,
    coalesce(s.order_count, 0) AS order_count,
    coalesce(s.units_sold, 0) AS units_sold,
    coalesce(s.item_revenue, 0) AS item_revenue,
    coalesce(s.gross_margin, 0) AS gross_margin,
    round(100.0 * coalesce(s.order_count, 0) / nullif(v.viewing_sessions, 0), 2) AS view_to_order_rate_pct
FROM shop.products AS p
JOIN shop.categories AS c ON c.category_id = p.category_id
LEFT JOIN sales AS s ON s.product_id = p.product_id
LEFT JOIN views AS v ON v.product_id = p.product_id;

CREATE OR REPLACE VIEW analytics.v_customer_summary AS
WITH orders AS (
    SELECT
        customer_id,
        count(*) AS all_orders,
        count(*) FILTER (WHERE order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')) AS paid_orders,
        round(sum(total_amount) FILTER (WHERE order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')), 2) AS lifetime_gross_revenue,
        min(ordered_at) AS first_order_at,
        max(ordered_at) AS last_order_at
    FROM shop.orders
    GROUP BY customer_id
),
sessions AS (
    SELECT
        customer_id,
        count(*) AS session_count,
        max(started_at) AS last_session_at
    FROM shop.web_sessions
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_key,
    c.email,
    c.first_name,
    c.last_name,
    c.country_code,
    c.acquisition_channel,
    c.signup_at,
    coalesce(o.all_orders, 0) AS all_orders,
    coalesce(o.paid_orders, 0) AS paid_orders,
    coalesce(o.lifetime_gross_revenue, 0) AS lifetime_gross_revenue,
    o.first_order_at,
    o.last_order_at,
    coalesce(s.session_count, 0) AS session_count,
    s.last_session_at,
    CASE
        WHEN coalesce(o.paid_orders, 0) >= 5 THEN 'loyal'
        WHEN coalesce(o.paid_orders, 0) >= 2 THEN 'repeat'
        WHEN coalesce(o.paid_orders, 0) = 1 THEN 'one_time'
        ELSE 'prospect'
    END AS customer_segment
FROM shop.customers AS c
LEFT JOIN orders AS o ON o.customer_id = c.customer_id
LEFT JOIN sessions AS s ON s.customer_id = c.customer_id;

CREATE OR REPLACE VIEW analytics.v_payment_health AS
SELECT
    attempted_at::date AS payment_date,
    payment_method,
    currency,
    count(*) AS payment_attempts,
    count(*) FILTER (WHERE payment_status IN ('succeeded', 'refunded')) AS successful_attempts,
    count(*) FILTER (WHERE payment_status = 'failed') AS failed_attempts,
    count(*) FILTER (WHERE payment_status = 'pending') AS pending_attempts,
    round(100.0 * count(*) FILTER (WHERE payment_status IN ('succeeded', 'refunded')) / nullif(count(*), 0), 2) AS success_rate_pct,
    round(sum(amount) FILTER (WHERE payment_status IN ('succeeded', 'refunded')), 2) AS successful_amount,
    round(sum(amount) FILTER (WHERE payment_status = 'failed'), 2) AS failed_amount
FROM shop.payments
GROUP BY attempted_at::date, payment_method, currency;

CREATE OR REPLACE VIEW analytics.v_conversion_funnel AS
WITH session_flags AS (
    SELECT
        ws.session_id,
        ws.started_at::date AS session_date,
        ws.source_channel,
        ws.device_type,
        bool_or(e.event_type = 'product_viewed') AS viewed_product,
        bool_or(e.event_type = 'added_to_cart') AS added_to_cart,
        bool_or(e.event_type = 'checkout_started') AS started_checkout,
        bool_or(e.event_type = 'payment_completed') AS completed_payment,
        bool_or(e.event_type = 'order_created') AS created_order
    FROM shop.web_sessions AS ws
    LEFT JOIN shop.events AS e ON e.session_id = ws.session_id
    GROUP BY ws.session_id, ws.started_at::date, ws.source_channel, ws.device_type
)
SELECT
    session_date,
    source_channel,
    device_type,
    count(*) AS sessions,
    count(*) FILTER (WHERE viewed_product) AS product_view_sessions,
    count(*) FILTER (WHERE added_to_cart) AS cart_sessions,
    count(*) FILTER (WHERE started_checkout) AS checkout_sessions,
    count(*) FILTER (WHERE completed_payment) AS payment_sessions,
    count(*) FILTER (WHERE created_order) AS purchasing_sessions,
    round(100.0 * count(*) FILTER (WHERE added_to_cart) / nullif(count(*) FILTER (WHERE viewed_product), 0), 2) AS view_to_cart_pct,
    round(100.0 * count(*) FILTER (WHERE started_checkout) / nullif(count(*) FILTER (WHERE added_to_cart), 0), 2) AS cart_to_checkout_pct,
    round(100.0 * count(*) FILTER (WHERE created_order) / nullif(count(*), 0), 2) AS overall_conversion_pct
FROM session_flags
GROUP BY session_date, source_channel, device_type;

CREATE OR REPLACE VIEW analytics.v_order_reconciliation AS
WITH payment_summary AS (
    SELECT
        order_id,
        sum(amount) FILTER (WHERE payment_status IN ('succeeded', 'refunded')) AS succeeded_amount,
        count(*) FILTER (WHERE payment_status IN ('succeeded', 'refunded')) AS succeeded_payments
    FROM shop.payments
    GROUP BY order_id
),
refund_summary AS (
    SELECT
        p.order_id,
        sum(r.amount) FILTER (WHERE r.refund_status = 'succeeded') AS refunded_amount
    FROM shop.refunds AS r
    JOIN shop.payments AS p ON p.payment_id = r.payment_id
    GROUP BY p.order_id
)
SELECT
    o.order_id,
    o.order_number,
    o.order_status,
    o.total_amount AS order_total,
    coalesce(ps.succeeded_amount, 0) AS succeeded_payment_amount,
    coalesce(rs.refunded_amount, 0) AS refunded_amount,
    coalesce(ps.succeeded_payments, 0) AS succeeded_payments,
    CASE
        WHEN o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded')
             AND coalesce(ps.succeeded_amount, 0) <> o.total_amount THEN 'payment_mismatch'
        WHEN o.order_status = 'refunded'
             AND coalesce(rs.refunded_amount, 0) = 0 THEN 'missing_refund'
        WHEN o.order_status IN ('created', 'pending_payment', 'cancelled')
             AND coalesce(ps.succeeded_amount, 0) > 0 THEN 'unexpected_payment'
        ELSE 'ok'
    END AS reconciliation_status
FROM shop.orders AS o
LEFT JOIN payment_summary AS ps ON ps.order_id = o.order_id
LEFT JOIN refund_summary AS rs ON rs.order_id = o.order_id;

CREATE OR REPLACE VIEW analytics.v_inventory_health AS
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    c.category_name,
    i.warehouse_code,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.quantity_on_hand - i.quantity_reserved AS quantity_available,
    i.reorder_level,
    CASE
        WHEN i.quantity_on_hand - i.quantity_reserved <= 0 THEN 'out_of_stock'
        WHEN i.quantity_on_hand - i.quantity_reserved <= i.reorder_level THEN 'reorder'
        ELSE 'healthy'
    END AS inventory_status,
    i.updated_at
FROM shop.inventory AS i
JOIN shop.products AS p ON p.product_id = i.product_id
JOIN shop.categories AS c ON c.category_id = p.category_id;

CREATE OR REPLACE VIEW analytics.v_data_freshness AS
SELECT
    'customers'::text AS source_name,
    max(updated_at) AS latest_record_at,
    now() - max(updated_at) AS data_age,
    count(*) AS row_count
FROM shop.customers
UNION ALL
SELECT 'orders', max(updated_at), now() - max(updated_at), count(*) FROM shop.orders
UNION ALL
SELECT 'payments', max(updated_at), now() - max(updated_at), count(*) FROM shop.payments
UNION ALL
SELECT 'events', max(ingested_at), now() - max(ingested_at), count(*) FROM shop.events;

COMMENT ON VIEW analytics.v_daily_sales IS 'Indicateurs quotidiens de commandes, remboursements et revenus nets.';
COMMENT ON VIEW analytics.v_product_performance IS 'Performance commerciale et comportementale par produit.';
COMMENT ON VIEW analytics.v_conversion_funnel IS 'Conversion des sessions par jour, canal et appareil.';
COMMENT ON VIEW analytics.v_order_reconciliation IS 'Contrôle entre le total des commandes, paiements réussis et remboursements.';

COMMIT;
