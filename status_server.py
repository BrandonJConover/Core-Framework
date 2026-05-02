#!/usr/bin/env python3
"""Simple HTTP status server for OpenRSC on port 5000."""
import http.server
import socketserver
import sqlite3
import os
import time

DB_PATH = "server/inc/sqlite/preservation.db"
PORT = 5000
HOST = "0.0.0.0"

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="30">
<title>OpenRSC Server</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: 'Segoe UI', Arial, sans-serif; background: #1a1a2e; color: #e0e0e0; min-height: 100vh; }}
.header {{ background: linear-gradient(135deg, #16213e 0%, #0f3460 100%); padding: 30px 20px; text-align: center; border-bottom: 3px solid #e94560; }}
.header h1 {{ font-size: 2.5em; color: #e94560; text-shadow: 0 0 20px rgba(233,69,96,0.5); letter-spacing: 2px; }}
.header p {{ color: #a0a0b0; margin-top: 8px; font-size: 1.1em; }}
.container {{ max-width: 900px; margin: 40px auto; padding: 0 20px; }}
.card {{ background: #16213e; border-radius: 12px; padding: 25px; margin-bottom: 25px; border: 1px solid #0f3460; box-shadow: 0 4px 20px rgba(0,0,0,0.3); }}
.card h2 {{ color: #e94560; margin-bottom: 15px; font-size: 1.3em; }}
.status-badge {{ display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 0.85em; font-weight: bold; margin-left: 10px; }}
.status-online {{ background: #1a4a1a; color: #4caf50; border: 1px solid #4caf50; }}
.info-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-top: 15px; }}
.info-item {{ background: #0f3460; border-radius: 8px; padding: 15px; text-align: center; }}
.info-item .value {{ font-size: 1.8em; font-weight: bold; color: #e94560; }}
.info-item .label {{ color: #a0a0b0; font-size: 0.85em; margin-top: 5px; }}
.port-list {{ display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; }}
.port-tag {{ background: #0f3460; border: 1px solid #e94560; border-radius: 6px; padding: 8px 15px; font-family: monospace; }}
.port-label {{ color: #a0a0b0; font-size: 0.8em; display: block; }}
.port-num {{ color: #e94560; font-size: 1.1em; font-weight: bold; }}
table {{ width: 100%; border-collapse: collapse; margin-top: 10px; }}
th {{ background: #0f3460; color: #e94560; padding: 10px 12px; text-align: left; font-size: 0.85em; text-transform: uppercase; letter-spacing: 0.5px; }}
td {{ padding: 10px 12px; border-bottom: 1px solid #0f3460; font-size: 0.9em; }}
tr:hover td {{ background: rgba(15,52,96,0.5); }}
.footer {{ text-align: center; color: #555; padding: 30px 20px; font-size: 0.85em; }}
</style>
</head>
<body>
<div class="header">
  <h1>OpenRSC</h1>
  <p>RuneScape Classic Emulator &mdash; Preservation World</p>
</div>
<div class="container">
  <div class="card">
    <h2>Server Status <span class="status-badge status-online">Running</span></h2>
    <div class="info-grid">
      <div class="info-item"><div class="value">{player_count}</div><div class="label">Registered Players</div></div>
      <div class="info-item"><div class="value">Preservation</div><div class="label">World Type</div></div>
      <div class="info-item"><div class="value">SQLite</div><div class="label">Database</div></div>
      <div class="info-item"><div class="value">Java 19</div><div class="label">Runtime</div></div>
    </div>
  </div>
  <div class="card">
    <h2>Connection Ports</h2>
    <div class="port-list">
      <div class="port-tag"><span class="port-label">Game TCP (RSC+ / OpenRSC Client)</span><span class="port-num">43594</span></div>
      <div class="port-tag"><span class="port-label">WebSocket (Web Client)</span><span class="port-num">43494</span></div>
      <div class="port-tag"><span class="port-label">Status Page (this page)</span><span class="port-num">5000</span></div>
    </div>
  </div>
  <div class="card">
    <h2>Registered Players ({player_count})</h2>
    <table>
      <tr><th>#</th><th>Username</th><th>Combat Lvl</th><th>Total Lvl</th><th>Last Seen</th></tr>
      {rows}
    </table>
  </div>
  <div class="card">
    <h2>About OpenRSC</h2>
    <p style="color:#a0a0b0; line-height:1.7;">OpenRSC is a RuneScape Classic emulator built through open-source cooperation. This server runs the Preservation world using a SQLite database. Connect using the <strong style="color:#e94560">RSC+</strong> client or the <strong style="color:#e94560">OpenRSC desktop client</strong> on TCP port <strong style="color:#e94560">43594</strong>.</p>
  </div>
</div>
<div class="footer">
  OpenRSC &bull; Open Source RuneScape Classic &bull; Auto-refreshes every 30s &bull; {timestamp}
</div>
</body>
</html>"""


def get_db_info():
    try:
        if not os.path.exists(DB_PATH):
            return 0, []
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM players")
        count = cur.fetchone()[0]
        cur.execute(
            "SELECT username, combat, skill_total, login_date "
            "FROM players ORDER BY login_date DESC LIMIT 20"
        )
        players = cur.fetchall()
        conn.close()
        return count, players
    except Exception:
        return 0, []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        player_count, players = get_db_info()
        ts = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())

        rows = ""
        for i, p in enumerate(players, 1):
            username = p[0] or "?"
            combat = p[1] if p[1] is not None else "?"
            total = p[2] if p[2] is not None else "?"
            login_ts = p[3]
            if login_ts:
                last_seen = time.strftime(
                    "%Y-%m-%d", time.gmtime(login_ts)
                )
            else:
                last_seen = "Never"
            rows += (
                f"<tr><td>{i}</td><td>{username}</td>"
                f"<td>{combat}</td><td>{total}</td><td>{last_seen}</td></tr>"
            )
        if not rows:
            rows = (
                "<tr><td colspan='5' style='text-align:center;color:#555;'>"
                "No players registered yet</td></tr>"
            )

        html = HTML.format(
            player_count=player_count,
            rows=rows,
            timestamp=ts,
        )
        data = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((HOST, PORT), Handler) as httpd:
        print(f"Status server running at http://{HOST}:{PORT}")
        httpd.serve_forever()
