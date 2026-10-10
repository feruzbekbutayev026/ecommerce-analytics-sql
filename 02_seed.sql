-- =====================================================================
-- Synthetic, reproducible seed data (≈ 2k customers, 15k orders, 75k events)
-- =====================================================================
SET search_path TO shop;
SELECT setseed(0.42);

INSERT INTO categories (name, parent_id) VALUES
  ('Electronics', NULL), ('Home', NULL), ('Fashion', NULL);
INSERT INTO categories (name, parent_id) VALUES
  ('Phones', 1), ('Laptops', 1), ('Audio', 1),
  ('Kitchen', 2), ('Furniture', 2),
  ('Men', 3), ('Women', 3);

INSERT INTO products (category_id, sku, name, unit_price, unit_cost)
SELECT c,
       'SKU-' || lpad(g::text, 5, '0'),
       'Product ' || g,
       p,
       round(p * (0.45 + random() * 0.35)::numeric, 2)
FROM generate_series(1, 200) g,
     LATERAL (SELECT 4 + (g % 7) AS c, round((5 + random() * 995)::numeric, 2) AS p) x;

INSERT INTO customers (email, full_name, country, signup_date)
SELECT 'user' || g || '@example.com',
       'Customer ' || g,
       (ARRAY['UZ','KZ','US','DE','TR','GB','AE'])[1 + floor(random() * 7)::int],
       DATE '2025-01-01' + floor(random() * 540)::int
FROM generate_series(1, 2000) g;

INSERT INTO orders (customer_id, status, ordered_at)
SELECT c.customer_id,
       (ARRAY['paid','shipped','delivered','delivered','delivered','cancelled','refunded']::order_status[])[1 + floor(random() * 7)::int],
       c.signup_date + (random() * (DATE '2026-09-30' - c.signup_date)) * INTERVAL '1 day'
FROM (SELECT customer_id, signup_date, 1 + floor(random() * 14)::int AS n_orders FROM customers) c
CROSS JOIN LATERAL generate_series(1, c.n_orders) n;

UPDATE orders
SET shipped_at = ordered_at + (1 + random() * 5) * INTERVAL '1 day'
WHERE status IN ('shipped','delivered');

INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount)
SELECT DISTINCT ON (l.order_id, p.product_id)
       l.order_id, p.product_id,
       1 + floor(random() * 3)::int,
       p.unit_price,
       (ARRAY[0,0,0,0.05,0.1,0.2])[1 + floor(random() * 6)::int]
FROM (
    SELECT o.order_id, 1 + floor(random() * 200)::bigint AS pid
    FROM (SELECT order_id, 1 + floor(random() * 4)::int AS n_lines FROM orders) o
    CROSS JOIN LATERAL generate_series(1, o.n_lines) n
) l
JOIN products p ON p.product_id = l.pid;

-- Funnel events: each session drops off at a random stage
INSERT INTO web_events (customer_id, session_id, product_id, event, occurred_at)
SELECT s.customer_id, s.session_id, s.product_id, e.ev,
       s.started + (e.idx * INTERVAL '2 minutes')
FROM (
    SELECT 1 + floor(random() * 2000)::bigint AS customer_id,
           gen_random_uuid()                  AS session_id,
           1 + floor(random() * 200)::bigint  AS product_id,
           TIMESTAMPTZ '2025-06-01' + random() * INTERVAL '480 days' AS started,
           1 + floor(power(random(), 2.2) * 4)::int AS depth
    FROM generate_series(1, 40000)
) s
CROSS JOIN LATERAL unnest(ARRAY['view','add_to_cart','checkout','purchase']::event_type[])
           WITH ORDINALITY AS e(ev, idx)
WHERE e.idx <= s.depth;

ANALYZE;
