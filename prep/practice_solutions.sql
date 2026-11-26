-- Practice solutions for prep/interview_guide.md, section 11 (generated from the guide).
-- Each expected answer matches a number in results/. Raw tables only.

-- E1 (easy). Count orders by status, largest first.
-- Expected: delivered 96,478 first (results/02_data_quality_output.txt).
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- E2 (easy). How many people (customer_unique_id) have more than one customer_id?
-- Expected: 2,997.
SELECT COUNT(*)
FROM (SELECT customer_unique_id
      FROM customers
      GROUP BY customer_unique_id
      HAVING COUNT(*) > 1) t;

-- E3 (easy). Delivered revenue (item price) for purchases from 2017-01-01 to 2018-08-31.
-- Expected: 13,181,027.13 (baseline.csv).
SELECT SUM(oi.price)
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= DATE '2017-01-01'
  AND o.order_purchase_timestamp <  DATE '2018-09-01';

-- E4 (easy-medium). Orders per month in the window, all statuses.
-- Expected: 2017-11 has 7,544 (baseline.csv).
SELECT date_trunc('month', order_purchase_timestamp)::date AS month, COUNT(*)
FROM orders
WHERE order_purchase_timestamp >= DATE '2017-01-01'
  AND order_purchase_timestamp <  DATE '2018-09-01'
GROUP BY 1
ORDER BY 1;

-- E5 (medium). Top 5 categories by delivered revenue, using the English name, else Portuguese, else 'unknown'.
-- Expected: health_beauty 1,229,557.50 first (14_top_categories.csv).
SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       SUM(oi.price) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= DATE '2017-01-01'
  AND o.order_purchase_timestamp <  DATE '2018-09-01'
GROUP BY 1
ORDER BY revenue DESC
LIMIT 5;

-- E6 (medium). On-time rate: delivered in the window, with a delivery date; on time = delivered date <= estimated date (calendar days).
-- Expected: 93.21.
SELECT ROUND(100.0 * COUNT(*) FILTER (
         WHERE order_delivered_customer_date::date <= order_estimated_delivery_date::date)
       / COUNT(*), 2)
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp >= DATE '2017-01-01'
  AND order_purchase_timestamp <  DATE '2018-09-01';

-- E7 (medium). Average review score in the window, keeping only the latest review per order.
-- Expected: 4.09.
WITH latest AS (
  SELECT order_id, review_score,
         ROW_NUMBER() OVER (PARTITION BY order_id
                            ORDER BY review_answer_timestamp DESC,
                                     review_creation_date DESC, review_id) AS rn
  FROM order_reviews
)
SELECT ROUND(AVG(l.review_score), 2)
FROM latest l
JOIN orders o ON o.order_id = l.order_id
WHERE l.rn = 1
  AND o.order_purchase_timestamp >= DATE '2017-01-01'
  AND o.order_purchase_timestamp <  DATE '2018-09-01';

-- E8 (medium-hard). Median days between a customer's first and second delivered order in the window, using LAG.
-- Expected: 29 (10_time_to_second_order_percentiles.csv).
WITH d AS (
  SELECT c.customer_unique_id,
         o.order_purchase_timestamp::date AS purchase_date,
         ROW_NUMBER() OVER w AS seq,
         LAG(o.order_purchase_timestamp::date) OVER w AS prev_date
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp >= DATE '2017-01-01'
    AND o.order_purchase_timestamp <  DATE '2018-09-01'
  WINDOW w AS (PARTITION BY c.customer_unique_id
               ORDER BY o.order_purchase_timestamp, o.order_id)
)
SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY purchase_date - prev_date)
FROM d
WHERE seq = 2;

-- E9 (hard). Share of delivered revenue from the top 1% of sellers.
-- Expected: 30 sellers, 25.93 (13_concentration.csv).
WITH seller_rev AS (
  SELECT oi.seller_id, SUM(oi.price) AS revenue
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp >= DATE '2017-01-01'
    AND o.order_purchase_timestamp <  DATE '2018-09-01'
  GROUP BY oi.seller_id
),
ranked AS (
  SELECT ROW_NUMBER() OVER (ORDER BY revenue DESC, seller_id) AS rnk,
         COUNT(*) OVER () AS n,
         SUM(revenue) OVER (ORDER BY revenue DESC, seller_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running,
         SUM(revenue) OVER () AS total
  FROM seller_rev
)
SELECT rnk, ROUND(100.0 * running / total, 2)
FROM ranked
WHERE rnk = CEIL(n * 0.01);

-- E10 (hard). Of customers whose first delivered order in the window was in January 2017, what share had a delivered order in February 2017?
-- Expected: cohort 718, 2 active, 0.28 (10_cohort_matrix_pct.csv, 2017-01 row, m1).
WITH d AS (
  SELECT c.customer_unique_id,
         date_trunc('month', o.order_purchase_timestamp)::date AS m
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
    AND o.order_purchase_timestamp >= DATE '2017-01-01'
    AND o.order_purchase_timestamp <  DATE '2018-09-01'
),
firsts AS (
  SELECT customer_unique_id, MIN(m) AS cohort
  FROM d
  GROUP BY customer_unique_id
),
active AS (
  SELECT DISTINCT f.customer_unique_id
  FROM firsts f
  JOIN d ON d.customer_unique_id = f.customer_unique_id
        AND d.m = f.cohort + INTERVAL '1 month'
  WHERE f.cohort = DATE '2017-01-01'
)
SELECT COUNT(*) AS cohort_size,
       (SELECT COUNT(*) FROM active) AS active_m1,
       ROUND(100.0 * (SELECT COUNT(*) FROM active) / COUNT(*), 2) AS pct
FROM firsts
WHERE cohort = DATE '2017-01-01';
