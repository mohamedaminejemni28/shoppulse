-- 1. Chiffre d'affaires quotidien net
SELECT
    order_date,
    orders_paid,
    purchasing_customers,
    gross_revenue,
    refunded_amount,
    net_revenue,
    average_order_value
FROM analytics.v_daily_sales
ORDER BY order_date DESC;

-- 2. Dix produits qui génèrent le plus de revenu
SELECT
    sku,
    product_name,
    category_name,
    units_sold,
    item_revenue,
    gross_margin,
    view_to_order_rate_pct
FROM analytics.v_product_performance
ORDER BY item_revenue DESC
LIMIT 10;

-- 3. Produits très consultés mais peu convertis
SELECT
    sku,
    product_name,
    product_views,
    order_count,
    view_to_order_rate_pct
FROM analytics.v_product_performance
WHERE product_views >= 10
ORDER BY view_to_order_rate_pct ASC NULLS FIRST, product_views DESC
LIMIT 10;

-- 4. Funnel global de conversion
SELECT
    sum(sessions) AS sessions,
    sum(product_view_sessions) AS product_view_sessions,
    sum(cart_sessions) AS cart_sessions,
    sum(checkout_sessions) AS checkout_sessions,
    sum(purchasing_sessions) AS purchasing_sessions,
    round(100.0 * sum(purchasing_sessions) / nullif(sum(sessions), 0), 2) AS conversion_pct
FROM analytics.v_conversion_funnel;

-- 5. Conversion par canal d'acquisition
SELECT
    source_channel,
    sum(sessions) AS sessions,
    sum(purchasing_sessions) AS purchases,
    round(100.0 * sum(purchasing_sessions) / nullif(sum(sessions), 0), 2) AS conversion_pct
FROM analytics.v_conversion_funnel
GROUP BY source_channel
ORDER BY conversion_pct DESC NULLS LAST;

-- 6. Santé des paiements
SELECT
    payment_method,
    sum(payment_attempts) AS attempts,
    sum(successful_attempts) AS successes,
    sum(failed_attempts) AS failures,
    round(100.0 * sum(successful_attempts) / nullif(sum(payment_attempts), 0), 2) AS success_rate_pct
FROM analytics.v_payment_health
GROUP BY payment_method
ORDER BY success_rate_pct DESC;

-- 7. Clients les plus précieux
SELECT
    customer_id,
    first_name,
    last_name,
    country_code,
    paid_orders,
    lifetime_gross_revenue,
    customer_segment
FROM analytics.v_customer_summary
ORDER BY lifetime_gross_revenue DESC
LIMIT 20;

-- 8. Produits à réapprovisionner
SELECT
    sku,
    product_name,
    warehouse_code,
    quantity_available,
    reorder_level,
    inventory_status
FROM analytics.v_inventory_health
WHERE inventory_status <> 'healthy'
ORDER BY quantity_available;

-- 9. Contrôle financier : cette requête doit renvoyer zéro ligne
SELECT *
FROM analytics.v_order_reconciliation
WHERE reconciliation_status <> 'ok';

-- 10. Fraîcheur et volumes des sources
SELECT *
FROM analytics.v_data_freshness
ORDER BY source_name;

