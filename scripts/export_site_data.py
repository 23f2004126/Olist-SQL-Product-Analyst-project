#!/usr/bin/env python3
"""
export_site_data.py: build the website's JSON data from query output.

Reads ONLY:
  * results/*.csv              (output of sql/02-15)
  * sql/*.sql                  (query text, schema, techniques)
  * docs/findings.md           (for the number check at the end)
Writes site/data/*.json.

No number is typed by hand. Every number in findings.json and kpis.json
is a "sourced number": it carries the CSV file, the row filter and the
column it came from. verify() re-reads the CSVs and stops the script (exit
code 1) if any value differs, or if any number appears without a source.
Headlines are rendered from templates whose only digits are listed
literals (years, thresholds); everything else is a placeholder filled from
sourced numbers.

Run from the repo root, after the SQL files:
    python3 scripts/export_site_data.py

Standard library only (Python 3.9+).
"""

import csv
import json
import math
import re
import sys
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
SQL_DIR = ROOT / "sql"
OUT = ROOT / "site" / "data"
FINDINGS_MD = ROOT / "docs" / "findings.md"
SITE_COPY = ROOT / "docs" / "site_copy.json"

MAP_MAX_BYTES = 500 * 1024

# Digits allowed inside hand-written label / headline TEMPLATE text. Every
# other number must be a placeholder filled from a sourced value.
# These are years and fixed thresholds that define a metric, not results.
LABEL_LITERALS = {
    "1", "2", "3", "4", "5", "7", "8",      # "1-2 star", "7+ days early", "8+ days late", quartile labels
    "10", "20", "30", "50", "90", "180",    # 10 minutes / top 10%, top 20%, 30+ orders, >30% / >50% freight, 90/180-day windows
    "12",                                   # test duration in weeks (a design choice, not a result)
    "500",                                  # 500+ orders threshold
    "100",                                  # "in 100" unit chart, month 0 = 100% of a cohort
    "0", "6",                               # "month 0" of a cohort; "1-6 days early" bucket label
    "4.0",                                  # dataset licence version (CC BY-NC-SA 4.0)
    "2016", "2017", "2018",                 # data years
}


# -----------------------------------------------------------------------------
# CSV helpers
# -----------------------------------------------------------------------------
_csv_cache = {}


def read_csv(name):
    """All rows of results/<name> as a list of dicts (values are strings)."""
    if name not in _csv_cache:
        with open(RESULTS / name, newline="", encoding="utf-8") as f:
            _csv_cache[name] = list(csv.DictReader(f))
    return _csv_cache[name]


def find_rows(name, where):
    """Rows of a CSV whose columns equal the given strings. A list value
    matches any of its strings (rows keep their CSV order)."""
    rows = read_csv(name)
    if not where:
        return rows
    def match(cell, want):
        return cell in want if isinstance(want, list) else cell == want
    return [r for r in rows if all(match(r[k], v) for k, v in where.items())]


def to_number(text):
    """CSV text -> int or float. Empty -> None. Non-numeric -> the string."""
    t = text.strip()
    if t == "":
        return None
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"-?\d+\.\d+", t):
        return float(t)
    if t in ("t", "f"):
        return t == "t"
    return t


def same_number(a, b):
    """Exact decimal equality (so 24.00 == 24.0 == 24)."""
    try:
        return Decimal(str(a)) == Decimal(str(b))
    except InvalidOperation:
        return False


def fmt_display(text, unit, trim_zeros=False):
    """Format CSV text for display: thousands separators, unit suffix.
    trim_zeros drops a fractional part ONLY when it is all zeros (24.00 -> 24),
    so the displayed number is still exactly equal to the source."""
    neg = text.startswith("-")
    t = text.lstrip("-")
    if "." in t:
        whole, frac = t.split(".")
        if trim_zeros and set(frac) == {"0"}:
            frac = ""
    else:
        whole, frac = t, ""
    s = ("-" if neg else "") + f"{int(whole):,}" + (("." + frac) if frac else "")
    if unit == "pct":
        return s + "%"
    if unit == "pp":
        return s + " pp"
    return s


# -----------------------------------------------------------------------------
# Sourced numbers and charts
# -----------------------------------------------------------------------------
def num(file, column, label, unit="count", where=None, trim_zeros=False):
    """A sourced number: value + display + where it came from."""
    rows = find_rows(file, where)
    if len(rows) != 1:
        sys.exit(f"ERROR: {file} {where} matched {len(rows)} rows (need exactly 1)")
    text = rows[0][column]
    return {
        "label": label,
        "value": to_number(text),
        "display": fmt_display(text, unit, trim_zeros),
        "unit": unit,
        "source": {"file": f"results/{file}", "column": column, "where": where or {}},
    }


def rounded(sourced, label):
    """A whole number derived from a sourced number by rounding half up
    (e.g. 2.15% -> 2 in 100). verify() re-derives it from the source."""
    value = int(Decimal(str(sourced["value"])).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    return {"label": label, "value": value, "display": f"{value:,}", "unit": "count",
            "derived": {"rule": "round half up to a whole number", "from": sourced}}


def chart(chart_id, title, kind, file, columns, x, y, where=None):
    """Chart data: rows copied from a CSV (optionally filtered), selected columns."""
    rows = [{c: to_number(r[c]) for c in columns} for r in find_rows(file, where)]
    return {
        "id": chart_id,
        "title": title,
        "type": kind,
        "x": x,
        "y": y,
        "source": {"file": f"results/{file}", "columns": columns, "where": where or {}},
        "rows": rows,
    }


def render(template, numbers):
    """Fill {placeholders} with the display text of sourced numbers."""
    return template.format(**{k: v["display"] for k, v in numbers.items()})


# -----------------------------------------------------------------------------
# KPIs
# -----------------------------------------------------------------------------
def build_kpis():
    b = "baseline.csv"
    kpis = {
        "orders_in_window": num(b, "value", "Orders in window", where={"section": "orders_by_status", "dimension": "all", "metric": "orders"}),
        "delivered_orders": num(b, "value", "Delivered orders", where={"section": "volume", "dimension": "all", "metric": "delivered_orders"}),
        "unique_customers": num(b, "value", "Customers", where={"section": "volume", "dimension": "all", "metric": "unique_customers"}),
        "active_sellers": num(b, "value", "Active sellers", where={"section": "volume", "dimension": "all", "metric": "active_sellers"}),
        "revenue": num(b, "value", "Revenue (BRL, item price)", "brl", where={"section": "money", "dimension": "all", "metric": "revenue"}),
        "freight": num(b, "value", "Freight (BRL)", "brl", where={"section": "money", "dimension": "all", "metric": "freight"}),
        "aov": num(b, "value", "Average order value (BRL)", "brl", where={"section": "money", "dimension": "all", "metric": "average_order_value"}),
        "repeat_rate_later_day": num("10_same_day_check.csv", "repeat_rate_later_day_pct", "Customers who returned on a later day", "pct"),
        "on_time_rate": num(b, "value", "On-time delivery", "pct", where={"section": "delivery", "dimension": "all", "metric": "on_time_rate_pct"}),
        "median_delivery_days": num(b, "value", "Median delivery days", "days", where={"section": "delivery", "dimension": "all", "metric": "median_delivery_days"}),
        "avg_review_score": num(b, "value", "Average review score", "score", where={"section": "reviews", "dimension": "all", "metric": "avg_review_score"}),
        "low_review_share": num(b, "value", "Share of 1-2 star reviews", "pct", where={"section": "reviews", "dimension": "all", "metric": "share_1_2_star_pct"}),
    }
    m = "15_metrics_tree.csv"
    tree = {
        "formula": "revenue = customers x orders per customer x average order value",
        "revenue": num(m, "revenue", "Revenue (BRL)", "brl"),
        "customers": num(m, "customers", "Customers"),
        "orders": num(m, "orders", "Delivered orders"),
        "orders_per_customer": num(m, "orders_per_customer", "Orders per customer", "ratio"),
        "aov": num(m, "aov", "Average order value (BRL)", "brl"),
        "note": "Factors are rounded (orders per customer to 4 decimals, AOV to 2), "
                "so their product is close to, not exactly, the revenue.",
    }
    return {
        "window": {"from": "2017-01-01", "to": "2018-08-31", "basis": "purchase date"},
        "kpis": kpis,
        "metrics_tree": tree,
    }


# -----------------------------------------------------------------------------
# Findings
# -----------------------------------------------------------------------------
def cohort_max_cell():
    """Highest cohort share in any month after the first (months 1-12): the
    cell is found here, then published as a sourced number."""
    best = None
    for r in read_csv("10_cohort_matrix_pct.csv"):
        for i in range(1, 13):
            t = r[f"m{i}"]
            if t != "" and (best is None or Decimal(t) > best[0]):
                best = (Decimal(t), r["cohort_month"], f"m{i}")
    return num("10_cohort_matrix_pct.csv", best[2], "Highest share of a cohort ordering in any later month", "pct",
               where={"cohort_month": best[1]})


def seller_curve_ranks():
    """Ranks sampled for the concentration curve: every 5th seller through the
    top 10% (where the curve bends), then the last seller in each top p%."""
    total = len(read_csv("13_seller_revenue_rank.csv"))
    ranks = {1} | set(range(5, math.ceil(total * 10 / 100) + 1, 5)) | \
            {math.ceil(total * p / 100) for p in range(1, 101)}
    return [str(r) for r in sorted(ranks)]


def build_findings():
    findings = []

    # ---------------- F1 retention
    n = {
        "repeat_later_day": num("10_same_day_check.csv", "repeat_rate_later_day_pct", "Returned on a later day", "pct"),
        "repeat_customers_later_day": num("10_same_day_check.csv", "repeat_customers_later_day", "Customers who returned on a later day"),
        "customers": num("10_same_day_check.csv", "customers", "Customers with a delivered order"),
        "repeat_any_day": num("10_same_day_check.csv", "repeat_rate_any_day_pct", "Returned on any day (incl. same day)", "pct"),
        "same_day_share": num("10_same_day_check.csv", "same_day_pct_of_second_orders", "Second orders placed the same day as the first", "pct"),
        "median_days_to_second": num("10_time_to_second_order_percentiles.csv", "median_days", "Median days to second order", "days"),
        "repeat_180_later_day": num("10_fixed_window_repeat.csv", "repeat_180d_later_day_pct", "Returned on a later day within 180 days", "pct", where={"cohort": "overall"}),
        "repeat_revenue_share": num("10_repeat_revenue.csv", "repeat_order_revenue_pct", "Revenue from second and later orders", "pct"),
        "cohort_max_later_month": cohort_max_cell(),
    }
    n["repeat_per_100"] = rounded(n["repeat_later_day"], "Customers in 100 who came back on a later day (rounded)")
    findings.append({
        "id": "F1",
        "topic": "Retention",
        "headline_template": "Only {repeat_later_day} of customers came back on a later day, and {same_day_share} of second orders were placed on the same day as the first.",
        "headline": render("Only {repeat_later_day} of customers came back on a later day, and {same_day_share} of second orders were placed on the same day as the first.", n),
        "key_numbers": n,
        "source": [{"file": "sql/10_retention_cohorts.sql", "queries": ["Q1", "Q2", "Q3", "Q5", "Q7"]}],
        "doesnt_show": "Why customers do not return, whether customers bought before 2017, or whether same-day second orders are one checkout split into several orders.",
        "charts": [
            chart("time_to_second", "Days from first to second order", "bar",
                  "10_time_to_second_order_buckets.csv", ["bucket", "customers", "pct_of_second_orders"],
                  "bucket", "pct_of_second_orders"),
            chart("cohort_matrix", "Share of each monthly cohort active N months later (%)", "heatmap",
                  "10_cohort_matrix_pct.csv",
                  ["cohort_month", "cohort_customers"] + [f"m{i}" for i in range(13)],
                  "months_since_first_order", "pct_of_cohort"),
        ],
        "recommendations": ["R3"],
    })

    # ---------------- F2 delivery promises and handover
    n = {
        "on_time": num("11_overall.csv", "on_time_rate_pct", "On-time delivery", "pct"),
        "median_promised": num("11_promise_medians.csv", "median_promised_days", "Median promised days", "days", trim_zeros=True),
        "median_actual": num("11_promise_medians.csv", "median_actual_calendar_days", "Median actual days (calendar)", "days", trim_zeros=True),
        "early_7plus": num("11_delay_buckets.csv", "pct_of_orders", "Delivered 7+ days early", "pct", where={"bucket": "7+ days early"}),
        "handover_after_share": num("11_seller_handling.csv", "pct_of_orders", "Orders handed over after the shipping limit", "pct", where={"handover": "after limit"}),
        "late_after_limit": num("11_seller_handling.csv", "late_rate_pct", "Late rate, handed over after the limit", "pct", where={"handover": "after limit"}),
        "late_on_time_handover": num("11_seller_handling.csv", "late_rate_pct", "Late rate, handed over on time", "pct", where={"handover": "on or before limit"}),
        "carrier_days_late": num("11_stage_medians.csv", "median_carrier_to_customer", "Median carrier-to-customer days, late orders", "days", where={"delivery_group": "late"}),
        "carrier_days_on_time": num("11_stage_medians.csv", "median_carrier_to_customer", "Median carrier-to-customer days, on-time orders", "days", where={"delivery_group": "on_time"}),
        "timed_orders": num("11_overall.csv", "orders", "Delivered orders with a delivery date"),
        "stage_orders": num("11_stage_medians.csv", "orders", "Orders with valid stage dates", where={"delivery_group": "all"}),
    }
    tpl = ("Orders arrived a median {median_actual} days after purchase against a {median_promised}-day promise, "
           "but orders handed to the carrier after the seller's shipping limit were late {late_after_limit} of the time, against {late_on_time_handover}.")
    findings.append({
        "id": "F2",
        "topic": "Delivery promises and handover",
        "headline_template": tpl,
        "headline": render(tpl, n),
        "key_numbers": n,
        "source": [{"file": "sql/11_delivery_performance.sql", "queries": ["Q1", "Q3", "Q5", "Q6"]}],
        "doesnt_show": "That late handover causes late delivery, how carriers perform, or the slowest deliveries of the last months (orders not yet delivered when the data ends).",
        "charts": [
            chart("delay_buckets", "Delivery vs promised date", "bar",
                  "11_delay_buckets.csv", ["bucket", "orders", "pct_of_orders"], "bucket", "pct_of_orders"),
            chart("stage_medians", "Median days per stage, late vs on-time orders", "stacked_bar",
                  "11_stage_medians.csv",
                  ["delivery_group", "orders", "median_purchase_to_approval", "median_approval_to_carrier", "median_carrier_to_customer"],
                  "median_days", "delivery_group", where={"delivery_group": ["late", "on_time"]}),
            chart("late_by_state", "Late rate by customer state (500+ orders)", "bar",
                  "11_by_state.csv", ["state", "orders", "median_delivery_days", "median_promised_days", "late_rate_pct"],
                  "state", "late_rate_pct"),
        ],
        "recommendations": ["R2"],
    })

    # ---------------- F3 reviews and review timing
    n = {
        "low_share": num("baseline.csv", "value", "Share of 1-2 star reviews", "pct", where={"section": "reviews", "dimension": "all", "metric": "share_1_2_star_pct"}),
        "low_7plus_early": num("12_by_delay_bucket.csv", "low_review_pct", "1-2 star share, 7+ days early", "pct", where={"bucket": "7+ days early"}),
        "low_8plus_late": num("12_by_delay_bucket.csv", "low_review_pct", "1-2 star share, 8+ days late", "pct", where={"bucket": "8+ days late"}),
        "late_reviewed_before": num("12_review_timing.csv", "pct_within_delivery_group", "Late orders reviewed before delivery", "pct", where={"delivery_group": "late", "review_timing": "before delivery"}),
        "low_before": num("12_review_timing.csv", "low_review_pct", "1-2 star share, late and reviewed before delivery", "pct", where={"delivery_group": "late", "review_timing": "before delivery"}),
        "low_after": num("12_review_timing.csv", "low_review_pct", "1-2 star share, late and reviewed after delivery", "pct", where={"delivery_group": "late", "review_timing": "on or after delivery"}),
        "late_share_of_low": num("12_low_review_sizing.csv", "pct_of_low_reviews", "Share of all 1-2 star reviews from late delivered orders", "pct", where={"sizing_group": "b) late delivered"}),
        "other_share_of_low": num("12_low_review_sizing.csv", "pct_of_low_reviews", "Share of all 1-2 star reviews from on-time single-seller orders", "pct", where={"sizing_group": "d) everything else"}),
        "score_before": num("12_review_timing.csv", "avg_score", "Average score, late and reviewed before delivery", "score", where={"delivery_group": "late", "review_timing": "before delivery"}),
        "score_after": num("12_review_timing.csv", "avg_score", "Average score, late and reviewed after delivery", "score", where={"delivery_group": "late", "review_timing": "on or after delivery"}),
        "late_reviewed_orders": num("12_review_creation_gap.csv", "orders", "Late delivered orders with a review", where={"delivery_group": "late"}),
        "review_days_after_estimate_late": num("12_review_creation_gap.csv", "median_days_after_estimate", "Late orders: median days from estimated date to review", "days", where={"delivery_group": "late"}),
    }
    tpl = ("The share of 1-2 star reviews rises from {low_7plus_early} for orders arriving 7+ days early to {low_8plus_late} for orders 8+ days late, "
           "and {late_reviewed_before} of late orders were reviewed before they arrived.")
    findings.append({
        "id": "F3",
        "topic": "Reviews and review timing",
        "headline_template": tpl,
        "headline": render(tpl, n),
        "key_numbers": n,
        "source": [{"file": "sql/12_review_drivers.sql", "queries": ["Q2", "Q7", "Q8", "Q8b"]}],
        "doesnt_show": "What drives the low reviews on on-time single-seller orders (review text was not analysed), or how Olist triggers the review request.",
        "charts": [
            # Only the six delivery-timing buckets (the same ones as F2's
            # chart); "no delivery timing" is not a point on that scale.
            chart("low_by_delay", "1-2 star share by delivery vs promise", "bar",
                  "12_by_delay_bucket.csv", ["bucket", "orders", "avg_score", "low_review_pct"], "bucket", "low_review_pct",
                  where={"bucket": [r["bucket"] for r in read_csv("11_delay_buckets.csv")]}),
            chart("late_review_timing", "Late orders: reviewed before vs after delivery", "split",
                  "12_review_timing.csv",
                  ["review_timing", "orders", "pct_within_delivery_group", "avg_score", "low_review_pct"],
                  "review_timing", "pct_within_delivery_group", where={"delivery_group": "late"}),
            chart("low_review_sizing", "Where 1-2 star reviews come from", "bar",
                  "12_low_review_sizing.csv", ["sizing_group", "low_reviews", "pct_of_low_reviews", "low_review_rate_pct"],
                  "sizing_group", "pct_of_low_reviews"),
        ],
        "recommendations": ["R1"],
    })

    # ---------------- F4 seller concentration
    n = {
        "top1_sellers": num("13_concentration.csv", "sellers_in_group", "Sellers in the top 1%", where={"top_pct": "1"}),
        "top1_share": num("13_concentration.csv", "revenue_share_pct", "Revenue share, top 1% of sellers", "pct", where={"top_pct": "1"}),
        "top20_share": num("13_concentration.csv", "revenue_share_pct", "Revenue share, top 20% of sellers", "pct", where={"top_pct": "20"}),
        "handover_top_sellers": num("13_handover_concentration.csv", "top10pct_sellers", "Sellers with the most late handovers (top 10% of scorecard)"),
        "handover_top_share": num("13_handover_concentration.csv", "pct_of_scorecard_late_handovers", "Their share of scorecard late handovers", "pct"),
        "handover_top_order_share": num("13_handover_concentration.csv", "pct_of_scorecard_handover_orders", "Their share of scorecard orders", "pct"),
        "problem_sellers": num("13_problem_sellers.csv", "problem_sellers", "Problem sellers (low-review share >= 2x benchmark)"),
        "problem_low_share": num("13_problem_sellers.csv", "pct_of_scorecard_low_reviews", "Problem sellers' share of low reviews", "pct"),
        "problem_order_share": num("13_problem_sellers.csv", "pct_of_scorecard_orders", "Problem sellers' share of orders", "pct"),
        "q4_late_delivery": num("13_handover_quartiles.csv", "late_delivery_pct", "Late delivery, sellers with most late handovers (quartile 4)", "pct", where={"handover_quartile": "4"}),
        "active_sellers": num("13_concentration.csv", "total_sellers", "Sellers with a delivered sale in the window", where={"top_pct": "1"}),
        "q1_late_delivery": num("13_handover_quartiles.csv", "late_delivery_pct", "Late delivery, sellers with fewest late handovers (quartile 1)", "pct", where={"handover_quartile": "1"}),
    }
    tpl = ("The top 1% of sellers ({top1_sellers} sellers) earned {top1_share} of revenue, "
           "and {handover_top_sellers} sellers account for {handover_top_share} of scorecard late handovers.")
    findings.append({
        "id": "F4",
        "topic": "Seller concentration",
        "headline_template": tpl,
        "headline": render(tpl, n),
        "key_numbers": n,
        "source": [{"file": "sql/13_seller_scorecard.sql", "queries": ["Q1", "Q4", "Q5", "Q6"]}],
        "doesnt_show": "Why some sellers hand over late, quality on multi-seller orders (not attributed to a seller), or what would happen if sellers were penalised.",
        "charts": [
            chart("seller_concentration", "Share of revenue from the top sellers", "bar",
                  "13_concentration.csv", ["top_pct", "sellers_in_group", "revenue_share_pct"], "top_pct", "revenue_share_pct"),
            chart("seller_curve", "Cumulative revenue share by seller rank (sampled ranks)", "line",
                  "13_seller_revenue_rank.csv", ["revenue_rank", "revenue", "cumulative_share_pct"],
                  "revenue_rank", "cumulative_share_pct", where={"revenue_rank": seller_curve_ranks()}),
            chart("handover_quartiles", "Sellers grouped by late-handover rate", "bar",
                  "13_handover_quartiles.csv",
                  ["handover_quartile", "sellers", "late_handover_pct", "late_delivery_pct", "low_review_pct"],
                  "handover_quartile", "late_delivery_pct"),
        ],
        "recommendations": ["R2"],
    })

    # ---------------- F5 volume growth and freight
    n = {
        "revenue_change": num("14_yoy_jan_aug.csv", "revenue_change_pct", "Revenue change, Jan-Aug 2018 vs 2017", "pct"),
        "orders_change": num("14_yoy_jan_aug.csv", "orders_change_pct", "Orders change", "pct"),
        "aov_change": num("14_yoy_jan_aug.csv", "aov_change_pct", "Average order value change", "pct"),
        "revenue_2017": num("14_yoy_jan_aug.csv", "revenue_2017", "Revenue Jan-Aug 2017 (BRL)", "brl"),
        "revenue_2018": num("14_yoy_jan_aug.csv", "revenue_2018", "Revenue Jan-Aug 2018 (BRL)", "brl"),
        "freight_pct": num("14_freight_overall.csv", "freight_pct_of_item_value", "Freight as share of item value", "pct"),
        "freight_gt50": num("14_freight_overall.csv", "pct_orders_freight_gt_50", "Orders where freight > 50% of item value", "pct"),
        "freight_q1": num("14_freight_by_value_quartile.csv", "freight_pct_of_item_value", "Freight share, cheapest quarter of orders", "pct", where={"value_quartile": "1"}),
        "freight_q4": num("14_freight_by_value_quartile.csv", "freight_pct_of_item_value", "Freight share, most expensive quarter of orders", "pct", where={"value_quartile": "4"}),
        "freight_ma": num("14_freight_by_state.csv", "freight_pct_of_item_value", "Freight share, MA (highest state)", "pct", where={"state": "MA"}),
        "freight_sp": num("14_freight_by_state.csv", "freight_pct_of_item_value", "Freight share, SP (lowest state)", "pct", where={"state": "SP"}),
    }
    tpl = ("Jan-Aug 2018 revenue was {revenue_change} above Jan-Aug 2017, with orders up {orders_change} and average order value up {aov_change}; "
           "freight adds {freight_pct} to item value, and {freight_q1} for the cheapest quarter of orders.")
    findings.append({
        "id": "F5",
        "topic": "Volume growth and freight",
        "headline_template": tpl,
        "headline": render(tpl, n),
        "key_numbers": n,
        "source": [{"file": "sql/14_revenue_rfm.sql", "queries": ["Q1", "Q4"]}],
        "doesnt_show": "Whether freight cost holds back orders or repeat purchases, or how much of the growth is seasonality, marketing or price changes.",
        "charts": [
            chart("monthly_revenue", "Delivered revenue by purchase month (BRL)", "line",
                  "14_monthly_revenue.csv", ["purchase_month", "orders", "revenue", "aov", "revenue_mom_pct"],
                  "purchase_month", "revenue"),
            chart("freight_by_value", "Freight as share of item value, by order-value quartile", "bar",
                  "14_freight_by_value_quartile.csv",
                  ["value_quartile", "min_order_value", "max_order_value", "orders", "freight_pct_of_item_value", "pct_orders_freight_gt_50"],
                  "value_quartile", "freight_pct_of_item_value"),
        ],
        "recommendations": ["R3"],
    })

    # ---------------- Recommendations (numbers are sourced evidence only;
    # test design text lives in docs/findings.md)
    by_id = {f["id"]: f["key_numbers"] for f in findings}
    r2_numbers = {"handover_top_sellers": by_id["F4"]["handover_top_sellers"]}
    recommendations = [
        {
            "id": "R1",
            "title": "Send the review request after delivery confirmation",
            "findings": ["F3"],
            "target_metric": "Share of 1-2 star reviews on late orders",
            "expected_direction": "down",
            "evidence": {
                "late_reviewed_before": by_id["F3"]["late_reviewed_before"],
                "low_before": by_id["F3"]["low_before"],
                "low_after": by_id["F3"]["low_after"],
                "late_share_of_low": by_id["F3"]["late_share_of_low"],
            },
            "effort": "low",
        },
        {
            "id": "R2",
            "title_template": "Seller handover SLA with alerts and a ranking penalty, starting with the {handover_top_sellers} sellers with the most late handovers",
            "title": render("Seller handover SLA with alerts and a ranking penalty, starting with the {handover_top_sellers} sellers with the most late handovers", r2_numbers),
            "title_numbers": r2_numbers,
            "findings": ["F2", "F4"],
            "target_metric": "Late-handover rate (primary); late-delivery rate (secondary)",
            "expected_direction": "down",
            "evidence": {
                "late_after_limit": by_id["F2"]["late_after_limit"],
                "late_on_time_handover": by_id["F2"]["late_on_time_handover"],
                "handover_top_share": by_id["F4"]["handover_top_share"],
                "handover_top_order_share": by_id["F4"]["handover_top_order_share"],
                "q4_late_delivery": by_id["F4"]["q4_late_delivery"],
                "q1_late_delivery": by_id["F4"]["q1_late_delivery"],
            },
            "effort": "medium",
        },
        {
            "id": "R3",
            "title": "Win back lapsed high-value one-time customers with a free-freight voucher",
            "findings": ["F1", "F5"],
            "target_metric": "Share of targeted customers placing a delivered order within the test window",
            "expected_direction": "up",
            "evidence": {
                "segment_customers": num("14_rfm_segments.csv", "customers", "Lapsed high-value one-time customers", where={"segment": "Lapsed high-value"}),
                "segment_revenue_share": num("14_rfm_segments.csv", "pct_of_revenue", "Their share of revenue", "pct", where={"segment": "Lapsed high-value"}),
                "segment_avg_revenue": num("14_rfm_segments.csv", "avg_revenue_per_customer", "Their average revenue per customer (BRL)", "brl", where={"segment": "Lapsed high-value"}),
                "segment_min_recency": num("14_rfm_segments.csv", "min_recency_days", "Days since last order, minimum", "days", where={"segment": "Lapsed high-value"}),
                "segment_max_recency": num("14_rfm_segments.csv", "max_recency_days", "Days since last order, maximum", "days", where={"segment": "Lapsed high-value"}),
                "repeat_later_day": by_id["F1"]["repeat_later_day"],
                "freight_pct": by_id["F5"]["freight_pct"],
            },
            "effort": "medium",
        },
    ]
    # ---------------- Limitations (collected from docs/data_quality_notes.md;
    # every number sourced from a CSV)
    def lim(lim_id, template, numbers):
        return {"id": lim_id, "text_template": template, "numbers": numbers,
                "text": render(template, numbers)}

    q = "15_quality_issues.csv"
    limitations = [
        lim("window",
            "The analysis covers purchases from 2017-01-01 to 2018-08-31; {outside} orders outside that window are excluded, "
            "and a customer's first order means their first delivered order inside the window.",
            {"outside": num(q, "affected", "Orders outside the window", where={"issue_id": "orders_outside_window"})}),
        lim("same_day",
            "{same_day} of {second_orders} second orders were placed on the same calendar day as the first, {within_10} of them within 10 minutes; "
            "they are not counted as returns.",
            {"same_day": num("10_same_day_check.csv", "same_day_second_orders", "Same-day second orders"),
             "second_orders": num("10_same_day_check.csv", "second_orders", "Second orders"),
             "within_10": num("10_same_day_gap.csv", "within_10_minutes", "Same-day second orders within 10 minutes")}),
        lim("payments",
            "{mismatch} delivered orders have payments that differ from items plus freight by more than one cent; the gap is unexplained. "
            "Revenue uses item prices, not payments.",
            {"mismatch": num(q, "affected", "Payment mismatches", where={"issue_id": "payment_mismatch"})}),
        lim("stages",
            "Stage times exclude {negative} orders with a negative stage duration and {missing} with a missing stage.",
            {"negative": num(q, "affected", "Orders with a negative stage", where={"issue_id": "negative_stage_duration"}),
             "missing": num("11_stage_exclusions.csv", "excluded_missing_stage_only", "Orders with a missing stage only")}),
        lim("recent_months",
            "Orders not yet delivered when the data ends have no delivery timing ({aug_untimed} of {aug_orders} orders from August 2018), "
            "so the most recent months may be missing their slowest deliveries.",
            {"aug_untimed": num("11_monthly_trend.csv", "orders_without_timing", "August 2018 orders without timing", where={"purchase_month": "2018-08-01"}),
             "aug_orders": num("baseline.csv", "value", "August 2018 orders", where={"section": "monthly", "dimension": "2018-08-01", "metric": "orders"})}),
        lim("distance",
            "Distances are between zip-prefix centres, not addresses; {used} of {single_seller} single-seller orders had usable coordinates.",
            {"used": num("11_geo_coverage.csv", "orders_used", "Orders with usable coordinates"),
             "single_seller": num("11_geo_coverage.csv", "single_seller_orders", "Single-seller orders")}),
        lim("attribution",
            "Seller quality metrics (reviews, lateness, handover) use single-seller orders only; {multi} multi-seller orders with delivery timing are not attributed to a seller.",
            {"multi": num("11_same_vs_cross_state.csv", "orders", "Multi-seller timed orders", where={"route": "excluded: multi-seller"})}),
        lim("small_counts",
            "Some comparisons rest on few customers: only {late_returners} customers whose first order was late came back. "
            "No significance tests were run; differences are described, not tested.",
            {"late_returners": num("12_first_order_return.csv", "repeat_customers", "Returners after a late first order", where={"dimension": "lateness", "first_order_group": "late"})}),
        lim("rfm",
            "RFM scores are quartiles (NTILE), so the four one-time segments are each about a quarter of customers by construction; "
            "their revenue shares, not their sizes, are the result.", {}),
        lim("associations",
            "All findings are associations in observational data from 2016-2018; none shows cause and effect.", {}),
    ]

    return {"findings": findings, "recommendations": recommendations, "limitations": limitations}


# -----------------------------------------------------------------------------
# Recommendation details, parsed from the tables in docs/findings.md
# (single source for that text; its numbers are covered by check_markdown)
# -----------------------------------------------------------------------------
def strip_md(text):
    return re.sub(r"[*`]", "", text).strip()


def parse_md_recommendations():
    text = FINDINGS_MD.read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r"^### (R\d)\. .*?\n(.*?)(?=^### |^---|\Z)", text, re.S | re.M):
        rid, body = m.group(1), m.group(2)
        fields = {k: v.strip() for k, v in re.findall(r"^\| \*\*(.+?)\*\* \| (.*) \|$", body, re.M)}
        need = ["Change", "Target metric", "Expected direction", "Test design", "Main risk", "Effort"]
        missing = [k for k in need if k not in fields]
        if missing:
            sys.exit(f"ERROR: docs/findings.md {rid} table is missing {missing}")
        # "*Unit:* order ... *Control:* ..." -> [{label, text}, ...]
        parts = re.split(r"\*([A-Z][\w ]*):\*\s*", fields["Test design"])
        design = [{"label": parts[i], "text": parts[i + 1].strip()} for i in range(1, len(parts) - 1, 2)]
        out[rid] = {
            "verified_by": "docs/findings.md number check",
            "change": strip_md(fields["Change"]),
            "target_metric": strip_md(fields["Target metric"]),
            "expected_direction": strip_md(fields["Expected direction"]).rstrip("."),
            "test_design": design,
            "risk": strip_md(fields["Main risk"]),
            "effort": strip_md(fields["Effort"]).rstrip("."),
        }
    return out


# -----------------------------------------------------------------------------
# site.json: authored copy (docs/site_copy.json) with sourced numbers
# -----------------------------------------------------------------------------
def build_site(kpis, findings):
    copy = json.loads(SITE_COPY.read_text(encoding="utf-8"))
    f_by_id = {f["id"]: f for f in findings["findings"]}
    r_by_id = {r["id"]: r for r in findings["recommendations"]}
    # Hero map: counts and shares of the 3,000-order map sample (sql/15 Q6)
    ms = "15_map_sample_summary.csv"
    map_numbers = {
        "sample_orders": num(ms, "sample_orders", "Orders in the map sample"),
        "on_time_pct": num(ms, "on_time_pct", "On-time share of the map sample", "pct"),
        "late_pct": num(ms, "late_pct", "Late share of the map sample", "pct"),
    }

    def resolve(ref):
        scope, key = ref.split(".", 1)
        try:
            if scope == "map":
                return map_numbers[key]
            if scope == "kpis":
                return kpis["kpis"][key]
            if scope == "tree":
                return kpis["metrics_tree"][key]
            if scope in f_by_id:
                return f_by_id[scope]["key_numbers"][key]
            if scope in r_by_id:
                return r_by_id[scope]["evidence"][key]
        except KeyError:
            pass
        sys.exit(f"ERROR: docs/site_copy.json ref {ref!r} does not resolve to a sourced number")

    def text(block):
        nums = {k: resolve(v) for k, v in block["refs"].items()}
        return {"text_template": block["template"], "numbers": nums, "text": render(block["template"], nums)}

    chapters = []
    for fid, ch in copy["chapters"].items():
        f = f_by_id[fid]
        bad = [c for c in ch["cards"] if c not in f["key_numbers"]]
        if bad:
            sys.exit(f"ERROR: site_copy chapter {fid} cards not in key numbers: {bad}")
        missing = [c for c in ch["charts"] if copy["charts"]["items"].get(c, {}).get("finding") != fid]
        if missing:
            sys.exit(f"ERROR: site_copy chapter {fid} lists charts without copy for {fid}: {missing}")
        chapters.append({
            "id": fid,
            "title": ch["title"],
            "cards": ch["cards"],
            "charts": ch["charts"],
            "why": text(ch["why"]),
            "recommendation": f["recommendations"][0],
        })

    # Charts: titles and subtitles are templates over sourced numbers; "data"
    # names the chart rows in findings.json that the chart draws.
    chart_items = {}
    for cid, c in copy["charts"]["items"].items():
        f = f_by_id[c["finding"]]
        if c["data"] is not None and not any(ch["id"] == c["data"] for ch in f["charts"]):
            sys.exit(f"ERROR: site_copy chart {cid} data {c['data']!r} is not a chart of {c['finding']}")
        chart_items[cid] = {
            "id": cid,
            "finding": c["finding"],
            "data": c["data"],
            "title": text(c["title"]),
            "subtitle": text(c["subtitle"]),
            "labels": c["labels"],
            "numbers": {k: resolve(v) for k, v in c.get("numbers", {}).items()},
        }
    # The delay-bucket settings must name real buckets.
    buckets = [r["bucket"] for r in read_csv("11_delay_buckets.csv")]
    db = copy["charts"]["delay_buckets"]
    unknown = [b for b in [db["promise"], *db["late"], *db["short"]] if b not in buckets]
    if unknown or set(db["short"]) != set(buckets):
        sys.exit(f"ERROR: site_copy charts.delay_buckets names unknown or missing buckets: {unknown}")

    mx = copy["recommendations"]["matrix"]
    if set(mx["impact"]) != set(r_by_id):
        sys.exit(f"ERROR: site_copy recommendations.matrix.impact must cover {sorted(r_by_id)}")
    bad = [v for v in mx["impact"].values() if v not in mx["levels"]]
    bad += [r["details"]["effort"].lower() for r in r_by_id.values() if r["details"]["effort"].lower() not in mx["levels"]]
    if bad:
        sys.exit(f"ERROR: matrix levels missing {bad}")

    return {
        "meta": {**{k: v for k, v in copy["meta"].items() if k != "subtitle"},
                 "subtitle": text(copy["meta"]["subtitle"])},
        "hero": {**{k: v for k, v in copy["hero"].items() if k != "kpis"},
                 "kpis": [{"label": k["label"], "number": resolve(k["ref"])} for k in copy["hero"]["kpis"]]},
        "question": {**{k: v for k, v in copy["question"].items() if k != "body"},
                     "body": [text(b) for b in copy["question"]["body"]]},
        "chapters": chapters,
        "charts": {"ui": copy["charts"]["ui"], "delay_buckets": db, "items": chart_items},
        "recommendations": copy["recommendations"],
        "under_the_hood": copy["under_the_hood"],
        "limitations": copy["limitations"],
        "ui": copy["ui"],
        "links": copy["links"],
        "footer": copy["footer"],
        "map": {
            **{k: v for k, v in copy["map"].items() if k not in ("caption", "legend")},
            "caption": text(copy["map"]["caption"]),
            "legend": [{"id": item["id"], "label": item["label"], "number": resolve(item["ref"])}
                       for item in copy["map"]["legend"]],
        },
    }


# -----------------------------------------------------------------------------
# map.json: per-state delivery figures for the hero map tooltip (all 27
# states, sql/15 Q7). Loaded only with the map, so it stays out of the main
# bundle. Cross-checked against file 11 Q4 for the states with 500+ orders.
# -----------------------------------------------------------------------------
def build_map_meta():
    f = "15_state_delivery.csv"
    states = {}
    for r in read_csv(f):
        st = r["state"]
        w = {"state": st}
        states[st] = {
            "delivered_orders": num(f, "delivered_orders", "Delivered orders", where=w),
            "late_rate_pct": num(f, "late_rate_pct", "Late rate", "pct", where=w),
            "median_delivery_days": num(f, "median_delivery_days", "Median delivery days", "days", where=w),
        }
    # Cross-check: same rule as file 11 Q4, so its 500+ states must match exactly.
    mismatches = []
    by11 = {r["state"]: r for r in read_csv("11_by_state.csv")}
    all15 = {r["state"]: r for r in read_csv(f)}
    for st, r11 in by11.items():
        r15 = all15.get(st)
        for c11, c15 in (("orders", "timed_orders"), ("median_delivery_days", "median_delivery_days"),
                         ("late_rate_pct", "late_rate_pct")):
            if r15 is None or not same_number(r11[c11], r15[c15]):
                mismatches.append(f"{st}.{c11}: {r11[c11]} vs {None if r15 is None else r15[c15]}")
    if mismatches:
        sys.exit("ERROR: 15_state_delivery.csv disagrees with 11_by_state.csv: " + "; ".join(mismatches))
    print(f"  map: {len(states)} states; {len(by11)} states cross-checked against 11_by_state.csv")
    return {"source": "results/15_state_delivery.csv (sql/15_site_support.sql, Q7)", "states": states}


# -----------------------------------------------------------------------------
# Pipelines
# -----------------------------------------------------------------------------
def build_pipelines():
    rows = read_csv("15_pipelines.csv")
    out = {}
    for r in rows:
        out.setdefault(r["finding"], []).append({
            "step": to_number(r["step"]),
            "label": r["label"],
            "row_count": to_number(r["row_count"]),
            "rows_dropped": to_number(r["rows_dropped"]),
            "drop_reason": r["reason"] or None,
        })
    # Cross-checks: a pipeline's counts must equal the same counts in the
    # analysis files they summarise. (Compared, never published as new numbers.)
    def step(f, s):
        return next(x["row_count"] for x in out[f] if x["step"] == s)

    def cell(file, col, where=None):
        return to_number(find_rows(file, where)[0][col])

    yoy = read_csv("14_yoy_jan_aug.csv")[0]
    checks = [
        ("F1 delivered orders", step("F1", 3), cell("baseline.csv", "value", {"section": "volume", "dimension": "all", "metric": "delivered_orders"})),
        ("F1 customers", step("F1", 4), cell("10_same_day_check.csv", "customers")),
        ("F1 later-day returners", step("F1", 5), cell("10_same_day_check.csv", "repeat_customers_later_day")),
        ("F2 timed orders", step("F2", 4), cell("11_overall.csv", "orders")),
        ("F2 handed over after limit", step("F2", 6), cell("11_seller_handling.csv", "orders", {"handover": "after limit"})),
        ("F3 orders with review", step("F3", 3), cell("baseline.csv", "value", {"section": "reviews", "dimension": "all", "metric": "orders_with_review"})),
        ("F3 late reviewed orders", step("F3", 5), cell("12_review_creation_gap.csv", "orders", {"delivery_group": "late"})),
        ("F3 reviewed before delivery", step("F3", 6), cell("12_review_timing.csv", "orders", {"delivery_group": "late", "review_timing": "before delivery"})),
        ("F4 active sellers", step("F4", 2), cell("13_concentration.csv", "total_sellers", {"top_pct": "1"})),
        ("F4 scorecard sellers", step("F4", 3), cell("13_problem_sellers.csv", "scorecard_sellers")),
        ("F5 Jan-Aug 2018 orders", step("F5", 5), int(yoy["orders_2018"])),
        ("F5 both periods", step("F5", 4), int(yoy["orders_2017"]) + int(yoy["orders_2018"])),
    ]
    bad = [c for c in checks if c[1] != c[2]]
    if bad:
        sys.exit("ERROR: pipeline cross-check failed: " + "; ".join(f"{n}: {a} vs {b}" for n, a, b in bad))
    print(f"  pipelines: {len(checks)} cross-checks against files 10-14 passed")
    return {"source": "results/15_pipelines.csv (sql/15_site_support.sql, Q2)", "pipelines": out}


# -----------------------------------------------------------------------------
# Checks shown under each funnel ("checks that passed"). Each one is tested
# here; the script stops if any fails, so only passing checks are published.
# Their numbers are sourced, so verify() covers the text.
# -----------------------------------------------------------------------------
def build_checks(findings):
    f = {x["id"]: x for x in findings["findings"]}
    fails = []

    def check(ok, template, numbers, what):
        if not ok:
            fails.append(what)
        return {"text_template": template, "numbers": numbers, "text": render(template, numbers)}

    def total(file, col, where=None):
        return sum(Decimal(r[col]) for r in find_rows(file, where))

    def fanout(view, grain_text):
        fo = "15_fanout_checks.csv"
        w = {"view_name": view}
        rows, keys = num(fo, "row_count", f"{view} rows", where=w), num(fo, "distinct_keys", f"{view} distinct keys", where=w)
        ok = find_rows(fo, w)[0]["passed"] == "t" and rows["value"] == keys["value"]
        return check(ok, f"{grain_text} in {view}: {{rows}} rows, {{keys}} distinct keys", {"rows": rows, "keys": keys},
                     f"fan-out {view}")

    b = "baseline.csv"
    delivered = num(b, "value", "Delivered orders", where={"section": "volume", "dimension": "all", "metric": "delivered_orders"})
    revenue = num(b, "value", "Revenue (BRL, item price)", "brl", where={"section": "money", "dimension": "all", "metric": "revenue"})
    reviewed = num(b, "value", "Orders with a review", where={"section": "reviews", "dimension": "all", "metric": "orders_with_review"})
    cohorts = read_csv("10_cohort_matrix_pct.csv")
    rank_rows = read_csv("13_seller_revenue_rank.csv")
    rank_by = {r["revenue_rank"]: r for r in rank_rows}
    conc = read_csv("13_concentration.csv")
    timing = {r["review_timing"]: r for r in find_rows("12_review_timing.csv", {"delivery_group": "late"})}
    ex = read_csv("11_stage_exclusions.csv")[0]

    def curve_matches(r):
        at = rank_by[str(math.ceil(int(r["total_sellers"]) * int(r["top_pct"]) / 100))]
        return Decimal(at["cumulative_share_pct"]).quantize(Decimal("0.01"), ROUND_HALF_UP) == Decimal(r["revenue_share_pct"])

    out = {
        "F1": [
            fanout("v_order_facts", "1 row per order"),
            check(total("10_cohort_matrix_pct.csv", "cohort_customers") == Decimal(str(f["F1"]["key_numbers"]["customers"]["value"])),
                  "Cohort sizes add up to {customers} customers", {"customers": f["F1"]["key_numbers"]["customers"]},
                  "cohort sizes"),
            check(all(Decimal(r["m0"]) == 100 for r in cohorts),
                  "Every cohort is 100% active in month 0", {}, "month 0"),
            check(next(s for s in pipelines_rows("F1") if s["step"] == "5")["row_count"]
                  == read_csv("10_same_day_check.csv")[0]["repeat_customers_later_day"],
                  "Later-day returners in the funnel match the retention query: {n}",
                  {"n": f["F1"]["key_numbers"]["repeat_customers_later_day"]}, "F1 returners"),
        ],
        "F2": [
            fanout("v_order_facts", "1 row per order"),
            check(total("11_delay_buckets.csv", "orders") == Decimal(str(f["F2"]["key_numbers"]["timed_orders"]["value"])),
                  "Delay buckets add up to {timed} orders with a delivery date", {"timed": f["F2"]["key_numbers"]["timed_orders"]},
                  "delay buckets"),
            check(int(ex["timed_orders"]) - int(ex["excluded_negative_stage"]) - int(ex["excluded_missing_stage_only"]) == int(ex["orders_used"]),
                  "Stage medians use {used} orders: {timed} minus {negative} with a negative stage and {missing} with a missing stage",
                  {"used": num("11_stage_exclusions.csv", "orders_used", "Orders used for stage medians"),
                   "timed": num("11_stage_exclusions.csv", "timed_orders", "Orders with a delivery date"),
                   "negative": num("11_stage_exclusions.csv", "excluded_negative_stage", "Excluded: negative stage"),
                   "missing": num("11_stage_exclusions.csv", "excluded_missing_stage_only", "Excluded: missing stage")},
                  "stage exclusions"),
        ],
        "F3": [
            fanout("v_order_review", "1 review per order"),
            check(total("12_by_delay_bucket.csv", "orders") == Decimal(str(reviewed["value"])),
                  "Review groups add up to {n} reviewed orders", {"n": reviewed}, "review groups"),
            check(int(timing["before delivery"]["orders"]) + int(timing["on or after delivery"]["orders"])
                  == f["F3"]["key_numbers"]["late_reviewed_orders"]["value"],
                  "Late orders reviewed before ({before}) and after ({after}) delivery add up to {late}",
                  {"before": num("12_review_timing.csv", "orders", "Late, reviewed before delivery", where={"delivery_group": "late", "review_timing": "before delivery"}),
                   "after": num("12_review_timing.csv", "orders", "Late, reviewed on or after delivery", where={"delivery_group": "late", "review_timing": "on or after delivery"}),
                   "late": f["F3"]["key_numbers"]["late_reviewed_orders"]},
                  "late review split"),
        ],
        "F4": [
            fanout("v_seller_orders", "1 row per order and seller"),
            check(total("13_seller_revenue_rank.csv", "revenue") == Decimal(str(revenue["value"])),
                  "Seller revenue adds back to {revenue} BRL", {"revenue": revenue}, "seller revenue"),
            check(Decimal(rank_rows[-1]["cumulative_share_pct"]) == 100 and len(rank_rows) == f["F4"]["key_numbers"]["active_sellers"]["value"],
                  "The curve reaches 100% at the last of {n} sellers", {"n": f["F4"]["key_numbers"]["active_sellers"]},
                  "curve end"),
            check(all(curve_matches(r) for r in conc),
                  "The curve matches the top 1%, 5%, 10% and 20% shares from the concentration query", {},
                  "curve vs concentration"),
        ],
        "F5": [
            fanout("v_order_lines", "1 row per order item"),
            check(total("14_monthly_revenue.csv", "revenue") == Decimal(str(revenue["value"])),
                  "Monthly revenue adds back to {revenue} BRL", {"revenue": revenue}, "monthly revenue"),
            check(total("14_monthly_revenue.csv", "orders") == Decimal(str(delivered["value"])),
                  "Monthly orders add up to {n} delivered orders", {"n": delivered}, "monthly orders"),
            check(total("14_freight_by_value_quartile.csv", "orders") == Decimal(str(delivered["value"])),
                  "Freight quartiles hold all {n} delivered orders", {"n": delivered}, "freight quartiles"),
        ],
    }
    if fails:
        sys.exit("ERROR: funnel checks failed: " + ", ".join(fails))
    print(f"  checks: {sum(len(v) for v in out.values())} funnel checks passed")
    return out


def pipelines_rows(finding):
    return find_rows("15_pipelines.csv", {"finding": finding})


# -----------------------------------------------------------------------------
# SQL text helpers: query extraction, section detection
# -----------------------------------------------------------------------------
HEADER_START = re.compile(r"^-- (Q\d+[a-z]?\.|BUILDING BLOCK|FAN-OUT CHECKS)")


def extract_query(sql_file, qid):
    """Text of one query block: from its '-- ====' header line to the line
    before the next header block (a '-- ====' or '-- ----' line followed by
    '-- Qn.', 'BUILDING BLOCK' or 'FAN-OUT CHECKS')."""
    lines = (SQL_DIR / sql_file).read_text(encoding="utf-8").splitlines()
    head = next((i for i, l in enumerate(lines) if l.startswith(f"-- {qid}. ")), None)
    if head is None:
        sys.exit(f"ERROR: query {qid} not found in {sql_file}")
    start = head - 1
    end = len(lines)
    for i in range(head + 1, len(lines) - 1):
        if (lines[i].startswith("-- ====") or lines[i].startswith("-- ----")) and HEADER_START.match(lines[i + 1]):
            end = i
            break
    return "\n".join(lines[start:end]).rstrip() + "\n"


SECTION_PATTERNS = [
    re.compile(r"^-- (Q\d+[a-z]?[.:] .*)$"),
    re.compile(r"^-- (BUILDING BLOCK.*)$"),
    re.compile(r"^-- (FAN-OUT CHECKS.*)$"),
    re.compile(r"^-- (v_\w+)\s*$"),
    re.compile(r"^-- (\d+[a-z]?\. .*)$"),          # 02_data_quality.sql numbering
    re.compile(r"^-- -+ (\d+\. .*)$"),             # 04_baseline.sql "-- ---- 1. Orders by status"
]


def code_lines_with_sections(sql_file):
    """(section, code_without_comment) for every line of a SQL file."""
    section = "(file header)"
    for line in (SQL_DIR / sql_file).read_text(encoding="utf-8").splitlines():
        for p in SECTION_PATTERNS:
            m = p.match(line)
            if m:
                section = m.group(1).strip()
                break
        code = line.split("--", 1)[0]
        yield section, code


# -----------------------------------------------------------------------------
# queries.json
# -----------------------------------------------------------------------------
QUERY_SPECS = [
    {
        "finding": "F1", "file": "10_retention_cohorts.sql", "query": "Q3",
        "result": "10_same_day_check.csv",
        "annotations": [
            ("FROM delivered_customers;", "One row per customer: delivered_customers collapses each customer's delivered orders, with the date of the first return on a LATER day (MIN(purchased_at) FILTER (WHERE purchase_date > first_purchase_date))."),
            ("(SELECT COUNT(*) FROM second_orders WHERE days_to_second = 0)", "Second orders on the same calendar day as the first; days_to_second comes from LAG over the customer's delivered orders."),
            ("COUNT(*) FILTER (WHERE delivered_orders >= 2)                          AS repeat_customers_any_day", "Any-day repeat: two or more delivered orders, even if placed minutes apart."),
            ("COUNT(*) FILTER (WHERE first_later_day_return_at IS NOT NULL)          AS repeat_customers_later_day", "Later-day repeat (decision C12): at least one delivered order on a later calendar day."),
        ],
    },
    {
        "finding": "F2", "file": "11_delivery_performance.sql", "query": "Q6",
        "result": "11_seller_handling.csv",
        "annotations": [
            ("OR latest_shipping_limit IS NULL", "Orders without a carrier date can't be judged, so they get their own group instead of being silently dropped."),
            ("WHEN order_delivered_carrier_date > latest_shipping_limit THEN 'after limit'", "Late handover: the carrier received the order after the seller's latest shipping deadline."),
            ("ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)", "Share of orders: the group count divided by the grand total, a window SUM over the grouped counts."),
            ("ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2)", "Late-delivery rate inside each handover group (calendar-day rule)."),
        ],
    },
    {
        "finding": "F3", "file": "12_review_drivers.sql", "query": "Q8",
        "result": "12_review_timing.csv",
        "annotations": [
            ("CASE WHEN review_creation_date::date < order_delivered_customer_date::date", "Review created on a calendar day before the parcel arrived."),
            ("ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY is_late), 2)", "PARTITION BY is_late makes the share add up to 100% within on-time and within late orders separately."),
            ("ROUND(100.0 * AVG(is_low_review), 2)", "is_low_review is 1 for a 1-2 star review and 0 otherwise, so its average is the low-review share."),
            ("WHERE has_delivery_timing", "Only delivered orders with a delivery date can be compared with the review date."),
        ],
    },
    {
        "finding": "F4", "file": "13_seller_scorecard.sql", "query": "Q1",
        "result": "13_concentration.csv",
        "annotations": [
            ("ROW_NUMBER() OVER (ORDER BY revenue DESC, seller_id)", "Rank sellers by revenue, biggest first; seller_id breaks ties so the ranking is always the same."),
            ("ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)", "Running total: revenue of every seller from rank 1 down to this one."),
            ("FROM (VALUES (1), (5), (10), (20)) AS p(top_pct)", "A four-row inline table of the cut-offs to report."),
            ("ON r.revenue_rank = CEIL(r.total_sellers * p.top_pct / 100.0);", "Read the cumulative share at the last seller inside each top p%."),
        ],
    },
    {
        "finding": "F5", "file": "14_revenue_rfm.sql", "query": "Q1",
        "result": "14_yoy_jan_aug.csv",
        "annotations": [
            ("LAG(revenue) OVER (ORDER BY purchase_month)                        AS prev_month_revenue", "LAG puts the previous month's revenue on each row for the month-over-month change."),
            ("COUNT(*)        FILTER (WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS orders_2017", "FILTER counts only Jan-Aug 2017 orders in the same pass that counts 2018."),
            ("ROUND(100.0 * (revenue_2018 - revenue_2017) / revenue_2017, 2)                      AS revenue_change_pct", "Year-on-year revenue change over the same eight months."),
            ("/ (revenue_2017 / orders_2017), 2)                                            AS aov_change_pct", "Average order value change: shows whether growth came from bigger orders or more orders."),
        ],
    },
]


def build_queries():
    out = []
    for spec in QUERY_SPECS:
        text = extract_query(spec["file"], spec["query"])
        lines = text.splitlines()
        notes = []
        for needle, note in spec["annotations"]:
            hits = [i for i, l in enumerate(lines) if needle in l]
            if not hits:
                sys.exit(f"ERROR: annotation line not found in {spec['file']} {spec['query']}: {needle!r}")
            notes.append({"line_number": hits[0] + 1, "line": lines[hits[0]].strip(), "note": note})
        result_rows = read_csv(spec["result"])
        out.append({
            "finding": spec["finding"],
            "file": f"sql/{spec['file']}",
            "query": spec["query"],
            "title": next(l for l in lines if l.startswith(f"-- {spec['query']}. "))[3:],
            "sql": text,
            "annotations": notes,
            "result": {
                "file": f"results/{spec['result']}",
                "columns": list(result_rows[0].keys()),
                # Kept as the exact CSV text (e.g. "21.10", not 21.1): this is a
                # preview of query output, shown verbatim.
                "rows": [dict(r) for r in result_rows[:5]],
                "total_rows": len(result_rows),
            },
        })
    return {"queries": out}


# -----------------------------------------------------------------------------
# techniques.json
# -----------------------------------------------------------------------------
TECHNIQUES = [
    ("CTE", "WITH name AS (...) names a step of the query so it reads top to bottom.",
     [r"\bWITH\s+\w+\s+AS\s*\(", r"^\s*\w+\s+AS\s*\(\s*$"]),
    ("ROW_NUMBER", "Numbers rows within a group: order sequence per customer, rank per seller, latest review per order.",
     [r"ROW_NUMBER\s*\(\s*\)"]),
    ("LAG", "Reads the previous row's value: time since the previous order, month-over-month change.",
     [r"\bLAG\s*\("]),
    ("NTILE", "Splits rows into equal-sized groups: value quartiles, RFM scores, handover quartiles.",
     [r"\bNTILE\s*\("]),
    ("PERCENTILE_CONT", "Exact median and percentiles (interpolated) instead of averages that outliers distort.",
     [r"percentile_cont\s*\("]),
    ("Running SUM", "SUM(...) OVER (ORDER BY ...) for cumulative shares (concentration curves, top-N category share).",
     [r"ROWS\s+BETWEEN\s+UNBOUNDED\s+PRECEDING", r"SUM\s*\([^()]*\)\s+OVER\s*\(\s*ORDER\s+BY"]),
    ("FILTER", "COUNT(*) FILTER (WHERE ...) computes several conditional counts in one pass.",
     [r"FILTER\s*\(\s*WHERE"]),
    ("Cohort matrix", "Customers or sellers grouped by first month, tracked by months since; unobservable cells left NULL.",
     [r"\bmonths_since\b", r"first_sale_month\s*\+\s*INTERVAL"]),
    ("Fan-out check", "Row count = distinct grain keys = expected count, for every clean view.",
     [r"\bfanout_check\b"]),
    ("DO-block assertion", "A PL/pgSQL DO block that RAISEs an exception, stopping the script when a check fails.",
     [r"RAISE\s+EXCEPTION"]),
]


def build_techniques(queries):
    files = sorted(p.name for p in SQL_DIR.glob("*.sql"))
    out = []
    def code_only(sql):
        return "\n".join(l.split("--", 1)[0] for l in sql.splitlines())
    for name, desc, patterns in TECHNIQUES:
        regs = [re.compile(p, re.IGNORECASE) for p in patterns]
        # Chapters whose "View SQL" panel shows a query using this technique,
        # so "See it used" only ever opens a panel where it is visible.
        chapters = [q["finding"] for q in queries["queries"] if any(r.search(code_only(q["sql"])) for r in regs)]
        uses = []
        for f in files:
            for section, code in code_lines_with_sections(f):
                if any(r.search(code) for r in regs):
                    use = {"file": f"sql/{f}", "section": section}
                    if use not in uses:
                        uses.append(use)
        if not uses:
            sys.exit(f"ERROR: technique {name} not found in any SQL file")
        out.append({"technique": name, "description": desc, "chapters": chapters, "uses": uses})
    return {"techniques": out}


# -----------------------------------------------------------------------------
# schema.json (parsed from 00_schema.sql and 03_clean_views.sql)
# -----------------------------------------------------------------------------
def grain_text(before):
    """The last '-- GRAIN:' comment before a view, joined across lines until
    its sentence ends (e.g. v_orders' grain runs onto a second line)."""
    lines = before.splitlines()
    i = max(k for k, l in enumerate(lines) if l.startswith("-- GRAIN: "))
    text = lines[i][len("-- GRAIN: "):].strip()
    while not text.endswith(".") and i + 1 < len(lines) and lines[i + 1].startswith("-- ") and lines[i + 1][3:].strip():
        i += 1
        text += " " + lines[i][3:].strip()
    return text


def build_schema():
    counts = {r["name"]: to_number(r["row_count"]) for r in read_csv("15_table_counts.csv")}
    text = (SQL_DIR / "00_schema.sql").read_text(encoding="utf-8")
    tables, relationships = [], []
    for m in re.finditer(r"CREATE TABLE (\w+) \((.*?)\n\);", text, re.S):
        name, body = m.group(1), m.group(2)
        columns, pk = [], []
        for raw in body.splitlines():
            line = raw.split("--", 1)[0].strip().rstrip(",")
            if not line:
                continue
            comp = re.match(r"PRIMARY KEY \(([^)]*)\)", line)
            if comp:
                pk = [c.strip() for c in comp.group(1).split(",")]
                continue
            cm = re.match(r"(\w+)\s+(.+)", line)
            if not cm:
                continue
            col, rest = cm.group(1), cm.group(2)
            ctype = re.match(r"([a-z]+(?:\s+precision)?(?:\(\d+(?:,\d+)?\))?)", rest).group(1)
            columns.append({"name": col, "type": ctype})
            if "PRIMARY KEY" in rest:
                pk = [col]
            ref = re.search(r"REFERENCES (\w+) \((\w+)\)", rest)
            if ref:
                relationships.append({"from": f"{name}.{col}", "to": f"{ref.group(1)}.{ref.group(2)}",
                                      "kind": "foreign key"})
        tables.append({"name": name, "kind": "table", "primary_key": pk,
                       "row_count": counts.get(name), "columns": columns})

    vtext = (SQL_DIR / "03_clean_views.sql").read_text(encoding="utf-8")
    views = []
    known = set(counts)
    # A view ends at the first ';' that closes its line (a trailing
    # '-- comment' after the ';' is allowed).
    for m in re.finditer(r"CREATE VIEW (\w+) AS(.*?);[ \t]*(?:--[^\n]*)?\n", vtext, re.S):
        name, body = m.group(1), m.group(2)
        before = vtext[: m.start()]
        grain = grain_text(before)
        code = "\n".join(l.split("--", 1)[0] for l in body.splitlines())
        sources = sorted({s for s in re.findall(r"\b(?:FROM|JOIN)\s+(\w+)", code) if s in known and s != name})
        views.append({"name": name, "kind": "view", "grain": grain,
                      "row_count": counts.get(name), "built_from": sources})
        for s in sources:
            relationships.append({"from": name, "to": s, "kind": "built from"})
    return {"source": "parsed from sql/00_schema.sql and sql/03_clean_views.sql; row counts from results/15_table_counts.csv",
            "tables": tables, "views": views, "relationships": relationships}


# -----------------------------------------------------------------------------
# map_arcs.json and quality.json
# -----------------------------------------------------------------------------
def build_map():
    rows = read_csv("15_map_arcs_sample.csv")
    columns = list(rows[0].keys())
    return {
        "source": "results/15_map_arcs_sample.csv (sql/15_site_support.sql, Q5)",
        "sample_rule": "Delivered in-window single-seller orders with a delivery date and coordinates inside Brazil; "
                       "first 3,000 by md5(order_id). Coordinates are zip-prefix centres rounded to 3 decimals.",
        "columns": columns,
        "rows": [[to_number(r[c]) for c in columns] for r in rows],
    }


def build_quality():
    first = json.loads(SITE_COPY.read_text(encoding="utf-8"))["under_the_hood"]["quality"]["first"]
    rows = read_csv("15_quality_issues.csv")
    ids = [r["issue_id"] for r in rows]
    if any(f not in ids for f in first):
        sys.exit(f"ERROR: site_copy under_the_hood.quality.first names unknown issues: {first}")
    rows = sorted(rows, key=lambda r: first.index(r["issue_id"]) if r["issue_id"] in first else len(first))
    return {
        "source": "results/15_quality_issues.csv (sql/15_site_support.sql, Q4); decisions detailed in docs/data_quality_notes.md",
        "issues": [{
            "id": r["issue_id"],
            "issue": r["issue"],
            "affected": to_number(r["affected"]),
            "unit": r["unit"],
            "decision_ref": r["decision_ref"],
            "decision": r["decision"],
        } for r in rows],
    }


# -----------------------------------------------------------------------------
# VERIFY: every number in findings.json and kpis.json traces to a CSV cell
# -----------------------------------------------------------------------------
TEMPLATE_PAIRS = [
    ("headline_template", "headline", "key_numbers"),
    ("title_template", "title", "title_numbers"),
    ("text_template", "text", "numbers"),
]


def verify(obj, path, errors, literal_uses):
    if isinstance(obj, dict) and obj.get("verified_by") == "docs/findings.md number check":
        return                                   # text parsed from findings.md; check_markdown covers it
    if isinstance(obj, dict):
        if "derived" in obj and "value" in obj:                       # rounded from a sourced number
            src = obj["derived"]["from"]
            verify(src, f"{path}.derived.from", errors, literal_uses)
            want = int(Decimal(str(src["value"])).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
            if obj["value"] != want or obj["display"] != f"{want:,}":
                errors.append(f"{path}: derived value {obj['value']!r} != round({src['value']})")
            check_text(obj.get("label", ""), f"{path}.label", errors, literal_uses)
            return
        if isinstance(obj.get("source"), dict) and "value" in obj:  # a sourced number
            src = obj["source"]
            rows = find_rows(Path(src["file"]).name, src["where"])
            if len(rows) != 1:
                errors.append(f"{path}: source matched {len(rows)} rows")
                return
            csv_text = rows[0][src["column"]]
            if not same_number(obj["value"], csv_text):
                errors.append(f"{path}: value {obj['value']} != CSV {csv_text}")
            shown = re.sub(r"[,%]| pp$", "", obj["display"]).strip()
            if not same_number(shown, csv_text):
                errors.append(f"{path}: display {obj['display']!r} != CSV {csv_text}")
            check_text(obj.get("label", ""), f"{path}.label", errors, literal_uses)
            return
        if isinstance(obj.get("source"), dict) and "rows" in obj:   # chart rows
            src = obj["source"]
            expect = find_rows(Path(src["file"]).name, src["where"])
            if len(expect) != len(obj["rows"]):
                errors.append(f"{path}: {len(obj['rows'])} rows vs {len(expect)} in CSV")
            for i, (got, exp) in enumerate(zip(obj["rows"], expect)):
                for c in src["columns"]:
                    g, e = got[c], exp[c]
                    ok = (g is None and e == "") or (isinstance(g, str) and g == e) or \
                         (isinstance(g, bool) and g == (e == "t")) or \
                         (isinstance(g, (int, float)) and not isinstance(g, bool) and same_number(g, e))
                    if not ok:
                        errors.append(f"{path}.rows[{i}].{c}: {g!r} != CSV {e!r}")
            for k in ("title", "x", "y"):
                check_text(obj.get(k, ""), f"{path}.{k}", errors, literal_uses)
            return
        # Rendered text must equal its template filled with sourced numbers;
        # the template itself may only contain listed literal digits.
        rendered_keys = set()
        for tpl_key, out_key, nums_key in TEMPLATE_PAIRS:
            if tpl_key in obj:
                if render(obj[tpl_key], obj[nums_key]) != obj[out_key]:
                    errors.append(f"{path}.{out_key}: does not match its template and sourced numbers")
                check_text(obj[tpl_key], f"{path}.{tpl_key}", errors, literal_uses)
                rendered_keys.update({tpl_key, out_key})
        for k, v in obj.items():
            if k in rendered_keys or k == "source":
                continue
            verify(v, f"{path}.{k}", errors, literal_uses)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            verify(v, f"{path}[{i}]", errors, literal_uses)
    elif isinstance(obj, bool) or obj is None:
        pass
    elif isinstance(obj, (int, float)):
        errors.append(f"{path}: number {obj} has no source")
    elif isinstance(obj, str):
        check_text(obj, path, errors, literal_uses)


def check_text(text, path, errors, literal_uses):
    """Digits in hand-written text are allowed only as listed literals (or as
    dates / placeholders)."""
    stripped = re.sub(r"\{\w+\}", "", text)                         # template placeholders
    stripped = re.sub(r"\d{4}-\d{2}-\d{2}", "", stripped)           # ISO dates
    for tok in re.findall(r"(?<![\w.])\d+(?:\.\d+)?(?![\w])", stripped):
        if tok in LABEL_LITERALS:
            literal_uses.add(tok)
        else:
            errors.append(f"{path}: literal number {tok!r} in text is not sourced")


def sourced_values(obj, acc):
    """Collect every sourced value (for the findings.md check)."""
    if isinstance(obj, dict):
        if isinstance(obj.get("source"), dict) and "value" in obj:
            acc.add(Decimal(str(obj["value"])))
        for v in obj.values():
            sourced_values(v, acc)
    elif isinstance(obj, list):
        for v in obj:
            sourced_values(v, acc)
    return acc


# Numbers allowed in docs/findings.md that are NOT results: thresholds,
# years, test-design parameters chosen for the recommendations.
MD_ALLOWED = {
    "1": "label (1-2 star, top 1%, quartile 1)", "2": "label (1-2 star, 2x, 2+ orders)",
    "3": "label (score 3, recency 3-4)", "4": "label (quartile 4, score 4) / test design: weeks",
    "5": "label (4-5 star)", "6": "label (1-6 days early)", "7": "label (7+ days early)",
    "8": "label (8+ days late) / test design: weeks",
    "10": "label (top 10%)", "20": "label (top 20%)", "30": "threshold (30+ orders, >30% freight)",
    "50": "threshold (>50% freight)", "500": "threshold (500+ orders)", "0.01": "threshold (payment mismatch)",
    "90": "window (90 days)", "180": "window (180 days)",
    "2016": "year", "2017": "year", "2018": "year",
    "12": "test design: weeks",
}


def check_markdown(allowed_values):
    """Every number in docs/findings.md must be a sourced value or an allowed
    literal. Returns the literals used so they can be reported."""
    if not FINDINGS_MD.exists():
        return ["docs/findings.md not found"], set()
    errors, used = [], set()
    text = FINDINGS_MD.read_text(encoding="utf-8")
    text = re.sub(r"\d{4}-\d{2}-\d{2}", "", text)                   # ISO dates
    for lineno, line in enumerate(text.splitlines(), 1):
        line = re.sub(r"^\s*\d+\.\s", "", line)                    # numbered-list markers
        for tok in re.findall(r"(?<![\w.\-])-?\d[\d,]*(?:\.\d+)?(?![\w])", line):
            clean = tok.replace(",", "")
            if clean in MD_ALLOWED:
                used.add(clean)
                continue
            try:
                d = Decimal(clean)
            except InvalidOperation:
                continue
            if d not in allowed_values:
                errors.append(f"docs/findings.md line {lineno}: {tok} is not a sourced value")
    return errors, used


# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
def write(name, data):
    path = OUT / name
    path.write_text(json.dumps(data, indent=None if name == "map_arcs.json" else 2,
                               separators=(",", ":") if name == "map_arcs.json" else None,
                               ensure_ascii=False) + "\n", encoding="utf-8")
    return path.stat().st_size


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print("Building site data from results/ and sql/ ...")
    kpis = build_kpis()
    findings = build_findings()
    md_recs = parse_md_recommendations()
    for r in findings["recommendations"]:
        r["details"] = md_recs[r["id"]]
    site = build_site(kpis, findings)
    pipelines = build_pipelines()
    pipelines["checks"] = build_checks(findings)
    # Chart rows and chart copy go to their own file, read only by the
    # lazily loaded chart code, so they stay out of the main bundle.
    charts = site.pop("charts")
    charts["source"] = "chart rows copied from results/*.csv (each chart lists its file, columns and row filter)"
    charts["data"] = {f["id"]: f.pop("charts") for f in findings["findings"]}
    queries = build_queries()
    techniques = build_techniques(queries)
    schema = build_schema()
    map_arcs = build_map()
    map_meta = build_map_meta()
    quality = build_quality()

    # ---- the number check (findings.json + kpis.json)
    errors, literal_uses = [], set()
    verify(kpis, "kpis", errors, literal_uses)
    verify(findings, "findings", errors, literal_uses)
    verify(site, "site", errors, literal_uses)
    verify(map_meta, "map", errors, literal_uses)
    verify(pipelines["checks"], "pipelines.checks", errors, literal_uses)
    verify(charts, "charts", errors, literal_uses)
    if errors:
        print("NUMBER CHECK FAILED:")
        for e in errors:
            print("  -", e)
        sys.exit(1)
    n_sourced = len(sourced_values(kpis, set())) + len(sourced_values(findings, set()))
    print(f"  number check passed: every number in kpis/findings/site traces to a CSV cell (kpis, findings, site, map, charts, funnel checks) "
          f"({n_sourced} distinct sourced values); label literals used: {sorted(literal_uses, key=float)}")

    # ---- findings.md check
    allowed = sourced_values(kpis, set()) | sourced_values(findings, set())
    for steps in pipelines["pipelines"].values():
        for s in steps:
            for k in ("row_count", "rows_dropped"):
                if s[k] is not None:
                    allowed.add(Decimal(str(s[k])))
    for q in quality["issues"]:
        allowed.add(Decimal(str(q["affected"])))
    md_errors, md_used = check_markdown(allowed)
    if md_errors:
        print("FINDINGS.MD CHECK FAILED:")
        for e in md_errors:
            print("  -", e)
        sys.exit(1)
    print(f"  findings.md check passed; non-result literals used: "
          f"{', '.join(f'{k} ({MD_ALLOWED[k]})' for k in sorted(md_used, key=float))}")

    # ---- size guard for the map
    sizes = {}
    for name, data in [("site.json", site), ("kpis.json", kpis), ("findings.json", findings), ("charts.json", charts),
                       ("pipelines.json", pipelines),
                       ("queries.json", queries), ("techniques.json", techniques), ("schema.json", schema),
                       ("map_arcs.json", map_arcs), ("map.json", map_meta), ("quality.json", quality)]:
        sizes[name] = write(name, data)
    if sizes["map_arcs.json"] > MAP_MAX_BYTES:
        sys.exit(f"ERROR: map_arcs.json is {sizes['map_arcs.json']} bytes, over the {MAP_MAX_BYTES} limit")
    for name, size in sizes.items():
        print(f"  wrote site/data/{name}  {size:,} bytes")
    print("Done.")


if __name__ == "__main__":
    main()
