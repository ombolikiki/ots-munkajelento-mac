#!/usr/bin/env python3
"""A használati útmutató Markdown forrásából önálló (képekkel együtt hordozható) HTML-t készít.
Használat: docs/build-guide.py <verzió> [kimenet.html]
A támogatott Markdown elemek: címsorok, bekezdés, listák, táblázat, kép (képaláírással), kód, idézet, vonal.
"""
import base64, html, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
version = sys.argv[1] if len(sys.argv) > 1 else "dev"
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "Használati útmutató.html")
src_name = sys.argv[3] if len(sys.argv) > 3 else "HASZNALATI_UTMUTATO.md"   # opcionális: másik Markdown forrás (pl. önálló kisfüzet)
doc_title = sys.argv[4] if len(sys.argv) > 4 else "OTS Munkajelentő Tracker – Használati útmutató"
src = open(os.path.join(here, src_name), encoding="utf-8").read().replace("{{VERZIO}}", version)

def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s

def img_tag(alt, path):
    full = os.path.join(here, path)
    mime = "image/png"
    data = base64.b64encode(open(full, "rb").read()).decode()
    return f'<figure><img alt="{html.escape(alt)}" src="data:{mime};base64,{data}"><figcaption>{html.escape(alt)}</figcaption></figure>'

lines = src.split("\n")
body, toc, i = [], [], 0
def slug(t): return re.sub(r"[^a-z0-9]+", "-", t.lower().encode("ascii", "ignore").decode()).strip("-") or "resz"
n_h2 = 0
while i < len(lines):
    ln = lines[i]
    if not ln.strip():
        i += 1; continue
    if ln.startswith("# "):
        body.append(f"<h1>{inline(ln[2:])}</h1>"); i += 1
    elif ln.startswith("## "):
        n_h2 += 1
        t = ln[3:]
        toc.append((f"r{n_h2}", t))
        body.append(f'<h2 id="r{n_h2}">{inline(t)}</h2>'); i += 1
    elif ln.startswith("### "):
        body.append(f"<h3>{inline(ln[4:])}</h3>"); i += 1
    elif ln.strip() == "---":
        body.append("<hr>"); i += 1
    elif ln.startswith("```"):
        i += 1
        code = []
        while i < len(lines) and not lines[i].startswith("```"):
            code.append(lines[i]); i += 1
        i += 1
        body.append("<pre><code>" + html.escape("\n".join(code), quote=False) + "</code></pre>")
    elif ln.startswith("> "):
        buf = []
        while i < len(lines) and lines[i].startswith("> "):
            buf.append(lines[i][2:]); i += 1
        body.append(f"<blockquote>{inline(' '.join(buf))}</blockquote>")
    elif m := re.match(r"!\[([^\]]*)\]\(([^)]+)\)", ln):
        group = []
        while i < len(lines) and (mm := re.match(r"!\[([^\]]*)\]\(([^)]+)\)", lines[i])):
            group.append(img_tag(mm.group(1), mm.group(2))); i += 1
        body.append(group[0] if len(group) == 1 else '<div class="row">' + "".join(group) + "</div>")
    elif ln.startswith("|"):
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
        head, rest = rows[0], [r for r in rows[2:]]
        t = "<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
        for r in rest:
            t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
        body.append(t + "</tbody></table>")
    elif re.match(r"^\d+\. ", ln):
        items = []
        while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
            items.append(re.sub(r"^\d+\. ", "", lines[i])); i += 1
        body.append("<ol>" + "".join(f"<li>{inline(x)}</li>" for x in items) + "</ol>")
    elif ln.startswith("- "):
        items = []
        while i < len(lines) and lines[i].startswith("- "):
            items.append(lines[i][2:]); i += 1
        body.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in items) + "</ul>")
    else:
        buf = []
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|>|\||- |\d+\. |!\[|---|```)", lines[i]):
            buf.append(lines[i]); i += 1
        body.append(f"<p>{inline(' '.join(buf))}</p>")

toc_html = "<nav><strong>Tartalom</strong><ol>" + "".join(f'<li><a href="#{a}">{inline(re.sub(r"^\d+\. ", "", t))}</a></li>' for a, t in toc) + "</ol></nav>"
# a tartalomjegyzék az első blockquote (összefoglaló) után kerül
idx = next((k for k, b in enumerate(body) if b.startswith("<blockquote")), 1)
body.insert(idx + 1, toc_html)

css = """
html{color-scheme:light}
:root{--ac:#2a6bbd;--ac2:#38a0dc;--bg:#fff;--fg:#1d1d1f;--mut:#6b7280;--card:#f4f6f9;--line:#e3e7ee}
*{box-sizing:border-box}
body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--fg);background:var(--bg);margin:0}
main{max-width:820px;margin:0 auto;padding:40px 24px 80px}
h1{font-size:2rem;line-height:1.2;margin:0 0 .3em;background:linear-gradient(90deg,var(--ac),var(--ac2));-webkit-background-clip:text;background-clip:text;color:transparent}
h2{margin:2.2em 0 .6em;padding-bottom:.3em;border-bottom:2px solid var(--line);font-size:1.45rem}
h3{margin:1.6em 0 .4em;font-size:1.15rem;color:var(--ac)}
p,li{max-width:70ch}
blockquote{margin:1.2em 0;padding:.9em 1.1em;background:var(--card);border-left:4px solid var(--ac);border-radius:0 10px 10px 0}
pre{margin:1em 0;padding:.9em 1.1em;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow-x:auto;page-break-inside:avoid}
pre code{background:none;padding:0;font-size:.88em;white-space:pre}
code{font:.9em ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--card);padding:.1em .35em;border-radius:5px}
table{border-collapse:collapse;width:100%;margin:1em 0;font-size:.94rem;display:block;overflow-x:auto}
th,td{border:1px solid var(--line);padding:.5em .7em;text-align:left;vertical-align:top}
th{background:var(--card)}
figure{margin:1.4em 0;text-align:center}
figure img{background:#f7f7f9;max-width:min(100%,440px);border-radius:14px;box-shadow:0 6px 24px rgba(0,0,0,.15);border:1px solid var(--line)}
figure:has(img[alt*="menüsori ikonok"]) img{max-width:100%}
.row{display:flex;flex-wrap:wrap;gap:14px;justify-content:center;margin:1.2em 0}.row figure{margin:0;flex:1 1 200px;max-width:260px}.row figure img{max-width:100%}
figcaption{font-size:.85rem;color:var(--mut);margin-top:.5em}
nav{background:var(--card);border-radius:12px;padding:.8em 1.2em;margin:1.2em 0}
nav ol{columns:2;margin:.4em 0 0;padding-left:1.3em}
hr{border:0;border-top:1px solid var(--line);margin:2.5em 0 1em}
a{color:var(--ac)}
@media print{h1{background:none;color:var(--ac);-webkit-text-fill-color:var(--ac)}main{padding:0}figure,table,blockquote{break-inside:avoid}h2,h3{break-after:avoid}figure img{max-width:360px}nav ol{columns:2}}
@media (max-width:600px){nav ol{columns:1}}
"""
doc = f"""<!doctype html>
<html lang="hu"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(doc_title)}</title><style>{css}</style></head>
<body><main>{''.join(body)}</main></body></html>"""
open(out, "w", encoding="utf-8").write(doc)
print(f"kész: {out} ({len(doc)//1024} KB)")
