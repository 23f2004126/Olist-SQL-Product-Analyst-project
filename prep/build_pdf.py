#!/usr/bin/env python3
"""Build prep/interview_guide.pdf from prep/interview_guide.md.

Uses the shared converter in scripts/md_to_pdf.py (headless Chrome).
Run from anywhere:  python3 prep/build_pdf.py
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))
from md_to_pdf import build  # noqa: E402

if __name__ == "__main__":
    build(HERE / "interview_guide.md", HERE / "interview_guide.pdf",
          "Olist interview prep", html_out=HERE / "interview_guide.html")
