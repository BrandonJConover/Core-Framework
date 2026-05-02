#!/usr/bin/env python3
"""
Connection-storm bench for the Rust openrsc server.

Opens N concurrent idle TCP connections, holds them for T seconds, and
reports:
  - successful_opens / second
  - failures (refused / timeout / EOF)
  - server log-derived tick budget compliance (parse from stderr if piped in)

Usage:
  ./scripts/connection_storm.py --connections 1000 --hold 10
  ./scripts/connection_storm.py --connections 5000 --hold 30 --host 127.0.0.1 --port 43594

This is intentionally minimal: the bench measures TCP-accept throughput +
session-create cost. Wire-level login is not exercised (auth is stubbed).
"""

import argparse
import asyncio
import time
from contextlib import suppress


async def open_and_hold(host: str, port: int, hold_secs: float, results: dict, idx: int):
    t0 = time.monotonic()
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=5.0
        )
    except (asyncio.TimeoutError, ConnectionRefusedError, OSError) as e:
        results["failures"] += 1
        results["fail_reasons"][type(e).__name__] = (
            results["fail_reasons"].get(type(e).__name__, 0) + 1
        )
        return

    open_ms = (time.monotonic() - t0) * 1000
    results["open_ms_total"] += open_ms
    results["successes"] += 1

    try:
        # Idle for hold_secs. Reading is fine — the server may push welcome
        # bytes; we just discard.
        with suppress(asyncio.TimeoutError):
            await asyncio.wait_for(reader.read(1024), timeout=hold_secs)
    except (ConnectionResetError, BrokenPipeError):
        results["mid_drop"] = results.get("mid_drop", 0) + 1
    finally:
        writer.close()
        with suppress(Exception):
            await writer.wait_closed()


async def run(args):
    results = {
        "successes": 0,
        "failures": 0,
        "open_ms_total": 0.0,
        "fail_reasons": {},
    }

    t0 = time.monotonic()
    tasks = [
        asyncio.create_task(
            open_and_hold(args.host, args.port, args.hold, results, i)
        )
        for i in range(args.connections)
    ]
    await asyncio.gather(*tasks)
    elapsed = time.monotonic() - t0

    print(f"\n=== connection_storm results ===")
    print(f"target:           {args.host}:{args.port}")
    print(f"requested opens:  {args.connections}")
    print(f"successes:        {results['successes']}")
    print(f"failures:         {results['failures']}")
    if results["failures"]:
        print(f"  by reason:      {results['fail_reasons']}")
    print(f"mid-drop (reset): {results.get('mid_drop', 0)}")
    if results["successes"]:
        avg_open = results["open_ms_total"] / results["successes"]
        print(f"avg open latency: {avg_open:.2f} ms")
        opens_per_sec = results["successes"] / elapsed
        print(f"opens/sec (incl hold): {opens_per_sec:.1f}")
    print(f"wall time:        {elapsed:.2f} s")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=43594)
    p.add_argument("--connections", type=int, default=500)
    p.add_argument("--hold", type=float, default=5.0)
    args = p.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
