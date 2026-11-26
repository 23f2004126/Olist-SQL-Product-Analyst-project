-- =============================================================================
-- 12_review_drivers.sql: Business question 3, reviews
-- "What drives 1 and 2 star reviews, and does a bad first order stop
--  customers coming back?"
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/12_review_drivers.sql
-- Each query is saved to results/12_<name>.csv and printed.
--
-- Scope (decisions in docs/data_quality_notes.md):
--   * In-window orders (v_order_facts) that have a review. The review is the
--     LATEST review per order (v_order_review).
--   * Low review = score 1 or 2.
--   * Late = delivered on a later calendar day than estimated (is_late).
--     It exists only for delivered orders with a delivery date.
--   * Repeat customer = returned on a LATER calendar day (C12).
--   * Reads clean views only (v_order_facts).
--
-- Unless a query says otherwise, the population is ALL reviewed orders,
-- including undelivered ones. Q6 and Q7 separate those out.
--
-- Describes what the data shows; it doesn't claim causes.
--
-- Pattern for every query:
--   CREATE TEMP VIEW qN_... AS <query>;   \copy it to CSV;   SELECT it.
-- Shares are percentages rounded to 2 decimals.
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- BUILDING BLOCK: reviewed_orders
-- GRAIN: one row per in-window order with a review.
-- is_low_review is a 1/0 flag, so AVG(is_low_review) * 100 = low-review share.
-- =============================================================================
CREATE TEMP VIEW reviewed_orders AS
SELECT
    f.*,
    CASE WHEN f.review_score <= 2 THEN 1 ELSE 0 END AS is_low_review
FROM v_order_facts f
WHERE f.review_score IS NOT NULL;


-- =============================================================================
-- Q1. SCORE DISTRIBUTION
-- Question: How are review scores spread?
-- Logic:    Count reviewed orders per score; share = count / total.
-- Result:   98,330 reviewed orders. 1: 11,263 (11.45%) | 2: 3,119 (3.17%) |
--           3: 8,110 (8.25%) | 4: 18,986 (19.31%) | 5: 56,852 (57.82%).
--           Low reviews (1-2): 14,382.
-- =============================================================================
CREATE TEMP VIEW q1_score_distribution AS
SELECT
    review_score,
    COUNT(*)                                            AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_reviews
FROM reviewed_orders
GROUP BY review_score;

\copy (SELECT * FROM q1_score_distribution ORDER BY review_score) TO 'results/12_score_distribution.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1_score_distribution ORDER BY review_score;


-- =============================================================================
-- Q2. BY DELAY BUCKET
-- Question: How do scores change with how early or late the order arrived?
-- Logic:    Same delay_days buckets as 11_delivery_performance.sql Q3.
--           Orders with no delivery timing (undelivered, or delivered
--           without a date) have no delay_days. They get their own row so
--           every reviewed order is counted once.
-- Result:   bucket              orders | avg  | low %
--           7+ days early       75,487 | 4.31 |  8.98
--           1-6 days early      12,415 | 4.18 | 10.58
--           on the day           1,280 | 4.03 | 12.42
--           1-3 days late        1,851 | 3.29 | 32.14
--           4-7 days late        1,748 | 2.10 | 67.68
--           8+ days late         2,779 | 1.70 | 79.27
--           no delivery timing   2,770 | 1.75 | 77.76
--           The low-review share rises at every step; the largest jump is
--           from 'on the day' to late.
-- =============================================================================
CREATE TEMP VIEW q2_by_delay AS
SELECT
    bucket_order,
    bucket,
    COUNT(*)                               AS orders,
    ROUND(AVG(review_score), 2)            AS avg_score,
    ROUND(100.0 * AVG(is_low_review), 2)   AS low_review_pct
FROM (
    SELECT
        review_score,
        is_low_review,
        CASE WHEN delay_days IS NULL THEN 7
             WHEN delay_days <= -7   THEN 1
             WHEN delay_days <= -1   THEN 2
             WHEN delay_days =  0    THEN 3
             WHEN delay_days <=  3   THEN 4
             WHEN delay_days <=  7   THEN 5
             ELSE 6 END AS bucket_order,
        CASE WHEN delay_days IS NULL THEN 'no delivery timing'
             WHEN delay_days <= -7   THEN '7+ days early'
             WHEN delay_days <= -1   THEN '1-6 days early'
             WHEN delay_days =  0    THEN 'on the day'
             WHEN delay_days <=  3   THEN '1-3 days late'
             WHEN delay_days <=  7   THEN '4-7 days late'
             ELSE '8+ days late' END AS bucket
    FROM reviewed_orders
) b
GROUP BY bucket_order, bucket;

\copy (SELECT bucket, orders, avg_score, low_review_pct FROM q2_by_delay ORDER BY bucket_order) TO 'results/12_by_delay_bucket.csv' WITH (FORMAT csv, HEADER true)
SELECT bucket, orders, avg_score, low_review_pct FROM q2_by_delay ORDER BY bucket_order;


-- =============================================================================
-- Q3. SPEED AMONG ON-TIME ORDERS
-- Question: If the order arrived on time, does a slower delivery still go
--           with lower scores?
-- Logic:    Only on-time orders (is_late = false). Band by actual calendar
--           days from purchase to delivery = promised_days + delay_days
--           (whole days, the same basis as the on-time rule; the identity is
--           asserted in file 11). Bands: 0-7, 8-14, 15-21, 22+.
-- Result:   0-7: 30,442 orders, avg 4.41, low 7.54% | 8-14: 37,361, 4.31,
--           8.86% | 15-21: 15,414, 4.16, 11.03% | 22+: 5,965, 3.90, 15.78%.
--           Even among on-time orders, slower delivery goes with lower scores.
-- =============================================================================
CREATE TEMP VIEW q3_ontime_speed AS
SELECT
    band_order,
    band,
    COUNT(*)                               AS orders,
    ROUND(AVG(review_score), 2)            AS avg_score,
    ROUND(100.0 * AVG(is_low_review), 2)   AS low_review_pct
FROM (
    SELECT
        review_score,
        is_low_review,
        CASE WHEN promised_days + delay_days <= 7  THEN 1
             WHEN promised_days + delay_days <= 14 THEN 2
             WHEN promised_days + delay_days <= 21 THEN 3
             ELSE 4 END AS band_order,
        CASE WHEN promised_days + delay_days <= 7  THEN '0-7 days'
             WHEN promised_days + delay_days <= 14 THEN '8-14 days'
             WHEN promised_days + delay_days <= 21 THEN '15-21 days'
             ELSE '22+ days' END AS band
    FROM reviewed_orders
    WHERE is_late = false          -- on-time only; NULL (no timing) is excluded too
) b
GROUP BY band_order, band;

\copy (SELECT band, orders, avg_score, low_review_pct FROM q3_ontime_speed ORDER BY band_order) TO 'results/12_ontime_speed.csv' WITH (FORMAT csv, HEADER true)
SELECT band, orders, avg_score, low_review_pct FROM q3_ontime_speed ORDER BY band_order;


-- =============================================================================
-- Q4. ORDER MAKE-UP
-- Question: Do orders with several items, or several sellers, get lower
--           scores?
-- Logic:    item_count and seller_count come from v_order_items_agg. Orders
--           with no items (cancelled / unavailable before items were
--           recorded) have NULL counts and get a 'no items' row.
--           All reviewed orders, so undelivered orders are included. Q7
--           shows how much of the low-review volume each group carries.
-- Result:   Single item: 87,954 orders, avg 4.16, low 12.67% | multi item:
--           9,655, 3.60, 27.61%. Single seller: 96,349, 4.12, 13.72% |
--           multi seller: 1,260, 2.86, 47.22%. No items: 721, 1.73, 79.06%.
-- =============================================================================
CREATE TEMP VIEW q4_order_makeup AS
SELECT
    'items' AS dimension,
    CASE WHEN item_count IS NULL THEN 'no items'
         WHEN item_count = 1     THEN 'single item'
         ELSE 'multi item' END                AS order_group,
    COUNT(*)                                  AS orders,
    ROUND(AVG(review_score), 2)               AS avg_score,
    ROUND(100.0 * AVG(is_low_review), 2)      AS low_review_pct
FROM reviewed_orders
GROUP BY 2
UNION ALL
SELECT
    'sellers',
    CASE WHEN seller_count IS NULL THEN 'no items'
         WHEN seller_count = 1     THEN 'single seller'
         ELSE 'multi seller' END,
    COUNT(*),
    ROUND(AVG(review_score), 2),
    ROUND(100.0 * AVG(is_low_review), 2)
FROM reviewed_orders
GROUP BY 2;

\copy (SELECT * FROM q4_order_makeup ORDER BY dimension, orders DESC) TO 'results/12_order_makeup.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4_order_makeup ORDER BY dimension, orders DESC;


-- =============================================================================
-- Q5. BY MAIN CATEGORY
-- Question: Which categories get the most and the fewest low reviews?
-- Logic:    Main category = category with the highest item value in the
--           order (v_order_main_category). Keep categories with 500+
--           reviewed orders. Rank by low-review share both ways with
--           ROW_NUMBER and keep the top 10 of each. Ties are broken by
--           category name.
-- Result:   27 categories have 500+ reviewed orders. Highest low-review
--           share: office_furniture 22.39%, unknown 19.11%, bed_bath_table
--           16.59%, furniture_decor 16.16%, computers_accessories 15.98%.
--           Lowest: books_general_interest 8.13%, luggage_accessories 9.17%,
--           stationery 11.13%. Full top and bottom 10 in the CSV. The range
--           across categories (8.13-22.39%) is much narrower than across
--           delay buckets (8.98-79.27%).
-- =============================================================================
CREATE TEMP VIEW q5_by_category AS
WITH cat AS (
    SELECT
        main_category                          AS category,
        COUNT(*)                               AS orders,
        ROUND(AVG(review_score), 2)            AS avg_score,
        ROUND(100.0 * AVG(is_low_review), 2)   AS low_review_pct
    FROM reviewed_orders
    WHERE main_category IS NOT NULL            -- orders with no items have no category
    GROUP BY main_category
    HAVING COUNT(*) >= 500
),
ranked AS (
    SELECT
        cat.*,
        ROW_NUMBER() OVER (ORDER BY low_review_pct DESC, category) AS rank_highest,
        ROW_NUMBER() OVER (ORDER BY low_review_pct ASC,  category) AS rank_lowest,
        COUNT(*) OVER ()                                           AS categories_500plus
    FROM cat
)
SELECT 'highest low-review share' AS list, rank_highest AS rank, category, orders,
       avg_score, low_review_pct, categories_500plus
FROM ranked WHERE rank_highest <= 10
UNION ALL
SELECT 'lowest low-review share', rank_lowest, category, orders,
       avg_score, low_review_pct, categories_500plus
FROM ranked WHERE rank_lowest <= 10;

\copy (SELECT * FROM q5_by_category ORDER BY list, rank) TO 'results/12_by_category.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5_by_category ORDER BY list, rank;


-- =============================================================================
-- Q6. BY ORDER STATUS
-- Question: How do scores differ by what happened to the order?
-- Logic:    delivered, canceled, unavailable and shipped as named groups;
--           every other status (invoiced, processing, created, approved)
--           goes into 'other'.
-- Result:   delivered 95,568 orders, avg 4.16, low 12.80% | shipped 1,024,
--           2.00, 69.43% | other 589, 1.45, 87.61% | unavailable 588, 1.53,
--           84.86% | canceled 561, 1.81, 76.11%.
-- =============================================================================
CREATE TEMP VIEW q6_by_status AS
SELECT
    CASE WHEN order_status IN ('delivered', 'canceled', 'unavailable', 'shipped')
         THEN order_status ELSE 'other' END   AS status_group,
    COUNT(*)                                  AS orders,
    ROUND(AVG(review_score), 2)               AS avg_score,
    ROUND(100.0 * AVG(is_low_review), 2)      AS low_review_pct
FROM reviewed_orders
GROUP BY 1;

\copy (SELECT * FROM q6_by_status ORDER BY orders DESC) TO 'results/12_by_status.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6_by_status ORDER BY orders DESC;


-- =============================================================================
-- Q7. SIZING: WHERE DO LOW REVIEWS COME FROM?
-- Question: Of all low reviews, what share come from (a) undelivered orders,
--           (b) late delivered orders, (c) on-time multi-seller orders,
--           (d) everything else?
-- Logic:    A CASE puts each order in exactly ONE group: it stops at the
--           first condition that is true, so the order of the WHEN lines
--           is the priority:
--             (a) not delivered                          (status <> delivered)
--             (b) delivered and late                     (is_late = true)
--             (c) delivered, on time, 2+ sellers         (is_late = false AND seller_count >= 2)
--             (d) everything else: on-time single-seller orders, plus the
--                 few delivered orders with no delivery date (is_late NULL)
--           Shares are of all low reviews. The DO block below checks the
--           groups add up to the total and stops the script if not.
--           Also shown per group: its total orders and its own low-review
--           rate, to compare share of the problem with size of the group.
-- Result:   14,382 low reviews (check passed: groups add up).
--           group                    low reviews | % of low | % of orders | low rate
--           a) undelivered                 2,153 |  14.97   |   2.81      | 77.95
--           b) late delivered              3,981 |  27.68   |   6.49      | 62.42
--           c) on-time multi-seller          584 |   4.06   |   1.27      | 46.87
--           d) everything else             7,664 |  53.29   |  89.44      |  8.71
--           Groups a-c are small but low-review rates there are high.
--           Group d has a low rate but, being 89.44% of orders, still
--           holds the majority of low reviews.
-- =============================================================================
CREATE TEMP VIEW low_review_groups AS
SELECT
    order_id,
    is_low_review,
    CASE WHEN NOT is_delivered                        THEN 'a) undelivered'
         WHEN is_late IS TRUE                         THEN 'b) late delivered'
         WHEN is_late IS FALSE AND seller_count >= 2  THEN 'c) on-time multi-seller'
         ELSE 'd) everything else' END AS sizing_group
FROM reviewed_orders;

CREATE TEMP VIEW q7_sizing AS
SELECT
    sizing_group,
    SUM(is_low_review)                                               AS low_reviews,
    ROUND(100.0 * SUM(is_low_review) / SUM(SUM(is_low_review)) OVER (), 2)
                                                                     AS pct_of_low_reviews,
    COUNT(*)                                                         AS reviewed_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct_of_reviewed_orders,
    ROUND(100.0 * AVG(is_low_review), 2)                             AS low_review_rate_pct
FROM low_review_groups
GROUP BY sizing_group;

\copy (SELECT * FROM q7_sizing ORDER BY sizing_group) TO 'results/12_low_review_sizing.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_sizing ORDER BY sizing_group;

-- Check: the four groups must add up to all low reviews (no gaps, no overlap).
-- Each order gets exactly one CASE label, so overlap is impossible; this
-- confirms nothing was lost.
DO $$
DECLARE
    total_low   bigint;
    grouped_low bigint;
BEGIN
    SELECT SUM(is_low_review) INTO total_low   FROM reviewed_orders;
    SELECT SUM(low_reviews)   INTO grouped_low FROM q7_sizing;
    IF total_low <> grouped_low THEN
        RAISE EXCEPTION 'Sizing groups (%) do not add up to total low reviews (%)', grouped_low, total_low;
    END IF;
    RAISE NOTICE 'Q7 check passed: groups add up to % low reviews.', total_low;
END
$$;


-- =============================================================================
-- Q8. REVIEW TIMING
-- Question: How often is the review created before the order was delivered,
--           and how do those reviews score?
-- Logic:    Delivered orders with a delivery date only. Compare calendar
--           days, because review_creation_date is almost always 00:00:00:
--           "before delivery" = review date < delivered date. Groups:
--           on-time / late x before / on-or-after delivery. pct_within is
--           the share inside the on-time or late group.
-- Result:   On time: 221 (0.25%) reviewed before delivery, low 17.65%;
--           88,961 (99.75%) on or after, low 9.23%.
--           Late: 4,749 (74.46%) reviewed BEFORE delivery, avg 1.84, low
--           75.22%; 1,629 (25.54%) on or after, avg 3.53, low 25.11%.
-- =============================================================================
CREATE TEMP VIEW q8_review_timing AS
SELECT
    CASE WHEN is_late THEN 'late' ELSE 'on_time' END                            AS delivery_group,
    CASE WHEN review_creation_date::date < order_delivered_customer_date::date
         THEN 'before delivery' ELSE 'on or after delivery' END                 AS review_timing,
    COUNT(*)                                                                    AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY is_late), 2)      AS pct_within_delivery_group,
    ROUND(AVG(review_score), 2)                                                 AS avg_score,
    ROUND(100.0 * AVG(is_low_review), 2)                                        AS low_review_pct
FROM reviewed_orders
WHERE has_delivery_timing
GROUP BY is_late, 2;

\copy (SELECT * FROM q8_review_timing ORDER BY delivery_group DESC, review_timing) TO 'results/12_review_timing.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q8_review_timing ORDER BY delivery_group DESC, review_timing;

-- -----------------------------------------------------------------------------
-- Q8b. WHEN IS THE REVIEW CREATED, RELATIVE TO THE PROMISE AND THE DELIVERY?
-- Question: Where does review creation fall: near the estimated date or
--           near the delivery date?
-- Logic:    Median calendar-day gap from the estimated date and from the
--           delivered date to review_creation_date, for on-time vs late.
--           Positive = review created after that date.
-- Result:   On time (89,182): median 12 days BEFORE the estimate, 1 day
--           AFTER delivery.
--           Late (6,378): median 2 days AFTER the estimate, 4 days BEFORE
--           delivery.
--           For late orders the review is typically created soon after
--           the promised date has passed, while the customer is still waiting.
--           This describes the timing only; the data doesn't say how
--           Olist triggers the review request.
-- -----------------------------------------------------------------------------
CREATE TEMP VIEW q8b_review_creation_gap AS
SELECT
    CASE WHEN is_late THEN 'late' ELSE 'on_time' END                         AS delivery_group,
    COUNT(*)                                                                 AS orders,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY review_creation_date::date - order_estimated_delivery_date::date)
                                                                             AS median_days_after_estimate,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY review_creation_date::date - order_delivered_customer_date::date)
                                                                             AS median_days_after_delivery
FROM reviewed_orders
WHERE has_delivery_timing
GROUP BY is_late;

\copy (SELECT * FROM q8b_review_creation_gap ORDER BY delivery_group DESC) TO 'results/12_review_creation_gap.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q8b_review_creation_gap ORDER BY delivery_group DESC;


-- =============================================================================
-- Q9. FIRST ORDER AND RETURN
-- Question: Do customers whose first order was late, or badly reviewed, come
--           back less often?
-- Logic:    Rebuild each customer's delivered-order sequence exactly as in
--           10_retention_cohorts.sql (delivered in-window orders, ordered by
--           purchase time, then order_id). Take attributes of the FIRST
--           delivered order: is_late and review_score.
--           Repeat = a delivered order on a LATER calendar day (C12).
--           Two versions:
--             * all-time: any later-day return within the window
--             * 180-day: later-day return within 180 days of the first
--               order, only for customers whose first order + 180 days is
--               before 2018-09-01 (same rule as file 10, Q5)
--           An 'all' row per dimension should equal file 10's figures:
--           2.15% (all-time later-day) and 1.97% (180-day later-day).
-- Result:   'all' rows: 93,104 customers, 2.15%; 180-day 56,194 eligible,
--           1.97%. Both match file 10.
--           first order          customers | repeat %  | 180d eligible | 180d %
--           on time                 86,744 |   2.19    |   52,264      | 2.00
--           late                     6,352 |   1.62    |    3,928      | 1.58
--           no delivery timing           8 |   0.00    |        2      | 0.00
--           review 4-5              72,974 |   2.24    |   43,443      | 2.03
--           review 3                 7,648 |   1.97    |    4,888      | 1.94
--           review 1-2              11,870 |   1.72    |    7,446      | 1.65
--           no review                  612 |   2.12    |      417      | 1.20
--           Late or badly reviewed first orders go with lower return rates,
--           in both versions, but the gaps are small (about half a
--           percentage point) and rest on few returners (late: 103
--           all-time, 62 in 180 days). No significance test was run.
-- =============================================================================

-- Delivered orders with each customer's sequence and first purchase date
CREATE TEMP VIEW delivered_seq AS
SELECT
    customer_unique_id,
    order_purchase_timestamp                       AS purchased_at,
    order_purchase_timestamp::date                 AS purchase_date,
    is_late,
    review_score,
    ROW_NUMBER() OVER (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp, order_id
    )                                              AS delivered_seq,
    MIN(order_purchase_timestamp::date) OVER (
        PARTITION BY customer_unique_id
    )                                              AS first_purchase_date
FROM v_order_facts
WHERE is_delivered;

-- GRAIN: one row per customer. MAX(...) FILTER (WHERE delivered_seq = 1)
-- picks the value from the single first-order row (same trick as file 10).
CREATE TEMP VIEW first_order_customers AS
SELECT
    customer_unique_id,
    MIN(purchased_at)                                                     AS first_purchased_at,
    BOOL_OR(is_late)      FILTER (WHERE delivered_seq = 1)                AS first_is_late,
    MAX(review_score)     FILTER (WHERE delivered_seq = 1)                AS first_review_score,
    MIN(purchased_at)     FILTER (WHERE purchase_date > first_purchase_date)
                                                                          AS first_later_day_return_at
FROM delivered_seq
GROUP BY customer_unique_id;
-- BOOL_OR is the boolean version of MAX: over one row it returns that
-- row's value (true / false / NULL when there is no delivery date).

-- One row per customer with its group labels and return flags
CREATE TEMP VIEW first_order_flags AS
SELECT
    CASE WHEN first_is_late IS NULL THEN 'no delivery timing'
         WHEN first_is_late         THEN 'late'
         ELSE 'on time' END                                               AS lateness_group,
    CASE WHEN first_review_score IS NULL THEN 'no review'
         WHEN first_review_score <= 2    THEN '1-2'
         WHEN first_review_score =  3    THEN '3'
         ELSE '4-5' END                                                   AS review_group,
    (first_later_day_return_at IS NOT NULL)                               AS returned_later_day,
    (first_purchased_at + INTERVAL '180 days' < TIMESTAMP '2018-09-01')   AS eligible_180,
    COALESCE(first_later_day_return_at <= first_purchased_at + INTERVAL '180 days', false)
                                                                          AS returned_180
FROM first_order_customers;

CREATE TEMP VIEW q9_first_order_return AS
WITH labelled AS (
    -- Stack the two breakdowns plus an 'all' row for each, so one query
    -- computes every row the same way.
    SELECT 'lateness' AS dimension, lateness_group AS first_order_group, * FROM first_order_flags
    UNION ALL
    SELECT 'lateness', 'all', * FROM first_order_flags
    UNION ALL
    SELECT 'review',   review_group, * FROM first_order_flags
    UNION ALL
    SELECT 'review',   'all', * FROM first_order_flags
)
SELECT
    dimension,
    first_order_group,
    COUNT(*)                                                                  AS customers,
    COUNT(*) FILTER (WHERE returned_later_day)                                AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE returned_later_day) / COUNT(*), 2)   AS repeat_rate_pct,
    COUNT(*) FILTER (WHERE eligible_180)                                      AS eligible_180,
    COUNT(*) FILTER (WHERE eligible_180 AND returned_180)                     AS repeat_180,
    ROUND(100.0 * COUNT(*) FILTER (WHERE eligible_180 AND returned_180)
          / NULLIF(COUNT(*) FILTER (WHERE eligible_180), 0), 2)               AS repeat_180d_pct
FROM labelled
GROUP BY dimension, first_order_group;

\copy (SELECT * FROM q9_first_order_return ORDER BY dimension, first_order_group) TO 'results/12_first_order_return.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q9_first_order_return ORDER BY dimension, first_order_group;
