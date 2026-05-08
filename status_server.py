#!/usr/bin/env python3
"""Small HTTP status dashboard for Replit-hosted OpenRSC."""

from __future__ import annotations

import html
import http.server
import os
import socketserver
import sqlite3
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "server" / "inc" / "sqlite" / "preservation.db"
HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "5000"))

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30">
<title>OpenRSC Server</title>
<style>
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  min-height: 100vh;
  background: #101214;
  color: #ededed;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}}
header {{
  padding: 28px 20px;
  border-bottom: 1px solid #2f353b;
  background: #171b1f;
}}
h1 {{ margin: 0; color: #f1c84b; font-size: 32px; }}
p {{ color: #b6bec7; line-height: 1.55; }}
.wrap {{ width: min(960px, 100%); margin: 0 auto; padding: 24px 18px 40px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; }}
.card {{
  margin: 0 0 18px;
  padding: 18px;
  border: 1px solid #2f353b;
  border-radius: 8px;
  background: #171b1f;
}}
.metric {{
  padding: 16px;
  border: 1px solid #323a42;
  border-radius: 8px;
  background: #20262b;
}}
.value {{ color: #f1c84b; font-size: 24px; font-weight: 700; }}
.label {{ margin-top: 4px; color: #9fa8b2; font-size: 13px; }}
.ports {{ display: flex; flex-wrap: wrap; gap: 10px; }}
.port {{
  padding: 10px 12px;
  border: 1px solid #6c5c24;
  border-radius: 7px;
  background: #20262b;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}}
table {{ width: 100%; border-collapse: collapse; }}
th, td {{ padding: 10px; border-bottom: 1px solid #2f353b; text-align: left; }}
th {{ color: #f1c84b; font-size: 12px; text-transform: uppercase; }}
footer {{ padding: 24px 18px; color: #707983; text-align: center; font-size: 13px; }}
</style>
</head>
<body>
<header>
  <div class="wrap">
    <h1>OpenRSC</h1>
    <p>RuneScape Classic emulator status dashboard for the Replit workflow.</p>
  </div>
</header>
<main class="wrap">
  <section class="card">
    <div class="grid">
      <div class="metric"><div class="value">{player_count}</div><div class="label">Registered players</div></div>
      <div class="metric"><div class="value">Preservation</div><div class="label">World</div></div>
      <div class="metric"><div class="value">SQLite</div><div class="label">Database</div></div>
      <div class="metric"><div class="value">{db_status}</div><div class="label">Database status</div></div>
    </div>
  </section>
  <section class="card">
    <h2>Connection Ports</h2>
    <div class="ports">
      <div class="port">TCP 43594</div>
      <div class="port">WebSocket 43494</div>
      <div class="port">HTTP {port}</div>
    </div>
  </section>
  <section class="card">
    <h2>Recent Players</h2>
    <table>
      <tr><th>#</th><th>Username</th><th>Combat</th><th>Total</th><th>Last Seen</th></tr>
      {rows}
    </table>
  </section>
</main>
<footer>Auto-refreshes every 30 seconds. Last updated {timestamp} UTC.</footer>
</body>
</html>
"""


def query_players() -> tuple[str, int, list[tuple[str, str, str, str]]]:
    if not DB_PATH.exists():
        return "missing", 0, []

    try:
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM players")
            count = int(cur.fetchone()[0])
            cur.execute(
                "SELECT username, combat, skill_total, login_date "
                "FROM players ORDER BY login_date DESC LIMIT 20"
            )
            rows = []
            for username, combat, total, login_date in cur.fetchall():
                last_seen = "Never"
                if login_date:
                    last_seen = time.strftime("%Y-%m-%d", time.gmtime(login_date))
                rows.append((
                    str(username or "?"),
                    str(combat if combat is not None else "?"),
                    str(total if total is not None else "?"),
                    last_seen,
                ))
            return "ok", count, rows
    except Exception:
        return "error", 0, []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        db_status, player_count, players = query_players()
        rows = []
        for index, (username, combat, total, last_seen) in enumerate(players, 1):
            rows.append(
                "<tr>"
                f"<td>{index}</td>"
                f"<td>{html.escape(username)}</td>"
                f"<td>{html.escape(combat)}</td>"
                f"<td>{html.escape(total)}</td>"
                f"<td>{html.escape(last_seen)}</td>"
                "</tr>"
            )
        if not rows:
            rows.append("<tr><td colspan=\"5\">No players found.</td></tr>")

        page = PAGE.format(
            db_status=html.escape(db_status),
            player_count=player_count,
            port=PORT,
            rows="\n".join(rows),
            timestamp=time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
        ).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((HOST, PORT), Handler) as httpd:
        print(f"Status server running at http://{HOST}:{PORT}")
        httpd.serve_forever()
