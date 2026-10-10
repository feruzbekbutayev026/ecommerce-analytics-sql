# E-Commerce Analytics in SQL

An end-to-end analytics project built entirely in **PostgreSQL**: a normalized store schema, a reproducible synthetic dataset (~2k customers, ~15k orders, ~38k order lines, ~75k web events) and a set of business-grade analytical queries.

## What it shows

| Area | Techniques |
|---|---|
| Schema design | ENUM types, CHECK / FK constraints, price snapshots, partial & BRIN indexes |
| Data generation | `generate_series`, `LATERAL`, `setseed` for reproducible data |
| Revenue trends | `lag`, moving averages with window frames, YTD running totals |
| Cohort retention | cohort assignment, `age()`, `FILTER` pivoting |
| RFM segmentation | `ntile(5)` scoring and rule-based segments |
| Conversion funnel | `bool_or`, `first_value`, stage-to-stage drop-off |
| Product ranking | `dense_rank`, Pareto cumulative share per category |
| Category hierarchy | `WITH RECURSIVE` roll-ups |
| Reporting layer | materialized view + `REFRESH ... CONCURRENTLY`, stored procedure, SQL function |

## Project structure

```
01_schema.sql      -- tables, types, constraints, indexes
02_seed.sql        -- synthetic, reproducible data
03_analytics.sql   -- 7 analytical queries (+ v_sales, v_rfm views)
04_reporting.sql   -- materialized KPI view, refresh procedure, kpi_summary()
```

## Run it

```bash
createdb shop
for f in 0*.sql; do psql -d shop -v ON_ERROR_STOP=1 -f "$f"; done
```

Then try:

```sql
SET search_path TO shop;
SELECT * FROM kpi_summary('2026-01-01', '2026-06-30');
SELECT segment, count(*) FROM v_rfm GROUP BY segment;
```

## Sample output — conversion funnel

| step | stage | sessions | % of top | step conversion % |
|---|---|---|---|---|
| 1 | view | 40000 | 100.0 | |
| 2 | add_to_cart | 18812 | 47.0 | 47.0 |
| 3 | checkout | 10940 | 27.4 | 58.2 |
| 4 | purchase | 5008 | 12.5 | 45.8 |

Requires PostgreSQL 14 or newer (tested on 16).
