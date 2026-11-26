-- =============================================================================
-- 02_data_quality.sql: data-quality checks after loading
--
-- Run:  psql -d olist -f sql/02_data_quality.sql
-- Read-only: every statement is a SELECT. Results are written up in
-- docs/data_quality_notes.md.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Row count per table
-- One UNION ALL so all counts come back as a single result.
-- -----------------------------------------------------------------------------
SELECT 'customers'                         AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'geolocation',                       COUNT(*) FROM geolocation
UNION ALL SELECT 'sellers',                           COUNT(*) FROM sellers
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
UNION ALL SELECT 'products',                          COUNT(*) FROM products
UNION ALL SELECT 'orders',                            COUNT(*) FROM orders
UNION ALL SELECT 'order_items',                       COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',                    COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',                     COUNT(*) FROM order_reviews
ORDER BY table_name;  -- UNION ALL has no guaranteed order, so sort explicitly


-- -----------------------------------------------------------------------------
-- 2. NULL counts on key and timestamp columns
-- COUNT(*) FILTER (WHERE col IS NULL) counts only the rows where col is NULL.
-- -----------------------------------------------------------------------------

-- 2a. orders: key plus all five timestamps
SELECT
    COUNT(*)                                                         AS total_rows,
    COUNT(*) FILTER (WHERE order_id                      IS NULL)    AS null_order_id,
    COUNT(*) FILTER (WHERE customer_id                   IS NULL)    AS null_customer_id,
    COUNT(*) FILTER (WHERE order_purchase_timestamp      IS NULL)    AS null_purchase_ts,
    COUNT(*) FILTER (WHERE order_approved_at             IS NULL)    AS null_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date  IS NULL)    AS null_delivered_carrier,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)    AS null_delivered_customer,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL)    AS null_estimated_delivery
FROM orders;

-- 2b. order_items: keys plus shipping limit and money
SELECT
    COUNT(*)                                                   AS total_rows,
    COUNT(*) FILTER (WHERE order_id            IS NULL)        AS null_order_id,
    COUNT(*) FILTER (WHERE product_id          IS NULL)        AS null_product_id,
    COUNT(*) FILTER (WHERE seller_id           IS NULL)        AS null_seller_id,
    COUNT(*) FILTER (WHERE shipping_limit_date IS NULL)        AS null_shipping_limit,
    COUNT(*) FILTER (WHERE price               IS NULL)        AS null_price,
    COUNT(*) FILTER (WHERE freight_value       IS NULL)        AS null_freight
FROM order_items;

-- 2c. order_payments: key plus money
SELECT
    COUNT(*)                                                   AS total_rows,
    COUNT(*) FILTER (WHERE order_id      IS NULL)              AS null_order_id,
    COUNT(*) FILTER (WHERE payment_type  IS NULL)              AS null_payment_type,
    COUNT(*) FILTER (WHERE payment_value IS NULL)              AS null_payment_value
FROM order_payments;

-- 2d. order_reviews: keys, score, timestamps, comments
SELECT
    COUNT(*)                                                         AS total_rows,
    COUNT(*) FILTER (WHERE review_id               IS NULL)          AS null_review_id,
    COUNT(*) FILTER (WHERE order_id                IS NULL)          AS null_order_id,
    COUNT(*) FILTER (WHERE review_score            IS NULL)          AS null_score,
    COUNT(*) FILTER (WHERE review_creation_date    IS NULL)          AS null_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL)          AS null_answer_ts,
    COUNT(*) FILTER (WHERE review_comment_title    IS NULL)          AS null_comment_title,
    COUNT(*) FILTER (WHERE review_comment_message  IS NULL)          AS null_comment_message
FROM order_reviews;

-- 2e. customers, sellers, products: key columns (plus product attributes)
SELECT
    (SELECT COUNT(*) FROM customers WHERE customer_id        IS NULL) AS null_customer_id,
    (SELECT COUNT(*) FROM customers WHERE customer_unique_id IS NULL) AS null_customer_unique_id,
    (SELECT COUNT(*) FROM sellers   WHERE seller_id          IS NULL) AS null_seller_id,
    (SELECT COUNT(*) FROM products  WHERE product_id         IS NULL) AS null_product_id,
    (SELECT COUNT(*) FROM products  WHERE product_category_name IS NULL) AS null_product_category,
    (SELECT COUNT(*) FROM products  WHERE product_weight_g   IS NULL) AS null_product_weight;


-- -----------------------------------------------------------------------------
-- 3. Duplicate keys
-- For each candidate key: how many key values appear more than once?
-- Declared PKs should give 0, which confirms the constraint. The
-- non-PK candidates show why they weren't used as keys.
-- -----------------------------------------------------------------------------
SELECT 'customers.customer_id' AS key_checked,
       COUNT(*) AS keys_appearing_more_than_once
FROM (SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'customers.customer_unique_id',
       COUNT(*) FROM (SELECT customer_unique_id FROM customers GROUP BY customer_unique_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'orders.order_id',
       COUNT(*) FROM (SELECT order_id FROM orders GROUP BY order_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_items.(order_id, order_item_id)',
       COUNT(*) FROM (SELECT order_id, order_item_id FROM order_items GROUP BY 1, 2 HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_payments.(order_id, payment_sequential)',
       COUNT(*) FROM (SELECT order_id, payment_sequential FROM order_payments GROUP BY 1, 2 HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_reviews.review_id',
       COUNT(*) FROM (SELECT review_id FROM order_reviews GROUP BY review_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_reviews.order_id',
       COUNT(*) FROM (SELECT order_id FROM order_reviews GROUP BY order_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_reviews.(review_id, order_id)',
       COUNT(*) FROM (SELECT review_id, order_id FROM order_reviews GROUP BY 1, 2 HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'products.product_id',
       COUNT(*) FROM (SELECT product_id FROM products GROUP BY product_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'sellers.seller_id',
       COUNT(*) FROM (SELECT seller_id FROM sellers GROUP BY seller_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'geolocation.zip_code_prefix',
       COUNT(*) FROM (SELECT geolocation_zip_code_prefix FROM geolocation GROUP BY 1 HAVING COUNT(*) > 1) d
ORDER BY key_checked;

-- 3b. geolocation: rows that are exact copies of another row (all 5 columns equal)
SELECT COUNT(*) - COUNT(DISTINCT (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
                                  geolocation_city, geolocation_state)) AS geolocation_exact_duplicate_rows
FROM geolocation;


-- -----------------------------------------------------------------------------
-- 4. Orders with no items, no payment, or no review
-- NOT EXISTS keeps an order when no matching child row exists.
-- -----------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM order_items    i WHERE i.order_id = o.order_id)) AS orders_without_items,
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id)) AS orders_without_payment,
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM order_reviews  r WHERE r.order_id = o.order_id)) AS orders_without_review;

-- 4b. Status breakdown of the orders with no items (are they mostly cancelled?)
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders_without_items DESC;


-- -----------------------------------------------------------------------------
-- 5. order_status distribution
-- -----------------------------------------------------------------------------
SELECT order_status,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 5b. Status vs delivery timestamp: does status agree with the dates?
SELECT order_status,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)     AS no_delivery_date,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL) AS has_delivery_date
FROM orders
GROUP BY order_status
ORDER BY order_status;


-- -----------------------------------------------------------------------------
-- 6. Date range and orders per month
-- -----------------------------------------------------------------------------
SELECT MIN(order_purchase_timestamp) AS first_purchase,
       MAX(order_purchase_timestamp) AS last_purchase
FROM orders;

-- date_trunc('month', ts) rounds each timestamp down to the 1st of its month.
SELECT date_trunc('month', order_purchase_timestamp)::date AS purchase_month,
       COUNT(*)                                            AS orders
FROM orders
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- 7. Customers with more than one order
-- customer_id is created per order, so counting by it should find (almost)
-- nobody with 2+ orders. customer_unique_id is the person, so it shows real
-- repeat buyers.
-- -----------------------------------------------------------------------------

-- 7a. By customer_id
SELECT COUNT(*) AS customer_ids_with_2plus_orders
FROM (
    SELECT customer_id
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) t;

-- 7b. By customer_unique_id (join orders to customers to get the person)
SELECT COUNT(*) AS unique_customers_with_2plus_orders
FROM (
    SELECT c.customer_unique_id
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
    HAVING COUNT(*) > 1
) t;

-- 7c. For context: how many unique customers place 1, 2, 3, ... orders
SELECT orders_per_customer, COUNT(*) AS unique_customers
FROM (
    SELECT c.customer_unique_id, COUNT(*) AS orders_per_customer
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
) t
GROUP BY orders_per_customer
ORDER BY orders_per_customer;


-- -----------------------------------------------------------------------------
-- 8. Relationships that were NOT enforced as foreign keys
-- These counts are the reason 00_schema.sql leaves those FKs out.
-- -----------------------------------------------------------------------------

-- 8a. Zip prefixes in customers / sellers that have no geolocation row
SELECT
    (SELECT COUNT(DISTINCT c.customer_zip_code_prefix) FROM customers c
      WHERE NOT EXISTS (SELECT 1 FROM geolocation g
                        WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)) AS customer_zips_missing,
    (SELECT COUNT(*) FROM customers c
      WHERE NOT EXISTS (SELECT 1 FROM geolocation g
                        WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)) AS customers_affected,
    (SELECT COUNT(DISTINCT s.seller_zip_code_prefix) FROM sellers s
      WHERE NOT EXISTS (SELECT 1 FROM geolocation g
                        WHERE g.geolocation_zip_code_prefix = s.seller_zip_code_prefix))   AS seller_zips_missing;

-- 8b. Product categories with no English translation
SELECT p.product_category_name, COUNT(*) AS products
FROM products p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM product_category_name_translation t
                  WHERE t.product_category_name = p.product_category_name)
GROUP BY p.product_category_name
ORDER BY products DESC;

-- 8c. The order(s) with no payment row, shown in full
SELECT o.order_id, o.order_status, o.order_purchase_timestamp,
       (SELECT COUNT(*) FROM order_items i WHERE i.order_id = o.order_id) AS items
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id);
