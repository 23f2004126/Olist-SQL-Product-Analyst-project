-- =============================================================================
-- 04_baseline.sql: headline numbers for the analysis window
--
-- Run FROM THE REPO ROOT (the \copy path is relative):
--     psql -d olist -f sql/04_baseline.sql
-- Writes results/baseline.csv and prints the same table.
--
-- Everything reads from v_order_facts, which already holds only orders
-- purchased 2017-01-01 to 2018-08-31 (one row per order).
--
-- Output is one "long" table (section, dimension, metric, value), so every
-- number fits in a single CSV:
--   section   = which block of the baseline
--   dimension = what the number is broken down by ('all' = no breakdown)
--   metric    = what is being measured
--   value     = the number (counts, money in BRL, rates in %)
--
-- Definitions:
--   delivered order   = order_status = 'delivered'
--   revenue           = SUM(order_items.price) on delivered orders (freight separate)
--   average order value (AOV) = revenue / delivered orders
--   unique customers  = distinct customer_unique_id with >= 1 delivered order
--   active sellers    = distinct sellers with >= 1 item in a delivered order
--   repeat rate       = customers with 2+ delivered orders / customers with >= 1
--   on-time           = delivered on or before the estimated date (is_late = false),
--                       over delivered orders that have a delivery date
--   reviews           = latest review per order, over in-window orders with a review
-- =============================================================================

\set ON_ERROR_STOP on

-- A temporary view holds the whole baseline, so the script can both print it
-- and \copy it to CSV without writing the query twice.
CREATE TEMP VIEW baseline AS

-- ---------------------------------------------------------------- 1. Orders by status
SELECT 1 AS sort_order, 'orders_by_status' AS section,
       order_status AS dimension, 'orders' AS metric,
       COUNT(*)::numeric AS value
FROM v_order_facts
GROUP BY order_status

UNION ALL
SELECT 1, 'orders_by_status', 'all', 'orders', COUNT(*)
FROM v_order_facts

-- ---------------------------------------------------------------- 2. Volume
UNION ALL
SELECT 2, 'volume', 'all', 'delivered_orders', COUNT(*)
FROM v_order_facts
WHERE is_delivered

UNION ALL
SELECT 2, 'volume', 'all', 'unique_customers', COUNT(DISTINCT customer_unique_id)
FROM v_order_facts
WHERE is_delivered

UNION ALL
-- Sellers live at item level, so join back to order_items. COUNT(DISTINCT)
-- makes the item-level fan-out harmless here.
SELECT 2, 'volume', 'all', 'active_sellers', COUNT(DISTINCT i.seller_id)
FROM order_items i
JOIN v_order_facts f ON f.order_id = i.order_id
WHERE f.is_delivered

-- ---------------------------------------------------------------- 3. Money (BRL)
UNION ALL
SELECT 3, 'money', 'all', 'revenue', SUM(item_value)
FROM v_order_facts
WHERE is_delivered

UNION ALL
SELECT 3, 'money', 'all', 'freight', SUM(freight_value)
FROM v_order_facts
WHERE is_delivered

UNION ALL
SELECT 3, 'money', 'all', 'average_order_value', ROUND(SUM(item_value) / COUNT(*), 2)
FROM v_order_facts
WHERE is_delivered

-- ---------------------------------------------------------------- 4. Monthly
-- orders = all statuses; delivered_orders and revenue = delivered only.
UNION ALL
SELECT 4, 'monthly', purchase_month::text, 'orders', COUNT(*)
FROM v_order_facts
GROUP BY purchase_month

UNION ALL
SELECT 4, 'monthly', purchase_month::text, 'delivered_orders', COUNT(*)
FROM v_order_facts
WHERE is_delivered
GROUP BY purchase_month

UNION ALL
SELECT 4, 'monthly', purchase_month::text, 'revenue', SUM(item_value)
FROM v_order_facts
WHERE is_delivered
GROUP BY purchase_month

-- ---------------------------------------------------------------- 5. Repeat rate
-- Inner query: delivered orders per customer. Outer query: count and rate.
UNION ALL
SELECT 5, 'repeat', 'all', 'customers_with_delivered_order', COUNT(*)
FROM (SELECT customer_unique_id, COUNT(*) AS n
      FROM v_order_facts WHERE is_delivered
      GROUP BY customer_unique_id) c

UNION ALL
SELECT 5, 'repeat', 'all', 'customers_with_2plus_delivered', COUNT(*) FILTER (WHERE n >= 2)
FROM (SELECT customer_unique_id, COUNT(*) AS n
      FROM v_order_facts WHERE is_delivered
      GROUP BY customer_unique_id) c

UNION ALL
SELECT 5, 'repeat', 'all', 'repeat_rate_pct',
       ROUND(100.0 * COUNT(*) FILTER (WHERE n >= 2) / COUNT(*), 2)
FROM (SELECT customer_unique_id, COUNT(*) AS n
      FROM v_order_facts WHERE is_delivered
      GROUP BY customer_unique_id) c

-- ---------------------------------------------------------------- 6. Delivery
-- has_delivery_timing = delivered AND has a customer delivery date.
UNION ALL
SELECT 6, 'delivery', 'all', 'orders_with_delivery_timing', COUNT(*)
FROM v_order_facts
WHERE has_delivery_timing

UNION ALL
SELECT 6, 'delivery', 'all', 'late_orders', COUNT(*) FILTER (WHERE is_late)
FROM v_order_facts
WHERE has_delivery_timing

UNION ALL
SELECT 6, 'delivery', 'all', 'on_time_rate_pct',
       ROUND(100.0 * COUNT(*) FILTER (WHERE NOT is_late) / COUNT(*), 2)
FROM v_order_facts
WHERE has_delivery_timing

UNION ALL
-- percentile_cont(0.5) = the median; it interpolates between the two middle
-- values when the count is even. It returns double precision, so cast back.
SELECT 6, 'delivery', 'all', 'median_delivery_days',
       ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2)
FROM v_order_facts
WHERE has_delivery_timing

-- ---------------------------------------------------------------- 7. Reviews
UNION ALL
SELECT 7, 'reviews', 'all', 'orders_with_review', COUNT(*)
FROM v_order_facts
WHERE review_score IS NOT NULL

UNION ALL
SELECT 7, 'reviews', 'all', 'avg_review_score', ROUND(AVG(review_score), 2)
FROM v_order_facts
WHERE review_score IS NOT NULL

UNION ALL
SELECT 7, 'reviews', 'all', 'share_1_2_star_pct',
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2)
FROM v_order_facts
WHERE review_score IS NOT NULL

-- ---------------------------------------------------------------- 8. Reconciliation
-- Delivered orders: item value + freight should equal total paid.
-- Payments can include installment interest or vouchers, so small gaps are
-- possible. Differences of 0.01 or less count as rounding.
UNION ALL
SELECT 8, 'reconciliation', 'all', 'delivered_orders_compared', COUNT(*)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'delivered_orders_missing_payment', COUNT(*)
FROM v_order_facts
WHERE is_delivered AND total_paid IS NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'items_plus_freight_total', SUM(item_value + freight_value)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'total_paid', SUM(total_paid)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'orders_diff_gt_0.01',
       COUNT(*) FILTER (WHERE ABS(total_paid - (item_value + freight_value)) > 0.01)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'orders_paid_more_than_items_freight',
       COUNT(*) FILTER (WHERE total_paid - (item_value + freight_value) > 0.01)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'orders_paid_less_than_items_freight',
       COUNT(*) FILTER (WHERE (item_value + freight_value) - total_paid > 0.01)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
-- Size of the gaps: total absolute difference across mismatched orders
SELECT 8, 'reconciliation', 'all', 'abs_diff_sum_on_mismatched',
       SUM(ABS(total_paid - (item_value + freight_value)))
         FILTER (WHERE ABS(total_paid - (item_value + freight_value)) > 0.01)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
SELECT 8, 'reconciliation', 'all', 'abs_diff_max',
       MAX(ABS(total_paid - (item_value + freight_value)))
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL

UNION ALL
-- Median gap among mismatched orders: is a typical gap cents or reais?
SELECT 8, 'reconciliation', 'all', 'abs_diff_median_on_mismatched',
       ROUND((percentile_cont(0.5) WITHIN GROUP (
                 ORDER BY ABS(total_paid - (item_value + freight_value))))::numeric, 2)
FROM v_order_facts
WHERE is_delivered AND item_value IS NOT NULL AND total_paid IS NOT NULL
  AND ABS(total_paid - (item_value + freight_value)) > 0.01;


-- Save to CSV. \copy must be written on ONE line (it is a psql command, not SQL).
\copy (SELECT section, dimension, metric, value FROM baseline ORDER BY sort_order, dimension, metric) TO 'results/baseline.csv' WITH (FORMAT csv, HEADER true)

-- Print the same table to the screen.
SELECT section, dimension, metric, value
FROM baseline
ORDER BY sort_order, dimension, metric;
