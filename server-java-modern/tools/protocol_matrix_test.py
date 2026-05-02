#!/usr/bin/env python3
"""
Audit the OpenRSC custom-client packet surface against the Java 21 server.

This is intentionally a source-level protocol matrix, not a gameplay script.
It answers the first question before expensive UI automation: every packet
number the maintained Java client can emit should map to a server OpcodeIn,
and gameplay packets should have a PayloadProcessor bound on the server.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path


SERVER_ONLY = {
    "LOGIN",
    "RELOGIN",
    "REGISTER_ACCOUNT",
    "FORGOT_PASSWORD",
    "RECOVERY_ATTEMPT",
    "CHANGE_RECOVERY_REQUEST",
    "CHANGE_DETAILS_REQUEST",
}

PRE_LOGIN_DIRECT = {
    19: "SEND_INITIAL_SERVER_CONFIGS",
}

LIVE_DIFFERENTIAL_OPCODES = {
    0: "custom_login",
    19: "server_configs",
}

NO_PROCESSOR_REQUIRED = SERVER_ONLY | {
    "NPC_DEFINITION_REQUEST",
    "SEND_INITIAL_SERVER_CONFIGS",
}


@dataclass(frozen=True)
class ClientUse:
    opcode: int
    source: str
    line: int
    expression: str


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def parse_custom_parser(path: Path) -> dict[int, str]:
    text = read(path)
    mapping: dict[int, str] = {}
    active_cases: list[int] = []
    in_opcode_switch = False
    depth = 0

    for raw in text.splitlines():
        line = raw.strip()
        if "switch (packet.getID())" in line:
            in_opcode_switch = True
            depth = raw.count("{") - raw.count("}")
            continue
        if not in_opcode_switch:
            continue

        depth += raw.count("{") - raw.count("}")
        if depth <= 0:
            break

        case_match = re.match(r"case\s+(\d+):", line)
        if case_match:
            active_cases.append(int(case_match.group(1)))
            continue

        opcode_match = re.search(r"opcode\s*=\s*OpcodeIn\.([A-Z0-9_]+)", line)
        if opcode_match and active_cases:
            opcode_name = opcode_match.group(1)
            for opcode in active_cases:
                mapping[opcode] = opcode_name
            active_cases = []
            continue

        if line.startswith("break;") or line.startswith("default:"):
            active_cases = []

    # Conflict opcodes are deliberately resolved by packet/player state.
    mapping.setdefault(4, "CAST_ON_INVENTORY_ITEM|FORGOT_PASSWORD")
    mapping.setdefault(8, "DUEL_FIRST_SETTINGS_CHANGED|RECOVERY_ATTEMPT")
    mapping.setdefault(197, "DUEL_DECLINED|CHANGE_RECOVERY_REQUEST")
    mapping.setdefault(247, "GROUND_ITEM_TAKE|CHANGE_DETAILS_REQUEST")
    return mapping


def parse_processor_bindings(path: Path) -> set[str]:
    text = read(path)
    return set(re.findall(r"bind\(OpcodeIn\.([A-Z0-9_]+),", text))


def parse_opcode_enum(path: Path) -> dict[str, int]:
    text = read(path)
    mapping: dict[str, int] = {}
    for name, value in re.findall(r"([A-Z0-9_]+)\((\d+)\)", text):
        mapping[name] = int(value)
    return mapping


def scan_client_uses(client_root: Path, enum_mapping: dict[str, int]) -> list[ClientUse]:
    uses: list[ClientUse] = []
    for path in sorted(client_root.rglob("*.java")):
        text = read(path)

        for match in re.finditer(r"newPacket\((\d+)\)", text):
            uses.append(ClientUse(
                opcode=int(match.group(1)),
                source=str(path),
                line=line_for_offset(text, match.start()),
                expression=match.group(0),
            ))

        for match in re.finditer(r"newPacket\(Opcodes\.Out\.([A-Z0-9_]+)\.getOpcode\(\)\)", text):
            name = match.group(1)
            if name in enum_mapping:
                uses.append(ClientUse(
                    opcode=enum_mapping[name],
                    source=str(path),
                    line=line_for_offset(text, match.start()),
                    expression=match.group(0),
                ))

    deduped: dict[tuple[int, str, int, str], ClientUse] = {}
    for use in uses:
        deduped[(use.opcode, use.source, use.line, use.expression)] = use
    return sorted(deduped.values(), key=lambda u: (u.opcode, u.source, u.line))


def coverage_for_opcode(opcode: int, opcode_name: str | None, bindings: set[str]) -> str:
    if opcode in LIVE_DIFFERENTIAL_OPCODES:
        return "live_differential"
    if opcode_name is None:
        return "unmapped"
    names = opcode_name.split("|")
    if len(names) > 1:
        return "contextual_static"
    if opcode_name in bindings or opcode_name in NO_PROCESSOR_REQUIRED:
        return "static_matrix"
    return "missing_handler"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args()

    repo = args.repo.resolve()
    server = repo / "server-java-modern" / "src" / "com" / "openrsc" / "server"
    client = repo / "Client_Base" / "src"

    custom_mapping = parse_custom_parser(server / "net" / "rsc" / "parsers" / "impl" / "PayloadCustomParser.java")
    custom_mapping.update(PRE_LOGIN_DIRECT)
    bindings = parse_processor_bindings(server / "net" / "rsc" / "PayloadProcessorManager.java")
    client_enum = parse_opcode_enum(client / "orsc" / "net" / "Opcodes.java")
    client_uses = scan_client_uses(client, client_enum)

    used_opcodes = sorted({u.opcode for u in client_uses})
    use_counts = {
        opcode: sum(1 for use in client_uses if use.opcode == opcode)
        for opcode in used_opcodes
    }
    missing_parser = [opcode for opcode in used_opcodes if opcode not in custom_mapping]
    missing_handlers = []
    ambiguous = []

    for opcode in used_opcodes:
        opcode_name = custom_mapping.get(opcode)
        if not opcode_name:
            continue
        names = opcode_name.split("|")
        if len(names) > 1:
            ambiguous.append({"opcode": opcode, "resolves_to": names})
        for name in names:
            if name not in bindings and name not in NO_PROCESSOR_REQUIRED:
                missing_handlers.append({"opcode": opcode, "opcode_in": name})

    client_only_uses = {
        opcode: [asdict(use) for use in client_uses if use.opcode == opcode]
        for opcode in missing_parser
    }
    opcode_statuses = []
    coverage_counts: dict[str, int] = {}
    for opcode in used_opcodes:
        opcode_name = custom_mapping.get(opcode)
        coverage = coverage_for_opcode(opcode, opcode_name, bindings)
        coverage_counts[coverage] = coverage_counts.get(coverage, 0) + 1
        opcode_statuses.append({
            "opcode": opcode,
            "opcode_in": opcode_name,
            "coverage": coverage,
            "send_sites": use_counts[opcode],
            "live_probe": LIVE_DIFFERENTIAL_OPCODES.get(opcode),
        })

    result = {
        "client_unique_opcodes": len(used_opcodes),
        "client_send_sites": len(client_uses),
        "server_custom_parser_opcodes": len(custom_mapping),
        "server_processor_bindings": len(bindings),
        "coverage_counts": coverage_counts,
        "opcode_statuses": opcode_statuses,
        "missing_parser": missing_parser,
        "missing_handlers": missing_handlers,
        "ambiguous_contextual_opcodes": ambiguous,
        "missing_parser_uses": client_only_uses,
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"Client send sites: {result['client_send_sites']}")
        print(f"Client unique opcodes: {result['client_unique_opcodes']}")
        print(f"Server custom parser opcodes: {result['server_custom_parser_opcodes']}")
        print(f"Server processor bindings: {result['server_processor_bindings']}")
        print("Coverage counts:")
        for coverage in sorted(coverage_counts):
            print(f"  {coverage}: {coverage_counts[coverage]}")
        print()
        if missing_parser:
            print("Missing server parser mapping:")
            for opcode in missing_parser:
                print(f"  {opcode}")
                for use in client_only_uses[opcode][:5]:
                    print(f"    {use['source']}:{use['line']} {use['expression']}")
        else:
            print("Missing server parser mapping: none")

        if missing_handlers:
            print("Missing server processor binding:")
            for item in missing_handlers:
                print(f"  {item['opcode']} -> {item['opcode_in']}")
        else:
            print("Missing server processor binding: none")

        if ambiguous:
            print("Contextual opcodes:")
            for item in ambiguous:
                print(f"  {item['opcode']} -> {', '.join(item['resolves_to'])}")

        static_only = [item for item in opcode_statuses if item["coverage"] == "static_matrix"]
        if static_only:
            print("Static-only coverage:")
            for item in static_only[:20]:
                print(f"  {item['opcode']:>3} -> {item['opcode_in']} ({item['send_sites']} send sites)")
            if len(static_only) > 20:
                print(f"  ... {len(static_only) - 20} more")

    return 1 if missing_parser or missing_handlers else 0


if __name__ == "__main__":
    sys.exit(main())
