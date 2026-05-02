#!/usr/bin/env python3
"""
Compare Java 21 server protocol responses against the Java 8 reference server.

The harness launches both server trees from temporary working directories,
sends identical TCP probes, and compares the raw bytes returned by each server.
It is deliberately small and deterministic so it can grow into a full packet
parity suite one scenario at a time.
"""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import shutil
import signal
import socket
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


REFERENCE_PORT = 45694
CANDIDATE_PORT = 45695
REFERENCE_WS_PORT = 45684
CANDIDATE_WS_PORT = 45685
DIFF_USERNAME = "diffprobe"
DIFF_PASSWORD = "diffpass123"
LOGIN_CAPABILITY_BLOCK = (
    ("h", 0),  # maxAnimationId
    ("i", 0),  # maxItemId
    ("i", 0),  # maxNpcId
    ("i", 0),  # maxSceneryId
    ("h", 0),  # maxPrayerId
    ("h", 0),  # maxSpellId
    ("B", 0),  # maxSkillId
    ("h", 0),  # maxRoofId
    ("h", 0),  # maxTextureId
    ("h", 0),  # maxTileId
    ("i", 0),  # maxBoundaryId
    ("B", 0),  # maxTeleBubbleId
    ("h", 0),  # maxProjectileSprite
    ("i", 0),  # maxSkinColor
    ("i", 0),  # maxHairColor
    ("i", 0),  # maxClothingColor
    ("h", 0),  # maxQuestId
    ("i", 0),  # numberOfSounds
    ("B", 0),  # supportsModSprites
    ("B", 0),  # maxDialogueOptions
    ("i", 0),  # maxBankItems
)
LIVE_PROBE_OPCODES = {
    0: "custom_login",
    19: "server_configs",
}


@dataclass
class ServerProcess:
    name: str
    root: Path
    workdir: Path
    port: int
    process: subprocess.Popen
    log_path: Path


def patch_config(text: str, port: int, ws_port: int) -> str:
    text = text.replace("server_port: 43596", f"server_port: {port}")
    text = text.replace("server_port: 43594", f"server_port: {port}")
    text = text.replace("ws_server_port: 43496", f"ws_server_port: {ws_port}")
    text = text.replace("ws_server_port: 43494", f"ws_server_port: {ws_port}")
    text = text.replace("enforce_custom_client_version: true", "enforce_custom_client_version: false")
    return text


def prepare_workdir(root: Path, temp_root: Path, port: int, ws_port: int) -> Path:
    workdir = temp_root / root.name
    workdir.mkdir(parents=True)

    for name in ("core.jar", "plugins.jar", "lib", "conf", "database", "connections.conf", "globalrules.txt", "client.pem", "server.pem"):
        src = root / name
        if src.exists():
            os.symlink(src, workdir / name)

    if (root / "inc").exists():
        shutil.copytree(root / "inc", workdir / "inc")
        seed_test_player(workdir / "inc" / "sqlite" / "preservation.db")

    conf = root / "preservation.conf"
    (workdir / "local.conf").write_text(
        patch_config(conf.read_text(encoding="utf-8"), port, ws_port),
        encoding="utf-8",
    )
    return workdir


def seed_test_player(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        existing_ids = [
            row["id"]
            for row in conn.execute("select id from players where username = ?", (DIFF_USERNAME,))
        ]
        delete_player_rows(conn, existing_ids)
        next_id = next_player_id(conn)
        insert_default_row(
            conn,
            "players",
            {
                "id": next_id,
                "username": DIFF_USERNAME,
                "pass": DIFF_PASSWORD,
                "salt": "",
                "email": "",
                "group_id": 10,
                "creation_date": int(time.time()),
                "creation_ip": "127.0.0.1",
                "login_date": 0,
                "login_ip": "0.0.0.0",
                "online": 0,
                "banned": "0",
                "muted": "0",
                "former_name": "",
            },
        )

        for table in ("curstats", "maxstats", "experience", "capped_experience"):
            insert_default_row(conn, table, {"playerID": next_id})

        conn.commit()
    finally:
        conn.close()


def delete_player_rows(conn: sqlite3.Connection, player_ids: list[int]) -> None:
    if not player_ids:
        return
    placeholders = ", ".join("?" for _ in player_ids)
    for table, key in (
        ("players", "id"),
        ("curstats", "playerID"),
        ("maxstats", "playerID"),
        ("experience", "playerID"),
        ("capped_experience", "playerID"),
    ):
        conn.execute(f"delete from {table} where {key} in ({placeholders})", player_ids)


def next_player_id(conn: sqlite3.Connection) -> int:
    max_player_id = 0
    for table, key in (
        ("players", "id"),
        ("curstats", "playerID"),
        ("maxstats", "playerID"),
        ("experience", "playerID"),
        ("capped_experience", "playerID"),
    ):
        value = conn.execute(f"select coalesce(max({key}), 0) from {table}").fetchone()[0]
        max_player_id = max(max_player_id, int(value))
    return max_player_id + 1


def insert_default_row(conn: sqlite3.Connection, table: str, overrides: dict[str, object]) -> None:
    columns = list(conn.execute(f"pragma table_info({table})"))
    names = [column["name"] for column in columns]
    values = {name: column_default(column) for name, column in zip(names, columns)}
    values.update(overrides)
    placeholders = ", ".join("?" for _ in names)
    conn.execute(
        f"insert into {table} ({', '.join(names)}) values ({placeholders})",
        [values[name] for name in names],
    )


def column_default(column: sqlite3.Row) -> object:
    default = column["dflt_value"]
    if default is None:
        return None
    default = default.strip()
    if default.startswith("'") and default.endswith("'"):
        return default[1:-1]
    if default.startswith('"') and default.endswith('"'):
        return default[1:-1]
    try:
        return int(default)
    except ValueError:
        try:
            return float(default)
        except ValueError:
            return default


def start_server(
    name: str,
    root: Path,
    workdir: Path,
    port: int,
    classpath_prefix: str | None,
    java_bin: str,
) -> ServerProcess:
    log_path = workdir / f"{name}.log"
    classpath_parts = []
    if classpath_prefix:
        classpath_parts.append(classpath_prefix)
    classpath_parts.extend(["core.jar", "plugins.jar", "lib/*"])
    cmd = [
        java_bin,
        "-DcoloredLogging=false",
        "-cp",
        ":".join(classpath_parts),
        "com.openrsc.server.Server",
    ]
    log = log_path.open("wb")
    process = subprocess.Popen(
        cmd,
        cwd=workdir,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    return ServerProcess(name, root, workdir, port, process, log_path)


def wait_ready(server: ServerProcess, timeout: float = 240.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if server.process.poll() is not None:
            raise RuntimeError(f"{server.name} exited early; log:\n{server.log_path.read_text(errors='replace')[-4000:]}")
        log_text = server.log_path.read_text(errors="replace") if server.log_path.exists() else ""
        try:
            with socket.create_connection(("127.0.0.1", server.port), timeout=0.25):
                if "Game world is now online on TCP port" in log_text:
                    return
        except OSError:
            pass
        time.sleep(0.5)
    raise TimeoutError(f"{server.name} did not listen on {server.port}; log:\n{server.log_path.read_text(errors='replace')[-4000:]}")


def stop_server(server: ServerProcess) -> None:
    if server.process.poll() is not None:
        return
    with contextlib.suppress(ProcessLookupError):
        os.killpg(server.process.pid, signal.SIGTERM)
    try:
        server.process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(server.process.pid, signal.SIGKILL)
        server.process.wait(timeout=5)


def frame(opcode: int, payload: bytes = b"") -> bytes:
    return struct.pack(">H", len(payload) + 1) + bytes([opcode]) + payload


def read_available(sock: socket.socket, idle_timeout: float = 0.4, max_wait: float = 3.0) -> bytes:
    sock.settimeout(idle_timeout)
    out = bytearray()
    deadline = time.time() + max_wait
    while time.time() < deadline:
        try:
            chunk = sock.recv(65535)
        except socket.timeout:
            if out:
                break
            continue
        if not chunk:
            break
        out.extend(chunk)
    return bytes(out)


def probe_server_configs(port: int) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.sendall(frame(19))
        return read_available(sock, idle_timeout=1.0, max_wait=8.0)


def probe_session_id(port: int) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        return read_available(sock, idle_timeout=1.0, max_wait=8.0)


def custom_login_payload(username: str, password: str) -> bytes:
    payload = bytearray()
    payload.append(0)  # reconnecting false
    payload.extend(struct.pack(">I", 10009))
    payload.extend(username.encode("utf-8") + b"\n")
    payload.extend(password.encode("utf-8") + b"\n")
    payload.extend(struct.pack(">Q", 0))
    for fmt, value in LOGIN_CAPABILITY_BLOCK:
        payload.extend(struct.pack(">" + fmt, value))
    payload.extend(b"\n")  # empty mapHash
    payload.extend(struct.pack(">B", 0))  # isAndroidClient false
    return bytes(payload)


def probe_custom_login(port: int, username: str, password: str) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.sendall(frame(0, custom_login_payload(username, password)))
        return read_available(sock, idle_timeout=1.0, max_wait=12.0)


def normalize_server_configs(data: bytes) -> bytes:
    # Server-config payload can include instance-specific RSA material. Keep
    # strict raw data available, but also expose a normalized comparison.
    return data


def normalize_session_id(data: bytes) -> bytes:
    return bytes(len(data))


def hexdump(data: bytes) -> str:
    return data.hex()


def first_diff_offset(reference: bytes, candidate: bytes) -> int | None:
    limit = min(len(reference), len(candidate))
    for index in range(limit):
        if reference[index] != candidate[index]:
            return index
    if len(reference) != len(candidate):
        return limit
    return None


def compare_bytes(name: str, reference: bytes, candidate: bytes, normalize=None) -> dict:
    if normalize is None:
        normalize = lambda data: data
    same = normalize(reference) == normalize(candidate)
    diff = []
    diff_offset = first_diff_offset(reference, candidate)
    if not same:
        diff = list(difflib.unified_diff(
            [hexdump(reference) + "\n"],
            [hexdump(candidate) + "\n"],
            fromfile=f"java8/{name}",
            tofile=f"java21/{name}",
            lineterm="",
        ))
    return {
        "name": name,
        "same": same,
        "reference_len": len(reference),
        "candidate_len": len(candidate),
        "reference_hex": hexdump(reference[:256]),
        "candidate_hex": hexdump(candidate[:256]),
        "first_diff_offset": diff_offset,
        "reference_diff_window": hexdump(reference[diff_offset:diff_offset + 32]) if diff_offset is not None else "",
        "candidate_diff_window": hexdump(candidate[diff_offset:diff_offset + 32]) if diff_offset is not None else "",
        "diff": diff,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--keep-workdirs", action="store_true")
    parser.add_argument("--modern-overlay", type=Path, default=Path("/tmp/orsc-server-overlay"))
    parser.add_argument("--reference-java", default=os.environ.get("JAVA8_BIN", "java"))
    parser.add_argument("--candidate-java", default=os.environ.get("JAVA21_BIN", "java"))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    repo = args.repo.resolve()
    reference_root = repo / "server"
    candidate_root = repo / "server-java-modern"
    temp_root = Path(tempfile.mkdtemp(prefix="orsc-diff-"))
    servers: list[ServerProcess] = []

    try:
        ref_workdir = prepare_workdir(reference_root, temp_root, REFERENCE_PORT, REFERENCE_WS_PORT)
        cand_workdir = prepare_workdir(candidate_root, temp_root, CANDIDATE_PORT, CANDIDATE_WS_PORT)

        overlay = str(args.modern_overlay) if args.modern_overlay.exists() else None
        servers = [
            start_server("java8", reference_root, ref_workdir, REFERENCE_PORT, None, args.reference_java),
            start_server("java21", candidate_root, cand_workdir, CANDIDATE_PORT, overlay, args.candidate_java),
        ]
        for server in servers:
            wait_ready(server)

        scenarios = [
            ("session_id", probe_session_id, normalize_session_id),
            ("server_configs", probe_server_configs, normalize_server_configs),
            ("custom_login_invalid", lambda port: probe_custom_login(port, "_nobody_", "wrongpass"), None),
            ("custom_login_success", lambda port: probe_custom_login(port, DIFF_USERNAME, DIFF_PASSWORD), None),
        ]
        results = []
        for name, probe, normalize in scenarios:
            ref = probe(REFERENCE_PORT)
            cand = probe(CANDIDATE_PORT)
            results.append(compare_bytes(name, ref, cand, normalize=normalize))

        passed = all(result["same"] for result in results)
        output = {
            "passed": passed,
            "reference_port": REFERENCE_PORT,
            "candidate_port": CANDIDATE_PORT,
            "results": results,
            "logs": {server.name: str(server.log_path) for server in servers},
        }

        if args.json:
            print(json.dumps(output, indent=2, sort_keys=True))
        else:
            print(f"Differential protocol test: {'PASS' if passed else 'FAIL'}")
            for result in results:
                status = "same" if result["same"] else "different"
                print(f"- {result['name']}: {status} ({result['reference_len']} vs {result['candidate_len']} bytes)")
                if not result["same"]:
                    print(f"  first diff offset: {result['first_diff_offset']}")
                    print(f"  java8:  {result['reference_hex']}")
                    print(f"  java21: {result['candidate_hex']}")
                    if result["reference_diff_window"] or result["candidate_diff_window"]:
                        print(f"  java8 diff window:  {result['reference_diff_window']}")
                        print(f"  java21 diff window: {result['candidate_diff_window']}")
            print("Logs:")
            for server in servers:
                print(f"- {server.name}: {server.log_path}")

        return 0 if passed else 1
    finally:
        for server in servers:
            stop_server(server)
        if args.keep_workdirs:
            print(f"Kept workdirs in {temp_root}", file=sys.stderr)
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
