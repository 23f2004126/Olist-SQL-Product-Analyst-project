-- =============================================================================
-- 14_revenue_rfm.sql: Business question 5, revenue
-- "Where does revenue come from, and which customers are worth winning back?"
--
-- Run FROM THE REPO ROOT (the \copy paths are relative):
--     psql -d olist -f sql/14_revenue_rfm.sql
-- Each query is saved to results/14_<name>.csv and printed.
--
-- Scope: in-window (2017-01-01 to 2018-08-31), DELIVERED orders.
--
-- Definitions (decisions in docs/data_quality_notes.md):
--   * Revenue = SUM(item price) on delivered orders. Freight is separate.
--   * Average order value (AOV) = revenue / delivered orders.
--   * Customer = customer_unique_id.
--   * Repeat = returned on a LATER calendar day (C12).
--   * Category revenue is counted per ITEM (v_order_lines), so a
--     two-category order splits its revenue between the categories.
--
-- Describes what the data shows; it doesn't claim causes.
--
-- Pattern: building blocks are TEMP TABLES (computed once for this
-- session). Each query is a TEMP VIEW, \copy'd to CSV, then printed.
-- Comparison periods: "Jan-Aug 2017" vs "Jan-Aug 2018" = purchase months
-- 2017-01..2017-08 vs 2018-01..2018-08 (8 months each).
-- =============================================================================

\set ON_ERROR_STOP on


-- =============================================================================
-- BUILDING BLOCK A: delivered
-- GRAIN: one row per delivered in-window order.
-- delivered_seq numbers each customer's delivered orders (as in file 10).
-- =============================================================================
CREATE TEMP TABLE delivered AS
SELECT
    order_id,
    customer_unique_id,
    customer_state,
    purchase_month,
    order_purchase_timestamp::date                  AS purchase_date,
    item_value,
    freight_value,
    main_payment_type,
    max_installments,
    ROW_NUMBER() OVER (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp, order_id
    )                                               AS delivered_seq
FROM v_order_facts
WHERE is_delivered;


-- =============================================================================
-- BUILDING BLOCK B: lines
-- GRAIN: one row per item sold on a delivered in-window order.
-- =============================================================================
CREATE TEMP TABLE lines AS
SELECT
    l.order_id,
    l.category,
    l.price,
    d.purchase_month
FROM v_order_lines l
JOIN delivered d ON d.order_id = l.order_id;   -- one row per order: no fan-out


-- =============================================================================
-- BUILDING BLOCK C: customers
-- GRAIN: one row per customer with at least one delivered in-window order.
-- Returned on a later day <=> their LAST purchase date is after their FIRST.
-- (Same result as file 10's definition, written more simply.)
-- =============================================================================
CREATE TEMP TABLE customers AS
SELECT
    customer_unique_id,
    COUNT(*)                                            AS frequency,          -- delivered orders
    SUM(item_value)                                     AS monetary,           -- revenue
    MIN(purchase_date)                                  AS first_purchase_date,
    MAX(purchase_date)                                  AS last_purchase_date,
    (MAX(purchase_date) > MIN(purchase_date))           AS returned_later_day,
    MAX(customer_state) FILTER (WHERE delivered_seq = 1) AS first_state        -- state at first order
FROM delivered
GROUP BY customer_unique_id;

-- Checks: totals must match the baseline / file 10 exactly.
DO $$
DECLARE
    rev       numeric;
    rev_lines numeric;
    n_cust    bigint;
    n_repeat  bigint;
BEGIN
    SELECT SUM(monetary), COUNT(*), COUNT(*) FILTER (WHERE returned_later_day)
      INTO rev, n_cust, n_repeat
      FROM customers;
    SELECT SUM(price) INTO rev_lines FROM lines;

    IF rev <> 13181027.13 OR rev_lines <> rev OR n_cust <> 93104 OR n_repeat <> 2005 THEN
        RAISE EXCEPTION 'Totals differ from baseline: revenue %, line revenue %, customers %, later-day repeat %',
                        rev, rev_lines, n_cust, n_repeat;
    END IF;
    RAISE NOTICE 'Checks passed: revenue %, customers %, later-day repeat customers %', rev, n_cust, n_repeat;
END
$$;


-- =============================================================================
-- Q1. MONTHLY TREND AND YEAR-ON-YEAR
-- Question: How did orders, revenue and AOV move month by month, and how
--           does Jan-Aug 2018 compare with Jan-Aug 2017?
-- Logic:    Q1a: group by purchase month. LAG(revenue) OVER (ORDER BY month)
--           returns the previous month's revenue on each row; MoM change =
--           (this - previous) / previous. The first month has no previous,
--           so its change is NULL.
--           Q1b: sum each 8-month period, then compare.
-- Result:   Q1a: revenue climbs through 2017 to a peak of 987,765.37 in
--           2017-11 (+52.37% MoM), then drops -26.50% in 2017-12. In 2018
--           monthly revenue stays between 826,437.13 and 977,544.69; MoM
--           changes are -12.43% to +27.36%. AOV ranges 124.38-149.06.
--           Q1b: Jan-Aug 2018 vs 2017: orders 21,998 -> 52,783 (+139.94%),
--           revenue 2,993,456.13 -> 7,218,125.12 (+141.13%), AOV 136.08 ->
--           136.75 (+0.49%). Growth came from more orders, not bigger ones.
-- =============================================================================
CREATE TEMP VIEW q1a_monthly AS
WITH m AS (
    SELECT
        purchase_month,
        COUNT(*)          AS orders,
        SUM(item_value)   AS revenue
    FROM delivered
    GROUP BY purchase_month
)
SELECT
    purchase_month,
    orders,
    revenue,
    ROUND(revenue / orders, 2)                                         AS aov,
    LAG(revenue) OVER (ORDER BY purchase_month)                        AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY purchase_month))
          / LAG(revenue) OVER (ORDER BY purchase_month), 2)            AS revenue_mom_pct
FROM m;

\copy (SELECT * FROM q1a_monthly ORDER BY purchase_month) TO 'results/14_monthly_revenue.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1a_monthly ORDER BY purchase_month;

CREATE TEMP VIEW q1b_yoy AS
WITH p AS (
    SELECT
        COUNT(*)        FILTER (WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS orders_2017,
        COUNT(*)        FILTER (WHERE purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01') AS orders_2018,
        SUM(item_value) FILTER (WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS revenue_2017,
        SUM(item_value) FILTER (WHERE purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01') AS revenue_2018
    FROM delivered
)
SELECT
    orders_2017,
    orders_2018,
    ROUND(100.0 * (orders_2018 - orders_2017) / orders_2017, 2)                         AS orders_change_pct,
    revenue_2017,
    revenue_2018,
    ROUND(100.0 * (revenue_2018 - revenue_2017) / revenue_2017, 2)                      AS revenue_change_pct,
    ROUND(revenue_2017 / orders_2017, 2)                                                AS aov_2017,
    ROUND(revenue_2018 / orders_2018, 2)                                                AS aov_2018,
    ROUND(100.0 * ((revenue_2018 / orders_2018) - (revenue_2017 / orders_2017))
          / (revenue_2017 / orders_2017), 2)                                            AS aov_change_pct
FROM p;

\copy (SELECT * FROM q1b_yoy) TO 'results/14_yoy_jan_aug.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q1b_yoy;


-- =============================================================================
-- Q2. BY CATEGORY
-- Question: Which categories bring in the most revenue?
-- Logic:    Item-level revenue per category. orders = distinct orders
--           containing the category (an order with two categories counts in
--           both). Rank by revenue, keep the top 15. Revenue share is of ALL
--           revenue; cumulative share is a running SUM over the rank.
-- Result:   74 categories. Top 15 = 76.33% of revenue. Top 5: health_beauty
--           9.33%, watches_gifts 8.83%, bed_bath_table 7.76%, sports_leisure
--           7.23%, computers_accessories 6.74%. Average item price ranges
--           from 70.02 (telephony) to 198.71 (watches_gifts).
-- =============================================================================
CREATE TEMP TABLE category_revenue AS
SELECT
    category,
    COUNT(DISTINCT order_id)                                     AS orders,
    COUNT(*)                                                     AS items,
    SUM(price)                                                   AS revenue,
    ROUND(AVG(price), 2)                                         AS avg_item_price,
    ROW_NUMBER() OVER (ORDER BY SUM(price) DESC, category)       AS revenue_rank
FROM lines
GROUP BY category;

CREATE TEMP VIEW q2_top_categories AS
SELECT
    revenue_rank,
    category,
    orders,
    revenue,
    ROUND(100.0 * revenue / (SELECT SUM(revenue) FROM category_revenue), 2)     AS revenue_share_pct,
    ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue_rank)
          / (SELECT SUM(revenue) FROM category_revenue), 2)                     AS cumulative_share_pct,
    avg_item_price,
    (SELECT COUNT(*) FROM category_revenue)                                     AS total_categories
FROM category_revenue
WHERE revenue_rank <= 15;
-- Note: the window SUM runs after WHERE, but because ranks 1..15 are kept in
-- order, the running total over ranks 1..n is exactly the top-n total.

\copy (SELECT * FROM q2_top_categories ORDER BY revenue_rank) TO 'results/14_top_categories.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q2_top_categories ORDER BY revenue_rank;


-- =============================================================================
-- Q3. CATEGORY GROWTH
-- Question: Which of the top 15 categories grew, and which shrank?
-- Logic:    For the same 15 categories, item revenue in Jan-Aug 2017 vs
--           Jan-Aug 2018, with the change in %. Sorted by change.
-- Result:   All 15 grew. Fastest: baby +268.56%, watches_gifts +241.98%,
--           health_beauty +210.33%, housewares +207.23%, telephony +202.97%.
--           Slowest: cool_stuff +10.39%, toys +41.94%, perfumery +42.98%,
--           garden_tools +53.70%. (Overall revenue: +141.13%.)
-- =============================================================================
CREATE TEMP VIEW q3_category_growth AS
SELECT
    c.revenue_rank,
    c.category,
    SUM(l.price) FILTER (WHERE l.purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS revenue_jan_aug_2017,
    SUM(l.price) FILTER (WHERE l.purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01') AS revenue_jan_aug_2018,
    ROUND(100.0 *
          ( SUM(l.price) FILTER (WHERE l.purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01')
          - SUM(l.price) FILTER (WHERE l.purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01'))
          / SUM(l.price) FILTER (WHERE l.purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01'), 2)
                                                                                                  AS change_pct
FROM category_revenue c
JOIN lines l ON l.category = c.category
WHERE c.revenue_rank <= 15
GROUP BY c.revenue_rank, c.category;

\copy (SELECT * FROM q3_category_growth ORDER BY change_pct DESC) TO 'results/14_category_growth.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q3_category_growth ORDER BY change_pct DESC;


-- =============================================================================
-- Q4. FREIGHT BURDEN
-- Question: How big is shipping cost relative to what the customer buys?
-- Logic:    Freight share = SUM(freight) / SUM(item value), pooled over the
--           group. Per order, freight / item value gives the share of
--           orders paying more than 30% and more than 50% in freight.
--           Three cuts: overall, customer state (500+ orders), and
--           order-value quartile (NTILE(4) on item value; 1 = cheapest).
-- Result:   Overall freight = 16.63% of item value; 35.12% of orders pay
--           more than 30%, 15.84% more than 50%.
--           State: highest MA 26.22%, PE 22.66%, PB 22.42%; lowest SP 13.85%.
--           Value quartile: cheapest (0.85-45.90) 53.41% of item value,
--           51.91% of those orders pay >50%; priciest (149.90+) 10.26%.
-- =============================================================================
CREATE TEMP VIEW q4a_freight_overall AS
SELECT
    COUNT(*)                                                                    AS orders,
    ROUND(100.0 * SUM(freight_value) / SUM(item_value), 2)                      AS freight_pct_of_item_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.3 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_30,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.5 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_50
FROM delivered;

\copy (SELECT * FROM q4a_freight_overall) TO 'results/14_freight_overall.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4a_freight_overall;

CREATE TEMP VIEW q4b_freight_by_state AS
SELECT
    customer_state                                                              AS state,
    COUNT(*)                                                                    AS orders,
    ROUND(100.0 * SUM(freight_value) / SUM(item_value), 2)                      AS freight_pct_of_item_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.3 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_30,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.5 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_50
FROM delivered
GROUP BY customer_state
HAVING COUNT(*) >= 500;

\copy (SELECT * FROM q4b_freight_by_state ORDER BY freight_pct_of_item_value DESC) TO 'results/14_freight_by_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4b_freight_by_state ORDER BY freight_pct_of_item_value DESC;

CREATE TEMP VIEW q4c_freight_by_value AS
SELECT
    value_quartile,
    MIN(item_value)                                                             AS min_order_value,
    MAX(item_value)                                                             AS max_order_value,
    COUNT(*)                                                                    AS orders,
    ROUND(100.0 * SUM(freight_value) / SUM(item_value), 2)                      AS freight_pct_of_item_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.3 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_30,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_value > 0.5 * item_value) / COUNT(*), 2) AS pct_orders_freight_gt_50
FROM (
    SELECT *, NTILE(4) OVER (ORDER BY item_value, order_id) AS value_quartile
    FROM delivered
) q
GROUP BY value_quartile;

\copy (SELECT * FROM q4c_freight_by_value ORDER BY value_quartile) TO 'results/14_freight_by_value_quartile.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q4c_freight_by_value ORDER BY value_quartile;


-- =============================================================================
-- Q5. PAYMENTS
-- Question: How do customers pay, and do bigger orders use more installments?
-- Logic:    Payment type = the order's main payment type (the highest-value
--           payment, v_order_payments_agg). Revenue is still item value.
--           Installment bands use max_installments, for orders whose main
--           type is credit_card. Values of 0 or 1 go into band '1'.
-- Result:   credit_card 75.48% of orders / 78.89% of revenue (AOV 143.19);
--           boleto 19.89% / 17.63% (121.39); voucher 3.09% / 2.14% (94.80);
--           debit_card 1.54% / 1.35% (119.88).
--           Card installments: 1 -> AOV 82.49 (32.10% of card orders);
--           2-3 -> 113.64 (30.24%); 4-6 -> 156.93 (21.54%); 7+ -> 301.22 (16.11%).
-- =============================================================================
CREATE TEMP VIEW q5a_payment_type AS
SELECT
    main_payment_type                                                  AS payment_type,
    COUNT(*)                                                           AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                 AS pct_of_orders,
    ROUND(100.0 * SUM(item_value) / SUM(SUM(item_value)) OVER (), 2)   AS pct_of_revenue,
    ROUND(SUM(item_value) / COUNT(*), 2)                               AS aov
FROM delivered
GROUP BY main_payment_type;

\copy (SELECT * FROM q5a_payment_type ORDER BY orders DESC) TO 'results/14_payment_type.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q5a_payment_type ORDER BY orders DESC;

CREATE TEMP VIEW q5b_installments AS
SELECT
    band_order,
    installment_band,
    COUNT(*)                                            AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_card_orders,
    ROUND(SUM(item_value) / COUNT(*), 2)                AS aov
FROM (
    SELECT
        item_value,
        CASE WHEN max_installments <= 1 THEN 1
             WHEN max_installments <= 3 THEN 2
             WHEN max_installments <= 6 THEN 3
             ELSE 4 END                                 AS band_order,
        CASE WHEN max_installments <= 1 THEN '1'
             WHEN max_installments <= 3 THEN '2-3'
             WHEN max_installments <= 6 THEN '4-6'
             ELSE '7+' END                              AS installment_band
    FROM delivered
    WHERE main_payment_type = 'credit_card'
) b
GROUP BY band_order, installment_band;

\copy (SELECT installment_band, orders, pct_of_card_orders, aov FROM q5b_installments ORDER BY band_order) TO 'results/14_installments.csv' WITH (FORMAT csv, HEADER true)
SELECT installment_band, orders, pct_of_card_orders, aov FROM q5b_installments ORDER BY band_order;


-- =============================================================================
-- Q6. CUSTOMER VALUE CONCENTRATION
-- Question: How much revenue comes from the highest-spending customers?
-- Logic:    Same method as file 13, Q1: rank customers by revenue,
--           running SUM / total = cumulative share, read at rank
--           CEIL(customers x p).
-- Result:   93,104 customers. Top 1% (932) = 11.48% of revenue; top 10%
--           (9,311) = 41.10%; top 20% (18,621) = 56.62%. Much less
--           concentrated than sellers (file 13: top 20% = 82.20%).
-- =============================================================================
CREATE TEMP VIEW q6_customer_concentration AS
WITH ranked AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY monetary DESC, customer_unique_id)            AS value_rank,
        COUNT(*)      OVER ()                                                     AS total_customers,
        SUM(monetary) OVER (ORDER BY monetary DESC, customer_unique_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)     AS cumulative_revenue,
        SUM(monetary) OVER ()                                                     AS total_revenue
    FROM customers
)
SELECT
    p.top_pct,
    r.value_rank                                              AS customers_in_group,
    r.total_customers,
    ROUND(100.0 * r.cumulative_revenue / r.total_revenue, 2)  AS revenue_share_pct
FROM (VALUES (1), (10), (20)) AS p(top_pct)
JOIN ranked r ON r.value_rank = CEIL(r.total_customers * p.top_pct / 100.0);

\copy (SELECT * FROM q6_customer_concentration ORDER BY top_pct) TO 'results/14_customer_concentration.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q6_customer_concentration ORDER BY top_pct;


-- =============================================================================
-- Q7. RFM SEGMENTS
-- Question: Which customers are worth winning back?
-- Logic:    Per customer:
--             recency   = days from last delivered purchase to 2018-08-31
--             frequency = delivered orders
--             monetary  = revenue (item value)
--           Scores 1-4 with NTILE(4) over ALL customers (4 = best):
--             r_score: sorted by recency_days DESCENDING, so the oldest
--                      buyers land in 1 and the most recent in 4
--             m_score: sorted by monetary ascending, so the top spenders
--                      land in 4
--             customer_unique_id breaks ties so the scores are always the same.
--           Segment: a CASE checks "repeat" first, so each customer lands in
--           exactly one segment. "One-time" = did NOT return on a later day,
--           so it includes customers whose 2+ orders were all on one day (C12).
--           The DO block checks segments add up to all customers and revenue.
-- Result:   Check passed: 93,104 customers in segments.
--           segment             customers (% cust) | % revenue | avg revenue
--           Lapsed high-value   22,369 (24.03%)    |  39.77    | 234.37
--           Recent high-value   22,473 (24.14%)    |  39.55    | 231.95
--           Lapsed low-value    23,415 (25.15%)    |   8.40    |  47.29
--           Recent low-value    22,842 (24.53%)    |   8.15    |  47.03
--           Repeat buyers        2,005  (2.15%)    |   4.13    | 271.47
--           The four one-time segments are near 25% each BY CONSTRUCTION:
--           NTILE makes quartiles, so customer counts aren't a finding.
--           Revenue share and average revenue are the findings.
--           Score bounds: recency 4 = 2-116 days, 3 = 116-220, 2 = 220-347,
--           1 = 347-603; monetary 4 = 154.19+, 3 = 89.70-154.17,
--           2 = 47.65-89.70, 1 = up to 47.65. NTILE splits ties, so a
--           boundary value (e.g. 220 days) can appear in two scores.
-- =============================================================================
CREATE TEMP TABLE rfm AS
SELECT
    customer_unique_id,
    DATE '2018-08-31' - last_purchase_date                          AS recency_days,
    frequency,
    monetary,
    returned_later_day,
    NTILE(4) OVER (ORDER BY DATE '2018-08-31' - last_purchase_date DESC,
                   customer_unique_id)                              AS r_score,
    NTILE(4) OVER (ORDER BY monetary, customer_unique_id)           AS m_score
FROM customers;

ALTER TABLE rfm ADD COLUMN segment text;
UPDATE rfm SET segment =
    CASE WHEN returned_later_day                        THEN 'Repeat buyers'
         WHEN r_score >= 3 AND m_score >= 3             THEN 'Recent high-value'
         WHEN r_score >= 3                              THEN 'Recent low-value'    -- m_score 1-2
         WHEN m_score >= 3                              THEN 'Lapsed high-value'   -- r_score 1-2
         ELSE                                                'Lapsed low-value'    -- r 1-2, m 1-2
    END;

\copy (SELECT customer_unique_id, recency_days, frequency, monetary, r_score, m_score, segment FROM rfm ORDER BY customer_unique_id) TO 'results/14_rfm_customers.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP VIEW q7_rfm_segments AS
SELECT
    segment,
    COUNT(*)                                                          AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                AS pct_of_customers,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2)      AS pct_of_revenue,
    ROUND(SUM(monetary) / COUNT(*), 2)                                AS avg_revenue_per_customer,
    MIN(recency_days)                                                 AS min_recency_days,
    MAX(recency_days)                                                 AS max_recency_days
FROM rfm
GROUP BY segment;

\copy (SELECT * FROM q7_rfm_segments ORDER BY pct_of_revenue DESC) TO 'results/14_rfm_segments.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7_rfm_segments ORDER BY pct_of_revenue DESC;

-- Score boundaries, so the segments can be explained in days and reais
CREATE TEMP VIEW q7b_rfm_score_bounds AS
SELECT 'recency' AS score_type, r_score AS score,
       MIN(recency_days)::numeric AS min_value, MAX(recency_days)::numeric AS max_value, COUNT(*) AS customers
FROM rfm GROUP BY r_score
UNION ALL
SELECT 'monetary', m_score, MIN(monetary), MAX(monetary), COUNT(*)
FROM rfm GROUP BY m_score;

\copy (SELECT * FROM q7b_rfm_score_bounds ORDER BY score_type, score) TO 'results/14_rfm_score_bounds.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q7b_rfm_score_bounds ORDER BY score_type, score;

-- Check: every customer in exactly one segment, and revenue fully covered.
DO $$
DECLARE
    seg_customers bigint;
    all_customers bigint;
    seg_revenue   numeric;
    all_revenue   numeric;
    unassigned    bigint;
BEGIN
    SELECT SUM(customers) INTO seg_customers FROM q7_rfm_segments;
    SELECT COUNT(*), SUM(monetary), COUNT(*) FILTER (WHERE segment IS NULL)
      INTO all_customers, all_revenue, unassigned FROM rfm;
    SELECT SUM(monetary) INTO seg_revenue FROM rfm WHERE segment IS NOT NULL;

    IF seg_customers <> all_customers OR unassigned > 0 OR seg_revenue <> all_revenue THEN
        RAISE EXCEPTION 'RFM segments do not cover all customers: % of %, % unassigned',
                        seg_customers, all_customers, unassigned;
    END IF;
    RAISE NOTICE 'Q7 check passed: % customers in segments = % customers.', seg_customers, all_customers;
END
$$;


-- =============================================================================
-- Q8. BY CUSTOMER STATE
-- Question: How do states differ in volume, order value and loyalty?
-- Logic:    Orders, revenue and AOV use the state on each order. The repeat
--           rate is per customer, grouped by the state of their FIRST
--           delivered order (as in file 10, Q6). States with 500+
--           delivered orders.
-- Result:   17 states. SP: 42.00% of orders, 38.36% of revenue, AOV 125.12
--           (lowest of the 17), repeat 2.30%. RJ 12.79% / 13.29%, MG 11.76% /
--           11.75%. AOV is highest in smaller, more distant states: PB
--           218.09, PA 184.06, MT 171.91, CE 171.33. Later-day repeat rates
--           range from 1.01% (MA) to 2.46% (MT).
-- =============================================================================
CREATE TEMP VIEW q8_by_state AS
WITH o AS (
    SELECT
        customer_state                                                     AS state,
        COUNT(*)                                                           AS orders,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                 AS pct_of_orders,
        ROUND(100.0 * SUM(item_value) / SUM(SUM(item_value)) OVER (), 2)   AS pct_of_revenue,
        ROUND(SUM(item_value) / COUNT(*), 2)                               AS aov
    FROM delivered
    GROUP BY customer_state
),
c AS (
    SELECT
        first_state                                                        AS state,
        COUNT(*)                                                           AS customers,
        ROUND(100.0 * COUNT(*) FILTER (WHERE returned_later_day) / COUNT(*), 2) AS repeat_rate_later_day_pct
    FROM customers
    GROUP BY first_state
)
SELECT o.state, o.orders, o.pct_of_orders, o.pct_of_revenue, o.aov,
       c.customers, c.repeat_rate_later_day_pct
FROM o
JOIN c ON c.state = o.state
WHERE o.orders >= 500;
-- The shares are computed in "o" BEFORE the 500+ filter, so they are shares
-- of ALL orders and revenue, not of the large states only.

\copy (SELECT * FROM q8_by_state ORDER BY orders DESC) TO 'results/14_by_state.csv' WITH (FORMAT csv, HEADER true)
SELECT * FROM q8_by_state ORDER BY orders DESC;
