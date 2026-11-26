-- =============================================================================
-- 15_site_support.sql: counts the website needs that earlier files don't
-- output. No new analysis: these re-count rules already defined in files
-- 03-14, so every number on the site comes from query output.
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/15_site_support.sql
-- Outputs: results/15_<name>.csv. scripts/export_site_data.py reads them
-- and cross-checks the final counts against files 10-14.
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- Q1. METRICS TREE
-- Question: Revenue = customers x orders per customer x average order value.
--           What are the three factors?
-- Logic:    Delivered in-window orders. Factors are shown rounded: orders per
--           customer to 4 decimals, AOV to 2 (and 4). Multiplying the rounded
--           factors therefore gives only approximately the exact revenue,
--           which is reported alongside.
-- Result:   93,104 customers x 1.0334 orders per customer x 137.00 AOV;
--           revenue 13,181,027.13 from 96,211 orders.
-- =============================================================================
CREATE TEMP VIEW q1_metrics_tree AS
SELECT
    COUNT(DISTINCT customer_unique_id)                                AS customers,
    COUNT(*)                                                          AS orders,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT customer_unique_id), 4)     AS orders_per_customer,
    ROUND(SUM(item_value) / COUNT(*), 2)                              AS aov,
    ROUND(SUM(item_value) / COUNT(*), 4)                              AS aov_4dp,
    SUM(item_value)                                                   AS revenue
FROM v_order_facts
WHERE is_delivered;

\copy (SELECT * FROM q1_metrics_tree) TO 'results/15_metrics_tree.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1_metrics_tree;


-- =============================================================================
-- Q2. PIPELINES ("how we got this")
-- Question: For each finding, how many rows survive each step, how many
--           are dropped, and why?
-- Logic:    One row per (finding, step) with its row count, built with
--           UNION ALL. rows_dropped = previous step's count minus this one,
--           using LAG within each finding (NULL for the first step). Each
--           count repeats the rule used in the source file.
-- Result:   See results/15_pipelines.csv (filled in after run).
-- =============================================================================
CREATE TEMP TABLE pipeline_counts AS
-- ---------- F1 retention (file 10)
SELECT 'F1' AS finding, 1 AS step, 'All orders' AS label,
       (SELECT COUNT(*) FROM v_orders) AS row_count,
       NULL::text AS reason
UNION ALL
SELECT 'F1', 2, 'Purchased in the analysis window',
       (SELECT COUNT(*) FROM v_orders WHERE in_window),
       'Purchased before 2017-01-01 or after 2018-08-31'
UNION ALL
SELECT 'F1', 3, 'Delivered orders',
       (SELECT COUNT(*) FROM v_order_facts WHERE is_delivered),
       'Not delivered (shipped, canceled, unavailable, invoiced, processing, created, approved)'
UNION ALL
SELECT 'F1', 4, 'Customers (customer_unique_id)',
       (SELECT COUNT(DISTINCT customer_unique_id) FROM v_order_facts WHERE is_delivered),
       'Orders collapsed to one row per customer'
UNION ALL
SELECT 'F1', 5, 'Customers who returned on a later day',
       (SELECT COUNT(*) FROM (
            SELECT customer_unique_id
            FROM v_order_facts WHERE is_delivered
            GROUP BY customer_unique_id
            HAVING MAX(order_purchase_timestamp::date) > MIN(order_purchase_timestamp::date)) r),
       'No delivered order on a later calendar day than the first'

-- ---------- F2 delivery and handover (file 11)
UNION ALL
SELECT 'F2', 1, 'All orders', (SELECT COUNT(*) FROM v_orders), NULL
UNION ALL
SELECT 'F2', 2, 'Purchased in the analysis window',
       (SELECT COUNT(*) FROM v_orders WHERE in_window),
       'Purchased before 2017-01-01 or after 2018-08-31'
UNION ALL
SELECT 'F2', 3, 'Delivered orders',
       (SELECT COUNT(*) FROM v_order_facts WHERE is_delivered),
       'Not delivered'
UNION ALL
SELECT 'F2', 4, 'With a customer delivery date',
       (SELECT COUNT(*) FROM v_order_facts WHERE has_delivery_timing),
       'Status delivered but no delivery date recorded'
UNION ALL
SELECT 'F2', 5, 'With a carrier handover date',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE has_delivery_timing
           AND order_delivered_carrier_date IS NOT NULL
           AND latest_shipping_limit IS NOT NULL),
       'No carrier handover date recorded'
UNION ALL
SELECT 'F2', 6, 'Handed to the carrier after the shipping limit',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE has_delivery_timing
           AND order_delivered_carrier_date > latest_shipping_limit),
       'Handed over on or before the shipping limit'

-- ---------- F3 reviews and review timing (file 12)
UNION ALL
SELECT 'F3', 1, 'All orders', (SELECT COUNT(*) FROM v_orders), NULL
UNION ALL
SELECT 'F3', 2, 'Purchased in the analysis window',
       (SELECT COUNT(*) FROM v_orders WHERE in_window),
       'Purchased before 2017-01-01 or after 2018-08-31'
UNION ALL
SELECT 'F3', 3, 'With a review',
       (SELECT COUNT(*) FROM v_order_facts WHERE review_score IS NOT NULL),
       'No review'
UNION ALL
SELECT 'F3', 4, 'Delivered with a delivery date',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE review_score IS NOT NULL AND has_delivery_timing),
       'Not delivered, or no delivery date'
UNION ALL
SELECT 'F3', 5, 'Delivered late',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE review_score IS NOT NULL AND has_delivery_timing AND is_late),
       'Delivered on or before the estimated day'
UNION ALL
SELECT 'F3', 6, 'Review created before delivery',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE review_score IS NOT NULL AND has_delivery_timing AND is_late
           AND review_creation_date::date < order_delivered_customer_date::date),
       'Review created on or after the delivery day'

-- ---------- F4 seller concentration (file 13)
UNION ALL
SELECT 'F4', 1, 'Sellers in the sellers table', (SELECT COUNT(*) FROM v_sellers), NULL
UNION ALL
SELECT 'F4', 2, 'Sellers with a delivered in-window sale',
       (SELECT COUNT(DISTINCT so.seller_id)
          FROM v_seller_orders so
          JOIN v_order_facts f ON f.order_id = so.order_id
         WHERE f.is_delivered),
       'No delivered sale in the analysis window'
UNION ALL
SELECT 'F4', 3, 'Scorecard sellers (30+ single-seller delivered orders)',
       (SELECT COUNT(*) FROM (
            SELECT so.seller_id
            FROM v_seller_orders so
            JOIN v_order_facts f ON f.order_id = so.order_id
            WHERE f.is_delivered AND f.seller_count = 1
            GROUP BY so.seller_id
            HAVING COUNT(*) >= 30) s),
       'Fewer than 30 single-seller delivered orders'

-- ---------- F5 volume growth (file 14)
UNION ALL
SELECT 'F5', 1, 'All orders', (SELECT COUNT(*) FROM v_orders), NULL
UNION ALL
SELECT 'F5', 2, 'Purchased in the analysis window',
       (SELECT COUNT(*) FROM v_orders WHERE in_window),
       'Purchased before 2017-01-01 or after 2018-08-31'
UNION ALL
SELECT 'F5', 3, 'Delivered orders',
       (SELECT COUNT(*) FROM v_order_facts WHERE is_delivered),
       'Not delivered'
UNION ALL
SELECT 'F5', 4, 'Purchased in Jan-Aug 2017 or Jan-Aug 2018',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE is_delivered
           AND (purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01'
             OR purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01')),
       'Purchased Sep-Dec 2017, outside the comparison months'
UNION ALL
SELECT 'F5', 5, 'Purchased in Jan-Aug 2018',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE is_delivered
           AND purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01'),
       'Purchased in Jan-Aug 2017 (the comparison base)';

CREATE TEMP VIEW q2_pipelines AS
SELECT
    finding,
    step,
    label,
    row_count,
    -- previous step's count minus this step's count; NULL on step 1
    LAG(row_count) OVER (PARTITION BY finding ORDER BY step) - row_count AS rows_dropped,
    reason
FROM pipeline_counts;

\copy (SELECT * FROM q2_pipelines ORDER BY finding, step) TO 'results/15_pipelines.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q2_pipelines ORDER BY finding, step;


-- =============================================================================
-- Q3. TABLE AND VIEW ROW COUNTS (for the data-model diagram)
-- Logic:    COUNT(*) of each raw table and each clean view.
-- Result:   See results/15_table_counts.csv.
-- =============================================================================
CREATE TEMP VIEW q3_table_counts AS
SELECT 'table' AS kind, 'customers' AS name, (SELECT COUNT(*) FROM customers) AS row_count
UNION ALL SELECT 'table', 'geolocation',                       (SELECT COUNT(*) FROM geolocation)
UNION ALL SELECT 'table', 'sellers',                           (SELECT COUNT(*) FROM sellers)
UNION ALL SELECT 'table', 'product_category_name_translation', (SELECT COUNT(*) FROM product_category_name_translation)
UNION ALL SELECT 'table', 'products',                          (SELECT COUNT(*) FROM products)
UNION ALL SELECT 'table', 'orders',                            (SELECT COUNT(*) FROM orders)
UNION ALL SELECT 'table', 'order_items',                       (SELECT COUNT(*) FROM order_items)
UNION ALL SELECT 'table', 'order_payments',                    (SELECT COUNT(*) FROM order_payments)
UNION ALL SELECT 'table', 'order_reviews',                     (SELECT COUNT(*) FROM order_reviews)
UNION ALL SELECT 'view',  'v_order_items_agg',     (SELECT COUNT(*) FROM v_order_items_agg)
UNION ALL SELECT 'view',  'v_order_payments_agg',  (SELECT COUNT(*) FROM v_order_payments_agg)
UNION ALL SELECT 'view',  'v_order_review',        (SELECT COUNT(*) FROM v_order_review)
UNION ALL SELECT 'view',  'v_geo',                 (SELECT COUNT(*) FROM v_geo)
UNION ALL SELECT 'view',  'v_products',            (SELECT COUNT(*) FROM v_products)
UNION ALL SELECT 'view',  'v_sellers',             (SELECT COUNT(*) FROM v_sellers)
UNION ALL SELECT 'view',  'v_order_lines',         (SELECT COUNT(*) FROM v_order_lines)
UNION ALL SELECT 'view',  'v_seller_orders',       (SELECT COUNT(*) FROM v_seller_orders)
UNION ALL SELECT 'view',  'v_order_main_category', (SELECT COUNT(*) FROM v_order_main_category)
UNION ALL SELECT 'view',  'v_orders',              (SELECT COUNT(*) FROM v_orders)
UNION ALL SELECT 'view',  'v_order_facts',         (SELECT COUNT(*) FROM v_order_facts);

\copy (SELECT * FROM q3_table_counts) TO 'results/15_table_counts.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3_table_counts;


-- =============================================================================
-- Q4. DATA-QUALITY ISSUES AND DECISIONS
-- Logic:    One row per issue found in files 02-14, re-counted here so the
--           number on the site is query output. decision_ref points to the
--           decision (C1-C12) or the notes section in
--           docs/data_quality_notes.md. Decision text is a short summary.
-- Result:   See results/15_quality_issues.csv.
-- =============================================================================
CREATE TEMP VIEW q4_quality_issues AS
SELECT 'orders_outside_window' AS issue_id,
       'Orders purchased outside the analysis window (thin months at both ends)' AS issue,
       (SELECT COUNT(*) FROM v_orders WHERE NOT in_window) AS affected,
       'orders' AS unit, 'C1' AS decision_ref,
       'Analyse 2017-01-01 to 2018-08-31 only' AS decision
UNION ALL
SELECT 'customer_id_per_order',
       'customer_id is created per order; one person can have several',
       (SELECT COUNT(*) FROM (SELECT customer_unique_id FROM customers
                              GROUP BY customer_unique_id HAVING COUNT(*) > 1) t),
       'people with 2+ customer_ids', 'C2',
       'Identify customers by customer_unique_id'
UNION ALL
SELECT 'orders_multiple_reviews',
       'Orders with more than one review',
       (SELECT COUNT(*) FROM (SELECT order_id FROM order_reviews
                              GROUP BY order_id HAVING COUNT(*) > 1) t),
       'orders', 'C3',
       'Keep the latest review per order'
UNION ALL
SELECT 'repeated_review_id',
       'review_id values that appear on more than one order',
       (SELECT COUNT(*) FROM (SELECT review_id FROM order_reviews
                              GROUP BY review_id HAVING COUNT(*) > 1) t),
       'review_ids', 'C3',
       'Never join on review_id; key reviews by (review_id, order_id)'
UNION ALL
SELECT 'payment_mismatch',
       'Delivered in-window orders where items + freight differ from total paid by more than 0.01',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE is_delivered AND total_paid IS NOT NULL
           AND ABS(total_paid - (item_value + freight_value)) > 0.01),
       'orders', 'C4, C11',
       'Revenue uses item prices; mismatches left unexplained and listed as a limitation'
UNION ALL
SELECT 'delivered_without_date',
       'Orders with status delivered but no customer delivery date',
       (SELECT COUNT(*) FROM orders
         WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL),
       'orders', 'C5',
       'Excluded from delivery-timing metrics'
UNION ALL
SELECT 'canceled_with_delivery_date',
       'Orders with status canceled that have a customer delivery date',
       (SELECT COUNT(*) FROM orders
         WHERE order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL),
       'orders', 'C5',
       'Kept as canceled; not used for delivery timing'
UNION ALL
SELECT 'products_without_category',
       'Products with no category',
       (SELECT COUNT(*) FROM products WHERE product_category_name IS NULL),
       'products', 'C6',
       'Shown as unknown'
UNION ALL
SELECT 'untranslated_category',
       'Products whose category has no English translation',
       (SELECT COUNT(*) FROM products p
         WHERE p.product_category_name IS NOT NULL
           AND p.product_category_name NOT IN
               (SELECT product_category_name FROM product_category_name_translation)),
       'products', 'C6',
       'Fall back to the Portuguese name'
UNION ALL
SELECT 'misspelled_columns',
       'Source columns spelled lenght instead of length',
       (SELECT COUNT(*) FROM information_schema.columns
         WHERE table_name = 'products' AND column_name LIKE '%lenght%'),
       'columns', 'C7',
       'Raw table unchanged; v_products exposes corrected names'
UNION ALL
SELECT 'negative_stage_duration',
       'Timed in-window orders with a negative stage duration',
       (SELECT COUNT(*) FROM v_order_facts
         WHERE has_delivery_timing
           AND (days_purchase_to_approval < 0
             OR days_approval_to_carrier < 0
             OR days_carrier_to_customer < 0)),
       'orders', 'C9',
       'Excluded from stage statistics only; reported as a limitation'
UNION ALL
SELECT 'same_day_second_order',
       'Second delivered orders placed on the same calendar day as the first',
       (SELECT COUNT(*) FROM (
            SELECT order_purchase_timestamp::date AS d,
                   LAG(order_purchase_timestamp::date) OVER (
                       PARTITION BY customer_unique_id
                       ORDER BY order_purchase_timestamp, order_id) AS prev_d,
                   ROW_NUMBER() OVER (
                       PARTITION BY customer_unique_id
                       ORDER BY order_purchase_timestamp, order_id) AS seq
            FROM v_order_facts WHERE is_delivered) t
         WHERE seq = 2 AND d = prev_d),
       'customers', 'C12',
       'A repeat customer is one who returned on a later calendar day'
UNION ALL
SELECT 'geo_exact_duplicates',
       'Geolocation rows that exactly duplicate another row',
       (SELECT COUNT(*) - COUNT(DISTINCT (geolocation_zip_code_prefix, geolocation_lat,
                                          geolocation_lng, geolocation_city, geolocation_state))
          FROM geolocation),
       'rows', 'v_geo',
       'v_geo averages distinct points, one row per zip prefix'
UNION ALL
SELECT 'customer_zip_missing_geo',
       'Customer zip prefixes with no geolocation row',
       (SELECT COUNT(DISTINCT c.customer_zip_code_prefix) FROM customers c
         WHERE c.customer_zip_code_prefix NOT IN (SELECT zip_code_prefix FROM v_geo)),
       'zip prefixes', 'Delivery notes',
       'Orders without coordinates left out of distance analysis'
UNION ALL
SELECT 'orders_without_items',
       'Orders with no order_items rows (all statuses, all dates)',
       (SELECT COUNT(*) FROM v_orders o
         WHERE o.order_id NOT IN (SELECT order_id FROM v_order_items_agg)),
       'orders', 'Section 4',
       'Drop out of item-level analysis naturally; kept in status counts';

\copy (SELECT * FROM q4_quality_issues) TO 'results/15_quality_issues.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4_quality_issues;


-- =============================================================================
-- Q5. MAP SAMPLE (3D arcs, seller -> customer)
-- Logic:    Delivered in-window single-seller orders with a delivery date
--           and coordinates inside Brazil's bounding box (same rules as
--           file 11, Q8). Take a fixed, repeatable sample of 3,000: sort by
--           md5(order_id), a fixed scramble of the ids, and keep the first
--           3,000. Coordinates are rounded to 3 decimals (about 100 m) to
--           keep the file small.
--           Performance: v_geo aggregates 1M rows and v_order_facts stacks
--           several views. Joined directly, the planner chose a very slow
--           plan, so both inputs are stored first as temp tables
--           (computed once).
-- Result:   See results/15_map_arcs_sample.csv.
-- =============================================================================
CREATE TEMP TABLE geo AS
SELECT zip_code_prefix, lat, lng FROM v_geo;

CREATE TEMP TABLE timed_single_seller AS
SELECT order_id, single_seller_id, customer_zip_code_prefix, customer_state,
       is_late, delivery_days
FROM v_order_facts
WHERE has_delivery_timing AND single_seller_id IS NOT NULL;

-- Temp tables get no automatic statistics (autovacuum skips them). Without
-- ANALYZE the planner guesses their size and picks nested loops; with it,
-- it uses hash joins and the query takes milliseconds.
ANALYZE geo;
ANALYZE timed_single_seller;

CREATE TEMP VIEW q5_map_sample AS
SELECT
    ROUND(sg.lat::numeric, 3)  AS seller_lat,
    ROUND(sg.lng::numeric, 3)  AS seller_lng,
    ROUND(cg.lat::numeric, 3)  AS customer_lat,
    ROUND(cg.lng::numeric, 3)  AS customer_lng,
    f.is_late,
    f.delivery_days,
    s.seller_state,
    f.customer_state
FROM timed_single_seller f
JOIN v_sellers s ON s.seller_id        = f.single_seller_id
JOIN geo       sg ON sg.zip_code_prefix = s.seller_zip_code_prefix
JOIN geo       cg ON cg.zip_code_prefix = f.customer_zip_code_prefix
WHERE TRUE
  AND cg.lat BETWEEN -34 AND 5.3 AND cg.lng BETWEEN -74 AND -34
  AND sg.lat BETWEEN -34 AND 5.3 AND sg.lng BETWEEN -74 AND -34
ORDER BY md5(f.order_id)
LIMIT 3000;

\copy (SELECT * FROM q5_map_sample) TO 'results/15_map_arcs_sample.csv' WITH (FORMAT csv, HEADER true)
SELECT COUNT(*) AS sample_rows, COUNT(*) FILTER (WHERE is_late) AS late_in_sample FROM q5_map_sample;


-- =============================================================================
-- Q6. MAP SAMPLE SUMMARY (legend and caption of the hero map)
-- Logic:    Counts and shares in the 3,000-order map sample from Q5.
--           Shares are of the sample, not of all orders.
-- Result:   See results/15_map_sample_summary.csv.
-- =============================================================================
CREATE TEMP VIEW q6_map_sample_summary AS
SELECT
    COUNT(*)                                                              AS sample_orders,
    COUNT(*) FILTER (WHERE NOT is_late)                                   AS on_time_orders,
    COUNT(*) FILTER (WHERE is_late)                                       AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT is_late) / COUNT(*), 2)      AS on_time_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2)          AS late_pct
FROM q5_map_sample;

\copy (SELECT * FROM q6_map_sample_summary) TO 'results/15_map_sample_summary.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6_map_sample_summary;


-- =============================================================================
-- Q7. DELIVERY BY CUSTOMER STATE, ALL 27 STATES (hero map tooltip)
-- Logic:    Same rules as 11_delivery_performance.sql Q4, without its 500+
--           orders filter, so every state on the map has a tooltip.
--             delivered_orders = delivered in-window orders
--             timed_orders     = delivered with a delivery date (file 11's "orders")
--             late rate and median delivery days use timed orders.
--           scripts/export_site_data.py checks that the states with 500+
--           orders match results/11_by_state.csv exactly.
-- Result:   See results/15_state_delivery.csv.
-- =============================================================================
CREATE TEMP VIEW q7_state_delivery AS
SELECT
    customer_state                                                                     AS state,
    COUNT(*)                                                                           AS delivered_orders,
    COUNT(*) FILTER (WHERE has_delivery_timing)                                        AS timed_orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2)    AS median_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late)
          / COUNT(*) FILTER (WHERE has_delivery_timing), 2)                            AS late_rate_pct
FROM v_order_facts
WHERE is_delivered
GROUP BY customer_state;
-- percentile_cont ignores NULLs, and delivery_days is NULL without timing,
-- so the median covers timed orders only, as in file 11.

\copy (SELECT * FROM q7_state_delivery ORDER BY state) TO 'results/15_state_delivery.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_state_delivery ORDER BY state;


-- =============================================================================
-- Q8. FAN-OUT CHECKS FOR THE SITE ("checks that passed" under each funnel)
-- Logic:    The same test as 03_clean_views.sql, for the views the findings
--           read: rows = distinct grain keys = expected rows from the raw
--           tables. Re-run here so the site shows checks from this run.
--             v_order_facts   (F1, F2, F3, F5)   one row per in-window order
--             v_order_review  (F3)               one review row per order
--             v_seller_orders (F4)               one row per order and seller
--             v_order_lines   (F5)               one row per order item
--           The DO block stops the script if any view fails.
-- Result:   See results/15_fanout_checks.csv.
-- =============================================================================
CREATE TEMP VIEW q8_fanout_checks AS
SELECT 'v_order_facts' AS view_name, 'order_id' AS grain_key,
       (SELECT COUNT(*)                 FROM v_order_facts) AS row_count,
       (SELECT COUNT(DISTINCT order_id) FROM v_order_facts) AS distinct_keys,
       (SELECT COUNT(*) FROM orders
         WHERE order_purchase_timestamp >= DATE '2017-01-01'
           AND order_purchase_timestamp <  DATE '2018-09-01')  AS expected_rows
UNION ALL
SELECT 'v_order_review', 'order_id',
       (SELECT COUNT(*)                 FROM v_order_review),
       (SELECT COUNT(DISTINCT order_id) FROM v_order_review),
       (SELECT COUNT(DISTINCT order_id) FROM order_reviews)
UNION ALL
SELECT 'v_seller_orders', '(order_id, seller_id)',
       (SELECT COUNT(*)                              FROM v_seller_orders),
       (SELECT COUNT(DISTINCT (order_id, seller_id)) FROM v_seller_orders),
       (SELECT COUNT(DISTINCT (order_id, seller_id)) FROM order_items)
UNION ALL
SELECT 'v_order_lines', '(order_id, order_item_id)',
       (SELECT COUNT(*)                                  FROM v_order_lines),
       (SELECT COUNT(DISTINCT (order_id, order_item_id)) FROM v_order_lines),
       (SELECT COUNT(*)                                  FROM order_items);

\copy (SELECT *, (row_count = distinct_keys AND row_count = expected_rows) AS passed FROM q8_fanout_checks ORDER BY view_name) TO 'results/15_fanout_checks.csv' WITH (FORMAT csv, HEADER true)
SELECT *, (row_count = distinct_keys AND row_count = expected_rows) AS passed FROM q8_fanout_checks ORDER BY view_name;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM q8_fanout_checks
               WHERE row_count <> distinct_keys OR row_count <> expected_rows) THEN
        RAISE EXCEPTION 'FAN-OUT CHECK FAILED in 15_site_support.sql Q8. See the table above.';
    END IF;
    RAISE NOTICE 'Q8: all site fan-out checks passed.';
END
$$;
