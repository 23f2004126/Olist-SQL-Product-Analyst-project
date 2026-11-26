#!/usr/bin/env python3
"""Check that every number in prep/interview_guide.md (outside code blocks)
appears in a results/ file (CSV cell or a number in a psql output .txt), or
is a listed non-result literal (threshold, label, year, design parameter).

Run from the repo root:  python3 prep/check_numbers.py
Exit code 1 if any number is unsourced.
"""
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / "prep" / "interview_guide.md"

# Literals that are not results. Each has a reason.
ALLOWED = {
    "0": "label (p25 = 0 days, months 0-12)", "1": "label", "2": "label", "3": "label", "4": "label",
    "5": "label", "6": "label", "7": "label", "8": "label", "9": "label", "10": "label/threshold",
    "11": "list numbering", "12": "label (months 0-12) / test weeks", "13": "list numbering",
    "15": "label (top 15 categories)", "16": "list numbering", "17": "label (17 orders)",
    "20": "label (top 20%)", "21": "list numbering", "22": "list numbering", "23": "list numbering",
    "24": "design: alert 24 hours before the limit", "30": "threshold (30+ orders)",
    "32": "type length varchar(32)", "10,2": "type numeric(10,2)", "50": "threshold", "80": "concept (80/20)",
    "90": "window (90 days)", "100": "percent base", "100.0": "SQL literal", "180": "window (180 days)",
    "200": "size band", "500": "threshold (500+)", "2000": "distance band", "1000": "distance band",
    "86400": "seconds per day", "0.5": "median p", "0.01": "threshold (one cent)",
    "2016": "year", "2017": "year", "2018": "year",
}

SKIP_FILES = {"13_seller_revenue_rank.csv", "14_rfm_customers.csv", "15_map_arcs_sample.csv", "13_scorecard.csv"}


def numbers_in_results():
    vals = set()
    for p in (ROOT / "results").iterdir():
        if p.name in SKIP_FILES or p.suffix not in (".csv", ".txt"):
            continue
        for tok in re.findall(r"-?\d+(?:\.\d+)?", p.read_text(encoding="utf-8", errors="ignore")):
            try:
                vals.add(Decimal(tok))
            except InvalidOperation:
                pass
    return vals


def main():
    known = numbers_in_results()
    text = GUIDE.read_text(encoding="utf-8")
    text = re.sub(r"```.*?```", "", text, flags=re.S)                 # code blocks
    text = re.sub(r"`[^`]*`", "", text)                              # inline code
    text = re.sub(r"\d{4}-\d{2}-\d{2}( \d{2}:\d{2}:\d{2})?", "", text)  # dates, timestamps
    text = re.sub(r"\b\d{4}-\d{2}\b", "", text)                      # year-month
    bad, literals = [], set()
    for lineno, line in enumerate(text.splitlines(), 1):
        line = re.sub(r"^\s*\d+\.\s", "", line)                      # list numbering
        for tok in re.findall(r"(?<![\w.\-])-?\d[\d,]*(?:\.\d+)?(?![\w])", line):
            clean = tok.replace(",", "")
            if tok in ALLOWED or clean.lstrip("-") in ALLOWED:
                literals.add(tok if tok in ALLOWED else clean.lstrip("-"))
                continue
            try:
                d = Decimal(clean)
            except InvalidOperation:
                continue
            if d not in known and -d not in known:
                bad.append(f"line ~{lineno}: {tok}")
    if bad:
        print("UNSOURCED NUMBERS:")
        print("\n".join("  " + b for b in bad))
        sys.exit(1)
    print(f"All numbers in the guide are in results/ or listed literals. Literals used: {sorted(literals)}")


if __name__ == "__main__":
    main()
