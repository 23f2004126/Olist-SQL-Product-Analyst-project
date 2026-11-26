#!/usr/bin/env python3
"""md_to_pdf.py: convert a Markdown file to PDF.

Converts a plain Markdown subset (headings, nested lists, tables, code
blocks, bold / italic / inline code, rules) to HTML with the standard
library, then prints it to PDF with headless Google Chrome.

Usage:
    python3 scripts/md_to_pdf.py <input.md> <output.pdf> [title]
Example (public case study for the site):
    python3 scripts/md_to_pdf.py docs/findings.md site/public/olist-case-study.pdf "Olist case study"
"""
import html
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = """
@page { size: A4; margin: 16mm 15mm 18mm 15mm; }
body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; font-size: 10.5pt;
       line-height: 1.45; color: #1a1a1a; }
h1 { font-size: 20pt; margin: 0 0 6pt; }
h2 { font-size: 15pt; border-bottom: 1.5px solid #333; padding-bottom: 3pt; margin-top: 0;
     page-break-before: always; }
h2.first { page-break-before: avoid; }
h3 { font-size: 12pt; margin: 14pt 0 4pt; page-break-after: avoid; }
h4 { font-size: 11pt; margin: 10pt 0 3pt; page-break-after: avoid; }
p { margin: 4pt 0; }
ul, ol { margin: 3pt 0 3pt 0; padding-left: 18pt; }
li { margin: 2pt 0; }
code { font-family: Menlo, Consolas, monospace; font-size: 9pt; background: #f2f2f2;
       padding: 0 2pt; border-radius: 2px; }
pre { background: #f5f5f5; border: 1px solid #ddd; border-radius: 3px; padding: 6pt 8pt;
      font-size: 8.6pt; line-height: 1.35; white-space: pre-wrap; page-break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.6pt; }
table { border-collapse: collapse; margin: 6pt 0; font-size: 9.5pt; page-break-inside: avoid; }
th, td { border: 1px solid #bbb; padding: 3pt 6pt; vertical-align: top; }
th { background: #eee; }
td.r, th.r { text-align: right; }
hr { border: none; border-top: 1px solid #ccc; margin: 10pt 0; }
"""


def inline(text):
    """Escape HTML, then apply inline code, bold and italics."""
    codes = []

    def stash(m):
        codes.append(html.escape(m.group(1)))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{codes[int(m.group(1))]}</code>", text)
    return text


def convert(md):
    out = []
    lines = md.splitlines()
    i = 0
    stack = []            # open lists: (indent, tag)
    para = []
    first_h2 = True

    def flush_para():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    def close_lists(to_indent=-1):
        while stack and stack[-1][0] > to_indent:
            _, tag = stack.pop()
            out.append(f"</li></{tag}>")

    while i < len(lines):
        line = lines[i]

        # fenced code block
        if line.strip().startswith("```"):
            flush_para()
            close_lists()
            i += 1
            buf = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            out.append("<pre><code>" + html.escape("\n".join(buf)) + "</code></pre>")
            i += 1
            continue

        # table
        if line.startswith("|"):
            flush_para()
            close_lists()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            header, sep, body = rows[0], rows[1], rows[2:]
            right = [s.endswith(":") for s in sep]
            out.append("<table><thead><tr>" + "".join(
                f'<th class="{"r" if right[k] else ""}">{inline(c)}</th>' for k, c in enumerate(header)) + "</tr></thead><tbody>")
            for r in body:
                out.append("<tr>" + "".join(
                    f'<td class="{"r" if k < len(right) and right[k] else ""}">{inline(c)}</td>' for k, c in enumerate(r)) + "</tr>")
            out.append("</tbody></table>")
            continue

        # headings
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            flush_para()
            close_lists()
            level = len(m.group(1))
            cls = ""
            if level == 2:
                cls = ' class="first"' if first_h2 else ""
                first_h2 = False
            out.append(f"<h{level}{cls}>{inline(m.group(2))}</h{level}>")
            i += 1
            continue

        # horizontal rule
        if line.strip() == "---":
            flush_para()
            close_lists()
            out.append("<hr>")
            i += 1
            continue

        # list item
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if m:
            flush_para()
            indent = len(m.group(1))
            tag = "ol" if m.group(2)[0].isdigit() else "ul"
            close_lists(indent)
            if stack and stack[-1][0] == indent:
                if stack[-1][1] != tag:
                    close_lists(indent - 1)
                    start = f' start="{m.group(2)[:-1]}"' if tag == "ol" else ""
                    out.append(f"<{tag}{start}><li>")
                    stack.append((indent, tag))
                else:
                    out.append("</li><li>")
            else:
                start = f' start="{m.group(2)[:-1]}"' if tag == "ol" and m.group(2) != "1." else ""
                out.append(f"<{tag}{start}><li>")
                stack.append((indent, tag))
            out.append(inline(m.group(3)))
            i += 1
            continue

        # blank line
        if not line.strip():
            flush_para()
            i += 1
            continue

        # indented continuation of a list item
        if stack and line.startswith(" "):
            out.append(" " + inline(line.strip()))
            i += 1
            continue

        # paragraph text
        close_lists()
        para.append(line.strip())
        i += 1

    flush_para()
    close_lists()
    return "\n".join(out)


def page_count(pdf_bytes):
    """Count page objects in the PDF (works for Chrome's uncompressed page tree)."""
    n = len(re.findall(rb"/Type\s*/Page(?![s\w])", pdf_bytes))
    if n:
        return n
    m = re.findall(rb"/Count\s+(\d+)", pdf_bytes)
    return max(int(x) for x in m) if m else None


def build(src, pdf_out, title, html_out=None):
    """Convert src (Markdown) to pdf_out. Returns the page count."""
    src, pdf_out = Path(src), Path(pdf_out)
    body = convert(src.read_text(encoding="utf-8"))
    page = ("<!doctype html><html><head><meta charset='utf-8'>"
            f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body>{body}</body></html>")
    if html_out is None:
        html_out = Path(tempfile.mkdtemp()) / "page.html"
    html_out = Path(html_out)
    html_out.write_text(page, encoding="utf-8")
    pdf_out.parent.mkdir(parents=True, exist_ok=True)
    if pdf_out.exists():
        pdf_out.unlink()
    cmd = [CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
           f"--print-to-pdf={pdf_out.resolve()}", html_out.resolve().as_uri()]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if not pdf_out.exists():
        sys.exit(f"Chrome did not write the PDF:\n{r.stderr}")
    pages = page_count(pdf_out.read_bytes())
    print(f"Wrote {pdf_out} ({pdf_out.stat().st_size:,} bytes, {pages} pages)")
    return pages


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else Path(sys.argv[1]).stem)
