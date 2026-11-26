# Data quality notes: Olist

Every number in sections 1-8 comes from `sql/02_data_quality.sql`, run against the
`olist` database on 2026-11-13. The full output is in `results/02_data_quality_output.txt`.
The decisions below are implemented in `sql/03_clean_views.sql` and the analysis files;
the site's data-quality cards (`results/15_quality_issues.csv`) refer to them by ID.

---

## Decisions

| # | Decision | Reason | Where it is applied |
|---|---|---|---|
| C1 | **Analysis window:** orders purchased 2017-01-01 to 2018-08-31 (inclusive), implemented as `>= '2017-01-01' AND < '2018-09-01'`. | Both ends of the data are very thin (section 6). | `v_orders.in_window`; `v_order_facts` keeps only in-window orders |
| C2 | **Customer = `customer_unique_id`.** | `customer_id` is created per order, so it never repeats (section 7). | `v_orders`, `v_order_facts` (sequence number and first order date) |
| C3 | **Reviews:** keep the latest review per order (latest `review_answer_timestamp`, then `review_creation_date`, then `review_id` as tie-breaker). Never join on `review_id` alone. | 547 orders have more than one review and 789 review_ids repeat (section 3); joining raw reviews would count orders twice. | `v_order_review` |
| C4 | **Revenue** = `SUM(order_items.price)` on delivered orders. Freight is reported separately. Payments are a cross-check only. | Item prices are complete for every order with items; payments have unexplained gaps (C11). | `v_order_items_agg`, `04_baseline.sql` |
| C5 | **Delivery timing** uses only delivered orders that have a customer delivery date. | 8 delivered orders have no delivery date and 6 canceled orders have one (section 2). | `v_orders.has_delivery_timing`; timing columns are NULL otherwise |
| C6 | **Category:** English name, else Portuguese name, else `'unknown'`. | 610 products have no category and 2 categories have no translation (sections 2 and 8). | `v_products.category` |
| C7 | **Raw tables are unchanged.** Views expose corrected names (`product_name_length`, `product_description_length`). | Two source columns are misspelled (`lenght`); the raw load stays a faithful copy of the CSVs. | `v_products` |
| C8 | **On-time uses the calendar-day definition:** delivered date ≤ estimated date, compared as dates (93.21% on-time). | The estimated date always has time 00:00:00, so a timestamp comparison counts any delivery *on* the promised day as late (91.87% on-time). | `v_orders.is_late` |
| C9 | **Negative stage durations** (1,325 approval→carrier, 19 carrier→customer) are excluded from stage statistics only and reported as a limitation. Those orders stay in every other metric. | The timestamps are inconsistent, but the orders themselves are valid. | `sql/11_delivery_performance.sql` (stage medians) |
| C10 | **Retention uses delivered orders only.** The customer order sequence is recomputed over delivered orders inside the retention analysis. `v_order_facts.customer_order_seq` (all statuses) is not used for retention. | A customer's first in-window order may be canceled; retention should count orders that reached the customer. | `sql/10_retention_cohorts.sql` (`delivered_orders.delivered_seq`) |
| C11 | **The 294 payment mismatches** stay unexplained and are listed as a limitation. | Revenue does not use payments (C4), so the gap does not affect any result. | Limitations |
| C12 | **"Repeat customer" = a customer who returned on a later calendar day** than their first delivered order. The any-day figure is shown alongside only where it helps. Headline repeat rate: **2.15%** later-day (any-day: 3.00%). | 827 of 2,789 second orders fall on the same day as the first, most within minutes: consistent with one checkout split into several orders. | All analysis files; `10_retention_cohorts.sql` reports both (`*_later_day_*` columns) |

## Implementation notes

Choices made while building the views, each with its reason.

- **On-time = delivered on or before the estimated *calendar day*** (C8).
  Decision: compare dates, not timestamps. Reason: on-time rate is **93.21%**
  comparing dates vs **91.87%** comparing timestamps, and the difference is
  entirely deliveries on the promised day.
- **Customer order sequence counts in-window orders of any status.** The window
  functions run after the window filter, so a customer's first order is their
  first order *in the window*, which may be canceled.
  Decision: keep it in `v_order_facts` for baselines; retention uses a
  delivered-only sequence (C10).
- **Stage times can be negative.** Among delivered orders with a delivery date,
  **1,325** reached the carrier before approval (negative `days_approval_to_carrier`)
  and **19** reached the customer before the carrier date. Purchase-to-approval is
  never negative. Stage times are NULL in 14 (approval) and 15 (carrier) of these orders.
  Decision: leave the values as they are, report stage medians (not means) and the
  excluded count (C9).
- **`v_geo` averages distinct points.** Exact duplicate rows are removed first, so a
  copied point doesn't pull the average towards itself.
- **Payment mismatches** (C11). 294 of 96,211 delivered in-window orders differ
  from items + freight by more than 0.01 (257 paid more, 37 paid less).
  The total absolute gap is 3,023.49 BRL, the median gap 5.66, the largest 182.81.
  The cause hasn't been investigated. Decision: accept, since revenue doesn't use payments (C4).
- **Clean views added for later analyses.** All fan-out checks pass (11 views).
  - `v_order_main_category`: one row per order, the category with the highest item
    value (ties go to the alphabetically first). Exposed as `v_order_facts.main_category`;
    98,666 rows = 98,666 distinct orders.
  - `v_sellers`: one row per seller_id, with seller zip, city and state.
  - `v_order_items_agg`: + `latest_shipping_limit` (MAX of the items' shipping_limit_date),
    + `single_seller_id` (set only when the order has exactly one seller).
  - `v_orders` / `v_order_facts`: + `customer_zip_code_prefix`, the raw milestone
    timestamps, and `promised_days` (estimated date − purchase date, in calendar days,
    timed orders only).
  - `v_seller_orders`: one row per (order_id, seller_id): the seller's items, revenue
    and latest shipping limit (100,010 pairs).
  - `v_order_lines`: one row per (order_id, order_item_id) with the item's cleaned
    category, so category revenue is item-level and multi-category orders split their revenue.

## Notes and limitations by analysis

### Retention

- **"First order" means first delivered order inside the window.** Orders before
  2017-01-01 aren't visible, so a 2016 buyer's first in-window order counts as their first.
- **Same-day second orders.** 827 of 2,789 second orders (29.65%) fall on the
  same calendar day as the first. 735 of those come within 10 minutes and 253
  have an identical timestamp. This is consistent with one checkout split into
  several orders. The repeat rate is 3.00% counting any day and 2.15% counting
  later days only. Both are reported (C12).
- **Payment mismatches (C11):** 294 delivered orders, unexplained.
- **Negative stage durations (C9):** 1,325 + 19 orders, excluded from stage statistics.

### Delivery notes

- **Recent months may be missing their slowest deliveries.** The last recorded delivery is
  2018-10-17. Orders not yet delivered have no timing, and late months still
  have some (2018-08: 161 of 6,512 in-window orders untimed).
- **Stage statistics** exclude 1,344 orders with a negative stage (C9) and 15 with
  a missing stage, which leaves 94,844 of 96,203.
- **Distances** are between zip-prefix centres (averaged v_geo points), not
  addresses. 478 single-seller orders are excluded for missing or out-of-Brazil
  coordinates; 94,453 are used.

### Reviews

- **Many reviews of late orders come before delivery.** 4,749 of 6,378 reviewed
  late orders (74.46%) have a review created before the delivery date. For late
  orders, the median review is created 2 days after the estimated date and 4 days
  before delivery. Their scores reflect waiting, not the received product. The data
  doesn't show how Olist triggers the review request.
- **First-order effects on return rest on small counts.** Only 103 customers
  whose first order was late came back (62 within 180 days). No significance
  test was run, so the gaps of about half a percentage point are described, not relied on.
- **`review_creation_date` is a date** (almost always 00:00:00), so review
  timing is compared on calendar days.

### Sellers

- **Attribution rule.** Decision: seller revenue comes from each seller's own items
  on all delivered orders, so multi-seller orders are split by item. Reviews, late
  delivery and late handover are attributed only on single-seller orders.
  Reason: a review or a late delivery on a multi-seller order can't be assigned to one seller.
- **The per-seller split adds back to the baseline revenue** of 13,181,027.13; this is
  checked inside `sql/13_seller_scorecard.sql`.
- **Scorecard threshold:** 30+ single-seller delivered orders. 614 of 2,945 sellers
  qualify; they hold 76.84% of revenue.
- **Seller activity uses an exact-month rule:** a seller who sells in month +2 and
  +4 but not +3 counts as inactive at +3, so the activity shares are a lower bound
  on "still selling". The 2017-01 cohort includes sellers who were already
  active in 2016.

### Revenue and RFM

- **RFM segment sizes are set by the method.** NTILE(4) puts about 25% of customers
  in each score, so the four one-time segments are each near 25% of customers.
  Revenue share and average revenue per segment are the meaningful outputs.
- **RFM recency is measured from 2018-08-31** (end of window). "One-time" includes
  customers whose 2+ orders all fell on one day (C12).
- **Payment type** is the order's main (highest-value) payment. 'not_defined' does
  not appear among delivered in-window orders.

---

## 1. Row counts

| Table | Rows |
|---|---:|
| customers | 99,441 |
| geolocation | 1,000,163 |
| order_items | 112,650 |
| order_payments | 103,886 |
| order_reviews | 99,224 |
| orders | 99,441 |
| product_category_name_translation | 71 |
| products | 32,951 |
| sellers | 3,095 |

Every count matches the CSV row count (header excluded). The reviews file has
104,720 physical lines but 99,224 records, because some comments contain line
breaks; the CSV loader handles these correctly.

`01_load.sql` was run twice and gave identical counts both times, so it is re-runnable.

## 2. NULLs in key and timestamp columns

Key columns have **no NULLs** in any table.

**orders** (99,441 rows)

| Column | NULLs |
|---|---:|
| order_purchase_timestamp | 0 |
| order_approved_at | 160 |
| order_delivered_carrier_date | 1,783 |
| order_delivered_customer_date | 2,965 |
| order_estimated_delivery_date | 0 |

**Other tables**
- order_items: 0 NULLs in shipping_limit_date, price and freight_value.
- order_payments: 0 NULLs in payment_type and payment_value.
- order_reviews: 0 NULLs in score and both timestamps. review_comment_title is NULL in 87,656 rows, review_comment_message in 58,247.
- products: product_category_name is NULL in 610 rows. product_weight_g is NULL in 2 rows.

**Status vs delivery date**

| order_status | no delivery date | has delivery date |
|---|---:|---:|
| delivered | 8 | 96,470 |
| canceled | 619 | 6 |
| shipped | 1,107 | 0 |
| unavailable | 609 | 0 |
| invoiced | 314 | 0 |
| processing | 301 | 0 |
| created | 5 | 0 |
| approved | 2 | 0 |

Most missing delivery dates are expected because those orders were never
delivered. Two groups contradict their status: **8 `delivered` orders with no
delivery date** and **6 `canceled` orders that have one**.

- **Decision (C5):** delivery-time analysis uses only
  `order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL`.
  The 8 + 6 inconsistent orders stay in the table and are listed as a limitation.
- **Decision (C6):** products with no category show as `'unknown'` in category
  analysis instead of being dropped.

## 3. Duplicate keys

| Key | Values appearing more than once |
|---|---:|
| customers.customer_id | 0 (PK) |
| orders.order_id | 0 (PK) |
| products.product_id | 0 (PK) |
| sellers.seller_id | 0 (PK) |
| order_items.(order_id, order_item_id) | 0 (PK) |
| order_payments.(order_id, payment_sequential) | 0 (PK) |
| order_reviews.(review_id, order_id) | 0 (PK) |
| **order_reviews.review_id** | **789** |
| **order_reviews.order_id** | **547** |
| customers.customer_unique_id | 2,997 (expected; see section 7) |
| geolocation.zip_code_prefix | 17,972 |

geolocation also has **261,831 rows that are exact copies** of another row.

- **Decision (C3): one review per order.** For the 547 orders with more than one
  review, keep the latest. Reason: joining orders to raw reviews would count
  those orders more than once.
- **Decision (C3): repeated review_ids.** Treat review_id as non-unique and never
  use it as a join key. Reason: the 789 repeated IDs look like one review attached
  to several orders, which the one-review-per-order rule already covers.
- **Decision: geolocation is never joined raw.** `v_geo` has one row per zip prefix
  (average lat/lng of distinct points, most common city/state).

## 4. Orders with no items, no payment, or no review

| Missing | Orders |
|---|---:|
| No items | 775 |
| No payment | 1 |
| No review | 768 |

**Status of the 775 orders with no items**

| Status | Orders |
|---|---:|
| unavailable | 603 |
| canceled | 164 |
| created | 5 |
| invoiced | 2 |
| shipped | 1 |

The order with no payment is `bfbd0f9bdef84302105ad712db648a6c`. Its status is
`delivered`, it was purchased 2016-09-15 and it has 3 items.

- **Decision:** item-level analysis (revenue, products, sellers) starts from
  `order_items`, so the 775 orders with no items drop out naturally. Order counts
  by status keep them.
- **Decision (C4):** revenue uses `order_items.price` (plus freight where relevant),
  not `order_payments`, so the single unpaid order doesn't affect revenue. Payment
  analysis leaves it out.
- **Decision:** review metrics are calculated only over orders that have a review;
  the 768 not reviewed are a coverage note.

## 5. order_status distribution

| Status | Orders | % |
|---|---:|---:|
| delivered | 96,478 | 97.02 |
| shipped | 1,107 | 1.11 |
| canceled | 625 | 0.63 |
| unavailable | 609 | 0.61 |
| invoiced | 314 | 0.32 |
| processing | 301 | 0.30 |
| created | 5 | 0.01 |
| approved | 2 | 0.00 |

- **Decision (C4, C5):** the "completed orders" metrics (revenue, AOV, delivery
  performance) use `delivered` orders only. The README states this definition.

## 6. Date range and orders per month

- First purchase: **2016-09-04 21:15:19**
- Last purchase: **2018-10-17 17:30:18**

| Month | Orders | | Month | Orders |
|---|---:|---|---|---:|
| 2016-09 | 4 | | 2017-10 | 4,631 |
| 2016-10 | 324 | | 2017-11 | 7,544 |
| 2016-11 | *(none)* | | 2017-12 | 5,673 |
| 2016-12 | 1 | | 2018-01 | 7,269 |
| 2017-01 | 800 | | 2018-02 | 6,728 |
| 2017-02 | 1,780 | | 2018-03 | 7,211 |
| 2017-03 | 2,682 | | 2018-04 | 6,939 |
| 2017-04 | 2,404 | | 2018-05 | 6,873 |
| 2017-05 | 3,700 | | 2018-06 | 6,167 |
| 2017-06 | 3,245 | | 2018-07 | 6,292 |
| 2017-07 | 4,026 | | 2018-08 | 6,512 |
| 2017-08 | 4,331 | | 2018-09 | 16 |
| 2017-09 | 4,285 | | 2018-10 | 4 |

The two ends are very thin. 2016-11 has no orders at all (the query returns
no row for it). After 2018-08 the counts drop to 16 and 4.

- **Decision (C1):** analysis covers **2017-01 to 2018-08** (20 full months).
  The 2016 and 2018-09/10 orders appear only in the raw counts above.

## 7. Customers with more than one order

| Counted by | Customers with 2+ orders |
|---|---:|
| customer_id | **0** |
| customer_unique_id | **2,997** |

**Orders per unique customer**

| Orders | Unique customers |
|---:|---:|
| 1 | 93,099 |
| 2 | 2,745 |
| 3 | 203 |
| 4 | 30 |
| 5 | 8 |
| 6 | 6 |
| 7 | 3 |
| 9 | 1 |
| 17 | 1 |

Counting by `customer_id` finds no repeat customers because Olist creates a new
customer_id for every order. Only `customer_unique_id` tracks a person across orders.

- **Decision (C2):** all retention, repeat-purchase and cohort analysis uses
  `customer_unique_id`. Repeat buyers are a small share (2,997 of 96,096 unique
  customers), which is a finding in its own right.

## 8. Relationships not enforced as foreign keys

| Gap | Count |
|---|---:|
| Customer zip prefixes not in geolocation | 157 prefixes (278 customers) |
| Seller zip prefixes not in geolocation | 7 |
| Product categories with no English translation | 2 (`portateis_cozinha_e_preparadores_de_alimentos`: 10 products, `pc_gamer`: 3) |

- **Decision (C6):** the translation table is joined with `LEFT JOIN`, so a missing
  translation falls back to the Portuguese name:
  `COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')`.
- **Decision:** orders whose zip prefix has no geolocation row are left out of
  distance analysis only (see "Delivery notes").
