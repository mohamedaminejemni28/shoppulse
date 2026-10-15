\set ON_ERROR_STOP on

DO $$
DECLARE
    actual_count bigint;
    invalid_count bigint;
BEGIN
    SELECT count(*) INTO actual_count FROM shop.customers;
    IF actual_count < 100 THEN
        RAISE EXCEPTION 'Nombre de clients insuffisant : attendu au moins 100, obtenu %', actual_count;
    END IF;

    SELECT count(*) INTO actual_count FROM shop.products;
    IF actual_count < 30 THEN
        RAISE EXCEPTION 'Nombre de produits insuffisant : attendu au moins 30, obtenu %', actual_count;
    END IF;

    SELECT count(*) INTO actual_count FROM shop.orders;
    IF actual_count < 500 THEN
        RAISE EXCEPTION 'Nombre de commandes insuffisant : attendu au moins 500, obtenu %', actual_count;
    END IF;

    SELECT count(*) INTO actual_count FROM shop.web_sessions;
    IF actual_count < 800 THEN
        RAISE EXCEPTION 'Nombre de sessions insuffisant : attendu au moins 800, obtenu %', actual_count;
    END IF;

    SELECT count(*) INTO actual_count FROM shop.events;
    IF actual_count < 2800 THEN
        RAISE EXCEPTION 'Nombre d''événements insuffisant : attendu au moins 2800, obtenu %', actual_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM shop.orders AS o
    LEFT JOIN shop.order_items AS oi ON oi.order_id = o.order_id
    WHERE oi.order_id IS NULL;
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% commandes ne possèdent aucune ligne', invalid_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM shop.orders
    WHERE total_amount <> round(subtotal_amount - discount_amount + shipping_amount + tax_amount, 2);
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% commandes ont un total invalide', invalid_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM analytics.v_order_reconciliation
    WHERE reconciliation_status <> 'ok';
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% commandes ne se réconcilient pas avec les paiements/remboursements', invalid_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM shop.events AS e
    LEFT JOIN shop.web_sessions AS s ON s.session_id = e.session_id
    WHERE s.session_id IS NULL;
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% événements sont orphelins', invalid_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM (
        SELECT payment_id, amount,
               coalesce((
                   SELECT sum(r.amount)
                   FROM shop.refunds AS r
                   WHERE r.payment_id = p.payment_id
                     AND r.refund_status = 'succeeded'
               ), 0) AS refunded
        FROM shop.payments AS p
    ) AS x
    WHERE refunded > amount;
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% paiements sont remboursés au-delà de leur montant', invalid_count;
    END IF;

    SELECT count(*)
    INTO invalid_count
    FROM analytics.v_conversion_funnel
    WHERE product_view_sessions > sessions
       OR cart_sessions > product_view_sessions
       OR checkout_sessions > cart_sessions
       OR purchasing_sessions > checkout_sessions;
    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% lignes du funnel ne sont pas monotones', invalid_count;
    END IF;
END;
$$;

SELECT
    'VALIDATION RÉUSSIE' AS result,
    (SELECT count(*) FROM shop.customers) AS customers,
    (SELECT count(*) FROM shop.products) AS products,
    (SELECT count(*) FROM shop.orders) AS orders,
    (SELECT count(*) FROM shop.order_items) AS order_items,
    (SELECT count(*) FROM shop.payments) AS payments,
    (SELECT count(*) FROM shop.refunds) AS refunds,
    (SELECT count(*) FROM shop.web_sessions) AS sessions,
    (SELECT count(*) FROM shop.events) AS events;
