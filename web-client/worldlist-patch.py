#!/usr/bin/env python3
"""
worldlist-patch.py — Patches rsc-c worldlist.c to point list[0] at a custom server.

Usage:
    python3 worldlist-patch.py \\
        --file /opt/rsc-c/src/ui/worldlist.c \\
        --host game.openrsc.com \\
        --ws-port 43494 \\
        --tcp-port 43594 \\
        --rsa-exp 00010001 \\
        --rsa-mod 87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25
"""

import argparse
import re
import sys


def patch(src: str, host: str, ws_port: int, tcp_port: int, rsa_exp: str, rsa_mod: str) -> str:
    # Patch list[0].host
    src = re.sub(
        r'(strcpy\s*\(\s*list\s*\[\s*0\s*\]\s*\.\s*host\s*,\s*")[^"]*(")',
        f'\\g<1>{host}\\g<2>',
        src
    )

    # Patch list[0].port for the USE_WEBSOCKS branch
    # Pattern: list[0].port = USE_WEBSOCKS ? <ws> : <tcp>;
    src = re.sub(
        r'(list\s*\[\s*0\s*\]\s*\.\s*port\s*=\s*USE_WEBSOCKS\s*\?\s*)\d+(\s*:\s*)\d+(\s*;)',
        f'\\g<1>{ws_port}\\g<2>{tcp_port}\\g<3>',
        src
    )

    # Patch list[0].rsa_exponent
    src = re.sub(
        r'(strcpy\s*\(\s*list\s*\[\s*0\s*\]\s*\.\s*rsa_exponent\s*,\s*")[^"]*(")',
        f'\\g<1>{rsa_exp}\\g<2>',
        src
    )

    # Patch list[0].rsa_modulus
    src = re.sub(
        r'(strcpy\s*\(\s*list\s*\[\s*0\s*\]\s*\.\s*rsa_modulus\s*,\s*")[^"]*(")',
        f'\\g<1>{rsa_mod}\\g<2>',
        src
    )

    return src


def verify(src: str, host: str, ws_port: int, tcp_port: int, rsa_exp: str, rsa_mod: str) -> list[str]:
    missing = []
    checks = {
        "host": host,
        "ws-port": str(ws_port),
        "tcp-port": str(tcp_port),
        "rsa-exp": rsa_exp,
        "rsa-mod": rsa_mod,
    }

    for label, value in checks.items():
        if value not in src:
            missing.append(label)

    return missing


def main():
    parser = argparse.ArgumentParser(description="Patch rsc-c worldlist.c for a custom server")
    parser.add_argument("--file",    default="src/ui/worldlist.c", help="Path to worldlist.c")
    parser.add_argument("--host",    required=True,  help="Server hostname")
    parser.add_argument("--ws-port", type=int, default=43494, help="WebSocket port")
    parser.add_argument("--tcp-port",type=int, default=43594, help="TCP port")
    parser.add_argument("--rsa-exp", default="00010001", help="RSA exponent (hex)")
    parser.add_argument("--rsa-mod", default="87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25", help="RSA modulus (hex)")
    parser.add_argument("--dry-run", action="store_true", help="Print patched file without writing")
    args = parser.parse_args()

    try:
        with open(args.file, "r") as f:
            src = f.read()
    except FileNotFoundError:
        print(f"ERROR: {args.file} not found", file=sys.stderr)
        sys.exit(1)

    patched = patch(src, args.host, args.ws_port, args.tcp_port, args.rsa_exp, args.rsa_mod)
    missing = verify(patched, args.host, args.ws_port, args.tcp_port, args.rsa_exp, args.rsa_mod)

    if missing:
        print(
            "ERROR: worldlist patch verification failed; missing "
            + ", ".join(missing),
            file=sys.stderr,
        )
        sys.exit(1)

    if args.dry_run:
        print(patched)
    else:
        with open(args.file, "w") as f:
            f.write(patched)
        print(f"Patched {args.file}")
        print(f"  host:    {args.host}")
        print(f"  ws-port: {args.ws_port}")
        print(f"  tcp-port:{args.tcp_port}")
        print(f"  rsa-exp: {args.rsa_exp}")
        print(f"  rsa-mod: {args.rsa_mod[:12]}...{args.rsa_mod[-12:]}")


if __name__ == "__main__":
    main()
