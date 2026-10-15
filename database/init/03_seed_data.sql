\set ON_ERROR_STOP on

BEGIN;

INSERT INTO shop.categories (category_key, category_name, slug, description)
VALUES
    (md5('category-electronics')::uuid, 'Électronique', 'electronique', 'Ordinateurs, téléphones et accessoires'),
    (md5('category-home')::uuid, 'Maison', 'maison', 'Équipement et décoration pour la maison'),
    (md5('category-fashion')::uuid, 'Mode', 'mode', 'Vêtements et accessoires'),
    (md5('category-sports')::uuid, 'Sport', 'sport', 'Équipement de sport et fitness'),
    (md5('category-books')::uuid, 'Livres', 'livres', 'Livres techniques, professionnels et loisirs'),
    (md5('category-beauty')::uuid, 'Beauté', 'beaute', 'Soins et produits de beauté');

INSERT INTO shop.products (
    product_key,
    category_id,
    sku,
    product_name,
    description,
    unit_price,
    unit_cost,
    currency,
    created_at
)
SELECT
    md5('product-' || g)::uuid,
    ((g - 1) % 6) + 1,
    'SKU-' || lpad(g::text, 4, '0'),
    (ARRAY[
        'Ordinateur portable', 'Écouteurs sans fil', 'Clavier mécanique', 'Souris ergonomique', 'Écran 27 pouces',
        'Lampe de bureau', 'Cafetière', 'Mixeur', 'Chaise de bureau', 'Rangement mural',
        'T-shirt premium', 'Sac à dos', 'Chaussures urbaines', 'Montre classique', 'Veste légère',
        'Tapis de yoga', 'Haltères', 'Ballon de football', 'Bouteille isotherme', 'Montre fitness',
        'SQL pour débutants', 'Data Engineering pratique', 'Architecture Cloud', 'Python appliqué', 'Analytics moderne',
        'Crème hydratante', 'Nettoyant visage', 'Huile capillaire', 'Parfum frais', 'Kit de soins'
    ])[g],
    'Produit de démonstration ShopPulse numéro ' || g,
    round((25 + g * 7.35 + (g % 4) * 11)::numeric, 2),
    round((14 + g * 3.20 + (g % 3) * 5)::numeric, 2),
    'USD',
    timestamptz '2025-01-01 09:00:00+01' + g * interval '1 day'
FROM generate_series(1, 30) AS g;

INSERT INTO shop.inventory (product_id, quantity_on_hand, quantity_reserved, reorder_level, warehouse_code)
SELECT
    product_id,
    60 + (product_id * 13 % 140)::integer,
    (product_id * 3 % 15)::integer,
    20 + (product_id % 10)::integer,
    CASE WHEN product_id % 3 = 0 THEN 'LAGOS-02' ELSE 'LAGOS-01' END
FROM shop.products;

INSERT INTO shop.customers (
    customer_key,
    email,
    first_name,
    last_name,
    phone,
    country_code,
    acquisition_channel,
    signup_at,
    created_at,
    updated_at
)
SELECT
    md5('customer-' || g)::uuid,
    'client' || lpad(g::text, 3, '0') || '@example.com',
    (ARRAY['Ada', 'Amara', 'Chidi', 'Fatou', 'Ibrahim', 'Kemi', 'Moussa', 'Nadia', 'Omar', 'Sarah'])[((g - 1) % 10) + 1],
    (ARRAY['Diallo', 'Okafor', 'Adeyemi', 'Mensah', 'Traoré', 'Bello', 'Nwosu', 'Camara', 'Sow', 'Diop'])[((g * 3 - 1) % 10) + 1],
    '+234800' || lpad(g::text, 4, '0'),
    (ARRAY['NG', 'GH', 'CI', 'SN', 'KE'])[((g - 1) % 5) + 1],
    (ARRAY['organic', 'paid_search', 'social', 'email', 'referral', 'direct'])[((g - 1) % 6) + 1],
    timestamptz '2025-02-01 08:00:00+01' + g * interval '2 days',
    timestamptz '2025-02-01 08:00:00+01' + g * interval '2 days',
    timestamptz '2025-02-01 08:00:00+01' + g * interval '2 days'
FROM generate_series(1, 100) AS g;

INSERT INTO shop.customer_addresses (
    customer_id,
    address_type,
    address_line_1,
    city,
    state_region,
    postal_code,
    country_code,
    is_default,
    created_at
)
SELECT
    customer_id,
    'shipping',
    (10 + customer_id)::text || ' Avenue ShopPulse',
    (ARRAY['Lagos', 'Accra', 'Abidjan', 'Dakar', 'Nairobi'])[((customer_id - 1) % 5) + 1],
    (ARRAY['Lagos', 'Greater Accra', 'Abidjan', 'Dakar', 'Nairobi County'])[((customer_id - 1) % 5) + 1],
    lpad((100000 + customer_id)::text, 6, '0'),
    country_code,
    true,
    signup_at
FROM shop.customers;

INSERT INTO shop.orders (
    order_key,
    order_number,
    customer_id,
    shipping_address_id,
    order_status,
    currency,
    source_channel,
    ordered_at,
    paid_at,
    completed_at,
    cancelled_at,
    created_at,
    updated_at
)
SELECT
    md5('order-' || g)::uuid,
    'SP-' || to_char(date '2025-06-01' + ((g - 1) % 365), 'YYYYMMDD') || '-' || lpad(g::text, 6, '0'),
    ((g - 1) % 100) + 1,
    ((g - 1) % 100) + 1,
    CASE
        WHEN g % 20 = 0 THEN 'refunded'
        WHEN g % 10 = 0 THEN 'cancelled'
        WHEN g % 14 = 0 THEN 'pending_payment'
        WHEN g % 5 = 0 THEN 'processing'
        ELSE 'completed'
    END,
    'USD',
    (ARRAY['web', 'mobile', 'web', 'web', 'marketplace'])[((g - 1) % 5) + 1],
    timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours',
    CASE
        WHEN g % 20 = 0 OR (g % 10 <> 0 AND g % 14 <> 0)
            THEN timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours' + interval '8 minutes'
        ELSE NULL
    END,
    CASE
        WHEN g % 5 <> 0 AND g % 14 <> 0
            THEN timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours' + interval '2 days'
        ELSE NULL
    END,
    CASE
        WHEN g % 10 = 0 AND g % 20 <> 0
            THEN timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours' + interval '20 minutes'
        ELSE NULL
    END,
    timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours',
    timestamptz '2025-06-01 09:00:00+01' + g * interval '8 hours'
FROM generate_series(1, 500) AS g;

INSERT INTO shop.order_items (
    order_id,
    product_id,
    product_name_snapshot,
    sku_snapshot,
    unit_price,
    unit_cost,
    quantity,
    discount_amount,
    created_at
)
SELECT
    o.order_id,
    p.product_id,
    p.product_name,
    p.sku,
    p.unit_price,
    p.unit_cost,
    1 + ((o.order_id + item_no) % 3)::integer,
    CASE
        WHEN (o.order_id + item_no) % 11 = 0
            THEN round((p.unit_price * (1 + ((o.order_id + item_no) % 3)) * 0.05)::numeric, 2)
        ELSE 0
    END,
    o.ordered_at
FROM shop.orders AS o
CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 3)::integer) AS item_no
JOIN shop.products AS p
  ON p.product_id = ((o.order_id + item_no * 7 - 1) % 30) + 1;

UPDATE shop.orders
SET
    discount_amount = CASE WHEN order_id % 9 = 0 THEN round(subtotal_amount * 0.10, 2) ELSE 0 END,
    shipping_amount = CASE WHEN subtotal_amount >= 250 THEN 0 ELSE 8.50 END;

INSERT INTO shop.payments (
    payment_key,
    order_id,
    attempt_number,
    provider_reference,
    payment_method,
    payment_status,
    amount,
    currency,
    failure_code,
    failure_message,
    attempted_at,
    processed_at,
    created_at
)
SELECT
    md5('payment-failed-' || order_id)::uuid,
    order_id,
    1,
    'PAY-FAIL-' || lpad(order_id::text, 8, '0'),
    (ARRAY['card', 'bank_transfer', 'mobile_money', 'wallet'])[((order_id - 1) % 4) + 1],
    'failed',
    total_amount,
    currency,
    CASE WHEN order_id % 2 = 0 THEN 'INSUFFICIENT_FUNDS' ELSE 'PROVIDER_TIMEOUT' END,
    CASE WHEN order_id % 2 = 0 THEN 'Solde insuffisant' ELSE 'Délai du fournisseur dépassé' END,
    ordered_at + interval '4 minutes',
    ordered_at + interval '4 minutes 20 seconds',
    ordered_at + interval '4 minutes'
FROM shop.orders
WHERE order_id % 7 = 0;

INSERT INTO shop.payments (
    payment_key,
    order_id,
    attempt_number,
    provider_reference,
    payment_method,
    payment_status,
    amount,
    currency,
    failure_code,
    failure_message,
    attempted_at,
    processed_at,
    created_at
)
SELECT
    md5('payment-primary-' || order_id)::uuid,
    order_id,
    CASE WHEN order_id % 7 = 0 THEN 2 ELSE 1 END,
    'PAY-' || lpad(order_id::text, 8, '0'),
    (ARRAY['card', 'bank_transfer', 'mobile_money', 'wallet', 'cash_on_delivery'])[((order_id - 1) % 5) + 1],
    CASE
        WHEN order_status IN ('completed', 'processing', 'paid', 'shipped', 'refunded') THEN 'succeeded'
        WHEN order_status = 'cancelled' THEN 'failed'
        ELSE 'pending'
    END,
    total_amount,
    currency,
    CASE WHEN order_status = 'cancelled' THEN 'CUSTOMER_CANCELLED' ELSE NULL END,
    CASE WHEN order_status = 'cancelled' THEN 'Paiement annulé avec la commande' ELSE NULL END,
    ordered_at + CASE WHEN order_id % 7 = 0 THEN interval '7 minutes' ELSE interval '5 minutes' END,
    CASE
        WHEN order_status = 'pending_payment' THEN NULL
        ELSE ordered_at + CASE WHEN order_id % 7 = 0 THEN interval '7 minutes 20 seconds' ELSE interval '5 minutes 20 seconds' END
    END,
    ordered_at + CASE WHEN order_id % 7 = 0 THEN interval '7 minutes' ELSE interval '5 minutes' END
FROM shop.orders;

INSERT INTO shop.refunds (
    refund_key,
    payment_id,
    provider_reference,
    refund_status,
    amount,
    reason,
    requested_at,
    processed_at,
    created_at
)
SELECT
    md5('refund-' || p.payment_id)::uuid,
    p.payment_id,
    'REF-' || lpad(p.payment_id::text, 8, '0'),
    'succeeded',
    p.amount,
    CASE WHEN p.order_id % 40 = 0 THEN 'Produit retourné' ELSE 'Demande du client' END,
    o.ordered_at + interval '4 days',
    o.ordered_at + interval '4 days 10 minutes',
    o.ordered_at + interval '4 days'
FROM shop.payments AS p
JOIN shop.orders AS o ON o.order_id = p.order_id
WHERE o.order_status = 'refunded'
  AND p.payment_status = 'succeeded';

INSERT INTO shop.web_sessions (
    session_id,
    customer_id,
    device_type,
    source_channel,
    campaign_name,
    started_at,
    ended_at,
    created_at
)
SELECT
    md5('session-' || g)::uuid,
    CASE WHEN g % 5 = 0 THEN NULL ELSE ((g - 1) % 100) + 1 END,
    (ARRAY['mobile', 'desktop', 'mobile', 'tablet'])[((g - 1) % 4) + 1],
    (ARRAY['organic', 'paid_search', 'social', 'email', 'referral', 'direct'])[((g - 1) % 6) + 1],
    CASE WHEN g % 3 = 0 THEN 'launch_week' WHEN g % 5 = 0 THEN 'retargeting' ELSE NULL END,
    timestamptz '2025-08-01 07:00:00+01' + g * interval '45 minutes',
    timestamptz '2025-08-01 07:00:00+01' + g * interval '45 minutes' + (5 + g % 28) * interval '1 minute',
    timestamptz '2025-08-01 07:00:00+01' + g * interval '45 minutes'
FROM generate_series(1, 800) AS g;

INSERT INTO shop.events (
    event_id, session_id, customer_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-session-started-' || row_number() OVER (ORDER BY started_at))::uuid,
    session_id,
    customer_id,
    'session_started',
    started_at,
    started_at + interval '3 seconds',
    jsonb_build_object('source_channel', source_channel, 'device_type', device_type)
FROM shop.web_sessions;

INSERT INTO shop.events (
    event_id, session_id, customer_id, product_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-product-viewed-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    ((s.seq * 7 - 1) % 30) + 1,
    'product_viewed',
    s.started_at + interval '45 seconds',
    s.started_at + interval '50 seconds',
    jsonb_build_object('page', '/products/' || (((s.seq * 7 - 1) % 30) + 1), 'position', 1 + s.seq % 8)
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
WHERE s.seq <= 700;

INSERT INTO shop.events (
    event_id, session_id, customer_id, product_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-cart-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    ((s.seq * 7 - 1) % 30) + 1,
    'added_to_cart',
    s.started_at + interval '2 minutes',
    s.started_at + interval '2 minutes 5 seconds',
    jsonb_build_object('quantity', 1 + s.seq % 3)
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
WHERE s.seq <= 380;

INSERT INTO shop.events (
    event_id, session_id, customer_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-checkout-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    'checkout_started',
    s.started_at + interval '4 minutes',
    s.started_at + interval '4 minutes 4 seconds',
    jsonb_build_object('step', 'payment')
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
WHERE s.seq <= 250;

INSERT INTO shop.events (
    event_id, session_id, customer_id, order_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-payment-failed-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    s.seq,
    'payment_failed',
    s.started_at + interval '5 minutes',
    s.started_at + interval '5 minutes 3 seconds',
    jsonb_build_object('failure_code', 'PROVIDER_TIMEOUT')
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
WHERE s.seq <= 250
  AND s.seq % 7 = 0;

INSERT INTO shop.events (
    event_id, session_id, customer_id, order_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-payment-completed-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    o.order_id,
    'payment_completed',
    s.started_at + interval '7 minutes',
    s.started_at + interval '7 minutes 3 seconds',
    jsonb_build_object('amount', o.total_amount, 'currency', o.currency)
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
JOIN shop.orders AS o ON o.order_id = s.seq
WHERE s.seq <= 190
  AND o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded');

INSERT INTO shop.events (
    event_id, session_id, customer_id, order_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-order-created-' || s.seq)::uuid,
    s.session_id,
    s.customer_id,
    o.order_id,
    'order_created',
    s.started_at + interval '7 minutes 15 seconds',
    s.started_at + interval '7 minutes 18 seconds',
    jsonb_build_object('order_number', o.order_number)
FROM (
    SELECT ws.*, row_number() OVER (ORDER BY started_at)::integer AS seq
    FROM shop.web_sessions AS ws
) AS s
JOIN shop.orders AS o ON o.order_id = s.seq
WHERE s.seq <= 190
  AND o.order_status IN ('paid', 'processing', 'shipped', 'completed', 'refunded');

INSERT INTO shop.events (
    event_id, session_id, customer_id, event_type, event_time, ingested_at, event_payload
)
SELECT
    md5('event-session-ended-' || row_number() OVER (ORDER BY started_at))::uuid,
    session_id,
    customer_id,
    'session_ended',
    ended_at,
    ended_at + interval '3 seconds',
    jsonb_build_object('duration_seconds', extract(epoch FROM ended_at - started_at)::integer)
FROM shop.web_sessions;

INSERT INTO meta.pipeline_runs (
    pipeline_run_id,
    pipeline_name,
    run_status,
    started_at,
    finished_at,
    rows_read,
    rows_written,
    rows_rejected,
    run_parameters
)
VALUES
    (md5('seed-customers-run')::uuid, 'seed_customers', 'succeeded', timestamptz '2025-02-01 07:58:00+01', timestamptz '2025-02-01 08:00:05+01', 100, 100, 0, '{"source":"generator","seed":42}'),
    (md5('seed-orders-run')::uuid, 'seed_orders', 'succeeded', timestamptz '2025-06-01 08:55:00+01', timestamptz '2025-06-01 09:00:20+01', 500, 500, 0, '{"source":"generator","seed":42}'),
    (md5('seed-events-run')::uuid, 'seed_events', 'succeeded', timestamptz '2025-08-01 06:55:00+01', timestamptz '2025-08-01 07:00:30+01', 3303, 3303, 0, '{"source":"generator","seed":42}');

INSERT INTO meta.ingestion_watermarks (source_name, last_processed_at, last_source_id)
VALUES
    ('postgres_customers', (SELECT max(updated_at) FROM shop.customers), (SELECT max(customer_id)::text FROM shop.customers)),
    ('postgres_orders', (SELECT max(updated_at) FROM shop.orders), (SELECT max(order_id)::text FROM shop.orders)),
    ('kafka_events',
     (SELECT max(ingested_at) FROM shop.events),
     (SELECT event_id::text
        FROM shop.events
       ORDER BY ingested_at DESC, event_id DESC
       LIMIT 1));

COMMIT;
