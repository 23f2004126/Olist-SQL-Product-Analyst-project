-- =============================================================================
-- 03_clean_views.sql: cleaned, analysis-ready views over the raw tables
--
-- Run:  psql -d olist -f sql/03_clean_views.sql
--
-- The raw tables (00_schema.sql) are never changed. Every cleaning rule
-- lives in these views, so it is visible and can be re-run.
--
-- Decisions applied here (C1-C12 in docs/data_quality_notes.md):
--   * Analysis window: purchases from 2017-01-01 to 2018-08-31 (in_window).
--   * A customer is customer_unique_id, not customer_id.
--   * Reviews: keep only the latest review per order.
--   * Delivery timing uses only delivered orders that have a customer
--     delivery date.
--   * Category: English name, else Portuguese name, else 'unknown'.
--   * Views use corrected column names ("length", not "lenght").
--
-- Every view states its GRAIN: what one row represents. The checks at the
-- end of the file stop with an error if any view has more than one row per
-- grain key ("fan-out").
-- =============================================================================

\set ON_ERROR_STOP on

-- Drop dependent views first (v_order_facts uses the others), so the script
-- can be re-run after the views have changed shape.
DROP VIEW IF EXISTS v_order_facts;
DROP VIEW IF EXISTS v_orders;
DROP VIEW IF EXISTS v_order_main_category;
DROP VIEW IF EXISTS v_seller_orders;
DROP VIEW IF EXISTS v_order_lines;
DROP VIEW IF EXISTS v_order_items_agg;
DROP VIEW IF EXISTS v_order_payments_agg;
DROP VIEW IF EXISTS v_order_review;
DROP VIEW IF EXISTS v_geo;
DROP VIEW IF EXISTS v_products;
DROP VIEW IF EXISTS v_sellers;


-- -----------------------------------------------------------------------------
-- v_order_items_agg
-- GRAIN: one row per order_id (only orders that have at least one item).
-- Rolls order_items up to order level. Then joining it to orders adds at
-- most one row per order and never duplicates orders.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_items_agg AS
SELECT
    order_id,
    COUNT(*)                  AS item_count,     -- one order_items row = one unit
    COUNT(DISTINCT seller_id) AS seller_count,   -- distinct sellers in the order
    SUM(price)                AS item_value,     -- goods value (this is "revenue")
    SUM(freight_value)        AS freight_value,  -- shipping, reported separately
    -- Seller's deadline to hand the order to the carrier. Items can have
    -- different limits; the LATEST is kept, the most lenient reading.
    MAX(shipping_limit_date)  AS latest_shipping_limit,
    -- The seller, but only when the order has exactly one. With
    -- one distinct seller, MIN(seller_id) is simply that seller.
    CASE WHEN COUNT(DISTINCT seller_id) = 1 THEN MIN(seller_id) END AS single_seller_id
FROM order_items
GROUP BY order_id;


-- -----------------------------------------------------------------------------
-- v_order_payments_agg
-- GRAIN: one row per order_id (only orders that have at least one payment).
-- Used only to cross-check revenue, never as the revenue source.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_payments_agg AS
WITH totals AS (
    -- Plain aggregates per order
    SELECT
        order_id,
        SUM(payment_value)        AS total_paid,
        COUNT(*)                  AS payment_rows,      -- 1 = single payment; more = split payment
        MAX(payment_installments) AS max_installments
    FROM order_payments
    GROUP BY order_id
),
ranked AS (
    -- Rank each order's payments by value, largest first. Ties are broken
    -- by payment_sequential so the result is always the same.
    SELECT
        order_id,
        payment_type,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY payment_value DESC, payment_sequential
        ) AS rn
    FROM order_payments
)
SELECT
    t.order_id,
    t.total_paid,
    t.payment_rows,
    t.max_installments,
    r.payment_type AS main_payment_type   -- type of the highest-value payment
FROM totals t
JOIN ranked r
  ON r.order_id = t.order_id
 AND r.rn = 1;                            -- exactly one row per order


-- -----------------------------------------------------------------------------
-- v_order_review
-- GRAIN: one row per order_id (only orders that have at least one review).
-- 547 orders have more than one review. The latest one is kept, by
-- answer timestamp, then creation date, then review_id as a final
-- tie-breaker so the choice is always the same.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_review AS
SELECT
    order_id,
    review_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    review_count               -- how many reviews the order had before one was kept
FROM (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_answer_timestamp DESC,
                     r.review_creation_date DESC,
                     r.review_id
        ) AS rn,
        COUNT(*) OVER (PARTITION BY r.order_id) AS review_count
    FROM order_reviews r
) t
WHERE rn = 1;


-- -----------------------------------------------------------------------------
-- v_geo
-- GRAIN: one row per zip code prefix.
-- The raw table has many points per prefix and 261,831 exact duplicate
-- rows. Duplicates are removed first (SELECT DISTINCT) so a copied point
-- doesn't pull the average towards itself.
-- -----------------------------------------------------------------------------
CREATE VIEW v_geo AS
SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    AVG(geolocation_lat)        AS lat,
    AVG(geolocation_lng)        AS lng,
    COUNT(*)                    AS distinct_points   -- how many points were averaged
FROM (
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng
    FROM geolocation
) g
GROUP BY geolocation_zip_code_prefix;


-- -----------------------------------------------------------------------------
-- v_products
-- GRAIN: one row per product_id.
-- LEFT JOIN keeps products whose category has no translation (2 categories)
-- or no category at all (610 products).
-- -----------------------------------------------------------------------------
CREATE VIEW v_products AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english,   -- 1st choice: English
             p.product_category_name,           -- 2nd: Portuguese
             'unknown')                         -- 3rd: no category at all
                                   AS category,
    p.product_category_name        AS category_pt,  -- original, for reference
    p.product_name_lenght          AS product_name_length,         -- typo fixed
    p.product_description_lenght   AS product_description_length,  -- typo fixed
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM products p
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = p.product_category_name;


-- -----------------------------------------------------------------------------
-- v_sellers
-- GRAIN: one row per seller_id.
-- A straight pass-through of the sellers table, so analysis reads seller
-- location from a clean view, not a raw table.
-- -----------------------------------------------------------------------------
CREATE VIEW v_sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM sellers;


-- -----------------------------------------------------------------------------
-- v_order_lines
-- GRAIN: one row per (order_id, order_item_id), i.e. one row per item sold.
-- Each item with its cleaned category, so category revenue is counted per
-- item. An order with items in two categories splits its revenue
-- between them.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_lines AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    p.category,                 -- English, else Portuguese, else 'unknown'
    oi.price,
    oi.freight_value
FROM order_items oi
JOIN v_products p ON p.product_id = oi.product_id;   -- one row per product: no fan-out


-- -----------------------------------------------------------------------------
-- v_seller_orders
-- GRAIN: one row per (order_id, seller_id) pair.
-- Each seller's part of an order: a multi-seller order has one row per
-- seller, so seller revenue can be attributed item by item.
-- -----------------------------------------------------------------------------
CREATE VIEW v_seller_orders AS
SELECT
    order_id,
    seller_id,
    COUNT(*)                 AS item_count,             -- this seller's items in the order
    SUM(price)               AS item_value,             -- this seller's revenue in the order
    SUM(freight_value)       AS freight_value,
    MAX(shipping_limit_date) AS latest_shipping_limit   -- this seller's handover deadline
FROM order_items
GROUP BY order_id, seller_id;


-- -----------------------------------------------------------------------------
-- v_order_main_category
-- GRAIN: one row per order_id (only orders that have at least one item).
-- An order can hold products from several categories. The "main" category
-- is the one with the highest item value in that order. Ties go to the
-- alphabetically first category so the result is always the same.
-- Used for repeat purchase by category.
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_main_category AS
SELECT
    order_id,
    category              AS main_category,
    category_item_value   AS main_category_value,  -- item value in that category
    category_count                                 -- how many categories the order had
FROM (
    -- Step 1 (GROUP BY): one row per (order, category) with its item value.
    -- Step 2 (window functions run after GROUP BY): rank categories within
    -- each order and count them.
    SELECT
        oi.order_id,
        p.category,
        SUM(oi.price) AS category_item_value,
        ROW_NUMBER() OVER (
            PARTITION BY oi.order_id
            ORDER BY SUM(oi.price) DESC, p.category
        ) AS rn,
        COUNT(*) OVER (PARTITION BY oi.order_id) AS category_count
    FROM order_items oi
    JOIN v_products p ON p.product_id = oi.product_id   -- 1 row per product, so no fan-out
    GROUP BY oi.order_id, p.category
) t
WHERE rn = 1;


-- -----------------------------------------------------------------------------
-- v_orders
-- GRAIN: one row per order_id. ALL orders, every status and date. Use
-- in_window to filter.
--
-- Time measures are in days. EXTRACT(EPOCH FROM interval) gives seconds;
-- dividing by 86400 (seconds per day) gives fractional days.
--
-- Timing columns are filled ONLY for delivered orders that have a customer
-- delivery date (has_delivery_timing). For every other order they are NULL,
-- so averages and medians can't pick up incomplete orders by accident.
-- -----------------------------------------------------------------------------
CREATE VIEW v_orders AS
WITH base AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.customer_unique_id,                  -- the real person (C2)
        c.customer_state,
        c.customer_zip_code_prefix,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        -- Half-open range: >= 1 Jan 2017 and < 1 Sep 2018. This includes
        -- every time on 31 Aug 2018 (a BETWEEN '2018-08-31' would stop at 00:00).
        (o.order_purchase_timestamp >= DATE '2017-01-01'
         AND o.order_purchase_timestamp <  DATE '2018-09-01')         AS in_window,
        (o.order_status = 'delivered')                                AS is_delivered,
        (o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL)             AS has_delivery_timing
    FROM orders o
    -- Inner join is safe: every orders.customer_id exists in customers (FK),
    -- and customer_id is the customers PK, so this can't duplicate orders.
    JOIN customers c ON c.customer_id = o.customer_id
)
SELECT
    order_id,
    customer_id,
    customer_unique_id,
    customer_state,
    customer_zip_code_prefix,
    order_status,
    order_purchase_timestamp,
    -- raw milestone timestamps, exposed as-is
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    date_trunc('month', order_purchase_timestamp)::date AS purchase_month,  -- 1st of the month
    in_window,
    is_delivered,
    has_delivery_timing,

    -- Promised time: purchase date -> estimated date, in whole
    -- calendar days. Same calendar-day basis as delay_days, so
    -- promised_days + delay_days = actual calendar days to delivery.
    CASE WHEN has_delivery_timing THEN
        order_estimated_delivery_date::date - order_purchase_timestamp::date
    END AS promised_days,

    -- Total delivery time: purchase -> customer receives it (fractional days)
    CASE WHEN has_delivery_timing THEN
        ROUND(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400, 2)
    END AS delivery_days,

    -- Delay vs promise, in whole calendar days. The estimate always has time
    -- 00:00, so dates are compared (C8). Negative = early, 0 = on the promised day,
    -- positive = late.
    CASE WHEN has_delivery_timing THEN
        order_delivered_customer_date::date - order_estimated_delivery_date::date
    END AS delay_days,

    -- Late = delivered on a later calendar day than estimated.
    CASE WHEN has_delivery_timing THEN
        order_delivered_customer_date::date > order_estimated_delivery_date::date
    END AS is_late,

    -- Stage times (fractional days). If either timestamp is NULL the
    -- subtraction gives NULL, so a missing stage stays NULL.
    CASE WHEN has_delivery_timing THEN
        ROUND(EXTRACT(EPOCH FROM (order_approved_at - order_purchase_timestamp)) / 86400, 2)
    END AS days_purchase_to_approval,
    CASE WHEN has_delivery_timing THEN
        ROUND(EXTRACT(EPOCH FROM (order_delivered_carrier_date - order_approved_at)) / 86400, 2)
    END AS days_approval_to_carrier,
    CASE WHEN has_delivery_timing THEN
        ROUND(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_delivered_carrier_date)) / 86400, 2)
    END AS days_carrier_to_customer
FROM base;


-- -----------------------------------------------------------------------------
-- v_order_facts
-- GRAIN: one row per order_id, ONLY orders in the analysis window.
-- The main table for analysis: order attributes plus items, payments and
-- review, each already rolled up to one row per order.
--
-- LEFT JOINs keep orders that have no items / payment / review (those
-- columns are NULL). Each joined view has one row per order_id, so the joins
-- can't multiply rows.
--
-- The window functions run AFTER the WHERE clause, so a customer's sequence
-- number and first order date count in-window orders only (all statuses).
-- -----------------------------------------------------------------------------
CREATE VIEW v_order_facts AS
SELECT
    o.order_id,
    o.customer_unique_id,
    o.customer_state,
    o.customer_zip_code_prefix,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.purchase_month,
    o.is_delivered,
    o.has_delivery_timing,
    o.promised_days,
    o.delivery_days,
    o.delay_days,
    o.is_late,
    o.days_purchase_to_approval,
    o.days_approval_to_carrier,
    o.days_carrier_to_customer,

    -- from v_order_items_agg
    i.item_count,
    i.seller_count,
    i.item_value,
    i.freight_value,
    i.latest_shipping_limit,
    i.single_seller_id,

    -- from v_order_main_category
    mc.main_category,

    -- from v_order_payments_agg (cross-check only)
    p.total_paid,
    p.payment_rows,
    p.max_installments,
    p.main_payment_type,

    -- from v_order_review (latest review only)
    r.review_score,
    r.review_creation_date,
    r.review_answer_timestamp,

    -- 1 = customer's first order in the window, 2 = second, ...
    -- order_id breaks ties when two orders share a purchase timestamp.
    ROW_NUMBER() OVER (
        PARTITION BY o.customer_unique_id
        ORDER BY o.order_purchase_timestamp, o.order_id
    ) AS customer_order_seq,

    -- Same value on every row of a customer: their first purchase in the window
    MIN(o.order_purchase_timestamp) OVER (
        PARTITION BY o.customer_unique_id
    ) AS customer_first_order_at
FROM v_orders o
LEFT JOIN v_order_items_agg     i  ON i.order_id  = o.order_id
LEFT JOIN v_order_main_category mc ON mc.order_id = o.order_id
LEFT JOIN v_order_payments_agg  p  ON p.order_id  = o.order_id
LEFT JOIN v_order_review       r ON r.order_id = o.order_id
WHERE o.in_window;


-- =============================================================================
-- FAN-OUT CHECKS
-- For each view:
--   row_count     = rows in the view
--   distinct_keys = distinct values of its grain key
--   expected_rows = what the grain says the count should be, from raw tables
-- A view passes only if all three are equal. If any fails, the DO block
-- raises an exception, and with ON_ERROR_STOP psql exits with an error.
-- =============================================================================

-- A temporary view exists only for this session. It lets the script print
-- the checks and then test them without writing the query twice.
CREATE TEMP VIEW fanout_check AS
SELECT 'v_order_items_agg' AS view_name, 'order_id' AS grain_key,
       (SELECT COUNT(*)                 FROM v_order_items_agg)    AS row_count,
       (SELECT COUNT(DISTINCT order_id) FROM v_order_items_agg)    AS distinct_keys,
       (SELECT COUNT(DISTINCT order_id) FROM order_items)          AS expected_rows
UNION ALL
SELECT 'v_order_main_category', 'order_id',
       (SELECT COUNT(*)                 FROM v_order_main_category),
       (SELECT COUNT(DISTINCT order_id) FROM v_order_main_category),
       (SELECT COUNT(DISTINCT order_id) FROM order_items)
UNION ALL
SELECT 'v_order_payments_agg', 'order_id',
       (SELECT COUNT(*)                 FROM v_order_payments_agg),
       (SELECT COUNT(DISTINCT order_id) FROM v_order_payments_agg),
       (SELECT COUNT(DISTINCT order_id) FROM order_payments)
UNION ALL
SELECT 'v_order_review', 'order_id',
       (SELECT COUNT(*)                 FROM v_order_review),
       (SELECT COUNT(DISTINCT order_id) FROM v_order_review),
       (SELECT COUNT(DISTINCT order_id) FROM order_reviews)
UNION ALL
SELECT 'v_geo', 'zip_code_prefix',
       (SELECT COUNT(*)                        FROM v_geo),
       (SELECT COUNT(DISTINCT zip_code_prefix) FROM v_geo),
       (SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM geolocation)
UNION ALL
SELECT 'v_products', 'product_id',
       (SELECT COUNT(*)                   FROM v_products),
       (SELECT COUNT(DISTINCT product_id) FROM v_products),
       (SELECT COUNT(*)                   FROM products)
UNION ALL
SELECT 'v_order_lines', '(order_id, order_item_id)',
       (SELECT COUNT(*)                                  FROM v_order_lines),
       (SELECT COUNT(DISTINCT (order_id, order_item_id)) FROM v_order_lines),
       (SELECT COUNT(*)                                  FROM order_items)
UNION ALL
-- Composite grain: COUNT(DISTINCT (a, b)) counts distinct pairs
SELECT 'v_seller_orders', '(order_id, seller_id)',
       (SELECT COUNT(*)                            FROM v_seller_orders),
       (SELECT COUNT(DISTINCT (order_id, seller_id)) FROM v_seller_orders),
       (SELECT COUNT(DISTINCT (order_id, seller_id)) FROM order_items)
UNION ALL
SELECT 'v_sellers', 'seller_id',
       (SELECT COUNT(*)                  FROM v_sellers),
       (SELECT COUNT(DISTINCT seller_id) FROM v_sellers),
       (SELECT COUNT(*)                  FROM sellers)
UNION ALL
SELECT 'v_orders', 'order_id',
       (SELECT COUNT(*)                 FROM v_orders),
       (SELECT COUNT(DISTINCT order_id) FROM v_orders),
       (SELECT COUNT(*)                 FROM orders)
UNION ALL
SELECT 'v_order_facts', 'order_id',
       (SELECT COUNT(*)                 FROM v_order_facts),
       (SELECT COUNT(DISTINCT order_id) FROM v_order_facts),
       (SELECT COUNT(*) FROM orders
         WHERE order_purchase_timestamp >= DATE '2017-01-01'
           AND order_purchase_timestamp <  DATE '2018-09-01');

-- Print the results so they appear in the run output.
SELECT view_name,
       grain_key,
       row_count,
       distinct_keys,
       expected_rows,
       (row_count = distinct_keys AND row_count = expected_rows) AS passed
FROM fanout_check
ORDER BY view_name;

-- Fail loudly: stop the script with an error if any check failed.
DO $$
BEGIN
    IF EXISTS (SELECT 1
               FROM fanout_check
               WHERE row_count <> distinct_keys
                  OR row_count <> expected_rows) THEN
        RAISE EXCEPTION 'FAN-OUT CHECK FAILED: at least one view does not have one row per grain key. See the table above.';
    END IF;
    RAISE NOTICE 'All fan-out checks passed.';
END
$$;
