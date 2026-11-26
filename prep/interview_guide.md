# Olist SQL Product Analytics: Interview Prep Guide

Private prep notes. Not committed (prep/ is in .gitignore).
Every number comes from a file in results/. Where a number was checked once
during the project but never saved to results/, this guide says so instead of
quoting it.

---

## 1. Pitches

### 30-second version

- I analysed 99,441 orders from Olist, a Brazilian e-commerce marketplace, in PostgreSQL, using plain SQL only.
- I built a cleaned data layer with checks that fail loudly if a join duplicates rows. Then I answered five product questions: retention, delivery, reviews, sellers and revenue.
- The headline: only 2.15% of customers came back on a later day, and late deliveries drive 1-2 star reviews: 79.27% of orders arriving 8+ days late got one, against 8.98% for orders arriving a week early.
- I ended with three testable recommendations:
  - send the review request after delivery
  - hold sellers to a handover deadline
  - win back lapsed high-value customers with free freight

### 2-minute version

- **Context.** Olist is a Brazilian marketplace that lets small sellers sell through one storefront. The public dataset has 99,441 orders from 2016 to 2018 across 9 tables: orders, items, payments, reviews, customers, sellers, products, a category translation and geolocation.
- **Setup.** I loaded it into PostgreSQL with typed columns. I declared keys only where profiling showed they were unique, and foreign keys only where every child row had a parent. I documented every data-quality issue and the decision I took. For example, reviews are not one per order: 547 orders have more than one review, so I keep the latest.
- **Clean layer.** I built views at a stated grain, one row per order, product or seller. Every view is checked automatically: row count equals distinct keys equals the expected count, or the script stops.
- **Scope.** Analysis window: purchases from 2017-01-01 to 2018-08-31 (99,092 orders, 96,211 delivered). Revenue is 13,181,027.13 BRL of item value.
- **Retention.** 97.00% of customers ordered once. Only 2.15% returned on a later day. Of the "second orders", 29.65% were placed the same day as the first, usually within seconds, so I count only later-day returns.
- **Delivery.** 93.21% of orders arrived on time, because promises are generous: a median 24-day promise against a median 10 calendar days actual. Orders handed to the carrier after the seller's shipping deadline were late 21.10% of the time, against 5.39%.
- **Reviews.** The 1-2 star share climbs from 8.98% (7+ days early) to 79.27% (8+ days late). 74.46% of late orders were reviewed before they arrived.
- **Sellers.** The top 1% of sellers (30) earn 25.93% of revenue. 62 sellers produce 55.42% of the scorecard's late handovers.
- **Revenue.** Jan-Aug 2018 revenue was 141.13% above Jan-Aug 2017. Orders rose 139.94% and average order value only 0.49%, so growth is volume.
- **Three recommendations, each with an A/B test design:**
  1. Send the review request after delivery confirmation, because late orders are reviewed before they arrive.
  2. Put a handover SLA with alerts and a ranking penalty on sellers, starting with those 62 sellers.
  3. Win back the 22,369 lapsed high-value one-time customers, who brought 39.77% of revenue, with a free-freight voucher.

---

## 2. The dataset

### What Olist is

- **The business.** Olist is a Brazilian company that connects small merchants to large online marketplaces through one contract. A customer buys on the marketplace, a seller ships the product, a carrier delivers it, and the customer receives a satisfaction survey (the review).
- **The data.** The public Kaggle dataset is real, anonymised commercial data. Customers, sellers and products are hashed IDs. Purchase dates run from 2016-09-04 21:15:19 to 2018-10-17 17:30:18 (results/02_data_quality_output.txt).

### The 9 tables: what one row means

| Table | Rows | One row = |
|---|---:|---|
| orders | 99,441 | one order: status and five timestamps (purchase, approval, carrier handover, customer delivery, estimated delivery) |
| customers | 99,441 | one customer_id. Olist creates a new customer_id for every order; the person is customer_unique_id |
| order_items | 112,650 | one item in an order (order_item_id 1, 2, 3 ... within the order), with product, seller, price, freight, shipping limit |
| order_payments | 103,886 | one payment part of an order (payment_sequential); an order can be split over card and voucher |
| order_reviews | 99,224 | one review attached to one order; not unique by review_id or by order_id |
| products | 32,951 | one product: Portuguese category, dimensions, weight, photo count |
| sellers | 3,095 | one seller: zip prefix, city, state |
| product_category_name_translation | 71 | Portuguese category name -> English |
| geolocation | 1,000,163 | one lat/lng point for a zip-code prefix; many points per prefix |

### How they join

- orders.customer_id -> customers.customer_id (one customer_id per order)
- order_items.order_id -> orders.order_id (many items per order)
- order_items.product_id -> products.product_id
- order_items.seller_id -> sellers.seller_id (one order can have several sellers)
- order_payments.order_id -> orders.order_id (many payments per order)
- order_reviews.order_id -> orders.order_id (usually one review, sometimes more)
- products.product_category_name -> translation.product_category_name (not enforced: 2 categories missing)
- customers / sellers zip prefix -> geolocation zip prefix (not a key: many rows per prefix)

### What the data can't answer

- **Why** customers leave or come back: there is no browsing, marketing, search or support data.
- **Margin or profit:** there are prices, but no costs, commissions or Olist fees.
- **Cause and effect:** everything is observational, and nothing was randomised.
- **Customer history before 2016, or behaviour on other channels.**
- **Carrier identity**, so carrier performance can't be split out.
- **Review text in English:** comments are Portuguese, and only the score was analysed.
- **Exact locations:** only zip-code prefixes, so distances are between prefix centres.

---

## 3. Setup and schema (00_schema.sql, 01_load.sql)

### Type choices

- **IDs are varchar(32).** They are 32-character hex hashes; the length documents that.
- **Zip prefixes are char(5), not integer.** As numbers, "01037" would lose its leading zero and become 1037.
- **Money is numeric(10,2).** numeric is exact. float can add rounding errors when summing money, and every source value has 2 decimals.
- **Latitude and longitude are double precision.** They are measurements, not money, so tiny float error doesn't matter.
- **Timestamps are timestamp without time zone.** The source has no time zone, and adding one would claim information the data doesn't have.
- **Counts and dimensions are integer; review_score is smallint.**
- **Column names match the CSV exactly, including Olist's typo "lenght".** Raw tables mirror the source; the clean view v_products exposes "length".

### Primary keys: only where profiling proved uniqueness

- **Single-column keys:** customers(customer_id), orders(order_id), products(product_id), sellers(seller_id), translation(product_category_name). Each is unique in the data.
- **order_items: (order_id, order_item_id).** order_item_id restarts at 1 in every order, so it is unique only with order_id.
- **order_payments: (order_id, payment_sequential).** Same idea: payments are numbered within an order.
- **order_reviews: (review_id, order_id).** Neither column is unique on its own: 789 review_ids repeat and 547 orders have more than one review. The pair is unique.
- **geolocation: no primary key.** There are 19,015 distinct zip prefixes across 1,000,163 rows, and 261,831 rows are exact copies of another row, so nothing identifies a row.

### Foreign keys: only where every child has a parent

- **Declared:** orders -> customers; order_items -> orders, products, sellers; order_payments -> orders; order_reviews -> orders. Each had 0 orphans when profiled.
- **Not declared: products -> translation.** 2 categories (portateis_cozinha_e_preparadores_de_alimentos with 10 products, pc_gamer with 3) have no translation. The constraint would reject those products, so I use a LEFT JOIN with a fallback instead.
- **Not declared: customers/sellers zip -> geolocation.** A foreign key must point at a unique column, and the zip prefix isn't unique in geolocation. Also, 157 customer zip prefixes (278 customers) and 7 seller prefixes are missing from geolocation.

### Load (01_load.sql)

- **\copy rather than COPY.** COPY reads files on the database server; \copy is a psql command that reads the file on my machine and streams it. It needs no server file permissions.
- **FORMAT csv, HEADER true.** CSV mode handles quoted commas and line breaks inside review comments. HEADER skips the column-name line, which also skips the hidden BOM at the start of the translation file.
- **Empty unquoted fields load as NULL** in CSV mode. That is how blank timestamps became NULLs.
- **One transaction (BEGIN ... COMMIT).** Either every table loads or nothing changes; no half-loaded state.
- **ON_ERROR_STOP.** psql stops at the first error instead of carrying on.
- **Re-runnable.** It starts with one TRUNCATE of all 9 tables; listing them together lets Postgres empty tables that reference each other. A second run gave identical counts.
- **Load order is parents before children** (customers, geolocation, sellers, translation, products, orders, items, payments, reviews), so every foreign key finds its parent.
- **ANALYZE at the end** refreshes planner statistics after a bulk load.
- **The schema script drops tables children-first,** so foreign keys don't block the drop and the schema can be rebuilt from scratch.

---

## 4. Data quality: issues, numbers, decisions and why

Sources: results/02_data_quality_output.txt, results/baseline.csv,
results/15_quality_issues.csv, docs/data_quality_notes.md (C1-C12 = confirmed decisions).

- **Thin months at both ends.**
  - *Numbers:* 2016-09 has 4 orders, 2016-10 has 324, 2016-11 has none, 2016-12 has 1; 2018-09 has 16, 2018-10 has 4.
  - *Decision (C1):* window 2017-01-01 to 2018-08-31. 349 orders fall outside it.
  - *Why:* partial months distort trends and month-over-month changes. The alternative of keeping everything and flagging it would still put misleading points on every chart.
- **customer_id is per order.**
  - *Numbers:* counting by customer_id, 0 customers have 2+ orders; by customer_unique_id, 2,997 do.
  - *Decision (C2):* identify customers by customer_unique_id.
  - *Why:* customer_id would make retention exactly zero. That is an artefact, not a finding.
- **Multiple reviews per order.**
  - *Numbers:* 547 orders have 2+ reviews, and 789 review_ids repeat across orders.
  - *Decision (C3):* keep the latest review per order (by answer time, then creation date, then review_id).
  - *Why:* the latest reflects the final opinion. An average would invent half-star scores; the first would ignore updates. Never join on review_id.
- **Revenue definition.**
  - *Decision (C4):* revenue = SUM(order_items.price) on delivered orders. Freight is separate; payments are a cross-check only.
  - *Why:* item price is what the seller sells. Payments include instalment interest and vouchers, and one order has no payment row.
- **Payments don't always reconcile.**
  - *Numbers:* 294 delivered in-window orders differ from items + freight by more than 0.01 (257 paid more, 37 paid less). Total gap 3,023.49 BRL; median 5.66; max 182.81.
  - *Decision (C11):* leave unexplained and list as a limitation.
  - *Why:* 294 of 96,211 orders, and revenue doesn't use payments.
- **Status contradicts dates.**
  - *Numbers:* 8 delivered orders have no delivery date, and 6 canceled orders have one.
  - *Decision (C5):* delivery timing uses only delivered orders with a delivery date (96,203).
  - *Why:* timing needs both dates; the contradictions are too few to matter and are kept but not timed.
- **Missing categories.**
  - *Numbers:* 610 products have no category; 13 products have an untranslated category.
  - *Decision (C6):* English name, else Portuguese, else 'unknown'.
  - *Why:* dropping them would remove real sales from category totals.
- **Column typo "lenght".**
  - *Decision (C7):* raw tables unchanged; v_products exposes corrected names.
  - *Why:* raw stays faithful to the source; analysis uses clean names.
- **On-time definition.**
  - *Decision (C8):* calendar days. Late = delivered on a later calendar day than estimated.
  - *Why:* the estimated date always has time 00:00:00, so a timestamp comparison would call a delivery on the promised day late. The timestamp version gave a lower rate when I checked it once; that number isn't saved in results/.
- **Negative stage durations.**
  - *Numbers:* 1,344 timed in-window orders have a stage running backwards (for example, carrier handover recorded before approval).
  - *Decision (C9):* exclude from stage statistics only, and report the count.
  - *Why:* they are clearly recording errors for stage timing, but the delivery itself is fine, so they stay in every other metric.
- **Retention population.**
  - *Decision (C10):* retention uses delivered orders only, with the sequence recomputed over delivered orders.
  - *Why:* a canceled first order isn't a real first purchase.
- **Same-day "second orders".**
  - *Numbers:* 827 of 2,789 second orders fall on the same day as the first. 735 are within 10 minutes, 253 have an identical timestamp, and the median gap is 0.0167 minutes (1 second).
  - *Decision (C12):* a repeat customer is one who returned on a later calendar day.
  - *Why:* these look like one checkout split into several orders, not a return visit. The any-day figure (3.00%) is shown alongside where it helps.
- **Geolocation duplicates.**
  - *Numbers:* 261,831 exact duplicate rows; 17,972 zip prefixes have more than one row.
  - *Decision:* v_geo averages distinct points, one row per prefix.
  - *Why:* without de-duplication, a copied point pulls the average towards itself.
- **Orders without children.**
  - *Numbers:* 775 orders have no items (603 unavailable, 164 canceled, 5 created, 2 invoiced, 1 shipped), 1 has no payment (delivered, 2016-09-15, outside the window) and 768 have no review.
  - *Decision:* item analysis naturally drops orders with no items; review metrics use reviewed orders only.
- **Geo coverage.**
  - *Numbers:* 157 customer zip prefixes (278 customers) and 7 seller prefixes are not in geolocation.
  - *Decision:* exclude those orders from distance analysis only.

---

## 5. Clean views (03_clean_views.sql)

### Why views at all

- **Raw tables are never changed.** All cleaning is visible SQL that can be re-run.
- **Every view states its grain** (what one row means), so joins can't silently multiply rows.

### The fan-out problem

- **What it is.** Joining orders (1 row per order) to order_items (many per order) gives one row per item. Any SUM or COUNT over that result counts orders several times.
- **Example.** An order with 3 items joined to its payment would count the payment 3 times.
- **The cure.** Aggregate the child table to one row per order first, then join one-to-one.

### Each view

- **v_order_items_agg** (98,666 rows, one per order with items)
  - item_count, seller_count, item_value, freight_value, latest_shipping_limit
  - single_seller_id: the seller when there is exactly one; MIN(seller_id) returns that seller.
- **v_order_payments_agg** (99,440 rows, one per order with payments)
  - total_paid, payment_rows, max_installments
  - main_payment_type: the highest-value payment, picked with ROW_NUMBER.
- **v_order_review** (98,673 rows, one per reviewed order)
  - The latest review, via ROW_NUMBER over order_id, plus review_count.
- **v_geo** (19,015 rows, one per zip prefix)
  - The average lat/lng of distinct points.
- **v_products** (32,951 rows, one per product)
  - Cleaned category (COALESCE English, Portuguese, 'unknown') and corrected column names.
- **v_sellers** (3,095 rows, one per seller)
  - A pass-through, so analysis reads seller location from a clean view.
- **v_order_lines** (112,650 rows, one per item)
  - Each item with its category, so category revenue is counted per item.
- **v_seller_orders** (100,010 rows, one per order-seller pair)
  - Each seller's part of an order, so seller revenue is split by item, not double-counted.
- **v_order_main_category** (98,666 rows, one per order with items)
  - The category with the highest item value in the order.
- **v_orders** (99,441 rows, all orders)
  - customer_unique_id and state, in_window, is_delivered, has_delivery_timing
  - promised_days, delivery_days, delay_days, is_late, three stage durations.
  - Every timing column is NULL unless the order is delivered with a date.
- **v_order_facts** (99,092 rows, in-window orders only)
  - v_orders LEFT JOINed to the per-order views. Missing children become NULLs and orders are never dropped.

### How the checks prove it

- **Three counts per view.** For every view: row_count, COUNT(DISTINCT grain key) and the expected count from the raw tables.
  - For example, v_order_items_agg must equal COUNT(DISTINCT order_id) in order_items.
- **Fail loudly.** A DO block raises an exception if any of the three differ, and with ON_ERROR_STOP psql exits with an error.
- **Tested.** I fed it a fake failing row to confirm it stops (psql exit code 3).
- **Result.** All 11 views pass (results/03_clean_views_output.txt).
- **Totals reconcile.** Other files assert totals: seller revenue split by item adds back to exactly 13,181,027.13, and the retention repeat rate matches the baseline.

---

## 6. The analyses, query by query

Format for each query: question / why it matters / logic / technique / result / insight / caveat.

### File 10: retention (results/10_*.csv)

Building blocks:
- **delivered_orders:** one row per delivered in-window order, with ROW_NUMBER (delivered_seq), LAG (previous purchase) and MIN OVER (first purchase date) per customer_unique_id.
- **delivered_customers:** one row per customer, using MAX(...) FILTER (WHERE delivered_seq = 1) to pull first-order attributes.

**Q1. Orders per customer**
- *Question:* how many customers have 1, 2, 3, 4+ delivered orders?
- *Why it matters:* it sizes the repeat business.
- *Logic:* bucket delivered_orders per customer and add a repeat-rate row.
- *Technique:* CASE buckets, SUM(COUNT(*)) OVER () for shares, and a DO-block check against the baseline.
- *Result:* 1 order 90,315 (97.00%); 2 orders 2,562 (2.75%); 3 orders 180 (0.19%); 4+ orders 47 (0.05%). Repeat (any day) 2,789 = 3.00%, matching the baseline.
- *Insight:* almost everyone buys once.
- *Caveat:* only the window is visible, so a 2016 buyer's first in-window order counts as their first.

**Q2. Time to second order**
- *Question:* for customers who return, how long until the second order?
- *Why it matters:* it sets the timing for re-engagement.
- *Logic:* on the delivered_seq = 2 row, LAG gives the first order's date; the gap is in calendar days.
- *Technique:* LAG and percentile_cont.
- *Result:* p25 0 days, median 29, p75 125, p90 245. Buckets: same day 827 (29.65%); 1-7 days 198 (7.10%); 8-30 days 387 (13.88%); 31-90 days 492 (17.64%); 91-180 days 413 (14.81%); 180+ days 472 (16.92%).
- *Insight:* the 25th percentile is 0, which exposed the same-day issue.
- *Caveat:* calendar days, not hours.

**Q3. Same-day check**
- *Question:* how many second orders are same-day, and what is the repeat rate without them?
- *Why it matters:* it decides whether the 3.00% repeat rate is real.
- *Logic:* a later-day repeat is any delivered order on a later calendar day than the first.
- *Technique:* FILTER counts.
- *Result:* 29.65% of second orders are same-day. Repeat rate is 3.00% for any day and 2.15% (2,005 customers) for a later day.
- *Insight:* about a third of apparent repeat behaviour isn't a return.
- *Caveat:* a split checkout is the likely explanation, but not proven.

**Q3b. Same-day gap**
- *Result:* of 827 same-day second orders, 253 have an identical timestamp, 735 come within 10 minutes, and the median gap is 0.0167 minutes.
- *Insight:* consistent with one checkout recorded as several orders.

**Q4. Monthly cohort matrix**
- *Question:* of customers who first bought in month X, what share bought again 1-12 months later?
- *Why it matters:* it is the standard view of retention decay.
- *Logic:* cohort = first delivered month. A grid of cohort x months 0-12 from generate_series is LEFT JOINed to activity. Cells after 2018-08 are NULL, not 0.
- *Technique:* cohort matrix, DISTINCT activity, month arithmetic (year x 12 + month), CROSS JOIN with generate_series.
- *Result:* 20 cohorts and 260 cells; cells after 2018-08 are NULL. Every observable month 1-12 cell is under 1%; the highest is 0.72% (2017-10, month 1).
- *Insight:* there is no retained core in any cohort.
- *Caveat:* exact-month activity: a customer who skips a month isn't counted in it.

**Q5. Fixed-window repeat**
- *Question:* what share order again within 90 / 180 days?
- *Why it matters:* it is fair across cohorts because everyone gets the same time to return.
- *Logic:* only customers whose first order + N days falls before 2018-09-01 count.
- *Technique:* interval arithmetic, COALESCE(comparison, false), NULLIF in the denominator.
- *Result:* 90 days: 75,448 eligible, 2.28% (later-day 1.30%). 180 days: 56,194 eligible, 3.12% (later-day 1.97%).
- *Caveat:* some cohorts are only partly eligible (2018-03 for 180 days: 927 of 6,775).

**Q6. Who comes back**
- *Question:* does the repeat rate differ by first-order category, state, payment type or value?
- *Logic:* segment customers by first-order attributes. Categories need 500+ customers. Value quartiles use NTILE(4).
- *Technique:* NTILE, HAVING.
- *Result, category:* home_appliances 8.74% any-day but 1.78% later-day; fashion_bags_accessories 5.63% (3.79% later-day); electronics 1.63%.
- *Result, state:* big states 2.65-3.26%.
- *Result, payment:* voucher 3.64%, credit_card 2.99%, boleto 2.99%, debit_card 2.29%.
- *Result, value quartile:* 3.15% / 3.12% / 2.89% / 2.81%, cheapest to most expensive.
- *Insight:* rankings change once same-day orders are removed, and value barely matters.
- *Caveat:* NTILE splits tied values across quartiles; small segments are noisy.

**Q7. Revenue from repeat customers**
- *Result:* total 13,181,027.13. Second and later orders: 381,515.75 = 2.89% of revenue (3,107 orders, 3.23% of orders). Repeat customers' orders including their first: 5.50%.
- *Insight:* retention is a growth lever not yet used, rather than a current revenue source.

### File 11: delivery (results/11_*.csv)

Population: 96,203 delivered in-window orders with a delivery date.

**Q1. Overall**
- *Result:* on time 93.21% (6,531 late). Delivery days: p50 10.21, p75 15.68, p90 23.06, p95 29.22.
- *Technique:* percentile_cont at several p values.
- *Insight:* the tail matters; the 95th percentile (29.22) is far above the median (10.21).

**Q2. Monthly trend**
- *Logic:* percentile_cont ignores NULLs, so medians cover timed orders only.
- *Result:* the late rate is 2.79-6.56% in most months, with spikes in 2017-11 (12.40%), 2018-02 (14.13%) and 2018-03 (18.96%). The median falls to 7.01 days in 2018-08.
- *Caveat:* recent months have undelivered orders (2018-08: 161 of 6,512 have no timing), so they may be missing their slowest deliveries.

**Q3. Promise accuracy**
- *Logic:* promised_days = estimated date - purchase date. Actual calendar days = promised_days + delay_days; a DO block asserts the identity with 0 mismatches.
- *Technique:* date subtraction (date - date gives an integer), CASE buckets.
- *Result:* median promise 24 days, actual 10, delay -12. Buckets: 7+ days early 75,882 (78.88%); 1-6 days early 12,499 (12.99%); on the day 1,291 (1.34%); 1-3 days late 1,869 (1.94%); 4-7 days late 1,802 (1.87%); 8+ days late 2,860 (2.97%).
- *Insight:* promises are very conservative, so being on time is mostly about the tail.

**Q4. By customer state (500+ orders)**
- *Result:* worst late rates MA 17.53%, CE 13.83%, BA 12.17%, RJ 12.14%; best PR 4.06%, SP 4.50%. SP is fastest (median 7.20 days, promise 19).
- *Insight:* the northeastern states get longer promises (MA 31, CE 32) and are still late more often. RJ is an outlier among large markets.

**Q5. Stage breakdown**
- *Logic:* three stages (purchase -> approval, approval -> carrier, carrier -> customer). Orders with any negative stage or any missing stage are excluded so all medians use the same orders. Filters use IS TRUE / IS NOT TRUE because a comparison with NULL is NULL.
- *Result:* excluded 1,344 negative + 15 missing; 94,844 used. Medians (approval / to carrier / carrier to customer): on time 0.01 / 1.79 / 6.96; late 0.02 / 3.06 / 26.21.
- *Insight:* late orders differ mostly in transit.

**Q6. Seller handover**
- *Logic:* handover is after the limit when carrier date > latest shipping_limit_date of the order's items.
- *Result:* after the limit: 8,581 orders (8.92%), late 21.10%, median 16.88 days. On or before: 87,621 (91.08%), late 5.39%, median 9.82 days.
- *Insight:* a strong association, though not proven cause.

**Q7. Same state vs cross state (single-seller orders)**
- *Result:* same state: 34,149 orders, median 6.56 days, late 4.57%. Cross state: 60,782 orders, median 12.84 days, late 8.16%. Excluded multi-seller orders: 1,272.

**Q8. Distance (haversine)**
- *Logic:* great-circle distance between zip-prefix centres, with bad coordinates dropped by a Brazil bounding box.
- *Result:* coverage 94,453 of 94,931 orders (99.50%). Late rate rises with every band: 4.48% (0-50 km), 4.71% (50-200 km), 6.48% (200-500 km), 7.21% (500-1000 km), 9.68% (1000-2000 km), 12.17% (2000+ km). Median days go from 4.90 to 18.26.
- *Caveat:* prefix centres, not addresses.

### File 12: reviews (results/12_*.csv)

Population: 98,330 in-window orders with a review (latest review); low = 1-2 stars (14,382 reviews).

**Q1. Distribution**
- *Result:* 1 star 11,263 (11.45%); 2 stars 3,119 (3.17%); 3 stars 8,110 (8.25%); 4 stars 18,986 (19.31%); 5 stars 56,852 (57.82%).
- *Insight:* the distribution is U-shaped, with more 1s than 2s.

**Q2. By delay bucket**
- *Result (low-review share):* 7+ days early 8.98%; 1-6 days early 10.58%; on the day 12.42%; 1-3 days late 32.14%; 4-7 days late 67.68%; 8+ days late 79.27%; no delivery timing 77.76%.
- *Insight:* the biggest jump is from "on the day" to late.

**Q3. Speed among on-time orders**
- *Result (low-review share):* 0-7 days 7.54%; 8-14 days 8.86%; 15-21 days 11.03%; 22+ days 15.78%.
- *Insight:* even when the promise is kept, slower delivery goes with lower scores.

**Q4. Order make-up**
- *Result (low-review share):* single item 12.67% vs multi item 27.61%; single seller 13.72% vs multi seller 47.22%.

**Q5. Category (500+ reviewed orders)**
- *Result:* 27 categories qualify. Highest low-review share: office_furniture 22.39%. Lowest: books_general_interest 8.13%.
- *Insight:* the spread across categories is much narrower than across delay buckets.

**Q6. Status**
- *Result (low-review share):* delivered 12.80%; shipped 69.43%; canceled 76.11%; unavailable 84.86%; other 87.61%.

**Q7. Sizing (non-overlapping groups)**
- *Logic:* a CASE assigns each order to exactly one group; the order of the WHEN lines is the priority. A DO block checks the groups add up to 14,382.
- *Result (share of all low reviews):* undelivered 14.97%; late delivered 27.68%; on-time multi-seller 4.06%; everything else 53.29%.
- *Insight:* the problem groups are small but bad; "everything else" is low-rate (8.71%) but large (89.44% of orders).

**Q8. Review timing**
- *Result:* on-time orders: 221 (0.25%) reviewed before delivery. Late orders: 4,749 (74.46%) reviewed before delivery, average 1.84 stars, 75.22% low. Late orders reviewed on or after delivery: average 3.53, 25.11% low.

**Q8b. When the review is created**
- *Result:* on-time orders: median review 12 days before the estimate and 1 day after delivery. Late orders: 2 days after the estimate and 4 days before delivery.
- *Insight:* for late orders, the review appears soon after the promised date passes, while the customer is still waiting.

**Q9. First order and return**
- *Result:* later-day repeat after a late first order 1.62%, after an on-time first order 2.19%. After a 1-2 star first review 1.72%; after 4-5 stars 2.24%. The 180-day versions are 1.58% vs 2.00%, and 1.65% vs 2.03%. The 'all' rows match file 10 (2.15% and 1.97%).
- *Caveat:* only 103 returners after a late first order, and no significance test was run.

### File 13: sellers (results/13_*.csv)

Attribution rule:
- Revenue goes to each seller by item on all delivered orders.
- Reviews, lateness and handover are attributed only on single-seller orders.

**Q1. Concentration**
- *Result:* top 1% (30 sellers) 25.93%; top 5% (148) 52.99%; top 10% (295) 67.04%; top 20% (589) 82.20% of revenue.
- *Technique:* ROW_NUMBER, running SUM, CEIL.

**Q2. Size bands**
- *Result:* 1-9 orders: 1,711 sellers (58.10%) with 9.16% of revenue. 200+ orders: 85 sellers (2.89%) with 36.21%.

**Q3. Scorecard (30+ single-seller orders)**
- *Result:* 614 of 2,945 sellers qualify, holding 76.84% of revenue. Pooled late handover 8.72%, late delivery 6.88%, low reviews 12.53%. Seller low-review share runs from 0.00% to 60.00% (median 10.835%).

**Q4. Problem sellers**
- *Result:* benchmark 12.34%, so the threshold is 24.68%. 31 sellers qualify: 4.36% of orders, 5.15% of revenue and 10.62% of low reviews. Their late delivery is 12.38% vs 6.63%, and late handover 27.89% vs 7.84%.

**Q5. Late-handover concentration**
- *Result:* the top 10% (62 sellers) have 3,817 of 6,887 scorecard late handovers (55.42%; 44.74% of all single-seller late handovers) on 31.93% of orders.

**Q6. Handover quartiles**
- *Result:* late delivery 4.90% -> 5.98% -> 7.24% -> 9.43%, and low reviews 10.16% -> 11.48% -> 12.47% -> 16.31%, from the lowest-handover to the highest-handover quartile.

**Q7. Seller state (30+ sellers)**
- *Result:* SP has 1,751 sellers and 64.39% of revenue, with the highest late-delivery rate of the 8 states (7.43%). PR has the highest late-handover rate (10.99%).

**Q8. Seller activity**
- *Result:* 70-236 new sellers a month. 44.39-63.47% are active exactly 3 months later and 37.43-57.08% at 6 months.
- *Caveat:* exact-month rule, so these are a lower bound.

### File 14: revenue (results/14_*.csv)

**Q1. Monthly and year-on-year**
- *Result:* revenue peaks at 987,765.37 in 2017-11 (+52.37% month-over-month), then drops 26.50% in December.
- *Result, Jan-Aug year-on-year:* orders 21,998 -> 52,783 (+139.94%); revenue 2,993,456.13 -> 7,218,125.12 (+141.13%); average order value 136.08 -> 136.75 (+0.49%).

**Q2. Top categories**
- *Result:* 74 categories in total; the top 15 earn 76.33% of revenue. health_beauty is first at 9.33%.

**Q3. Category growth**
- *Result:* all top 15 grew. baby grew most (+268.56%) and cool_stuff least (+10.39%).

**Q4. Freight**
- *Result:* freight is 16.63% of item value overall. 35.12% of orders pay more than 30% in freight, and 15.84% more than 50%.
- *Result, by value:* the cheapest quartile pays 53.41% of item value; the most expensive pays 10.26%.
- *Result, by state:* MA 26.22%, SP 13.85%.

**Q5. Payments**
- *Result:* credit card 75.48% of orders and 78.89% of revenue.
- *Result, card instalments:* average order value is 82.49 BRL for 1 instalment and 301.22 BRL for 7+.

**Q6. Customer concentration**
- *Result:* top 1% of customers (932) bring 11.48% of revenue; top 10% bring 41.10%; top 20% bring 56.62%.

**Q7. RFM**
- *Result:* lapsed high-value 22,369 customers, 39.77% of revenue, 234.37 BRL average. Recent high-value 22,473 customers, 39.55%. Lapsed low-value 8.40% and recent low-value 8.15% of revenue. Repeat buyers 2,005 customers, 4.13% of revenue, 271.47 BRL average.
- *Caveat:* NTILE makes the four one-time segments about 25% each by construction.

**Q8. By state**
- *Result:* SP has 42.00% of orders and the lowest average order value (125.12). PB has the highest (218.09). Later-day repeat ranges from 1.01% (MA) to 2.46% (MT).

---

## 7. Findings and recommendations

### Metrics tree (results/15_metrics_tree.csv)

- **Revenue 13,181,027.13** = customers 93,104 x orders per customer 1.0334 x average order value 137.00.
- **Why it matters:** orders per customer is barely above 1, so growth has to come from more customers or bigger orders. F5 shows it came from more orders.

### F1. Retention

**Evidence chain** (results/15_pipelines.csv):
1. 99,441 orders
2. 99,092 in window (349 dropped)
3. 96,211 delivered (2,881 dropped)
4. 93,104 customers
5. 2,005 returned on a later day

**Headline:** 2.15% returned on a later day; 29.65% of second orders were same-day.

### F2. Delivery promises and handover

**Evidence chain:**
1. 96,211 delivered
2. 96,203 with a delivery date
3. 96,202 with a carrier date
4. 8,581 handed over after the limit

**Headline:** median 10 days actual vs a 24-day promise; late 21.10% after a late handover vs 5.39%.

### F3. Reviews and review timing

**Evidence chain:**
1. 99,092 in window
2. 98,330 with a review
3. 95,560 delivered with a date
4. 6,378 late
5. 4,749 reviewed before delivery

**Headline:** low share 8.98% -> 79.27% across delay buckets; 74.46% of late orders were reviewed before arrival.

### F4. Seller concentration

**Evidence chain:**
1. 3,095 sellers
2. 2,945 with a delivered sale
3. 614 on the scorecard
4. 62 with the most late handovers

**Headline:** the top 1% (30 sellers) earn 25.93% of revenue; 62 sellers hold 55.42% of scorecard late handovers.

### F5. Volume growth and freight

**Evidence chain:**
1. 96,211 delivered
2. 74,781 in the Jan-Aug comparison months
3. 52,783 in Jan-Aug 2018

**Headline:** revenue +141.13%, orders +139.94%, average order value +0.49%; freight is 16.63% of item value, 53.41% for the cheapest quarter.

### R1. Send the review request after delivery confirmation

- **Evidence:** 74.46% of late orders were reviewed before arrival (75.22% low, against 25.11% when reviewed after). Late orders produce 27.68% of all low reviews.
- **Test:**
  - *Unit:* order, randomised by order id.
  - *Control:* current timing.
  - *Primary metric:* low-review share, read separately for late and on-time orders.
  - *Guardrails:* review response rate, and days from delivery to review.
  - *Duration:* 4 weeks of orders, analysed once they are delivered.
- **Why that metric:** it is the outcome the change targets. The response-rate guardrail catches the obvious failure, which is fewer people reviewing at all.
- **Effort:** low; it is a trigger change.

### R2. Seller handover SLA, starting with the 62 sellers

- **Evidence:** late 21.10% after a late handover vs 5.39%. The 62 sellers hold 55.42% of scorecard late handovers on 31.93% of orders. The top handover quartile delivers late 9.43% of the time vs 4.90% for the bottom.
- **Test:**
  - *Unit:* seller.
  - *Control:* a random half of the 62 sellers.
  - *Primary metric:* late-handover rate.
  - *Guardrails:* seller order volume, the share of sellers still active, and low-review share.
  - *Duration:* 8 weeks.
- **Why that metric:** handover is under the seller's control, so it is the most direct metric. Late delivery is downstream and noisier because of carriers.
- **Risk:** low power with 62 sellers, and the penalty may push sellers to leave.
- **Effort:** medium.

### R3. Free-freight win-back for lapsed high-value one-time customers

- **Evidence:** 22,369 customers brought 39.77% of revenue at 234.37 BRL each, and last ordered 220 to 602 days before the window end. Only 2.15% of customers return on a later day, and freight is 16.63% of item value.
- **Test:**
  - *Unit:* customer.
  - *Control:* a random holdout with no voucher.
  - *Primary metric:* share placing a delivered order within 90 days.
  - *Guardrails:* net revenue per targeted customer after the freight subsidy, and voucher cost.
  - *Duration:* 12 weeks.
- **Why that metric:** it measures the behaviour we want, and the net-revenue guardrail stops "success" that loses money.
- **Risk:** subsidising orders that would have happened anyway, which is exactly why the holdout is needed.
- **Effort:** medium.

### Impact vs effort

- **R1:** low effort, and it affects the quality signal sellers and buyers see. It is the first thing to try.
- **R2:** medium effort, and it targets the operational root of lateness.
- **R3:** medium effort and costs money per order, with a large but uncertain revenue upside.

---

## 8. SQL concepts explained simply

### CTEs (WITH ... AS)

- **What:** named steps inside one query, read top to bottom.
- **Example:** v_order_payments_agg builds totals (sums per order), then ranked (ROW_NUMBER per payment), then joins them.
- **Why:** readability. Each step can be explained on its own.

### Joins and fan-out

- **INNER JOIN** keeps matches only. **LEFT JOIN** keeps every left row and fills NULLs.
- **Fan-out:** joining one-to-many multiplies rows, so sums double-count.
- **Example:** v_order_facts LEFT JOINs only views with one row per order_id. The fan-out check proves it.

### GROUP BY vs window functions

- **GROUP BY** collapses rows: one row per group.
- **A window function** (OVER) keeps every row and adds a value computed over related rows.
- **Example:** SUM(COUNT(*)) OVER () computes the share of the total next to each group's count.

### ROW_NUMBER vs RANK vs DENSE_RANK

- **ROW_NUMBER** gives 1, 2, 3, 4 with no ties. It needs a tie-breaker to be deterministic.
- **RANK** gives 1, 2, 2, 4: ties share a rank and leave a gap.
- **DENSE_RANK** gives 1, 2, 2, 3: ties share a rank with no gap.
- **Example:** latest review per order uses ROW_NUMBER, ordered by answer time DESC, then creation date DESC, then review_id, and keeps rn = 1. RANK could keep two rows when timestamps tie.

### LAG / LEAD

- **LAG(x)** reads the previous row's x in the window order; **LEAD(x)** reads the next.
- **Examples:** time to second order (file 10 Q2); month-over-month revenue (file 14 Q1).

### NTILE

- **What:** splits ordered rows into N equal-sized buckets.
- **Examples:** RFM scores and value quartiles.
- **Gotcha:** ties can be split across buckets (45.90 appears in two quartiles).

### PERCENTILE_CONT

- **What:** exact percentile, interpolated: percentile_cont(0.5) WITHIN GROUP (ORDER BY x) is the median.
- **Gotchas:** it returns double precision, so cast to numeric before ROUND. It ignores NULLs.
- **Example:** median delivery 10.21 days.

### Running totals

- **What:** SUM(x) OVER (ORDER BY rank ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW).
- **Example:** seller concentration, the cumulative revenue share by rank.
- **Why ROWS:** the default RANGE frame groups tied values together.

### FILTER vs CASE

- **FILTER:** COUNT(*) FILTER (WHERE is_late) counts only matching rows. It is clean and lets one pass compute many counts.
- **CASE equivalent:** SUM(CASE WHEN is_late THEN 1 ELSE 0 END).
- **CASE is still needed** for labels and buckets, where FILTER can't help.

### Cohort analysis

- **Steps:** cohort = first month; months_since = (year x 12 + month) difference.
- **Grid:** cohorts x 0..12 with generate_series, LEFT JOINed to activity, so empty cells exist.
- **NULL rule:** cells that can't be observed yet are NULL, not 0.

### NULL handling

- **Comparisons:** NULL compared with anything is NULL, not false. So x < 0 on a NULL stage is NULL.
- **IS TRUE / IS NOT TRUE** turn NULL into a definite answer (file 11 Q5).
- **COALESCE(a, b)** returns the first non-NULL value (category fallback; returned_90 defaulting to false).
- **NULLIF(x, 0)** avoids division by zero.
- **COUNT(col)** counts non-NULLs, which gives eligible denominators in the seller scorecard.

### Date maths

- **date - date** = integer days (delay_days).
- **timestamp - timestamp** = interval. EXTRACT(EPOCH FROM interval) / 86400 = fractional days (delivery_days).
- **date_trunc('month', ts)** = first day of the month.
- **ts + INTERVAL '180 days'** shifts a date.
- **Half-open window:** >= '2017-01-01' AND < '2018-09-01'. It includes every time on 31 August, which BETWEEN would cut off at midnight.

### Indexes and EXPLAIN

- **No indexes beyond primary keys:** the analysis is full-table aggregation, where sequential scans and hash joins are right.
- **EXPLAIN shows the plan.** Two real problems came up:
  1. An EXISTS over stacked views ran for minutes. I rewrote it as COUNT(*), and it took seconds.
  2. Temp tables had no statistics, so the planner picked nested loops. ANALYZE fixed the plan to hash joins, and the query took milliseconds.
- **Lesson:** temp tables aren't analysed automatically.

### Views

- **What:** a saved query that runs each time it is used. Good for one source of truth.
- **Cost:** stacked views can be slow. Files 13-14 copy building blocks into temp tables once per session.

### DO-block checks

- **What:** PL/pgSQL inside DO $$ ... $$. IF something is wrong THEN RAISE EXCEPTION. With ON_ERROR_STOP the script exits with an error.
- **Examples:** fan-out checks; the repeat rate must match the baseline; seller revenue must add back to the total; sizing groups must add up.

---

## 9. PM concepts used

- **Metrics tree.**
  - *What:* break a goal metric into factors you can act on.
  - *Here:* revenue = customers x orders per customer x average order value (93,104 x 1.0334 x 137.00).
  - *Use:* find which factor moved or can move.
- **Cohort retention.**
  - *What:* group users by start month and track what share return each later month.
  - *Why:* it separates growth in new users from loyalty.
- **Repeat rate.**
  - *What:* the share of customers with a second purchase.
  - *Here:* the definition matters: 3.00% for any day vs 2.15% for a later day. Always state the definition.
- **RFM.**
  - *What:* recency, frequency and monetary value. Segments for targeting.
  - *Here:* frequency is nearly always 1, so repeat status replaced the frequency score.
- **Concentration (80/20).**
  - *What:* how much of the outcome comes from the top share of units.
  - *Here:* sellers are concentrated (top 20% = 82.20% of revenue); customers less so (top 20% = 56.62%).
- **Correlation vs causation.**
  - *What:* two things moving together doesn't prove one causes the other.
  - *Here:* late handover goes with late delivery, but busy sellers in far-away states could drive both. Only a randomised test shows cause.
- **A/B test design.**
  - *What:* unit of randomisation, control, primary metric, guardrails, duration, and the risk of contamination.
  - *Units:* order-level (R1), seller-level (R2), customer-level (R3).
- **Guardrail metrics.**
  - *What:* metrics that must not get worse while the primary metric improves.
  - *Examples:* response rate for R1, seller volume for R2, net revenue for R3.
- **Impact vs effort.**
  - *What:* rank ideas by expected value against cost.
  - *Here:* R1 first (low effort, direct evidence), then R2, then R3.

---

## 10. Likely interview questions with model answers

### SQL

1. **Walk me through the cohort matrix query.**
   - *Answer:*
     1. I take one row per customer with their cohort, the month of their first delivered order.
     2. For activity, I list each distinct (customer, month with a delivered order) and compute months_since as (year x 12 + month) of the order minus the same for the cohort.
     3. I build a grid of every cohort x months 0-12 with generate_series, so empty cells still exist, and LEFT JOIN activity to it.
     4. I count active customers per cell and divide by cohort size.
     5. If the cell's calendar month is after 2018-08, I return NULL instead of 0, because it can't be observed yet.
     6. A second query pivots it wide with MAX(...) FILTER (WHERE months_since = k).
2. **Walk me through the LAG query.**
   - *Answer:*
     1. In delivered_orders, LAG(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id) puts the previous order's timestamp on each row.
     2. On the row where delivered_seq = 2, that previous value is the first order.
     3. Subtracting the dates gives days to second order.
     4. Then percentile_cont gives median 29 and p90 245, and a CASE puts each gap in a bucket.
     5. order_id in the ORDER BY breaks ties when two orders share a timestamp.
3. **Walk me through the RFM query.**
   - *Answer:*
     1. One row per customer: recency = 2018-08-31 minus last purchase date, frequency = delivered orders, monetary = revenue.
     2. NTILE(4) over recency sorted descending gives 1 to the oldest buyers and 4 to the newest. NTILE(4) over monetary ascending gives 4 to the top spenders. customer_unique_id breaks ties.
     3. A CASE assigns the segment, checking repeat buyers first so each customer gets exactly one.
     4. A DO block confirms the segments cover all 93,104 customers and all revenue.
4. **Walk me through the concentration query.**
   - *Answer:*
     1. Revenue per seller, then ROW_NUMBER by revenue descending (seller_id as tie-breaker).
     2. A running SUM over that order with ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW, divided by the grand total SUM() OVER (), gives the cumulative share.
     3. A VALUES list of cut-offs (1, 5, 10, 20) joins to the seller at rank CEIL(sellers x p / 100). Its cumulative share is the answer: top 1% = 30 sellers = 25.93%.
5. **What is fan-out and how did you prevent it?**
   - *Answer:* Joining a one-to-many table repeats the parent rows, so sums double-count. I aggregate children to one row per order first, and a check proves every view has row count = distinct keys = expected count.
6. **Why ROW_NUMBER and not RANK for the latest review?**
   - *Answer:* I need exactly one row per order. RANK can return two rows on a tie. ROW_NUMBER with a full tie-breaker always returns one, and always the same one.
7. **What is the difference between WHERE and HAVING?**
   - *Answer:* WHERE filters rows before grouping; HAVING filters groups after aggregation. For example, HAVING COUNT(*) >= 500 keeps categories with 500+ customers.
8. **When does a window function run relative to WHERE?**
   - *Answer:* After WHERE and GROUP BY. That's why customer_order_seq in v_order_facts counts only in-window orders: the window filter runs first.
9. **Why use a half-open date range?**
   - *Answer:* `< '2018-09-01'` includes every time on 31 August. `BETWEEN ... '2018-08-31'` stops at midnight, because '2018-08-31' means 00:00:00.
10. **How do you count conditionally?**
    - *Answer:* COUNT(*) FILTER (WHERE condition), or SUM(CASE WHEN ... THEN 1 ELSE 0 END). AVG of a 1/0 flag gives a rate directly.
11. **What does NULL do in comparisons and aggregates?**
    - *Answer:* Comparisons with NULL return NULL. Aggregates skip NULLs, except COUNT(*). I used IS TRUE, COALESCE and NULLIF to make that explicit.
12. **How did you get the median?**
    - *Answer:* percentile_cont(0.5) WITHIN GROUP (ORDER BY x). It interpolates, returns double precision, and I cast it to numeric to round.
13. **Why numeric and not float for money?**
    - *Answer:* numeric is exact decimal arithmetic. Floats are binary approximations, and sums can drift by fractions of a cent.
14. **Why are some foreign keys missing?**
    - *Answer:* Foreign keys must reference unique columns and every child must have a parent. The zip prefix isn't unique in geolocation and 157 customer prefixes are missing; 2 categories have no translation.
15. **COPY vs \copy?**
    - *Answer:* COPY runs on the server and reads server files. \copy runs in psql and streams a local file. I used \copy so no server file access was needed.
16. **How is the load re-runnable and safe?**
    - *Answer:* It runs in one transaction: TRUNCATE all tables, load parents before children, COMMIT. With ON_ERROR_STOP, a failure rolls back and nothing is half-loaded.
17. **How do you pick one value per group without a subquery?**
    - *Answer:* MAX(x) FILTER (WHERE delivered_seq = 1) inside a GROUP BY. Only one row matches, so MAX returns it. I used this for first-order state, category and payment type.
18. **A query ran for 10 minutes. What did you do?**
    - *Answer:* I checked pg_stat_activity and EXPLAIN. Once the cause was EXISTS over stacked views, and I rewrote it as COUNT(*). Once it was temp tables without statistics, and I added ANALYZE, which switched to hash joins.
19. **Views or tables?**
    - *Answer:* Views keep one definition of every rule. For heavy reuse within one script I copy them into temp tables once per session, which is faster and still has no duplicated logic.
20. **How would you write the on-time rate from raw tables?**
    - *Answer:* Filter to delivered orders with a delivery date in the window. Then ROUND(100.0 * COUNT(*) FILTER (WHERE delivered::date <= estimated::date) / COUNT(*), 2), which gives 93.21.
21. **Why 100.0 and not 100?**
    - *Answer:* Integer division truncates. 100.0 forces numeric division.
22. **How did you make sure a multi-seller order's revenue isn't double-counted?**
    - *Answer:* v_seller_orders has one row per (order, seller) with that seller's own items. A DO block asserts the seller totals add back to exactly 13,181,027.13.
23. **What does SUM(COUNT(*)) OVER () do?**
    - *Answer:* The inner COUNT(*) is the group count. The window SUM adds those counts across all groups. Dividing gives each group's share in one query.

### Analysis and statistics

1. **Why median rather than mean for delivery days?**
   - *Answer:* Delivery times are skewed: the p95 (29.22 days) is far above the median (10.21), so the mean would be pulled up by a few very slow orders.
2. **Is the late-handover effect causal?**
   - *Answer:* No. It is an association: late 21.10% vs 5.39%. Confounders such as seller location, product size and season could drive both. That's why R2 is a randomised test.
3. **Why fixed-window repeat rates as well as all-time?**
   - *Answer:* All-time favours early cohorts, which had more time to return. A 90- or 180-day window gives everyone the same time, and I only include customers whose full window is observed.
4. **Why are some cohort cells NULL?**
   - *Answer:* Those months are after the data ends. 0 would claim nobody returned; NULL says "not observed yet".
5. **How confident are you in the first-order return differences?**
   - *Answer:* Not very. The gaps are about half a point and rest on 103 returners after a late first order. I didn't run significance tests, so I describe them and don't claim them.
6. **What is survivorship or censoring in your data?**
   - *Answer:* Recent orders that weren't yet delivered have no timing, so recent months under-represent slow deliveries (2018-08: 161 of 6,512 orders untimed).
7. **Why pooled rates rather than averages of seller rates?**
   - *Answer:* Pooled rates weight by orders, so a seller with 30 orders doesn't count as much as one with 3,000. An average of rates answers a different question: the typical seller.
8. **What is Simpson's paradox, and could it apply here?**
   - *Answer:* It is when a trend in groups reverses when they are combined. For example, SP sellers have the highest late-delivery rate overall, but that could reflect where their customers are. I'd check within customer state before concluding anything.
9. **How did you handle outliers?**
   - *Answer:* I mostly used medians and percentiles. Coordinates outside a Brazil bounding box were excluded (8 orders) because they are data errors, not real extremes.
10. **What would a significance test look like for R1?**
    - *Answer:* A two-proportion test on the low-review share, treatment vs control. Before starting, I'd fix the sample size from the minimum detectable effect I care about and from the baseline rate.
11. **Why exclude negative stage durations only from stage stats?**
    - *Answer:* The stage timestamps are clearly wrong, but the order and its delivery are real, so removing them everywhere would bias delivery and revenue metrics.
12. **What is the risk of NTILE-based segments?**
    - *Answer:* Segment sizes are fixed by construction (about 25% each), and ties can be split across buckets. Only the revenue shares and averages are findings.

### Product and PM

1. **What would you do next?**
   - *Answer:* Run R1 first, because it is cheap and has direct evidence. Then analyse review text for the 53.29% of low reviews on normal orders. Then size R3 with a proper power calculation.
2. **How would you measure success of R1?**
   - *Answer:* Primary metric: low-review share, split by late and on-time orders. Guardrails: response rate and days to review. Success means lower low-review share with no drop in response rate.
3. **How would you measure success of R2?**
   - *Answer:* Late-handover rate falls for treated sellers vs control, without falling order volume or more sellers going inactive. Late delivery is the secondary metric.
4. **How would you measure success of R3?**
   - *Answer:* A higher share of targeted customers order within 90 days than the holdout, with positive net revenue after the freight subsidy.
5. **Which metric would you put on a dashboard for the CEO?**
   - *Answer:* Revenue with its three factors (customers, orders per customer, average order value), plus on-time rate and low-review share as quality guardrails.
6. **Why did revenue grow?**
   - *Answer:* Volume. Orders rose 139.94% Jan-Aug year on year while average order value moved 0.49%.
7. **Is low retention a problem?**
   - *Answer:* Probably, but it's partly the category mix: many purchases (furniture, appliances) are infrequent. I'd compare repeat rates with category purchase cycles before setting a target.
8. **Which recommendation would you drop if you could only do two?**
   - *Answer:* R3. It costs money per order and its evidence is indirect, while R1 and R2 target observed problems.
9. **Who are the stakeholders for R2?**
   - *Answer:* Seller operations, the marketplace ranking team, and sellers themselves. Seller churn is the main risk, so seller success should co-own it.
10. **How would you prioritise the problem sellers?**
    - *Answer:* By the volume of harm, not just the rate. The 62 sellers with the most late handovers cover 55.42% of them, so starting there gives the most effect per seller contacted.
11. **What surprised you?**
    - *Answer:* Three things:
      - Reviews for late orders mostly come before delivery.
      - Almost a third of "second orders" are seconds apart.
      - SP sellers have the highest late-delivery rate even though SP customers get the fastest deliveries.
12. **What would you need to know that the data doesn't say?**
    - *Answer:* Margins and fees, marketing spend, support contacts, and how review requests are triggered.
13. **How would you set the shipping-limit SLA?**
    - *Answer:* Start from the current limit, and alert at, say, 24 hours before it. Then look at the distribution of handover delays in the test to tune the penalty threshold.
14. **What is a North Star metric for Olist?**
    - *Answer:* Delivered orders that get a 4-5 star review. It combines volume, fulfilment and satisfaction.
15. **How do freight costs affect the business?**
    - *Answer:* Freight is 16.63% of item value overall but 53.41% for the cheapest quarter of orders. Small baskets are expensive to ship, which suggests minimum-basket or bundling ideas, to be tested.
16. **How would you validate that same-day orders are split checkouts?**
    - *Answer:* Check whether they share a payment or session, or have different sellers. Ask the data owner how carts with several sellers are stored.

### Behavioural and honesty

1. **Did you use AI tools?**
   - *Answer:* Yes. I used AI tools to move faster: drafting SQL, documentation and checks. I set the questions and made the analysis decisions myself. That includes the window, the customer and repeat-customer definitions, the review rule, the revenue definition and the seller attribution rule; each is recorded as a confirmed decision. I reviewed the outputs and can explain every query in this project line by line.
2. **What was the hardest part?**
   - *Answer:* Definitions. "Repeat customer" changed the headline from 3.00% to 2.15% once same-day orders were understood. Getting that right mattered more than any query.
3. **What would you do differently?**
   - *Answer:* Decide the repeat definition and the attribution rule before building views, and save every one-off check's output to results/ from the start.
4. **Tell me about a mistake you caught.**
   - *Answer:* A schema comment claimed review creation dates were always midnight; profiling showed some aren't, so I corrected it. A first export of the data model also listed a wrong source for one view; the parser was fixed and re-checked.
5. **How do you make sure your numbers are right?**
   - *Answer:* Assertions in SQL (fan-out checks, totals adding back, rates matching the baseline). Every website number is traced to a CSV cell by a script that fails on any mismatch, and I tested that it really fails.
6. **How do you communicate uncertainty?**
   - *Answer:* Each finding has a "what this doesn't show" line, and the limitations list counts what was excluded and why.

---

## 11. Live SQL practice (raw tables)

Solutions are in prep/practice_solutions.sql. Each expected answer matches a number in results/.

### E1 (easy). Count orders by status, largest first.

- *Expected:* delivered 96,478 first (results/02_data_quality_output.txt).
- *Solution:*

```sql
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;
```

### E2 (easy). How many people (customer_unique_id) have more than one customer_id?

- *Expected:* 2,997.
- *Solution:*

```sql
SELECT COUNT(*)
FROM (SELECT customer_unique_id
      FROM customers
      GROUP BY customer_unique_id
      HAVING COUNT(*) > 1) t;
```

### E3 (easy). Delivered revenue (item price) for purchases from 2017-01-01 to 2018-08-31.

- *Expected:* 13,181,027.13 (baseline.csv).
- *Solution:*

```sql
SELECT SUM(oi.price)
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= DATE '2017-01-01'
  AND o.order_purchase_timestamp <  DATE '2018-09-01';
```

### E4 (easy-medium). Orders per month in the window, all statuses.

- *Expected:* 2017-11 has 7,544 (baseline.csv).
- *Solution:*

```sql
SELECT date_trunc('month', order_purchase_timestamp)::date AS month, COUNT(*)
FROM orders
WHERE order_purchase_timestamp >= DATE '2017-01-01'
  AND order_purchase_timestamp <  DATE '2018-09-01'
GROUP BY 1
ORDER BY 1;
```

### E5 (medium). Top 5 categories by delivered revenue, using the English name, else Portuguese, else 'unknown'.

- *Expected:* health_beauty 1,229,557.50 first (14_top_categories.csv).
- *Solution:*

```sql
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
```

### E6 (medium). On-time rate: delivered in the window, with a delivery date; on time = delivered date <= estimated date (calendar days).

- *Expected:* 93.21.
- *Solution:*

```sql
SELECT ROUND(100.0 * COUNT(*) FILTER (
         WHERE order_delivered_customer_date::date <= order_estimated_delivery_date::date)
       / COUNT(*), 2)
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp >= DATE '2017-01-01'
  AND order_purchase_timestamp <  DATE '2018-09-01';
```

### E7 (medium). Average review score in the window, keeping only the latest review per order.

- *Expected:* 4.09.
- *Solution:*

```sql
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
```

### E8 (medium-hard). Median days between a customer's first and second delivered order in the window, using LAG.

- *Expected:* 29 (10_time_to_second_order_percentiles.csv).
- *Solution:*

```sql
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
```

### E9 (hard). Share of delivered revenue from the top 1% of sellers.

- *Expected:* 30 sellers, 25.93 (13_concentration.csv).
- *Solution:*

```sql
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
```

### E10 (hard). Of customers whose first delivered order in the window was in January 2017, what share had a delivered order in February 2017?

- *Expected:* cohort 718, 2 active, 0.28 (10_cohort_matrix_pct.csv, 2017-01 row, m1).
- *Solution:*

```sql
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
```

Practice tips:
- Say the grain out loud before every join.
- Write the half-open date filter from memory.
- Check your answer against the expected number.

---

## 12. Numbers cheat sheet

### Data and scope

- **Raw tables:** orders 99,441; customers 99,441; items 112,650; payments 103,886; reviews 99,224; products 32,951; sellers 3,095; categories 71; geolocation 1,000,163.
- **Window:** 2017-01-01 to 2018-08-31. 99,092 orders in window, 349 outside.
- **Delivered:** 96,211. Customers 93,104. Active sellers 2,945.

### Money

- **Revenue:** 13,181,027.13 BRL. Freight 2,192,092.88. Average order value 137.00. Orders per customer 1.0334.
- **Jan-Aug 2018 vs 2017:** revenue +141.13%, orders +139.94%, average order value +0.49%.
- **Concentration:** top 15 categories 76.33%. Top 20% of sellers 82.20%; top 1% of sellers 25.93%. Top 20% of customers 56.62%.

### Retention

- **Repeat:** later-day 2.15% (2,005); any-day 3.00% (2,789). Same-day second orders 29.65%.
- **Timing and windows:** median days to second order 29. Within 180 days, later-day 1.97%.
- **Revenue from second and later orders:** 2.89%.

### Delivery

- **On time:** 93.21%. Median delivery 10.21 days; p95 29.22.
- **Promise vs actual:** promise 24 days vs actual 10. 78.88% arrive 7+ days early.
- **Handover:** 8.92% handed over after the limit. Late 21.10% after a late handover vs 5.39%.
- **States:** worst MA 17.53%; best PR 4.06%.

### Reviews

- **Overall:** average 4.09; low (1-2 stars) 14.63% (14,382 reviews).
- **By delay:** low share 8.98% (7+ days early) to 79.27% (8+ days late).
- **Timing:** 74.46% of late orders reviewed before delivery.
- **Low-review sources:** late 27.68%; undelivered 14.97%; everything else 53.29%.

### Sellers

- **Scorecard:** 614 sellers.
- **Problem sellers:** 31, holding 10.62% of low reviews on 4.36% of orders.
- **Late handovers:** 62 sellers = 55.42% of late handovers on 31.93% of orders.

### RFM

- **Lapsed high-value:** 22,369 customers, 39.77% of revenue, 234.37 BRL each.
- **Repeat buyers:** 2,005 customers, 4.13% of revenue, 271.47 BRL each.

### Freight

- **Overall:** 16.63% of item value.
- **Cheapest quarter of orders:** 53.41%. Orders with freight over 50% of item value: 15.84%.

### Data quality

- **Reviews:** 547 orders with multiple reviews; 789 repeated review_ids.
- **Payments:** 294 mismatches.
- **Stages:** 1,344 negative stage durations.
- **Status contradictions:** 8 delivered without a date; 6 canceled with a date.
- **Missing children:** 775 orders without items.
- **Geolocation:** 261,831 duplicate rows.

---

## 13. Limitations and what I'd do next

### Limitations

- **Window.** 349 orders outside the window are excluded, and "first order" means first inside the window.
- **Same-day orders.** 827 same-day second orders are not counted as returns, which is a definition choice.
- **Payments.** 294 payment mismatches are unexplained.
- **Stages.** Stage stats exclude 1,344 negative and 15 missing-stage orders.
- **Recent months.** They lack their slowest deliveries (2018-08: 161 of 6,512 untimed).
- **Distances.** They are between zip-prefix centres; 94,453 of 94,931 single-seller orders were usable.
- **Seller attribution.** Seller quality uses single-seller orders only; 1,272 multi-seller timed orders aren't attributed.
- **Small counts.** Some comparisons are small (103 returners after a late first order), and there are no significance tests.
- **RFM.** Segment sizes are set by NTILE.
- **Review dates.** They are day-level only.
- **Seller activity.** The exact-month rule makes it a lower bound.
- **Observational data.** All results are associations, not causes.

### What I'd do next with more data or time

- **Run R1 as an A/B test,** with a power calculation from the current low-review share.
- **Analyse Portuguese review text** for the 53.29% of low reviews on ordinary orders (topic modelling or keyword counts).
- **Confirm the split-checkout hypothesis** with the data owner, or check shared payments or sessions.
- **Check SP sellers within customer state** to rule out a Simpson's-paradox effect on seller lateness.
- **Add margin data** to turn revenue findings into profit and to price the free-freight voucher.
- **Join carrier data** if available, to separate carrier performance from seller handover.
- **Add significance tests and confidence intervals** to segment comparisons, using bootstrap for medians.
- **Build a monitoring dashboard** for on-time rate, late-handover rate and low-review share by week, with alerts.
