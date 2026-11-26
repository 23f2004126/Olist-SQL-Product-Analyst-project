-- =============================================================================
-- 13_seller_scorecard.sql: Business question 4, sellers
-- "Which sellers hurt the marketplace, and how concentrated is it?"
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/13_seller_scorecard.sql
-- Each query is saved to results/13_<name>.csv and printed.
--
-- Scope: in-window (2017-01-01 to 2018-08-31), DELIVERED orders unless a query
-- says otherwise.
--
-- ATTRIBUTION RULE
--   * Revenue: each seller gets the price of their own items in every
--     delivered order (v_seller_orders), multi-seller orders included. A
--     multi-seller order's revenue is split by item, not double-counted.
--   * Reviews, late delivery and late handover belong to the whole order,
--     not to one seller. They are attributed to a seller ONLY on
--     single-seller orders, where there is exactly one seller to attribute
--     them to. Multi-seller orders count for revenue and order counts, but
--     not for these quality metrics.
--
-- Definitions
--   * Late handover: carrier handover after the seller's latest
--     shipping_limit_date (timestamp comparison, as in file 11, Q6).
--     Orders with no carrier date are left out of that rate.
--   * Late delivery: is_late (calendar-day rule), orders with timing only.
--   * Low review: latest review score 1 or 2, reviewed orders only.
--   * Rates are POOLED: total events / total eligible orders across the
--     group, not an average of per-seller rates.
--
-- Describes what the data shows; it doesn't claim causes.
--
-- Pattern: building blocks are TEMP TABLES (computed once and stored for
-- this session, so the eight queries don't recompute the stacked views).
-- Each query is a TEMP VIEW, \copy'd to CSV, then printed.
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- BUILDING BLOCK A: seller_orders
-- GRAIN: one row per (order_id, seller_id) for delivered in-window orders.
-- Quality columns are filled only when the order is single-seller.
-- =============================================================================
CREATE TEMP TABLE seller_orders AS
SELECT
    so.order_id,
    so.seller_id,
    f.purchase_month,
    so.item_value,                                    -- this seller's revenue in the order
    (f.seller_count = 1)                    AS is_single_seller,

    -- Late handover (single-seller orders with a carrier date only)
    CASE WHEN f.seller_count = 1 AND f.order_delivered_carrier_date IS NOT NULL
         THEN f.order_delivered_carrier_date > so.latest_shipping_limit
    END                                     AS is_late_handover,

    -- Late delivery (single-seller orders with delivery timing only)
    CASE WHEN f.seller_count = 1 THEN f.is_late END   AS is_late_delivery,

    -- Review (single-seller orders with a review only)
    CASE WHEN f.seller_count = 1 THEN f.review_score END AS review_score
FROM v_seller_orders so
JOIN v_order_facts f ON f.order_id = so.order_id   -- one row per order: no fan-out
WHERE f.is_delivered;                              -- v_order_facts is already in-window

-- Check: revenue here must equal the baseline revenue (sum of item_value
-- on delivered in-window orders in v_order_facts). Splitting orders by
-- seller must not create or lose money.
DO $$
DECLARE
    rev_sellers  numeric;
    rev_baseline numeric;
BEGIN
    SELECT SUM(item_value) INTO rev_sellers  FROM seller_orders;
    SELECT SUM(item_value) INTO rev_baseline FROM v_order_facts WHERE is_delivered;
    IF rev_sellers <> rev_baseline THEN
        RAISE EXCEPTION 'Seller revenue % <> baseline revenue %', rev_sellers, rev_baseline;
    END IF;
    RAISE NOTICE 'Revenue check passed: %', rev_sellers;
END
$$;


-- =============================================================================
-- BUILDING BLOCK B: seller_stats
-- GRAIN: one row per seller with at least one delivered in-window order.
-- Counts are the building blocks for every rate (numerator / denominator).
-- COUNT(x) counts non-NULL values only, so it naturally gives "eligible"
-- denominators. COUNT(*) FILTER (WHERE flag) counts events.
-- =============================================================================
CREATE TEMP TABLE seller_stats AS
SELECT
    so.seller_id,
    s.seller_state,
    COUNT(*)                                                    AS delivered_orders,       -- all, incl. multi-seller
    SUM(so.item_value)                                          AS revenue,
    MIN(so.purchase_month)                                      AS first_sale_month,
    COUNT(*) FILTER (WHERE so.is_single_seller)                 AS single_seller_orders,
    COUNT(so.is_late_handover)                                  AS handover_eligible,
    COUNT(*) FILTER (WHERE so.is_late_handover)                 AS late_handovers,
    COUNT(so.is_late_delivery)                                  AS delivery_eligible,
    COUNT(*) FILTER (WHERE so.is_late_delivery)                 AS late_deliveries,
    COUNT(so.review_score)                                      AS reviewed_orders,
    SUM(so.review_score)                                        AS review_score_sum,
    COUNT(*) FILTER (WHERE so.review_score <= 2)                AS low_reviews
FROM seller_orders so
JOIN v_sellers s ON s.seller_id = so.seller_id     -- one row per seller: no fan-out
GROUP BY so.seller_id, s.seller_state;


-- =============================================================================
-- Q1. CONCENTRATION
-- Question: How much revenue comes from the biggest sellers?
-- Logic:    Rank sellers by revenue (highest first; seller_id breaks ties).
--           Running SUM(revenue) OVER (ORDER BY rank) / total revenue =
--           cumulative share. "Top p%" = the first CEIL(p * sellers)
--           sellers, and its share is the cumulative share at that rank.
--           The full ranking is saved for a Lorenz-style chart.
-- Result:   2,945 sellers (matches baseline active sellers).
--           Top 1% (30 sellers)   = 25.93% of revenue
--           Top 5% (148)          = 52.99%
--           Top 10% (295)         = 67.04%
--           Top 20% (589)         = 82.20%
-- =============================================================================
CREATE TEMP VIEW seller_revenue_rank AS
SELECT
    seller_id,
    revenue,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, seller_id)                        AS revenue_rank,
    COUNT(*)     OVER ()                                                        AS total_sellers,
    -- Running total: sum of revenue from rank 1 down to this row
    SUM(revenue) OVER (ORDER BY revenue DESC, seller_id
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)       AS cumulative_revenue,
    SUM(revenue) OVER ()                                                        AS total_revenue
FROM seller_stats;

\copy (SELECT revenue_rank, seller_id, revenue, ROUND(100.0 * cumulative_revenue / total_revenue, 4) AS cumulative_share_pct FROM seller_revenue_rank ORDER BY revenue_rank) TO 'results/13_seller_revenue_rank.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP VIEW q1_concentration AS
SELECT
    p.top_pct,
    r.revenue_rank                                             AS sellers_in_group,
    r.total_sellers,
    ROUND(100.0 * r.cumulative_revenue / r.total_revenue, 2)   AS revenue_share_pct
FROM (VALUES (1), (5), (10), (20)) AS p(top_pct)             -- the four cut-offs
JOIN seller_revenue_rank r
  ON r.revenue_rank = CEIL(r.total_sellers * p.top_pct / 100.0);

\copy (SELECT * FROM q1_concentration ORDER BY top_pct) TO 'results/13_concentration.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1_concentration ORDER BY top_pct;


-- =============================================================================
-- Q2. SIZE BANDS
-- Question: How are sellers spread by size, and how much of the business
--           does each size band carry?
-- Logic:    Band sellers by delivered orders (1-9, 10-49, 50-199, 200+).
--           Order share = the band's seller-orders / all seller-orders. A
--           multi-seller order counts once for each seller in it, so this
--           is a share of (order, seller) pairs, not of distinct orders.
-- Result:   band    sellers (% of sellers) | % of orders | % of revenue
--           1-9      1,711 (58.10%)        |   6.07      |   9.16
--           10-49      810 (27.50%)        |  18.28      |  22.75
--           50-199     339 (11.51%)        |  33.12      |  31.88
--           200+        85  (2.89%)        |  42.54      |  36.21
-- =============================================================================
CREATE TEMP VIEW q2_size_bands AS
SELECT
    band_order,
    size_band,
    COUNT(*)                                                       AS sellers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS pct_of_sellers,
    ROUND(100.0 * SUM(delivered_orders) / SUM(SUM(delivered_orders)) OVER (), 2)
                                                                   AS pct_of_orders,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2)     AS pct_of_revenue
FROM (
    SELECT
        delivered_orders,
        revenue,
        CASE WHEN delivered_orders <  10 THEN 1
             WHEN delivered_orders <  50 THEN 2
             WHEN delivered_orders < 200 THEN 3
             ELSE 4 END AS band_order,
        CASE WHEN delivered_orders <  10 THEN '1-9'
             WHEN delivered_orders <  50 THEN '10-49'
             WHEN delivered_orders < 200 THEN '50-199'
             ELSE '200+' END AS size_band
    FROM seller_stats
) b
GROUP BY band_order, size_band;

\copy (SELECT size_band, sellers, pct_of_sellers, pct_of_orders, pct_of_revenue FROM q2_size_bands ORDER BY band_order) TO 'results/13_size_bands.csv' WITH (FORMAT csv, HEADER true)
SELECT size_band, sellers, pct_of_sellers, pct_of_orders, pct_of_revenue FROM q2_size_bands ORDER BY band_order;


-- =============================================================================
-- Q3. SCORECARD
-- Question: For every seller with enough single-seller orders to judge,
--           how do they perform?
-- Logic:    Sellers with 30+ single-seller delivered orders. Each rate is
--           events / eligible orders from seller_stats. NULLIF avoids
--           dividing by zero. The full table goes to CSV; the screen shows
--           a summary only.
-- Result:   614 of 2,945 sellers qualify. They hold 76.84% of revenue and
--           83.21% of single-seller orders. Pooled: late handover 8.72%, late
--           delivery 6.88%, low review 12.53%. Per seller, the low-review share
--           ranges 0.00-60.00% (median 10.835%). Full table:
--           results/13_scorecard.csv.
-- =============================================================================
CREATE TEMP TABLE scorecard AS
SELECT
    seller_id,
    seller_state,
    delivered_orders,
    revenue,
    single_seller_orders,
    handover_eligible,
    late_handovers,
    ROUND(100.0 * late_handovers  / NULLIF(handover_eligible, 0), 2)   AS late_handover_rate_pct,
    delivery_eligible,
    late_deliveries,
    ROUND(100.0 * late_deliveries / NULLIF(delivery_eligible, 0), 2)   AS late_delivery_rate_pct,
    reviewed_orders,
    low_reviews,
    ROUND(1.0 * review_score_sum  / NULLIF(reviewed_orders, 0), 2)     AS avg_review,
    ROUND(100.0 * low_reviews     / NULLIF(reviewed_orders, 0), 2)     AS low_review_pct
FROM seller_stats
WHERE single_seller_orders >= 30;

\copy (SELECT * FROM scorecard ORDER BY revenue DESC) TO 'results/13_scorecard.csv' WITH (FORMAT csv, HEADER true)

-- Summary of the scorecard population
CREATE TEMP VIEW q3_scorecard_summary AS
SELECT
    COUNT(*)                                                                AS scorecard_sellers,
    (SELECT COUNT(*) FROM seller_stats)                                     AS all_sellers,
    ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM seller_stats), 2) AS pct_of_revenue,
    ROUND(100.0 * SUM(single_seller_orders)
          / (SELECT SUM(single_seller_orders) FROM seller_stats), 2)        AS pct_of_single_seller_orders,
    ROUND(100.0 * SUM(late_handovers)  / SUM(handover_eligible), 2)         AS pooled_late_handover_pct,
    ROUND(100.0 * SUM(late_deliveries) / SUM(delivery_eligible), 2)         AS pooled_late_delivery_pct,
    ROUND(100.0 * SUM(low_reviews)     / SUM(reviewed_orders), 2)           AS pooled_low_review_pct,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY low_review_pct)             AS median_seller_low_review_pct,
    MIN(low_review_pct)                                                     AS min_seller_low_review_pct,
    MAX(low_review_pct)                                                     AS max_seller_low_review_pct
FROM scorecard;

\copy (SELECT * FROM q3_scorecard_summary) TO 'results/13_scorecard_summary.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3_scorecard_summary;


-- =============================================================================
-- Q4. PROBLEM SELLERS
-- Question: Which scorecard sellers get low reviews far more often than
--           normal, and how much of the business do they hold?
-- Logic:    Benchmark = the overall low-review share across ALL single-seller
--           delivered reviewed orders (every seller, not just the scorecard).
--           Problem seller = scorecard seller with low_review_pct >= 2 x
--           benchmark. Their shares are of scorecard totals: single-seller
--           orders, revenue (attribution rule) and low reviews.
-- Result:   Benchmark 12.34%, threshold 24.68%. 31 problem sellers (5.05% of
--           614). They hold 4.36% of scorecard orders, 5.15% of revenue and
--           10.62% of low reviews. Their late delivery is 12.38% vs 6.63% for
--           other scorecard sellers; late handover 27.89% vs 7.84%.
-- =============================================================================
CREATE TEMP VIEW q4_problem_sellers AS
WITH benchmark AS (
    SELECT ROUND(100.0 * SUM(low_reviews) / SUM(reviewed_orders), 2) AS overall_low_review_pct
    FROM seller_stats
),
flagged AS (
    SELECT
        sc.*,
        (sc.low_review_pct >= 2 * b.overall_low_review_pct) AS is_problem
    FROM scorecard sc
    CROSS JOIN benchmark b          -- one benchmark row, attached to every seller
)
SELECT
    (SELECT overall_low_review_pct FROM benchmark)                         AS benchmark_low_review_pct,
    (SELECT 2 * overall_low_review_pct FROM benchmark)                     AS threshold_pct,
    COUNT(*)                                                               AS scorecard_sellers,
    COUNT(*) FILTER (WHERE is_problem)                                     AS problem_sellers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_problem) / COUNT(*), 2)        AS pct_of_scorecard_sellers,
    ROUND(100.0 * SUM(single_seller_orders) FILTER (WHERE is_problem)
          / SUM(single_seller_orders), 2)                                  AS pct_of_scorecard_orders,
    ROUND(100.0 * SUM(revenue) FILTER (WHERE is_problem)
          / SUM(revenue), 2)                                               AS pct_of_scorecard_revenue,
    ROUND(100.0 * SUM(low_reviews) FILTER (WHERE is_problem)
          / SUM(low_reviews), 2)                                           AS pct_of_scorecard_low_reviews,
    -- Their pooled rates, for comparison with everyone else
    ROUND(100.0 * SUM(late_deliveries) FILTER (WHERE is_problem)
          / SUM(delivery_eligible) FILTER (WHERE is_problem), 2)           AS problem_late_delivery_pct,
    ROUND(100.0 * SUM(late_deliveries) FILTER (WHERE NOT is_problem)
          / SUM(delivery_eligible) FILTER (WHERE NOT is_problem), 2)       AS other_late_delivery_pct,
    ROUND(100.0 * SUM(late_handovers) FILTER (WHERE is_problem)
          / SUM(handover_eligible) FILTER (WHERE is_problem), 2)           AS problem_late_handover_pct,
    ROUND(100.0 * SUM(late_handovers) FILTER (WHERE NOT is_problem)
          / SUM(handover_eligible) FILTER (WHERE NOT is_problem), 2)       AS other_late_handover_pct
FROM flagged;

\copy (SELECT * FROM q4_problem_sellers) TO 'results/13_problem_sellers.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4_problem_sellers;


-- =============================================================================
-- Q5. LATE-HANDOVER CONCENTRATION
-- Question: Are late handovers spread out, or concentrated in a few sellers?
-- Logic:    Rank scorecard sellers by number of late handovers (most first;
--           seller_id breaks ties). Top 10% = first CEIL(0.1 x sellers).
--           Their share of late handovers is given against (a) all
--           scorecard sellers and (b) all single-seller orders of every
--           seller. Their share of scorecard handover-eligible orders is
--           given too, since big sellers have more handovers simply from volume.
-- Result:   Top 10% = 62 of 614 sellers, with 3,817 late handovers: 55.42% of
--           scorecard late handovers (6,887) and 44.74% of all single-seller
--           late handovers. They hold 31.93% of scorecard handover-eligible
--           orders, so their share of late handovers is bigger than their
--           share of volume.
-- =============================================================================
CREATE TEMP VIEW q5_handover_concentration AS
WITH ranked AS (
    SELECT
        seller_id,
        late_handovers,
        handover_eligible,
        ROW_NUMBER() OVER (ORDER BY late_handovers DESC, seller_id) AS lh_rank,
        COUNT(*)     OVER ()                                         AS n_sellers
    FROM scorecard
)
SELECT
    MAX(n_sellers)                                                             AS scorecard_sellers,
    COUNT(*) FILTER (WHERE lh_rank <= CEIL(0.1 * n_sellers))                   AS top10pct_sellers,
    SUM(late_handovers) FILTER (WHERE lh_rank <= CEIL(0.1 * n_sellers))        AS top10pct_late_handovers,
    SUM(late_handovers)                                                        AS scorecard_late_handovers,
    ROUND(100.0 * SUM(late_handovers) FILTER (WHERE lh_rank <= CEIL(0.1 * n_sellers))
          / SUM(late_handovers), 2)                                            AS pct_of_scorecard_late_handovers,
    ROUND(100.0 * SUM(late_handovers) FILTER (WHERE lh_rank <= CEIL(0.1 * n_sellers))
          / (SELECT SUM(late_handovers) FROM seller_stats), 2)                 AS pct_of_all_late_handovers,
    ROUND(100.0 * SUM(handover_eligible) FILTER (WHERE lh_rank <= CEIL(0.1 * n_sellers))
          / SUM(handover_eligible), 2)                                         AS pct_of_scorecard_handover_orders
FROM ranked;

\copy (SELECT * FROM q5_handover_concentration) TO 'results/13_handover_concentration.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5_handover_concentration;


-- =============================================================================
-- Q6. HANDOVER AND REVIEWS AT SELLER LEVEL
-- Question: Do sellers who hand over late more often also have more late
--           deliveries and low reviews?
-- Logic:    NTILE(4) over scorecard sellers sorted by late-handover rate
--           (1 = lowest rate). Per quartile: seller count, rate range, and
--           pooled late-handover, late-delivery and low-review rates.
-- Result:   quartile  seller rate range | late handover | late delivery | low review
--           1 (154)     0.00- 1.56      |   0.62        |   4.90        | 10.16
--           2 (154)     1.59- 5.00      |   3.30        |   5.98        | 11.48
--           3 (153)     5.00-12.40      |   8.05        |   7.24        | 12.47
--           4 (153)    12.50-87.50      |  24.19        |   9.43        | 16.31
--           Late delivery and low reviews rise with each quartile. NTILE
--           splits tied rates, so 5.00 appears in quartiles 2 and 3.
-- =============================================================================
CREATE TEMP VIEW q6_handover_quartiles AS
SELECT
    handover_quartile,
    COUNT(*)                                                         AS sellers,
    MIN(late_handover_rate_pct)                                      AS min_seller_handover_pct,
    MAX(late_handover_rate_pct)                                      AS max_seller_handover_pct,
    SUM(single_seller_orders)                                        AS single_seller_orders,
    ROUND(100.0 * SUM(late_handovers)  / SUM(handover_eligible), 2)  AS late_handover_pct,
    ROUND(100.0 * SUM(late_deliveries) / SUM(delivery_eligible), 2)  AS late_delivery_pct,
    ROUND(100.0 * SUM(low_reviews)     / SUM(reviewed_orders), 2)    AS low_review_pct
FROM (
    SELECT *,
           NTILE(4) OVER (ORDER BY late_handover_rate_pct, seller_id) AS handover_quartile
    FROM scorecard
) q
GROUP BY handover_quartile;

\copy (SELECT * FROM q6_handover_quartiles ORDER BY handover_quartile) TO 'results/13_handover_quartiles.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6_handover_quartiles ORDER BY handover_quartile;


-- =============================================================================
-- Q7. BY SELLER STATE
-- Question: Where are sellers based, and how do they perform by state?
-- Logic:    All sellers with a delivered in-window order (not just the
--           scorecard), grouped by seller_state; states with 30+ sellers.
--           Revenue share is of all seller revenue. Rates are pooled over
--           single-seller orders.
-- Result:   8 states with 30+ sellers. SP: 1,751 sellers, 64.39% of revenue,
--           late handover 8.96%, late delivery 7.43%. PR: 334, 9.30%, 10.99%,
--           5.50%. MG: 235, 7.40%, 7.64%, 4.91%. RJ: 161, 6.17%, 8.13%, 7.32%.
--           SP has the highest late-delivery rate of the 8; PR has the
--           highest late-handover rate.
-- =============================================================================
CREATE TEMP VIEW q7_by_seller_state AS
SELECT
    seller_state,
    COUNT(*)                                                               AS sellers,
    ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM seller_stats), 2) AS pct_of_revenue,
    ROUND(100.0 * SUM(late_handovers)  / NULLIF(SUM(handover_eligible), 0), 2) AS late_handover_pct,
    ROUND(100.0 * SUM(late_deliveries) / NULLIF(SUM(delivery_eligible), 0), 2) AS late_delivery_pct
FROM seller_stats
GROUP BY seller_state
HAVING COUNT(*) >= 30;

\copy (SELECT * FROM q7_by_seller_state ORDER BY sellers DESC) TO 'results/13_by_seller_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_by_seller_state ORDER BY sellers DESC;


-- =============================================================================
-- Q8. SELLER ACTIVITY
-- Question: How many new sellers start each month, and how many are still
--           selling 3 and 6 months later?
-- Logic:    Seller cohort = month of their first delivered in-window sale.
--           "Still selling at month +k" = at least one delivered sale in
--           the calendar month cohort + k (same exact-month rule as the
--           customer cohort matrix in file 10). Cells whose month +k is
--           after 2018-08 can't be observed yet: NULL, not 0.
--           Note: the 2017-01 cohort includes sellers who already sold in
--           2016, because the window starts in 2017.
-- Result:   New sellers per month range 70 (2017-06) to 236 (2017-02).
--           Active at month +3: 44.39% (2017-11) to 63.47% (2017-01).
--           Active at month +6: 37.43% (2017-11) to 57.08% (2017-01).
--           The exact-month rule counts a seller who skips that one month as
--           inactive, so these are a lower bound on "still selling".
--           NULL cells: +3 from 2018-06 on, +6 from 2018-03 on.
-- =============================================================================
CREATE TEMP VIEW q8_seller_cohorts AS
WITH active_months AS (
    -- One row per (seller, month with at least one delivered sale)
    SELECT DISTINCT seller_id, purchase_month
    FROM seller_orders
),
cohort_flags AS (
    SELECT
        st.seller_id,
        st.first_sale_month                                       AS cohort_month,
        -- EXISTS-style flags written as COUNT > 0 over a join
        COUNT(*) FILTER (WHERE am.purchase_month = st.first_sale_month + INTERVAL '3 months') > 0 AS active_m3,
        COUNT(*) FILTER (WHERE am.purchase_month = st.first_sale_month + INTERVAL '6 months') > 0 AS active_m6
    FROM seller_stats st
    JOIN active_months am ON am.seller_id = st.seller_id
    GROUP BY st.seller_id, st.first_sale_month
)
SELECT
    cohort_month,
    COUNT(*)                                                                AS new_sellers,
    CASE WHEN cohort_month + INTERVAL '3 months' <= DATE '2018-08-01'
         THEN COUNT(*) FILTER (WHERE active_m3) END                         AS active_m3,
    CASE WHEN cohort_month + INTERVAL '3 months' <= DATE '2018-08-01'
         THEN ROUND(100.0 * COUNT(*) FILTER (WHERE active_m3) / COUNT(*), 2) END AS pct_active_m3,
    CASE WHEN cohort_month + INTERVAL '6 months' <= DATE '2018-08-01'
         THEN COUNT(*) FILTER (WHERE active_m6) END                         AS active_m6,
    CASE WHEN cohort_month + INTERVAL '6 months' <= DATE '2018-08-01'
         THEN ROUND(100.0 * COUNT(*) FILTER (WHERE active_m6) / COUNT(*), 2) END AS pct_active_m6
FROM cohort_flags
GROUP BY cohort_month;

\copy (SELECT * FROM q8_seller_cohorts ORDER BY cohort_month) TO 'results/13_seller_cohorts.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q8_seller_cohorts ORDER BY cohort_month;
