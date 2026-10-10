-- =====================================================================
-- E-Commerce Analytics — Schema
-- PostgreSQL 14+
-- =====================================================================
DROP SCHEMA IF EXISTS shop CASCADE;
CREATE SCHEMA shop;
SET search_path TO shop;

CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE event_type   AS ENUM ('view', 'add_to_cart', 'checkout', 'purchase');

CREATE TABLE customers (
    customer_id   BIGSERIAL PRIMARY KEY,
    email         TEXT        NOT NULL UNIQUE CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    full_name     TEXT        NOT NULL,
    country       CHAR(2)     NOT NULL,
    signup_date   DATE        NOT NULL DEFAULT CURRENT_DATE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
    category_id   SERIAL PRIMARY KEY,
    parent_id     INT REFERENCES categories(category_id) ON DELETE SET NULL,
    name          TEXT NOT NULL UNIQUE
);

CREATE TABLE products (
    product_id    BIGSERIAL PRIMARY KEY,
    category_id   INT           NOT NULL REFERENCES categories(category_id),
    sku           TEXT          NOT NULL UNIQUE,
    name          TEXT          NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    unit_cost     NUMERIC(10,2) NOT NULL CHECK (unit_cost >= 0),
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT price_above_cost CHECK (unit_price >= unit_cost)
);

CREATE TABLE orders (
    order_id      BIGSERIAL PRIMARY KEY,
    customer_id   BIGINT       NOT NULL REFERENCES customers(customer_id),
    status        order_status NOT NULL DEFAULT 'pending',
    ordered_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    shipped_at    TIMESTAMPTZ,
    CONSTRAINT shipped_after_order CHECK (shipped_at IS NULL OR shipped_at >= ordered_at)
);

CREATE TABLE order_items (
    order_id      BIGINT        NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id    BIGINT        NOT NULL REFERENCES products(product_id),
    quantity      INT           NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL,          -- price snapshot at purchase time
    discount      NUMERIC(4,3)  NOT NULL DEFAULT 0 CHECK (discount BETWEEN 0 AND 0.9),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE web_events (
    event_id      BIGSERIAL PRIMARY KEY,
    customer_id   BIGINT     REFERENCES customers(customer_id),
    session_id    UUID       NOT NULL,
    product_id    BIGINT     REFERENCES products(product_id),
    event         event_type NOT NULL,
    occurred_at   TIMESTAMPTZ NOT NULL
);

-- Indexes tuned for the analytics queries
CREATE INDEX idx_orders_customer_time ON orders (customer_id, ordered_at);
CREATE INDEX idx_orders_status_paid   ON orders (ordered_at) WHERE status IN ('paid','shipped','delivered');
CREATE INDEX idx_items_product        ON order_items (product_id);
CREATE INDEX idx_events_session       ON web_events (session_id, occurred_at);
CREATE INDEX idx_events_time_brin     ON web_events USING BRIN (occurred_at);
