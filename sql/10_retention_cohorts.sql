-- =============================================================================
-- 10_retention_cohorts.sql: Business question 1, retention
-- "How many customers come back, and when?"
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/10_retention_cohorts.sql
-- Each query is saved to results/10_<name>.csv and printed.
--
-- Rules applied (decisions in docs/data_quality_notes.md):
--   * Reads only the clean views (v_order_facts), never raw tables.
--   * Window: purchases 2017-01-01 to 2018-08-31 (v_order_facts holds only these).
--   * A customer is customer_unique_id.
--   * Retention counts DELIVERED orders only. The order sequence is
--     recomputed here over delivered orders. v_order_facts.customer_order_seq
--     is NOT used, because it counts all statuses.
--
-- Known limitation: "first order" means first delivered order IN THE WINDOW.
-- A customer who also bought in 2016 still has their first in-window order
-- counted as their first.
--
-- Pattern used for every query:
--   CREATE TEMP VIEW qN_... AS <query>;     -- define once
--   \copy (SELECT * FROM qN_...) TO csv     -- save
--   SELECT * FROM qN_...;                   -- print
-- Temp views disappear when the psql session ends.
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- BUILDING BLOCK A: delivered_orders
-- GRAIN: one row per delivered order in the window.
-- Adds each customer's delivered-order sequence and the previous order's
-- timestamp (LAG). Ties on timestamp are broken by order_id so the
-- numbering is always the same.
-- =============================================================================
CREATE TEMP VIEW delivered_orders AS
SELECT
    order_id,
    customer_unique_id,
    customer_state,
    order_purchase_timestamp        AS purchased_at,
    order_purchase_timestamp::date  AS purchase_date,     -- calendar day
    purchase_month,
    item_value,
    main_category,
    main_payment_type,
    -- 1 = customer's first delivered order, 2 = second, ...
    ROW_NUMBER() OVER (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp, order_id
    ) AS delivered_seq,
    -- Timestamp of the customer's previous delivered order (NULL for the first)
    LAG(order_purchase_timestamp) OVER (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp, order_id
    ) AS prev_purchased_at,
    -- Calendar day of the customer's first delivered order, on every row
    MIN(order_purchase_timestamp::date) OVER (
        PARTITION BY customer_unique_id
    ) AS first_purchase_date
FROM v_order_facts
WHERE is_delivered;


-- =============================================================================
-- BUILDING BLOCK B: delivered_customers
-- GRAIN: one row per customer_unique_id with at least one delivered order.
-- One GROUP BY collapses each customer's orders. "MAX(x) FILTER (WHERE
-- delivered_seq = 1)" picks x from the first order: only one row has
-- delivered_seq = 1, so MAX just returns that row's value.
-- =============================================================================
CREATE TEMP VIEW delivered_customers AS
SELECT
    customer_unique_id,
    MIN(purchased_at)                                        AS first_purchased_at,
    MIN(purchase_date)                                       AS first_purchase_date,
    MIN(purchase_month)                                      AS cohort_month,
    COUNT(*)                                                 AS delivered_orders,
    -- When the 2nd delivered order happened (NULL if there isn't one)
    MIN(purchased_at) FILTER (WHERE delivered_seq = 2)       AS second_purchased_at,
    -- First delivered order on a LATER calendar day than the first order
    MIN(purchased_at) FILTER (WHERE purchase_date > first_purchase_date)
                                                             AS first_later_day_return_at,
    -- Attributes of the first order
    MAX(customer_state)    FILTER (WHERE delivered_seq = 1)  AS first_state,
    MAX(main_category)     FILTER (WHERE delivered_seq = 1)  AS first_category,
    MAX(main_payment_type) FILTER (WHERE delivered_seq = 1)  AS first_payment_type,
    MAX(item_value)        FILTER (WHERE delivered_seq = 1)  AS first_order_value
FROM delivered_orders
GROUP BY customer_unique_id;


-- =============================================================================
-- Q1. ORDERS PER CUSTOMER
-- Question: How many customers have 1, 2, 3, 4+ delivered orders?
-- Logic:    Bucket delivered_customers.delivered_orders, and add a repeat
--           rate row (2+ orders / all customers). It must equal the
--           baseline's 3.00%; the DO block below stops the script if not.
-- Result:   93,104 customers. 1 order: 90,315 (97.00%) | 2: 2,562 (2.75%) |
--           3: 180 (0.19%) | 4+: 47 (0.05%). Repeat (2+): 2,789 = 3.00%,
--           matches baseline.
-- =============================================================================
CREATE TEMP VIEW q1_orders_per_customer AS
SELECT
    CASE WHEN delivered_orders >= 4 THEN '4+'
         ELSE delivered_orders::text END                        AS delivered_orders,
    COUNT(*)                                                    AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_customers
FROM delivered_customers
GROUP BY 1
UNION ALL
SELECT
    'repeat (2+)',
    COUNT(*) FILTER (WHERE delivered_orders >= 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2)
FROM delivered_customers;

\copy (SELECT * FROM q1_orders_per_customer ORDER BY delivered_orders) TO 'results/10_orders_per_customer.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1_orders_per_customer ORDER BY delivered_orders;

-- Consistency check against the baseline method (04_baseline.sql counts
-- delivered orders per customer straight from v_order_facts).
DO $$
DECLARE
    rate_here     numeric;
    rate_baseline numeric;
BEGIN
    SELECT pct_of_customers INTO rate_here
    FROM q1_orders_per_customer WHERE delivered_orders = 'repeat (2+)';

    SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE n >= 2) / COUNT(*), 2) INTO rate_baseline
    FROM (SELECT customer_unique_id, COUNT(*) AS n
          FROM v_order_facts WHERE is_delivered
          GROUP BY customer_unique_id) c;

    IF rate_here <> rate_baseline THEN
        RAISE EXCEPTION 'Repeat rate % does not match baseline %', rate_here, rate_baseline;
    END IF;
    RAISE NOTICE 'Q1 repeat rate % matches baseline %', rate_here, rate_baseline;
END
$$;


-- =============================================================================
-- Q2. TIME TO SECOND ORDER
-- Question: For customers who come back, how long until the 2nd order?
-- Logic:    On the delivered_seq = 2 row, LAG gave the 1st order's
--           timestamp. Gap = calendar days between the two purchase dates
--           (0 = same day). Percentiles use percentile_cont. Buckets: same
--           day, 1-7, 8-30, 31-90, 91-180 and 180+ (181 days or more).
-- Result:   2,789 customers with a 2nd order. p25 = 0 days, median = 29,
--           p75 = 125, p90 = 245.
--           Buckets: same day 827 (29.65%) | 1-7: 198 (7.10%) |
--           8-30: 387 (13.88%) | 31-90: 492 (17.64%) | 91-180: 413 (14.81%) |
--           180+: 472 (16.92%).
-- =============================================================================
CREATE TEMP VIEW second_orders AS
SELECT
    customer_unique_id,
    purchase_date - prev_purchased_at::date AS days_to_second   -- date - date = integer days
FROM delivered_orders
WHERE delivered_seq = 2;

-- Q2a: percentiles
CREATE TEMP VIEW q2a_time_to_second_pct AS
SELECT
    COUNT(*)                                                                  AS customers_with_second_order,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY days_to_second)              AS p25_days,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY days_to_second)              AS median_days,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY days_to_second)              AS p75_days,
    percentile_cont(0.90) WITHIN GROUP (ORDER BY days_to_second)              AS p90_days
FROM second_orders;

\copy (SELECT * FROM q2a_time_to_second_pct) TO 'results/10_time_to_second_order_percentiles.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q2a_time_to_second_pct;

-- Q2b: buckets. bucket_order keeps the rows in a logical order.
CREATE TEMP VIEW q2b_time_to_second_buckets AS
SELECT
    bucket_order,
    bucket,
    COUNT(*)                                            AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_second_orders
FROM (
    SELECT
        CASE WHEN days_to_second = 0    THEN 1
             WHEN days_to_second <= 7   THEN 2
             WHEN days_to_second <= 30  THEN 3
             WHEN days_to_second <= 90  THEN 4
             WHEN days_to_second <= 180 THEN 5
             ELSE 6 END AS bucket_order,
        CASE WHEN days_to_second = 0    THEN 'same day'
             WHEN days_to_second <= 7   THEN '1-7'
             WHEN days_to_second <= 30  THEN '8-30'
             WHEN days_to_second <= 90  THEN '31-90'
             WHEN days_to_second <= 180 THEN '91-180'
             ELSE '180+' END AS bucket
    FROM second_orders
) b
GROUP BY bucket_order, bucket;

\copy (SELECT bucket, customers, pct_of_second_orders FROM q2b_time_to_second_buckets ORDER BY bucket_order) TO 'results/10_time_to_second_order_buckets.csv' WITH (FORMAT csv, HEADER true)
SELECT bucket, customers, pct_of_second_orders FROM q2b_time_to_second_buckets ORDER BY bucket_order;


-- =============================================================================
-- Q3. SAME-DAY CHECK
-- Question: How many "second orders" fall on the same calendar day as the
--           first? What is the repeat rate if only a return on a later
--           day counts?
-- Logic:    same-day share = second orders with days_to_second = 0 / all
--           second orders. Later-day repeat = customers with ANY delivered
--           order on a later calendar day (first_later_day_return_at is not
--           NULL). A customer whose 2nd order was same-day but whose 3rd was
--           later still counts.
-- Result:   827 of 2,789 second orders (29.65%) are same-day.
--           Repeat rate, any day:   2,789 / 93,104 = 3.00%
--           Repeat rate, later day: 2,005 / 93,104 = 2.15%
-- =============================================================================
CREATE TEMP VIEW q3_same_day_check AS
SELECT
    (SELECT COUNT(*) FROM second_orders)                                   AS second_orders,
    (SELECT COUNT(*) FROM second_orders WHERE days_to_second = 0)          AS same_day_second_orders,
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second = 0) / COUNT(*), 2)
       FROM second_orders)                                                 AS same_day_pct_of_second_orders,
    COUNT(*)                                                               AS customers,
    COUNT(*) FILTER (WHERE delivered_orders >= 2)                          AS repeat_customers_any_day,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2)
                                                                           AS repeat_rate_any_day_pct,
    COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL)          AS repeat_customers_later_day,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL) / COUNT(*), 2)
                                                                           AS repeat_rate_later_day_pct
FROM delivered_customers;

\copy (SELECT * FROM q3_same_day_check) TO 'results/10_same_day_check.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3_same_day_check;

-- -----------------------------------------------------------------------------
-- Q3b. HOW FAR APART ARE SAME-DAY SECOND ORDERS?
-- Question: Are same-day "second orders" real return visits, or the same
--           checkout recorded as several orders?
-- Logic:    For 2nd orders on the same calendar day as the 1st, measure the
--           gap in minutes (EPOCH seconds / 60).
-- Result:   827 same-day second orders. 253 have the IDENTICAL timestamp,
--           735 come within 10 minutes, median gap = 0.0167 minutes (1 second).
--           Consistent with one checkout split into several orders, not
--           a return visit. The data can't prove the cause.
-- -----------------------------------------------------------------------------
CREATE TEMP VIEW q3b_same_day_gap AS
SELECT
    COUNT(*)                                                     AS same_day_second_orders,
    COUNT(*) FILTER (WHERE purchased_at = prev_purchased_at)     AS identical_timestamp,
    COUNT(*) FILTER (WHERE purchased_at - prev_purchased_at <= INTERVAL '10 minutes')
                                                                 AS within_10_minutes,
    ROUND((percentile_cont(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM purchased_at - prev_purchased_at) / 60))::numeric, 4)
                                                                 AS median_minutes_apart
FROM delivered_orders
WHERE delivered_seq = 2
  AND purchase_date = prev_purchased_at::date;

\copy (SELECT * FROM q3b_same_day_gap) TO 'results/10_same_day_gap.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3b_same_day_gap;


-- =============================================================================
-- Q4. MONTHLY COHORT MATRIX
-- Question: Of customers whose first delivered order was in month X, what
--           share bought again 1, 2, ... 12 months later?
-- Logic:    cohort = month of first delivered order.
--           months_since = (order month) - (cohort month), counted in months.
--           A customer is "active" in a cell if they have >= 1 delivered
--           order in that month (DISTINCT, so 2 orders = 1 active customer).
--           A grid (every cohort x months 0..12) makes empty cells show up.
--           Cells after 2018-08 can't be observed yet: NULL, not 0.
--           Month 0 is 100% by definition.
-- Result:   20 cohorts (2017-01 to 2018-08), 260 cells, 78 of them NULL
--           (not yet observable). Every observable cell for months 1-12 is
--           under 1%; the highest is 0.72% (2017-10, month 1). There is no
--           cohort whose retention clearly stands out.
-- =============================================================================
CREATE TEMP VIEW q4_cohort_long AS
WITH cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM delivered_customers
    GROUP BY cohort_month
),
activity AS (
    -- One row per (customer, month they were active in), with months since cohort.
    -- year*12 + month turns a date into a running month number.
    SELECT DISTINCT
        c.cohort_month,
        o.customer_unique_id,
        ( (EXTRACT(YEAR FROM o.purchase_month) * 12 + EXTRACT(MONTH FROM o.purchase_month))
        - (EXTRACT(YEAR FROM c.cohort_month)   * 12 + EXTRACT(MONTH FROM c.cohort_month)) )::int
            AS months_since
    FROM delivered_orders o
    JOIN delivered_customers c ON c.customer_unique_id = o.customer_unique_id
),
grid AS (
    -- Every cohort paired with every month offset 0..12
    SELECT s.cohort_month, s.cohort_customers, m.months_since
    FROM cohort_size s
    CROSS JOIN generate_series(0, 12) AS m(months_since)
)
SELECT
    g.cohort_month,
    g.cohort_customers,
    g.months_since,
    -- Observable only if the calendar month of this cell is 2018-08 or earlier
    CASE WHEN g.cohort_month + g.months_since * INTERVAL '1 month' <= DATE '2018-08-01'
         THEN COUNT(a.customer_unique_id) END                                AS active_customers,
    CASE WHEN g.cohort_month + g.months_since * INTERVAL '1 month' <= DATE '2018-08-01'
         THEN ROUND(100.0 * COUNT(a.customer_unique_id) / g.cohort_customers, 2) END
                                                                            AS pct_of_cohort
FROM grid g
LEFT JOIN activity a
       ON a.cohort_month = g.cohort_month
      AND a.months_since = g.months_since
GROUP BY g.cohort_month, g.cohort_customers, g.months_since;

\copy (SELECT * FROM q4_cohort_long ORDER BY cohort_month, months_since) TO 'results/10_cohort_matrix_long.csv' WITH (FORMAT csv, HEADER true)

-- Wide version (one row per cohort, one column per month offset) for reading
-- and charting. MAX(...) FILTER picks the single value for each column.
CREATE TEMP VIEW q4_cohort_wide_pct AS
SELECT
    cohort_month,
    cohort_customers,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 0)  AS m0,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 1)  AS m1,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 2)  AS m2,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 3)  AS m3,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 4)  AS m4,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 5)  AS m5,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 6)  AS m6,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 7)  AS m7,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 8)  AS m8,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 9)  AS m9,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 10) AS m10,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 11) AS m11,
    MAX(pct_of_cohort) FILTER (WHERE months_since = 12) AS m12
FROM q4_cohort_long
GROUP BY cohort_month, cohort_customers;

\copy (SELECT * FROM q4_cohort_wide_pct ORDER BY cohort_month) TO 'results/10_cohort_matrix_pct.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4_cohort_wide_pct ORDER BY cohort_month;


-- =============================================================================
-- Q5. FIXED-WINDOW REPEAT RATE (90 and 180 days)
-- Question: What share of customers order again within 90 / 180 days of
--           their first order?
-- Logic:    A customer counts only if the full window is observed, i.e.
--           first order + N days is before the data ends (2018-09-01).
--           "Returned within N days" = 2nd delivered order no later than
--           first order + N days. The "later-day" columns count only a
--           return on a later calendar day than the first order (see Q3).
--           One row per cohort month, plus an 'overall' row. Rates are NULL
--           where no customer in the cohort is eligible.
-- Result:   Overall 90-day:  75,448 eligible, 2.28% return (1.30% later-day).
--           Overall 180-day: 56,194 eligible, 3.12% return (1.97% later-day).
--           Partial cohorts (only early-month customers eligible): 2018-03
--           for 180d (927 of 6,775), 2018-06 for 90d (316 of 5,879). Read
--           those rows with care.
-- =============================================================================
CREATE TEMP VIEW customer_windows AS
SELECT
    cohort_month,
    first_purchased_at + INTERVAL '90 days'  < TIMESTAMP '2018-09-01'                 AS eligible_90,
    first_purchased_at + INTERVAL '180 days' < TIMESTAMP '2018-09-01'                 AS eligible_180,
    COALESCE(second_purchased_at       <= first_purchased_at + INTERVAL '90 days',  false) AS returned_90,
    COALESCE(second_purchased_at       <= first_purchased_at + INTERVAL '180 days', false) AS returned_180,
    COALESCE(first_later_day_return_at <= first_purchased_at + INTERVAL '90 days',  false) AS returned_90_later_day,
    COALESCE(first_later_day_return_at <= first_purchased_at + INTERVAL '180 days', false) AS returned_180_later_day
FROM delivered_customers;
-- COALESCE(..., false): a customer with no second order has NULL there.
-- A comparison with NULL gives NULL, which COALESCE turns into "did not return".

CREATE TEMP VIEW q5_fixed_window AS
SELECT
    cohort_month::text                                                         AS cohort,
    COUNT(*) FILTER (WHERE eligible_90)                                        AS eligible_90,
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_90 AND returned_90)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_90), 0), 2)                 AS repeat_90d_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_90 AND returned_90_later_day)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_90), 0), 2)                 AS repeat_90d_later_day_pct,
    COUNT(*) FILTER (WHERE eligible_180)                                       AS eligible_180,
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_180 AND returned_180)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_180), 0), 2)                AS repeat_180d_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_180 AND returned_180_later_day)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_180), 0), 2)                AS repeat_180d_later_day_pct
FROM customer_windows
GROUP BY cohort_month
UNION ALL
SELECT
    'overall',
    COUNT(*) FILTER (WHERE eligible_90),
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_90 AND returned_90)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_90), 0), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_90 AND returned_90_later_day)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_90), 0), 2),
    COUNT(*) FILTER (WHERE eligible_180),
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_180 AND returned_180)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_180), 0), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_180 AND returned_180_later_day)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_180), 0), 2)
FROM customer_windows;

\copy (SELECT * FROM q5_fixed_window ORDER BY cohort) TO 'results/10_fixed_window_repeat.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5_fixed_window ORDER BY cohort;


-- =============================================================================
-- Q6. WHO COMES BACK
-- Question: Does the repeat rate differ by what / where / how the customer
--           first bought?
-- Logic:    Segment delivered_customers by attributes of their FIRST
--           delivered order. repeat_rate = 2+ delivered orders; later-day
--           rate as in Q3. Category only where 500+ first-time customers.
--           Value quartile: NTILE(4) over first-order item value
--           (1 = cheapest 25%).
-- Result:   Category (26 with 500+): highest home_appliances 8.74% (but
--           later-day only 1.78%), fashion_bags_accessories 5.63%,
--           furniture_decor 4.61%, bed_bath_table 4.44%; lowest electronics
--           1.63%. State: large states 2.65-3.26% (SP 3.11%, RJ 3.26%,
--           MG 2.93%); small states are too small to read. Payment:
--           credit_card 2.99%, boleto 2.99%, voucher 3.64%, debit_card 2.29%.
--           Value quartile: 3.15% / 3.12% / 2.89% / 2.81% (cheapest to
--           priciest). Only a small decline. NTILE splits tied values, so
--           boundary values (e.g. 45.90) appear in two quartiles.
-- =============================================================================

-- Q6a: by main category of the first order (500+ customers only)
CREATE TEMP VIEW q6a_by_category AS
SELECT
    first_category                                                             AS category,
    COUNT(*)                                                                   AS customers,
    COUNT(*) FILTER (WHERE delivered_orders >= 2)                              AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2) AS repeat_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL) / COUNT(*), 2)
                                                                               AS repeat_rate_later_day_pct
FROM delivered_customers
GROUP BY first_category
HAVING COUNT(*) >= 500;

\copy (SELECT * FROM q6a_by_category ORDER BY repeat_rate_pct DESC) TO 'results/10_repeat_by_category.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6a_by_category ORDER BY repeat_rate_pct DESC;

-- Q6b: by customer state at first order (all states; check customer counts
-- before reading small states)
CREATE TEMP VIEW q6b_by_state AS
SELECT
    first_state                                                                AS state,
    COUNT(*)                                                                   AS customers,
    COUNT(*) FILTER (WHERE delivered_orders >= 2)                              AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2) AS repeat_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL) / COUNT(*), 2)
                                                                               AS repeat_rate_later_day_pct
FROM delivered_customers
GROUP BY first_state;

\copy (SELECT * FROM q6b_by_state ORDER BY customers DESC) TO 'results/10_repeat_by_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6b_by_state ORDER BY customers DESC;

-- Q6c: by main payment type of the first order
CREATE TEMP VIEW q6c_by_payment AS
SELECT
    first_payment_type                                                         AS payment_type,
    COUNT(*)                                                                   AS customers,
    COUNT(*) FILTER (WHERE delivered_orders >= 2)                              AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2) AS repeat_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL) / COUNT(*), 2)
                                                                               AS repeat_rate_later_day_pct
FROM delivered_customers
GROUP BY first_payment_type;

\copy (SELECT * FROM q6c_by_payment ORDER BY customers DESC) TO 'results/10_repeat_by_payment_type.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6c_by_payment ORDER BY customers DESC;

-- Q6d: by first-order value quartile
CREATE TEMP VIEW q6d_by_value_quartile AS
SELECT
    value_quartile,
    MIN(first_order_value)                                                     AS min_value,
    MAX(first_order_value)                                                     AS max_value,
    COUNT(*)                                                                   AS customers,
    COUNT(*) FILTER (WHERE delivered_orders >= 2)                              AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders >= 2) / COUNT(*), 2) AS repeat_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL) / COUNT(*), 2)
                                                                               AS repeat_rate_later_day_pct
FROM (
    -- NTILE(4) splits customers, sorted by first-order value, into 4 equal-sized groups
    SELECT *, NTILE(4) OVER (ORDER BY first_order_value) AS value_quartile
    FROM delivered_customers
) q
GROUP BY value_quartile;

\copy (SELECT * FROM q6d_by_value_quartile ORDER BY value_quartile) TO 'results/10_repeat_by_value_quartile.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6d_by_value_quartile ORDER BY value_quartile;


-- =============================================================================
-- Q7. REVENUE FROM REPEAT CUSTOMERS
-- Question: What share of delivered revenue comes from 2nd and later orders?
-- Logic:    Revenue = item_value on delivered orders (C4).
--           Split by delivered_seq = 1 vs >= 2. Total must equal the
--           baseline revenue (13,181,027.13). For context, also the share
--           from repeat customers' orders including their first.
-- Result:   Total 13,181,027.13 (matches baseline). 2nd+ orders: 381,515.75
--           = 2.89% of revenue (3,107 orders = 3.23% of delivered orders).
--           All orders of repeat customers, incl. their first: 5.50%.
-- =============================================================================
CREATE TEMP VIEW q7_repeat_revenue AS
SELECT
    SUM(o.item_value)                                                    AS total_revenue,
    SUM(o.item_value) FILTER (WHERE o.delivered_seq = 1)                 AS first_order_revenue,
    SUM(o.item_value) FILTER (WHERE o.delivered_seq >= 2)                AS repeat_order_revenue,
    ROUND(100.0 * SUM(o.item_value) FILTER (WHERE o.delivered_seq >= 2)
          / SUM(o.item_value), 2)                                        AS repeat_order_revenue_pct,
    COUNT(*) FILTER (WHERE o.delivered_seq >= 2)                         AS repeat_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.delivered_seq >= 2) / COUNT(*), 2)
                                                                         AS repeat_orders_pct,
    -- All orders (incl. first) of customers who have 2+ delivered orders
    ROUND(100.0 * SUM(o.item_value) FILTER (WHERE c.delivered_orders >= 2)
          / SUM(o.item_value), 2)                                        AS repeat_customers_all_orders_revenue_pct
FROM delivered_orders o
JOIN delivered_customers c ON c.customer_unique_id = o.customer_unique_id;

\copy (SELECT * FROM q7_repeat_revenue) TO 'results/10_repeat_revenue.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_repeat_revenue;
