-- =====================================================================
-- Advanced analytics queries
-- =====================================================================
SET search_path TO shop;

-- ---------------------------------------------------------------------
-- Reusable view: one row per order line with revenue and margin
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_sales AS
SELECT o.order_id,
       o.customer_id,
       o.ordered_at,
       date_trunc('month', o.ordered_at)::date                 AS order_month,
       oi.product_id,
       p.category_id,
       oi.quantity,
       round(oi.quantity * oi.unit_price * (1 - oi.discount), 2) AS revenue,
       round(oi.quantity * (oi.unit_price * (1 - oi.discount) - p.unit_cost), 2) AS margin
FROM orders o
JOIN order_items oi USING (order_id)
JOIN products p     USING (product_id)
WHERE o.status IN ('paid', 'shipped', 'delivered');

-- ---------------------------------------------------------------------
-- 1. Monthly revenue with MoM growth and 3-month moving average
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT order_month, sum(revenue) AS revenue, count(DISTINCT order_id) AS orders
    FROM v_sales GROUP BY order_month
)
SELECT order_month,
       revenue,
       orders,
       round(revenue / orders, 2)                                              AS aov,
       round(100.0 * (revenue / lag(revenue) OVER w - 1), 1)                   AS mom_growth_pct,
       round(avg(revenue) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma_3m,
       sum(revenue) OVER (PARTITION BY date_trunc('year', order_month) ORDER BY order_month) AS ytd_revenue
FROM monthly
WINDOW w AS (ORDER BY order_month)
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- 2. Monthly cohort retention matrix (% of cohort active in month N)
-- ---------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_id, min(order_month) AS cohort
    FROM v_sales GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT s.customer_id, f.cohort,
           (extract(year  FROM age(s.order_month, f.cohort)) * 12 +
            extract(month FROM age(s.order_month, f.cohort)))::int AS month_n
    FROM v_sales s JOIN first_purchase f USING (customer_id)
),
cohort_size AS (
    SELECT cohort, count(*) AS size FROM first_purchase GROUP BY cohort
)
SELECT a.cohort,
       c.size,
       round(100.0 * count(*) FILTER (WHERE month_n = 1) / c.size, 1) AS m1,
       round(100.0 * count(*) FILTER (WHERE month_n = 2) / c.size, 1) AS m2,
       round(100.0 * count(*) FILTER (WHERE month_n = 3) / c.size, 1) AS m3,
       round(100.0 * count(*) FILTER (WHERE month_n = 6) / c.size, 1) AS m6
FROM activity a JOIN cohort_size c USING (cohort)
GROUP BY a.cohort, c.size
ORDER BY a.cohort;

-- ---------------------------------------------------------------------
-- 3. RFM segmentation with NTILE quintiles
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_rfm AS
WITH base AS (
    SELECT customer_id,
           (DATE '2026-10-01' - max(ordered_at)::date) AS recency_days,
           count(DISTINCT order_id)                     AS frequency,
           sum(revenue)                                 AS monetary
    FROM v_sales GROUP BY customer_id
),
scored AS (
    SELECT *,
           ntile(5) OVER (ORDER BY recency_days DESC) AS r,
           ntile(5) OVER (ORDER BY frequency)         AS f,
           ntile(5) OVER (ORDER BY monetary)          AS m
    FROM base
)
SELECT *,
       CASE
         WHEN r >= 4 AND f >= 4 AND m >= 4 THEN 'Champions'
         WHEN r >= 3 AND f >= 3            THEN 'Loyal'
         WHEN r >= 4 AND f <= 2            THEN 'New / Promising'
         WHEN r <= 2 AND f >= 4            THEN 'At Risk'
         WHEN r <= 2 AND f <= 2            THEN 'Hibernating'
         ELSE 'Needs Attention'
       END AS segment
FROM scored;

SELECT segment,
       count(*)                          AS customers,
       round(avg(recency_days))          AS avg_recency_days,
       round(avg(frequency), 1)          AS avg_orders,
       round(sum(monetary), 2)           AS total_revenue,
       round(100.0 * sum(monetary) / sum(sum(monetary)) OVER (), 1) AS revenue_share_pct
FROM v_rfm
GROUP BY segment
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------
-- 4. Conversion funnel with stage-to-stage drop-off
-- ---------------------------------------------------------------------
WITH sessions AS (
    SELECT session_id,
           bool_or(event = 'view')        AS viewed,
           bool_or(event = 'add_to_cart') AS carted,
           bool_or(event = 'checkout')    AS checked_out,
           bool_or(event = 'purchase')    AS purchased
    FROM web_events GROUP BY session_id
),
stages AS (
    SELECT 1 AS step, 'view' AS stage,      count(*) FILTER (WHERE viewed)      AS sessions FROM sessions
    UNION ALL SELECT 2, 'add_to_cart',      count(*) FILTER (WHERE carted)      FROM sessions
    UNION ALL SELECT 3, 'checkout',         count(*) FILTER (WHERE checked_out) FROM sessions
    UNION ALL SELECT 4, 'purchase',         count(*) FILTER (WHERE purchased)   FROM sessions
)
SELECT step, stage, sessions,
       round(100.0 * sessions / first_value(sessions) OVER (ORDER BY step), 1) AS pct_of_top,
       round(100.0 * sessions / lag(sessions) OVER (ORDER BY step), 1)         AS step_conversion_pct
FROM stages ORDER BY step;

-- ---------------------------------------------------------------------
-- 5. Top 3 products per category (ranking + Pareto share)
-- ---------------------------------------------------------------------
WITH product_rev AS (
    SELECT c.name AS category, p.name AS product, sum(s.revenue) AS revenue
    FROM v_sales s
    JOIN products p   USING (product_id)
    JOIN categories c ON c.category_id = p.category_id
    GROUP BY c.name, p.name
),
ranked AS (
    SELECT *,
           dense_rank() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk,
           round(100.0 * sum(revenue) OVER (PARTITION BY category ORDER BY revenue DESC)
                 / sum(revenue) OVER (PARTITION BY category), 1)            AS cumulative_share_pct
    FROM product_rev
)
SELECT * FROM ranked WHERE rnk <= 3 ORDER BY category, rnk;

-- ---------------------------------------------------------------------
-- 6. Category tree revenue roll-up (recursive CTE)
-- ---------------------------------------------------------------------
WITH RECURSIVE tree AS (
    SELECT category_id, category_id AS root_id, name AS path, 0 AS depth
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.category_id, t.root_id, t.path || ' > ' || c.name, t.depth + 1
    FROM categories c JOIN tree t ON c.parent_id = t.category_id
)
SELECT r.name AS root_category,
       t.path,
       coalesce(sum(s.revenue), 0) AS revenue,
       sum(coalesce(sum(s.revenue), 0)) OVER (PARTITION BY r.name) AS root_total
FROM tree t
JOIN categories r ON r.category_id = t.root_id
LEFT JOIN v_sales s ON s.category_id = t.category_id
WHERE t.depth > 0
GROUP BY r.name, t.path
ORDER BY r.name, revenue DESC;

-- ---------------------------------------------------------------------
-- 7. Repeat-purchase gap: median days between consecutive orders
-- ---------------------------------------------------------------------
WITH gaps AS (
    SELECT customer_id,
           ordered_at::date - lag(ordered_at::date) OVER (PARTITION BY customer_id ORDER BY ordered_at) AS gap_days
    FROM orders
    WHERE status IN ('paid','shipped','delivered')
)
SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY gap_days) AS median_gap_days,
       percentile_cont(0.9) WITHIN GROUP (ORDER BY gap_days) AS p90_gap_days,
       round(avg(gap_days), 1)                                AS avg_gap_days
FROM gaps WHERE gap_days IS NOT NULL;
