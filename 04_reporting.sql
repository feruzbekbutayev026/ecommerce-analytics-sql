-- =====================================================================
-- Reporting layer: materialized view, refresh function, KPI function
-- =====================================================================
SET search_path TO shop;

DROP MATERIALIZED VIEW IF EXISTS mv_daily_kpis;
CREATE MATERIALIZED VIEW mv_daily_kpis AS
SELECT ordered_at::date            AS day,
       count(DISTINCT order_id)    AS orders,
       count(DISTINCT customer_id) AS buyers,
       sum(revenue)                AS revenue,
       sum(margin)                 AS margin,
       round(100 * sum(margin) / nullif(sum(revenue), 0), 2) AS margin_pct
FROM v_sales
GROUP BY ordered_at::date;

CREATE UNIQUE INDEX ON mv_daily_kpis (day);   -- required for CONCURRENTLY

CREATE OR REPLACE PROCEDURE refresh_reporting()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_kpis;
    RAISE NOTICE 'mv_daily_kpis refreshed at %', now();
END $$;

-- KPI summary for any date range
CREATE OR REPLACE FUNCTION kpi_summary(p_from DATE, p_to DATE)
RETURNS TABLE (orders BIGINT, buyers BIGINT, revenue NUMERIC, margin_pct NUMERIC, best_day DATE)
LANGUAGE sql STABLE AS $$
    SELECT sum(orders)::bigint,
           (SELECT count(DISTINCT customer_id) FROM v_sales
             WHERE ordered_at::date BETWEEN p_from AND p_to),
           sum(revenue),
           round(100 * sum(margin) / nullif(sum(revenue), 0), 2),
           (array_agg(day ORDER BY revenue DESC))[1]
    FROM mv_daily_kpis
    WHERE day BETWEEN p_from AND p_to;
$$;

-- Example usage
CALL refresh_reporting();
SELECT * FROM kpi_summary('2026-01-01', '2026-06-30');
