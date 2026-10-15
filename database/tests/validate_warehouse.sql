\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'warehouse') THEN
        RAISE EXCEPTION 'Le schéma warehouse est absent';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM warehouse.fact_sales AS f
        LEFT JOIN warehouse.dim_date AS d ON d.date_key = f.date_key
        LEFT JOIN warehouse.dim_customer AS c ON c.customer_sk = f.customer_sk
        LEFT JOIN warehouse.dim_product AS p ON p.product_sk = f.product_sk
        WHERE d.date_key IS NULL OR c.customer_sk IS NULL OR p.product_sk IS NULL
    ) THEN
        RAISE EXCEPTION 'Une clé étrangère du fait des ventes est orpheline';
    END IF;
END;
$$;

SELECT
    'WAREHOUSE VALIDÉ' AS result,
    (SELECT count(*) FROM warehouse.dim_date) AS dates,
    (SELECT count(*) FROM warehouse.dim_customer) AS customers,
    (SELECT count(*) FROM warehouse.dim_product) AS products,
    (SELECT count(*) FROM warehouse.fact_sales) AS sales,
    (SELECT count(*) FROM warehouse.fact_events) AS events;
