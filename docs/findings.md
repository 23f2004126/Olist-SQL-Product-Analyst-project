# Olist marketplace: findings and recommendations

SQL product analysis of the Olist Brazilian e-commerce dataset (PostgreSQL).
Scope: orders purchased from 2017-01-01 to 2018-08-31, delivered orders unless
stated. A customer is a `customer_unique_id`. Revenue is the sum of item prices
on delivered orders; freight is reported separately. A repeat customer is one
who ordered again on a later calendar day. Every number below comes from query
output in `results/` and is checked by `scripts/export_site_data.py`.

All findings describe associations in observational data. None of them shows
cause and effect.

---

## Metrics tree

```
Revenue  13,181,027.13 BRL
  = Customers               93,104
  x Orders per customer     1.0334     (96,211 delivered orders)
  x Average order value     137.00 BRL
```

Factors are rounded, so their product is close to, not exactly, the revenue.
Source: `sql/15_site_support.sql` Q1 (`results/15_metrics_tree.csv`).

Orders per customer is barely above one, so revenue moves almost one-for-one
with the number of customers and the order value. F1 shows why the middle
factor is so low; F5 shows which factor drove growth.

---

## Findings

### F1. Retention

**Only 2.15% of customers came back on a later day, and 29.65% of second
orders were placed on the same day as the first.**

- 2,005 of 93,104 customers returned on a later day. Counting same-day orders
  as returns, the rate is 3.00%.
- The median time from first to second order is 29 days.
- Within 180 days of the first order (customers with the full 180 days
  observed), 1.97% returned on a later day.
- Second and later orders bring in 2.89% of revenue.

Source: `sql/10_retention_cohorts.sql`: Q1 (orders per customer), Q2 (time to
second order), Q3 (same-day check), Q5 (fixed window), Q7 (revenue).

*What this doesn't show:* why customers do not return, whether customers
bought before 2017, or whether same-day second orders are one checkout split
into several orders.

### F2. Delivery promises and handover

**Orders arrived a median 10 days after purchase against a 24-day promise, but
orders handed to the carrier after the seller's shipping limit were late
21.10% of the time, against 5.39%.**

- 93.21% of orders arrived on or before the estimated day, and 78.88% arrived
  7 or more days early.
- 8.92% of orders were handed to the carrier after the seller's shipping
  limit.
- Late orders spent a median 26.21 days between carrier and customer, against
  6.96 days for on-time orders.

Source: `sql/11_delivery_performance.sql`: Q1 (overall), Q3 (promise
accuracy), Q5 (stages), Q6 (seller handover).

*What this doesn't show:* that late handover causes late delivery, how
carriers perform, or the slowest deliveries of the last months (orders not
yet delivered when the data ends).

### F3. Reviews and review timing

**The share of 1-2 star reviews rises from 8.98% for orders arriving 7+ days
early to 79.27% for orders 8+ days late, and 74.46% of late orders were
reviewed before they arrived.**

- Overall, 14.63% of reviews are 1-2 stars.
- Among late orders, reviews written before delivery are 75.22% low, against
  25.11% for reviews written after delivery.
- For late orders, the median review is created 2 days after the estimated
  date.
- Late delivered orders produce 27.68% of all 1-2 star reviews. On-time
  single-seller orders, despite a low rate, produce 53.29%.

Source: `sql/12_review_drivers.sql`: Q2 (delay buckets), Q7 (sizing), Q8 and
Q8b (review timing).

*What this doesn't show:* what drives the low reviews on on-time
single-seller orders (review text was not analysed), or how Olist triggers the
review request.

### F4. Seller concentration

**The top 1% of sellers (30 sellers) earned 25.93% of revenue, and 62 sellers
account for 55.42% of scorecard late handovers.**

- The top 20% of sellers earned 82.20% of revenue.
- The 62 sellers with the most late handovers handle 31.93% of scorecard
  orders.
- 31 problem sellers (low-review share at least twice the benchmark) hold
  10.62% of scorecard low reviews but 4.36% of scorecard orders.
- Sellers in the top quartile for late-handover rate deliver late 9.43% of the
  time, against 4.90% in the bottom quartile.

Source: `sql/13_seller_scorecard.sql`: Q1 (concentration), Q4 (problem
sellers), Q5 (handover concentration), Q6 (handover quartiles).

*What this doesn't show:* why some sellers hand over late, quality on
multi-seller orders (not attributed to a seller), or what would happen if
sellers were penalised.

### F5. Volume growth and freight

**Jan-Aug 2018 revenue was 141.13% above Jan-Aug 2017, with orders up 139.94%
and average order value up 0.49%; freight adds 16.63% to item value, and
53.41% for the cheapest quarter of orders.**

- Revenue rose from 2,993,456.13 BRL (Jan-Aug 2017) to 7,218,125.12 BRL
  (Jan-Aug 2018).
- On 15.84% of orders, freight is more than 50% of item value.
- By state, freight ranges from 13.85% of item value (SP) to 26.22% (MA).

Source: `sql/14_revenue_rfm.sql`: Q1 (monthly trend and year-on-year), Q4
(freight).

*What this doesn't show:* whether freight cost holds back orders or repeat
purchases, or how much of the growth is seasonality, marketing or price
changes.

---

## Recommendations

Each recommendation is a hypothesis to test, not a proven effect. Durations
and test units are design choices, not results.

### R1. Send the review request after delivery confirmation

| | |
|---|---|
| **Change** | Trigger the review request when delivery is confirmed instead of on the current schedule. |
| **Evidence** | 74.46% of late orders were reviewed before they arrived; those reviews are 75.22% low against 25.11% after arrival. Late delivered orders produce 27.68% of all 1-2 star reviews (F3). |
| **Target metric** | Share of 1-2 star reviews on late orders. |
| **Expected direction** | Down. |
| **Test design** | *Unit:* order (randomised by order id). *Control:* current request timing. *Primary metric:* share of 1-2 star reviews, read separately for late and on-time orders. *Guardrail:* review response rate (share of delivered orders with a review) and days from delivery to review. *Duration:* 4 weeks of orders, analysed once those orders are delivered. |
| **Main risk** | Fewer reviews from customers whose delivery is never confirmed; complaints may move to other channels instead of disappearing. |
| **Effort** | Low. |

### R2. Seller handover SLA with alerts and a ranking penalty, starting with the 62 sellers with the most late handovers

| | |
|---|---|
| **Change** | Alert sellers before their shipping limit and lower the search ranking of sellers who repeatedly hand over late. Start with the 62 sellers with the most late handovers. |
| **Evidence** | Orders handed over after the limit were late 21.10% of the time against 5.39% (F2). The 62 sellers hold 55.42% of scorecard late handovers on 31.93% of scorecard orders. Sellers in the top late-handover quartile deliver late 9.43% of the time against 4.90% (F4). |
| **Target metric** | Late-handover rate (primary); late-delivery rate (secondary). |
| **Expected direction** | Down. |
| **Test design** | *Unit:* seller. *Control:* half of the 62 sellers, randomly chosen, keep the current rules. *Primary metric:* late-handover rate. *Guardrail:* seller order volume, share of sellers still active, and 1-2 star review share. *Duration:* 8 weeks. |
| **Main risk** | Penalties may push sellers off the platform or cut supply in some categories; with 62 sellers the test has limited statistical power. |
| **Effort** | Medium. |

### R3. Win back lapsed high-value one-time customers with a free-freight voucher

| | |
|---|---|
| **Change** | Offer a free-freight voucher to one-time customers with above-median spend whose last order was a long time ago. |
| **Evidence** | 22,369 lapsed high-value customers brought in 39.77% of revenue, 234.37 BRL each on average, and last ordered 220 to 602 days before the end of the window (`sql/14_revenue_rfm.sql` Q7). Only 2.15% of customers return on a later day (F1), and freight adds 16.63% to item value (F5). |
| **Target metric** | Share of targeted customers placing a delivered order within 90 days of the voucher. |
| **Expected direction** | Up. |
| **Test design** | *Unit:* customer in the lapsed high-value segment. *Control:* a random holdout group that receives no voucher. *Primary metric:* share placing a delivered order within 90 days. *Guardrail:* net revenue per targeted customer after the freight subsidy, and voucher cost. *Duration:* 12 weeks after the send. |
| **Main risk** | Paying for freight on orders that would have happened anyway; a low base rate means a large group is needed to detect a change. |
| **Effort** | Medium. |

---

## Limitations

Collected from `docs/data_quality_notes.md`.

1. **Window.** The analysis covers purchases from 2017-01-01 to 2018-08-31;
   349 orders outside that window are excluded. A customer's first order means
   their first delivered order inside the window.
2. **Same-day second orders.** 827 of 2,789 second orders were placed on the
   same calendar day as the first, 735 of them within 10 minutes. They are not
   counted as returns.
3. **Payments.** 294 delivered orders have payments that differ from items plus
   freight by more than 0.01 BRL. The gap is unexplained, and revenue uses item
   prices, not payments.
4. **Stage times** exclude 1,344 orders with a negative stage duration and 15
   with a missing stage.
5. **Recent months.** Orders not yet delivered when the data ends have no
   delivery timing (161 of 6,512 orders from August 2018), so the most recent
   months may be missing their slowest deliveries.
6. **Distances** are between zip-prefix centres, not addresses; 94,453 of
   94,931 single-seller orders had usable coordinates.
7. **Seller attribution.** Seller quality metrics (reviews, lateness, handover)
   use single-seller orders only; 1,272 multi-seller orders with delivery
   timing are not attributed to a seller.
8. **Small counts.** Only 103 customers whose first order was late came back.
   No significance tests were run, so differences are described, not tested.
9. **RFM segment sizes.** RFM scores are quartiles, so the four one-time
   segments are each about a quarter of customers by construction. Their
   revenue shares, not their sizes, are the result.
10. **Review dates** are recorded as dates, not times, so review timing is
    compared on calendar days.
11. **Seller activity** uses an exact-month rule, so the share of sellers still
    selling is a lower bound.
12. **Observational data.** All findings are associations in data from
    2016-2018; none shows cause and effect.
