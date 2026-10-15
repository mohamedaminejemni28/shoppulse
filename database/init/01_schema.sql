\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE shop.customers (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    email text NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    phone text,
    country_code char(2) NOT NULL DEFAULT 'NG',
    acquisition_channel text NOT NULL,
    customer_status text NOT NULL DEFAULT 'active',
    signup_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customers_email_unique UNIQUE (email),
    CONSTRAINT customers_email_format CHECK (email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
    --amine        @    gmail    .    com
 --  ↑              ↑              ↑
 --utilisateur     domaine       extension

    CONSTRAINT customers_country_upper CHECK (country_code = upper(country_code)),
    CONSTRAINT customers_channel_check CHECK (acquisition_channel IN ('organic', 'paid_search', 'social', 'email', 'referral', 'direct')),
    CONSTRAINT customers_status_check CHECK (customer_status IN ('active', 'inactive', 'blocked'))
);


CREATE TABLE shop.customer_addresses (
    address_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES shop.customers(customer_id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping',
    address_line_1 text NOT NULL,
    address_line_2 text,
    city text NOT NULL,
    state_region text,
    postal_code text,
    country_code char(2) NOT NULL DEFAULT 'NG',
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customer_addresses_type_check CHECK (address_type IN ('shipping', 'billing')),
    CONSTRAINT customer_addresses_country_upper CHECK (country_code = upper(country_code))
);

CREATE TABLE shop.categories (
    category_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    category_name text NOT NULL UNIQUE,
    slug text NOT NULL UNIQUE,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT categories_slug_format CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

CREATE TABLE shop.products (
    product_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    category_id bigint NOT NULL REFERENCES shop.categories(category_id),
    sku text NOT NULL UNIQUE,
    product_name text NOT NULL,
    description text,
    unit_price numeric(12, 2) NOT NULL,
    unit_cost numeric(12, 2) NOT NULL,
    currency char(3) NOT NULL DEFAULT 'USD',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT products_price_nonnegative CHECK (unit_price >= 0),
    CONSTRAINT products_cost_nonnegative CHECK (unit_cost >= 0),
    CONSTRAINT products_price_above_cost CHECK (unit_price >= unit_cost),
    CONSTRAINT products_currency_upper CHECK (currency = upper(currency))
);

CREATE TABLE shop.inventory (
    product_id bigint PRIMARY KEY REFERENCES shop.products(product_id) ON DELETE CASCADE,
    quantity_on_hand integer NOT NULL DEFAULT 0,
    quantity_reserved integer NOT NULL DEFAULT 0,
    reorder_level integer NOT NULL DEFAULT 10,
    warehouse_code text NOT NULL DEFAULT 'MAIN',
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_on_hand_nonnegative CHECK (quantity_on_hand >= 0),
    CONSTRAINT inventory_reserved_nonnegative CHECK (quantity_reserved >= 0),
    CONSTRAINT inventory_reserved_available CHECK (quantity_reserved <= quantity_on_hand),
    CONSTRAINT inventory_reorder_nonnegative CHECK (reorder_level >= 0)
);

CREATE TABLE shop.orders (
    order_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    order_number text NOT NULL UNIQUE,
    customer_id bigint NOT NULL REFERENCES shop.customers(customer_id),
    shipping_address_id bigint REFERENCES shop.customer_addresses(address_id),
    order_status text NOT NULL DEFAULT 'created',
    currency char(3) NOT NULL DEFAULT 'USD',
    subtotal_amount numeric(12, 2) NOT NULL DEFAULT 0,
    discount_amount numeric(12, 2) NOT NULL DEFAULT 0,
    shipping_amount numeric(12, 2) NOT NULL DEFAULT 0,
    tax_amount numeric(12, 2) NOT NULL DEFAULT 0,
    total_amount numeric(12, 2) NOT NULL DEFAULT 0,
    source_channel text NOT NULL DEFAULT 'web',
    ordered_at timestamptz NOT NULL DEFAULT now(),
    paid_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT orders_status_check CHECK (order_status IN ('created', 'pending_payment', 'paid', 'processing', 'shipped', 'completed', 'cancelled', 'refunded')),
    CONSTRAINT orders_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT orders_amounts_nonnegative CHECK (
        subtotal_amount >= 0
        AND discount_amount >= 0
        AND shipping_amount >= 0
        AND tax_amount >= 0
        AND total_amount >= 0
    ),
    CONSTRAINT orders_discount_not_excessive CHECK (discount_amount <= subtotal_amount),
    CONSTRAINT orders_total_formula CHECK (
        total_amount = round(subtotal_amount - discount_amount + shipping_amount + tax_amount, 2)
    ),
    CONSTRAINT orders_source_channel_check CHECK (source_channel IN ('web', 'mobile', 'marketplace', 'support'))
);

CREATE TABLE shop.order_items (
    order_item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id bigint NOT NULL REFERENCES shop.orders(order_id) ON DELETE CASCADE,
    product_id bigint NOT NULL REFERENCES shop.products(product_id),
    product_name_snapshot text NOT NULL,
    sku_snapshot text NOT NULL,
    unit_price numeric(12, 2) NOT NULL,
    unit_cost numeric(12, 2) NOT NULL,
    quantity integer NOT NULL,
    discount_amount numeric(12, 2) NOT NULL DEFAULT 0,
    line_total numeric(12, 2) GENERATED ALWAYS AS (round((unit_price * quantity) - discount_amount, 2)) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT order_items_order_product_unique UNIQUE (order_id, product_id),
    CONSTRAINT order_items_price_nonnegative CHECK (unit_price >= 0),
    CONSTRAINT order_items_cost_nonnegative CHECK (unit_cost >= 0),
    CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT order_items_discount_nonnegative CHECK (discount_amount >= 0),
    CONSTRAINT order_items_discount_limit CHECK (discount_amount <= unit_price * quantity)
);

CREATE TABLE shop.payments (
    payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    order_id bigint NOT NULL REFERENCES shop.orders(order_id),
    attempt_number smallint NOT NULL DEFAULT 1,
    provider_reference text NOT NULL UNIQUE,
    payment_method text NOT NULL,
    payment_status text NOT NULL,
    amount numeric(12, 2) NOT NULL,
    currency char(3) NOT NULL DEFAULT 'USD',
    failure_code text,
    failure_message text,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payments_order_attempt_unique UNIQUE (order_id, attempt_number),
    CONSTRAINT payments_method_check CHECK (payment_method IN ('card', 'bank_transfer', 'mobile_money', 'wallet', 'cash_on_delivery')),
    CONSTRAINT payments_status_check CHECK (payment_status IN ('pending', 'authorized', 'succeeded', 'failed', 'cancelled', 'refunded')),
    CONSTRAINT payments_amount_positive CHECK (amount > 0),
    CONSTRAINT payments_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT payments_failure_details_check CHECK (
        payment_status = 'failed' OR (failure_code IS NULL AND failure_message IS NULL)
    )
);

CREATE TABLE shop.refunds (
    refund_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    refund_key uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    payment_id bigint NOT NULL REFERENCES shop.payments(payment_id),
    provider_reference text NOT NULL UNIQUE,
    refund_status text NOT NULL DEFAULT 'pending',
    amount numeric(12, 2) NOT NULL,
    reason text NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT refunds_status_check CHECK (refund_status IN ('pending', 'succeeded', 'failed', 'cancelled')),
    CONSTRAINT refunds_amount_positive CHECK (amount > 0)
);

CREATE TABLE shop.web_sessions (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id bigint REFERENCES shop.customers(customer_id) ON DELETE SET NULL,
    device_type text NOT NULL,
    source_channel text NOT NULL,
    campaign_name text,
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT web_sessions_device_check CHECK (device_type IN ('desktop', 'mobile', 'tablet')),
    CONSTRAINT web_sessions_channel_check CHECK (source_channel IN ('organic', 'paid_search', 'social', 'email', 'referral', 'direct')),
    CONSTRAINT web_sessions_time_check CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE shop.events (
    event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES shop.web_sessions(session_id) ON DELETE CASCADE,
    customer_id bigint REFERENCES shop.customers(customer_id) ON DELETE SET NULL,
    product_id bigint REFERENCES shop.products(product_id) ON DELETE SET NULL,
    order_id bigint REFERENCES shop.orders(order_id) ON DELETE SET NULL,
    event_type text NOT NULL,
    event_time timestamptz NOT NULL,
    ingested_at timestamptz NOT NULL DEFAULT now(),
    schema_version smallint NOT NULL DEFAULT 1,
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT events_type_check CHECK (event_type IN (
        'session_started',
        'product_searched',
        'product_viewed',
        'added_to_cart',
        'removed_from_cart',
        'checkout_started',
        'payment_failed',
        'payment_completed',
        'order_created',
        'session_ended'
    )),
    CONSTRAINT events_schema_version_positive CHECK (schema_version > 0),
    CONSTRAINT events_ingestion_time_check CHECK (ingested_at >= event_time - interval '5 minutes')
);

CREATE TABLE shop.order_status_history (
    history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id bigint NOT NULL REFERENCES shop.orders(order_id) ON DELETE CASCADE,
    previous_status text,
    new_status text NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now(),
    change_source text NOT NULL DEFAULT 'database'
);

CREATE TABLE meta.pipeline_runs (
    pipeline_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_name text NOT NULL,
    run_status text NOT NULL DEFAULT 'running',
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    rows_read bigint NOT NULL DEFAULT 0,
    rows_written bigint NOT NULL DEFAULT 0,
    rows_rejected bigint NOT NULL DEFAULT 0,
    error_message text,
    run_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pipeline_runs_status_check CHECK (run_status IN ('running', 'succeeded', 'failed', 'cancelled')),
    CONSTRAINT pipeline_runs_counts_nonnegative CHECK (rows_read >= 0 AND rows_written >= 0 AND rows_rejected >= 0),
    CONSTRAINT pipeline_runs_time_check CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE meta.ingestion_watermarks (
    source_name text PRIMARY KEY,
    last_processed_at timestamptz NOT NULL,
    last_source_id text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_customers_signup_at ON shop.customers (signup_at);
CREATE INDEX idx_customers_channel ON shop.customers (acquisition_channel);
CREATE INDEX idx_addresses_customer ON shop.customer_addresses (customer_id);
CREATE UNIQUE INDEX idx_default_address_per_type ON shop.customer_addresses (customer_id, address_type) WHERE is_default;
CREATE INDEX idx_products_category_active ON shop.products (category_id, is_active);
CREATE INDEX idx_products_name_search ON shop.products USING gin (to_tsvector('simple', product_name));
CREATE INDEX idx_orders_customer_ordered ON shop.orders (customer_id, ordered_at DESC);
CREATE INDEX idx_orders_status_ordered ON shop.orders (order_status, ordered_at DESC);
CREATE INDEX idx_orders_updated_at ON shop.orders (updated_at);
CREATE INDEX idx_order_items_product ON shop.order_items (product_id);
CREATE INDEX idx_payments_order_status ON shop.payments (order_id, payment_status);
CREATE INDEX idx_payments_attempted_at ON shop.payments (attempted_at);
CREATE INDEX idx_refunds_payment ON shop.refunds (payment_id);
CREATE INDEX idx_sessions_customer_started ON shop.web_sessions (customer_id, started_at DESC);
CREATE INDEX idx_sessions_started ON shop.web_sessions (started_at);
CREATE INDEX idx_events_session_time ON shop.events (session_id, event_time);
CREATE INDEX idx_events_type_time ON shop.events (event_type, event_time DESC);
CREATE INDEX idx_events_customer_time ON shop.events (customer_id, event_time DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_events_product_time ON shop.events (product_id, event_time DESC) WHERE product_id IS NOT NULL;
CREATE INDEX idx_events_payload ON shop.events USING gin (event_payload);
CREATE INDEX idx_pipeline_runs_name_started ON meta.pipeline_runs (pipeline_name, started_at DESC);

COMMENT ON TABLE shop.orders IS 'Une ligne représente une commande client.';
COMMENT ON TABLE shop.order_items IS 'Une ligne représente un produit dans une commande.';
COMMENT ON TABLE shop.payments IS 'Une ligne représente une tentative de paiement.';
COMMENT ON TABLE shop.web_sessions IS 'Une ligne représente une visite du site ou de l''application.';
COMMENT ON TABLE shop.events IS 'Une ligne représente un événement comportemental immuable.';

COMMIT;

