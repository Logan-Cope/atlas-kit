#!/usr/bin/env python3
"""Render the mission-control dashboard: one static HTML file from the state folder.

Reads missions.json, worklog.jsonl, decisions.jsonl and fleet/*.md. Standard
library only, no JavaScript in the output, so the file opens anywhere and can be
served from GitHub Pages as is.

    python3 bin/build-dashboard.py --state examples/state --out site/index.html
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import pathlib
import re

STATUS_ORDER = ["blocked", "in_progress", "backlog", "done"]
STATUS_LABEL = {
    "blocked": "Blocked",
    "in_progress": "In progress",
    "backlog": "Backlog",
    "done": "Done",
}
FLEET_COLUMNS = ["task", "lane", "model", "owns", "done when", "session", "status", "evidence"]


def esc(value: object) -> str:
    return html.escape(str(value if value is not None else ""), quote=True)


def read_json(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text(errors="replace"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def read_jsonl(path: pathlib.Path) -> list[dict]:
    rows: list[dict] = []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return rows
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue  # one bad line never hides the rest of the log
        if isinstance(row, dict):
            rows.append(row)
    return rows


def parse_ledger(path: pathlib.Path) -> dict:
    """A fleet ledger is markdown: a few header lines, then one task table."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return {"batch": path.stem, "title": path.stem, "tasks": []}
    tasks: list[dict] = []
    header: list[str] | None = None
    for line in text.splitlines():
        if not line.startswith("|"):
            if header is not None and tasks:
                break
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            if cells and cells[0].lower() == "task":
                header = [c.lower() for c in cells]
            continue
        if all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
            continue
        tasks.append(dict(zip(header, cells)))
    lead = next((ln.lstrip("# ").strip() for ln in text.splitlines() if ln.strip()), path.stem)
    return {"batch": path.stem, "title": lead, "tasks": tasks}


def load_state(state: pathlib.Path) -> dict:
    missions = read_json(state / "missions.json").get("missions", [])
    fleet_dir = state / "fleet"
    ledgers = sorted(fleet_dir.glob("*.md"), reverse=True) if fleet_dir.is_dir() else []
    return {
        "missions": [m for m in missions if isinstance(m, dict)],
        "worklog": read_jsonl(state / "worklog.jsonl"),
        "decisions": read_jsonl(state / "decisions.jsonl"),
        "fleet": [parse_ledger(p) for p in ledgers],
    }


def pill(status: str) -> str:
    slug = re.sub(r"[^a-z]+", "-", status.lower()).strip("-") or "unknown"
    return f'<span class="pill pill-{esc(slug)}">{esc(status)}</span>'


def mission_card(m: dict) -> str:
    parts = [
        f'<li class="card"><p class="proj">{esc(m.get("project", ""))}</p>',
        f'<h3>{esc(m.get("title", m.get("id", "")))}</h3>',
    ]
    if m.get("blocker"):
        parts.append(f'<p class="blocker"><strong>Blocked:</strong> {esc(m["blocker"])}</p>')
    if m.get("next_action"):
        parts.append(f'<p class="next"><strong>Next:</strong> {esc(m["next_action"])}</p>')
    parts.append(f'<p class="meta">{esc(m.get("id", ""))} · updated {esc(m.get("updated", ""))}</p></li>')
    return "".join(parts)


def render(data: dict, note: str = "", generated: str = "") -> str:
    missions = data["missions"]
    counts = {s: sum(1 for m in missions if m.get("status") == s) for s in STATUS_ORDER}

    stats = "".join(
        f'<li class="stat stat-{s}"><span class="n">{counts[s]}</span> {STATUS_LABEL[s]}</li>'
        for s in STATUS_ORDER
    )

    columns = []
    for s in STATUS_ORDER:
        items = [m for m in missions if m.get("status") == s]
        items.sort(key=lambda m: str(m.get("updated", "")), reverse=True)
        body = "".join(mission_card(m) for m in items) or '<li class="empty">Nothing here</li>'
        columns.append(
            f'<section class="col col-{s}" aria-labelledby="h-{s}">'
            f'<h2 id="h-{s}">{STATUS_LABEL[s]} <span class="count">{counts[s]}</span></h2>'
            f"<ul>{body}</ul></section>"
        )

    fleet_html = []
    for batch in data["fleet"]:
        rows = []
        for t in batch["tasks"]:
            rows.append(
                "<tr>"
                f'<th scope="row">{esc(t.get("task", ""))}</th>'
                f'<td>{esc(t.get("lane", ""))}</td>'
                f'<td>{esc(t.get("model", ""))}</td>'
                f'<td>{pill(t.get("status", ""))}</td>'
                f'<td class="ev">{esc(t.get("evidence", ""))}</td>'
                "</tr>"
            )
        running = sum(1 for t in batch["tasks"] if t.get("status") in ("running", "launching"))
        fleet_html.append(
            f'<article class="batch"><h3>{esc(batch["batch"])}'
            f' <span class="count">{len(batch["tasks"])} tasks · {running} running</span></h3>'
            '<div class="scroll"><table><thead><tr><th scope="col">Task</th><th scope="col">Lane</th>'
            '<th scope="col">Model</th><th scope="col">Status</th><th scope="col">Evidence</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div></article>'
        )
    if not fleet_html:
        fleet_html.append('<p class="empty">No fleet batches yet.</p>')

    wraps = "".join(
        f'<li><time datetime="{esc(w.get("ts", ""))}">{esc(str(w.get("ts", ""))[:16].replace("T", " "))}</time>'
        f' <span class="proj">{esc(w.get("project", ""))}</span>'
        f' <span class="sum">{esc(w.get("summary", ""))}</span></li>'
        for w in reversed(data["worklog"][-8:])
    ) or '<li class="empty">No wraps yet.</li>'

    decisions = "".join(
        f'<li><p><time datetime="{esc(d.get("ts", ""))}">{esc(str(d.get("ts", ""))[:10])}</time>'
        f' <span class="proj">{esc(d.get("mission", ""))}</span></p>'
        f'<p class="what">{esc(d.get("decision", ""))}</p>'
        + (f'<p class="why">Why: {esc(d["why"])}</p>' if d.get("why") else "")
        + "</li>"
        for d in reversed(data["decisions"][-6:])
    ) or '<li class="empty">No decisions logged.</li>'

    note_html = f'<p class="note">{esc(note)}</p>' if note else ""
    gen_html = f'<p class="gen">Generated {esc(generated)}</p>' if generated else ""

    return TEMPLATE.format(
        stats=stats,
        columns="".join(columns),
        fleet="".join(fleet_html),
        wraps=wraps,
        decisions=decisions,
        note=note_html,
        generated=gen_html,
    )


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Mission control for several Claude Code sessions: open missions, recent wraps, fleet batches and decisions, generated from plain state files.">
<title>Mission control · atlas-kit</title>
<link rel="icon" href="data:,">
<style>
:root {{
  color-scheme: light dark;
  --bg: #f6f5f1; --panel: #ffffff; --ink: #1d1d1b; --muted: #5b5a55; --line: #e2e0d8;
  --blocked: #b42318; --progress: #1f5fbf; --backlog: #6b5d00; --done: #217a3c;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #121311; --panel: #1c1d1a; --ink: #ecebe6; --muted: #a9a79f; --line: #2e2f2b;
    --blocked: #ff8a7a; --progress: #8ab4ff; --backlog: #e2cf5b; --done: #7fd69a;
  }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--ink);
  font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
header, main {{ max-width: 1200px; margin: 0 auto; padding: 0 20px; }}
header {{ padding-top: 28px; }}
h1 {{ font-size: 26px; margin: 0; letter-spacing: -0.01em; }}
h2 {{ font-size: 15px; margin: 0 0 10px; text-transform: uppercase; letter-spacing: 0.06em; }}
h3 {{ font-size: 15px; margin: 2px 0 6px; }}
p {{ margin: 0; }}
.note, .gen {{ color: var(--muted); }}
.stats {{ display: flex; flex-wrap: wrap; gap: 10px; list-style: none; padding: 0; margin: 18px 0 8px; }}
.stat {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 8px 14px; }}
.stat .n {{ font-size: 20px; font-weight: 700; margin-right: 4px; }}
.stat-blocked .n {{ color: var(--blocked); }} .stat-in_progress .n {{ color: var(--progress); }}
.stat-backlog .n {{ color: var(--backlog); }} .stat-done .n {{ color: var(--done); }}
.board {{ display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin: 18px 0 30px; }}
@media (max-width: 900px) {{ .board {{ grid-template-columns: 1fr 1fr; }} }}
@media (max-width: 560px) {{ .board {{ grid-template-columns: 1fr; }} }}
.col ul, .feed {{ list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }}
.col h2 {{ border-top: 4px solid var(--line); padding-top: 8px; }}
.col-blocked h2 {{ border-color: var(--blocked); }} .col-in_progress h2 {{ border-color: var(--progress); }}
.col-backlog h2 {{ border-color: var(--backlog); }} .col-done h2 {{ border-color: var(--done); }}
.count {{ color: var(--muted); font-weight: 400; text-transform: none; letter-spacing: 0; font-size: 13px; }}
.card {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 12px; }}
.card p {{ font-size: 14px; margin-top: 4px; }}
.proj {{ color: var(--muted); font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }}
.blocker strong {{ color: var(--blocked); }}
.meta {{ color: var(--muted); font-size: 12px !important; }}
.empty {{ color: var(--muted); font-style: italic; }}
.lower {{ display: grid; grid-template-columns: 3fr 2fr; gap: 24px; margin-bottom: 40px; }}
@media (max-width: 900px) {{ .lower {{ grid-template-columns: 1fr; }} }}
.lower > *, .board > * {{ min-width: 0; }}
section.panel {{ margin-bottom: 30px; }}
.batch {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 12px; margin-bottom: 12px; }}
.scroll {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; font-size: 14px; }}
th, td {{ text-align: left; padding: 6px 8px; border-top: 1px solid var(--line); vertical-align: top; }}
thead th {{ border-top: 0; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }}
td.ev {{ color: var(--muted); min-width: 220px; }}
tbody th, tbody td:nth-child(2), tbody td:nth-child(3) {{ white-space: nowrap; }}
.pill {{ display: inline-block; border-radius: 999px; padding: 1px 9px; font-size: 12px; font-weight: 600;
  border: 1px solid currentColor; white-space: nowrap; }}
.pill-running, .pill-launching {{ color: var(--progress); }}
.pill-done-verified, .pill-done {{ color: var(--done); }}
.pill-blocked, .pill-partial {{ color: var(--blocked); }}
.pill-plan-ready {{ color: var(--backlog); }}
.feed li {{ background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; font-size: 14px; }}
.feed time {{ color: var(--muted); font-variant-numeric: tabular-nums; margin-right: 6px; }}
.feed .sum {{ display: block; margin-top: 2px; }}
.why {{ color: var(--muted); margin-top: 2px; }}
footer {{ max-width: 1200px; margin: 0 auto; padding: 0 20px 30px; color: var(--muted); font-size: 13px; }}
footer a {{ color: inherit; }}
</style>
</head>
<body>
<header>
<h1>Mission control</h1>
{note}
<ul class="stats" aria-label="Missions by status">{stats}</ul>
</header>
<main>
<div class="board">{columns}</div>
<div class="lower">
<div>
<section class="panel" aria-labelledby="h-fleet"><h2 id="h-fleet">Fleet batches</h2>{fleet}</section>
<section class="panel" aria-labelledby="h-dec"><h2 id="h-dec">Decisions</h2><ul class="feed">{decisions}</ul></section>
</div>
<section class="panel" aria-labelledby="h-wraps"><h2 id="h-wraps">Recently wrapped</h2><ul class="feed">{wraps}</ul></section>
</div>
</main>
<footer>{generated}<p>Built by <a href="https://github.com/Logan-Cope/atlas-kit">atlas-kit</a> from plain state files.</p></footer>
</body>
</html>
"""


def main() -> None:
    home = pathlib.Path(os.environ.get("ATLAS_HOME", pathlib.Path(__file__).resolve().parent.parent))
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--state", type=pathlib.Path,
                    default=pathlib.Path(os.environ.get("ATLAS_STATE", home / "state")))
    ap.add_argument("--out", type=pathlib.Path, default=home / "dashboard" / "index.html")
    ap.add_argument("--note", default="", help="a line shown under the title")
    ap.add_argument("--no-timestamp", action="store_true",
                    help="leave out the generated time, for reproducible output")
    args = ap.parse_args()

    generated = "" if args.no_timestamp else dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    page = render(load_state(args.state), note=args.note, generated=generated)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_name(args.out.name + ".tmp")
    tmp.write_text(page)
    tmp.replace(args.out)
    print(args.out)


if __name__ == "__main__":
    main()
