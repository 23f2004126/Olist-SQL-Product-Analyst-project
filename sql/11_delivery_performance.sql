-- =============================================================================
-- 11_delivery_performance.sql: Business question 2, delivery
-- "How late are deliveries, and where?"
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/11_delivery_performance.sql
-- Each query is saved to results/11_<name>.csv and printed.
--
-- Scope (decisions in docs/data_quality_notes.md):
--   * In-window orders (v_order_facts) that are delivered AND have a customer
--     delivery date (has_delivery_timing): 96,203 orders.
--   * Late = delivered on a later calendar day than estimated (is_late).
--   * Orders with a negative stage duration are excluded from stage
--     statistics only (Q5).
--   * Reads clean views only: v_order_facts, v_sellers, v_geo.
--
-- Describes what the data shows; it doesn't claim causes.
--
-- Pattern for every query:
--   CREATE TEMP VIEW qN_... AS <query>;   \copy it to CSV;   SELECT it.
--
-- Median and percentiles use percentile_cont(p) WITHIN GROUP (ORDER BY x).
-- It returns double precision, so it is cast to numeric before rounding.
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- BUILDING BLOCK: timed_orders
-- GRAIN: one row per in-window delivered order with a delivery date.
-- =============================================================================
CREATE TEMP VIEW timed_orders AS
SELECT *
FROM v_order_facts
WHERE has_delivery_timing;


-- =============================================================================
-- Q1. OVERALL
-- Question: How often are orders on time, and how long does delivery take?
-- Logic:    on-time rate = orders not late / all timed orders.
--           delivery_days = purchase -> delivered, fractional days.
-- Result:   96,203 orders, 6,531 late. On-time 93.21% (matches baseline).
--           Delivery days: p50 10.21 | p75 15.68 | p90 23.06 | p95 29.22.
-- =============================================================================
CREATE TEMP VIEW q1_overall AS
SELECT
    COUNT(*)                                                                    AS orders,
    COUNT(*) FILTER (WHERE is_late)                                             AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT is_late) / COUNT(*), 2)            AS on_time_rate_pct,
    ROUND((percentile_cont(0.50) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p50_days,
    ROUND((percentile_cont(0.75) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p75_days,
    ROUND((percentile_cont(0.90) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p90_days,
    ROUND((percentile_cont(0.95) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS p95_days
FROM timed_orders;

\copy (SELECT * FROM q1_overall) TO 'results/11_overall.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1_overall;


-- =============================================================================
-- Q2. MONTHLY TREND
-- Question: Did delivery speed and lateness change over time?
-- Logic:    Group in-window orders by purchase month. delivery_days and
--           is_late are NULL for orders without timing, and
--           percentile_cont ignores NULLs, so the medians cover timed orders
--           only. orders_without_timing gives context: recent months have
--           orders still undelivered when the data ends (last recorded
--           delivery 2018-10-17). Slow deliveries from those months may be
--           missing.
-- Result:   Late rate is 2.79-6.56% in most months, with three spikes:
--           2017-11 12.40% (median 12.70 days), 2018-02 14.13% (14.26 days),
--           2018-03 18.96% (13.37 days). From 2018-04 medians fall: 9.32,
--           9.15, 7.96, 7.50, 7.01 days (2018-04 to 2018-08). Recent months
--           still have untimed orders (2018-08: 161 of 6,512), so read their
--           medians with care.
-- =============================================================================
CREATE TEMP VIEW q2_monthly AS
SELECT
    purchase_month,
    COUNT(*) FILTER (WHERE has_delivery_timing)                                 AS timed_orders,
    COUNT(*) FILTER (WHERE NOT has_delivery_timing)                             AS orders_without_timing,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS median_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late)
          / COUNT(*) FILTER (WHERE has_delivery_timing), 2)                     AS late_rate_pct
FROM v_order_facts
GROUP BY purchase_month;

\copy (SELECT * FROM q2_monthly ORDER BY purchase_month) TO 'results/11_monthly_trend.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q2_monthly ORDER BY purchase_month;


-- =============================================================================
-- Q3. PROMISE ACCURACY
-- Question: How does the promised delivery time compare with the actual one?
-- Logic:    promised_days = estimated date - purchase date (calendar days).
--           actual calendar days = promised_days + delay_days, because
--           delay_days = delivered date - estimated date. The DO block
--           below checks this equals delivered date - purchase date for
--           every order, and stops the script if not.
--           delay_days buckets: negative = early, 0 = on the promised day.
-- Result:   Median promised 24 days vs median actual 10 calendar days;
--           median delay -12 (12 days early).
--           7+ days early 75,882 (78.88%) | 1-6 early 12,499 (12.99%) |
--           on the day 1,291 (1.34%) | 1-3 late 1,869 (1.94%) |
--           4-7 late 1,802 (1.87%) | 8+ late 2,860 (2.97%).
-- =============================================================================

-- Identity check: promised_days + delay_days must equal actual calendar days.
-- COUNT(*) rather than EXISTS: EXISTS lets the planner stop at the first row,
-- and over these stacked views that picks a very slow row-by-row plan.
-- COUNT reads everything once with hash joins and finishes in seconds.
DO $$
DECLARE
    mismatches bigint;
BEGIN
    SELECT COUNT(*) INTO mismatches
    FROM timed_orders
    WHERE promised_days + delay_days
          <> order_delivered_customer_date::date - order_purchase_timestamp::date;

    IF mismatches > 0 THEN
        RAISE EXCEPTION 'promised_days + delay_days differs from actual calendar days for % orders', mismatches;
    END IF;
    RAISE NOTICE 'Q3 identity check passed (0 mismatches).';
END
$$;

-- Q3a: medians
CREATE TEMP VIEW q3a_promise_medians AS
SELECT
    COUNT(*)                                                                         AS orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY promised_days))::numeric, 2)  AS median_promised_days,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY promised_days + delay_days))::numeric, 2)
                                                                                     AS median_actual_calendar_days,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delay_days))::numeric, 2)     AS median_delay_days
FROM timed_orders;

\copy (SELECT * FROM q3a_promise_medians) TO 'results/11_promise_medians.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3a_promise_medians;

-- Q3b: delay_days distribution
CREATE TEMP VIEW q3b_delay_buckets AS
SELECT
    bucket_order,
    bucket,
    COUNT(*)                                            AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_orders
FROM (
    SELECT
        CASE WHEN delay_days <= -7 THEN 1
             WHEN delay_days <= -1 THEN 2
             WHEN delay_days =  0  THEN 3
             WHEN delay_days <=  3 THEN 4
             WHEN delay_days <=  7 THEN 5
             ELSE 6 END AS bucket_order,
        CASE WHEN delay_days <= -7 THEN '7+ days early'
             WHEN delay_days <= -1 THEN '1-6 days early'
             WHEN delay_days =  0  THEN 'on the day'
             WHEN delay_days <=  3 THEN '1-3 days late'
             WHEN delay_days <=  7 THEN '4-7 days late'
             ELSE '8+ days late' END AS bucket
    FROM timed_orders
) b
GROUP BY bucket_order, bucket;

\copy (SELECT bucket, orders, pct_of_orders FROM q3b_delay_buckets ORDER BY bucket_order) TO 'results/11_delay_buckets.csv' WITH (FORMAT csv, HEADER true)
SELECT bucket, orders, pct_of_orders FROM q3b_delay_buckets ORDER BY bucket_order;


-- =============================================================================
-- Q4. BY CUSTOMER STATE
-- Question: Where are deliveries slowest and most often late?
-- Logic:    Group by customer state, keep states with 500+ timed orders,
--           sort by late rate (highest first). Median promised days is
--           included to show how long the promise was in each state.
-- Result:   17 states with 500+ orders. Highest late rates: MA 17.53%,
--           CE 13.83%, BA 12.17%, RJ 12.14% (RJ: 12,310 orders). Lowest:
--           PR 4.06%, SP 4.50%, MG 4.59%. SP is fastest (median 7.20 days,
--           promise 19). The high-late states also have longer promises
--           (MA promise 31, CE 32, BA 30) and are still late more often.
-- =============================================================================
CREATE TEMP VIEW q4_by_state AS
SELECT
    customer_state                                                                   AS state,
    COUNT(*)                                                                         AS orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2)  AS median_delivery_days,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY promised_days))::numeric, 2)  AS median_promised_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2)                     AS late_rate_pct
FROM timed_orders
GROUP BY customer_state
HAVING COUNT(*) >= 500;

\copy (SELECT * FROM q4_by_state ORDER BY late_rate_pct DESC) TO 'results/11_by_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4_by_state ORDER BY late_rate_pct DESC;


-- =============================================================================
-- Q5. STAGE BREAKDOWN
-- Question: Where does the time go: approval, seller handover to the
--           carrier, or carrier transit? Does that differ for late orders?
-- Logic:    Three stages from v_order_facts (fractional days):
--             purchase -> approval, approval -> carrier, carrier -> customer.
--           Excluded (decision C9): orders with ANY negative stage.
--           Also excluded: orders with ANY missing stage, so all three
--           medians describe the same set of orders. Both counts are
--           reported in Q5a.
--           Q5b shows medians for on-time, late and all eligible orders.
-- Result:   Excluded: 1,344 with a negative stage, 15 with a missing stage
--           (no negative). Used: 94,844 of 96,203.
--           Medians (days)  approval | to carrier | carrier->customer
--             all            0.01   |   1.84     |   7.11
--             on_time        0.01   |   1.79     |   6.96
--             late           0.02   |   3.06     |  26.21
--           Late orders differ most in the carrier->customer stage.
-- =============================================================================

-- Flag each timed order once, so Q5a and Q5b use the same rule.
CREATE TEMP VIEW stage_orders AS
SELECT
    order_id,
    is_late,
    days_purchase_to_approval,
    days_approval_to_carrier,
    days_carrier_to_customer,
    (days_purchase_to_approval < 0
     OR days_approval_to_carrier < 0
     OR days_carrier_to_customer < 0)                   AS has_negative_stage,
    (days_purchase_to_approval IS NULL
     OR days_approval_to_carrier IS NULL
     OR days_carrier_to_customer IS NULL)               AS has_missing_stage
FROM timed_orders;
-- Note: when a stage is NULL, "x < 0" is NULL. Then has_negative_stage can
-- be NULL instead of false, which is why the filters below use IS TRUE / IS NOT TRUE.

-- Q5a: how many orders are excluded and why
CREATE TEMP VIEW q5a_stage_exclusions AS
SELECT
    COUNT(*)                                                         AS timed_orders,
    COUNT(*) FILTER (WHERE has_negative_stage IS TRUE)               AS excluded_negative_stage,
    COUNT(*) FILTER (WHERE has_missing_stage
                       AND has_negative_stage IS NOT TRUE)           AS excluded_missing_stage_only,
    COUNT(*) FILTER (WHERE has_negative_stage IS NOT TRUE
                       AND NOT has_missing_stage)                    AS orders_used
FROM stage_orders;

\copy (SELECT * FROM q5a_stage_exclusions) TO 'results/11_stage_exclusions.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5a_stage_exclusions;

-- Q5b: median days per stage, by on-time vs late
CREATE TEMP VIEW q5b_stage_medians AS
SELECT
    CASE WHEN is_late THEN 'late' ELSE 'on_time' END                                             AS delivery_group,
    COUNT(*)                                                                                     AS orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_purchase_to_approval))::numeric, 2)  AS median_purchase_to_approval,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_approval_to_carrier))::numeric, 2)   AS median_approval_to_carrier,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_carrier_to_customer))::numeric, 2)   AS median_carrier_to_customer
FROM stage_orders
WHERE has_negative_stage IS NOT TRUE AND NOT has_missing_stage
GROUP BY is_late
UNION ALL
SELECT
    'all',
    COUNT(*),
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_purchase_to_approval))::numeric, 2),
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_approval_to_carrier))::numeric, 2),
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_carrier_to_customer))::numeric, 2)
FROM stage_orders
WHERE has_negative_stage IS NOT TRUE AND NOT has_missing_stage;

\copy (SELECT * FROM q5b_stage_medians ORDER BY delivery_group) TO 'results/11_stage_medians.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5b_stage_medians ORDER BY delivery_group;


-- =============================================================================
-- Q6. SELLER HANDLING
-- Question: How often does the seller hand the order to the carrier after
--           the shipping limit, and are those orders late more often?
-- Logic:    latest_shipping_limit = the latest shipping_limit_date among the
--           order's items (v_order_items_agg). Handover is "after the limit"
--           when order_delivered_carrier_date > latest_shipping_limit
--           (timestamp comparison). Orders with no carrier date are left
--           out and counted. Compare the late-delivery rate for the two
--           groups. This shows an association only.
-- Result:   After limit: 8,581 orders (8.92%), late rate 21.10%, median
--           16.88 days. On or before: 87,621 (91.08%), late rate 5.39%,
--           median 9.82 days. No carrier date: 1 order.
-- =============================================================================
CREATE TEMP VIEW q6_seller_handling AS
WITH h AS (
    SELECT
        is_late,
        delivery_days,
        CASE
            WHEN order_delivered_carrier_date IS NULL
              OR latest_shipping_limit IS NULL                      THEN 'no carrier date'
            WHEN order_delivered_carrier_date > latest_shipping_limit THEN 'after limit'
            ELSE 'on or before limit'
        END AS handover
    FROM timed_orders
)
SELECT
    handover,
    COUNT(*)                                                                          AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                                AS pct_of_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2)                      AS late_rate_pct,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2)   AS median_delivery_days
FROM h
GROUP BY handover;

\copy (SELECT * FROM q6_seller_handling ORDER BY handover) TO 'results/11_seller_handling.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6_seller_handling ORDER BY handover;


-- =============================================================================
-- Q7. SAME STATE vs CROSS STATE
-- Question: Are deliveries faster and less often late when seller and
--           customer are in the same state?
-- Logic:    Single-seller orders only (single_seller_id is not NULL), so
--           each order has exactly one seller location. Join v_sellers
--           (one row per seller, so no fan-out) and compare seller_state with
--           customer_state.
-- Result:   Same state: 34,149 orders, median 6.56 days, promise 18, late
--           4.57%. Cross state: 60,782 orders, median 12.84 days, promise 27,
--           late 8.16%. Excluded multi-seller: 1,272.
-- =============================================================================
CREATE TEMP VIEW q7_same_vs_cross_state AS
SELECT
    CASE WHEN s.seller_state = t.customer_state THEN 'same state'
         ELSE 'cross state' END                                                       AS route,
    COUNT(*)                                                                          AS orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY t.delivery_days))::numeric, 2) AS median_delivery_days,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY t.promised_days))::numeric, 2) AS median_promised_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE t.is_late) / COUNT(*), 2)                    AS late_rate_pct
FROM timed_orders t
JOIN v_sellers s ON s.seller_id = t.single_seller_id
GROUP BY 1
UNION ALL
-- How many timed orders were left out because they have 2+ sellers
SELECT 'excluded: multi-seller', COUNT(*), NULL, NULL, NULL
FROM timed_orders
WHERE single_seller_id IS NULL;

\copy (SELECT * FROM q7_same_vs_cross_state ORDER BY route) TO 'results/11_same_vs_cross_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_same_vs_cross_state ORDER BY route;


-- =============================================================================
-- Q8. DISTANCE (optional)
-- Question: Does delivery time and lateness grow with seller-to-customer
--           distance?
-- Logic:    Single-seller orders. Coordinates come from v_geo (average point
--           per zip prefix), for the customer's and the seller's zip prefix.
--           So distance is between zip-prefix centres, an approximation.
--           Left out (and counted in Q8a): orders where either zip has no
--           v_geo row, or either point lies outside a rough Brazil bounding
--           box (lat -34 to 5.3, lng -74 to -34). That box catches bad
--           coordinates.
--           Haversine great-circle distance, Earth radius 6371 km:
--             d = 2R * asin( sqrt( sin^2(dlat/2)
--                                 + cos(lat1) cos(lat2) sin^2(dlng/2) ) )
--           with all angles converted to radians.
-- Result:   Coverage is good enough: 94,453 of 94,931 single-seller orders
--           used (99.50%). Left out: 258 missing customer geo, 213 missing
--           seller geo, 8 outside the box.
--           Bucket       orders | median days | promise | late %
--           0-50 km      11,591 |  4.90 | 14 |  4.48
--           50-200       12,688 |  6.47 | 18 |  4.71
--           200-500      29,722 | 10.00 | 23 |  6.48
--           500-1000     25,313 | 12.17 | 26 |  7.21
--           1000-2000     9,594 | 15.40 | 30 |  9.68
--           2000+         5,545 | 18.26 | 34 | 12.17
--           Delivery days, promised days and late rate all rise with every
--           distance band.
-- =============================================================================
CREATE TEMP VIEW geo_orders AS
SELECT
    t.order_id,
    t.is_late,
    t.delivery_days,
    t.promised_days,
    cg.lat AS c_lat, cg.lng AS c_lng,        -- customer zip centre (NULL if not in v_geo)
    sg.lat AS s_lat, sg.lng AS s_lng,        -- seller zip centre
    (cg.lat BETWEEN -34 AND 5.3 AND cg.lng BETWEEN -74 AND -34
     AND sg.lat BETWEEN -34 AND 5.3 AND sg.lng BETWEEN -74 AND -34) AS inside_brazil_box
FROM timed_orders t
JOIN v_sellers s     ON s.seller_id        = t.single_seller_id         -- single-seller only
LEFT JOIN v_geo cg   ON cg.zip_code_prefix = t.customer_zip_code_prefix -- one row per zip: no fan-out
LEFT JOIN v_geo sg   ON sg.zip_code_prefix = s.seller_zip_code_prefix;

-- Q8a: coverage. Is there enough coordinate data to use?
CREATE TEMP VIEW q8a_geo_coverage AS
SELECT
    COUNT(*)                                                             AS single_seller_orders,
    COUNT(*) FILTER (WHERE c_lat IS NULL)                                AS missing_customer_geo,
    COUNT(*) FILTER (WHERE s_lat IS NULL)                                AS missing_seller_geo,
    COUNT(*) FILTER (WHERE c_lat IS NOT NULL AND s_lat IS NOT NULL
                       AND NOT inside_brazil_box)                        AS outside_brazil_box,
    COUNT(*) FILTER (WHERE inside_brazil_box)                            AS orders_used,
    ROUND(100.0 * COUNT(*) FILTER (WHERE inside_brazil_box) / COUNT(*), 2) AS pct_used
FROM geo_orders;

\copy (SELECT * FROM q8a_geo_coverage) TO 'results/11_geo_coverage.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q8a_geo_coverage;

-- Q8b: distance buckets
CREATE TEMP VIEW q8b_distance AS
WITH d AS (
    SELECT
        is_late,
        delivery_days,
        promised_days,
        2 * 6371 * ASIN(SQRT(
              POWER(SIN(RADIANS(c_lat - s_lat) / 2), 2)
            + COS(RADIANS(s_lat)) * COS(RADIANS(c_lat))
              * POWER(SIN(RADIANS(c_lng - s_lng) / 2), 2)
        )) AS distance_km
    FROM geo_orders
    WHERE inside_brazil_box               -- also drops rows with missing coordinates (NULL)
)
SELECT
    CASE WHEN distance_km <   50 THEN 1
         WHEN distance_km <  200 THEN 2
         WHEN distance_km <  500 THEN 3
         WHEN distance_km < 1000 THEN 4
         WHEN distance_km < 2000 THEN 5
         ELSE 6 END                                                                 AS bucket_order,
    CASE WHEN distance_km <   50 THEN '0-50 km'
         WHEN distance_km <  200 THEN '50-200 km'
         WHEN distance_km <  500 THEN '200-500 km'
         WHEN distance_km < 1000 THEN '500-1000 km'
         WHEN distance_km < 2000 THEN '1000-2000 km'
         ELSE '2000+ km' END                                                        AS distance_bucket,
    COUNT(*)                                                                        AS orders,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 2) AS median_delivery_days,
    ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY promised_days))::numeric, 2) AS median_promised_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2)                    AS late_rate_pct
FROM d
GROUP BY 1, 2;

\copy (SELECT distance_bucket, orders, median_delivery_days, median_promised_days, late_rate_pct FROM q8b_distance ORDER BY bucket_order) TO 'results/11_distance_buckets.csv' WITH (FORMAT csv, HEADER true)
SELECT distance_bucket, orders, median_delivery_days, median_promised_days, late_rate_pct
FROM q8b_distance ORDER BY bucket_order;
