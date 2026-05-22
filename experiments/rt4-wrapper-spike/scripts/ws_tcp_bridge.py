#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import socket
import struct
import threading
import time
from typing import BinaryIO


GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def read_exact(stream: BinaryIO, length: int) -> bytes:
    data = bytearray()
    while len(data) < length:
        chunk = stream.read(length - len(data))
        if not chunk:
            raise EOFError("connection closed")
        data.extend(chunk)
    return bytes(data)


def read_http_headers(stream: BinaryIO) -> dict[str, str]:
    raw = bytearray()
    while b"\r\n\r\n" not in raw:
        chunk = stream.read(1)
        if not chunk:
            raise EOFError("connection closed during handshake")
        raw.extend(chunk)
        if len(raw) > 64 * 1024:
            raise ValueError("WebSocket handshake is too large")

    lines = raw.decode("iso-8859-1").split("\r\n")
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if not line or ":" not in line:
            continue
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    return headers


def accept_websocket(client: socket.socket) -> BinaryIO:
    stream = client.makefile("rwb", buffering=0)
    headers = read_http_headers(stream)
    key = headers.get("sec-websocket-key")
    if not key:
        raise ValueError("missing Sec-WebSocket-Key")

    accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest()).decode("ascii")
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n"
        "\r\n"
    )
    stream.write(response.encode("ascii"))
    return stream


def read_ws_frame(stream: BinaryIO) -> tuple[int, bytes]:
    head = read_exact(stream, 2)
    opcode = head[0] & 0x0F
    masked = (head[1] & 0x80) != 0
    length = head[1] & 0x7F

    if length == 126:
        length = struct.unpack("!H", read_exact(stream, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", read_exact(stream, 8))[0]

    mask = read_exact(stream, 4) if masked else b""
    payload = bytearray(read_exact(stream, length))
    if masked:
        for i in range(length):
            payload[i] ^= mask[i % 4]
    return opcode, bytes(payload)


def write_ws_frame(stream: BinaryIO, payload: bytes, opcode: int = 2) -> None:
    first = 0x80 | opcode
    length = len(payload)
    if length < 126:
        header = struct.pack("!BB", first, length)
    elif length <= 0xFFFF:
        header = struct.pack("!BBH", first, 126, length)
    else:
        header = struct.pack("!BBQ", first, 127, length)
    stream.write(header + payload)


def format_preview(data: bytes) -> str:
    return data[:32].hex(" ")


def bridge_client(client: socket.socket, target_host: str, target_port: int, label: str) -> None:
    target: socket.socket | None = None
    stream: BinaryIO | None = None
    client_to_target = 0
    target_to_client = 0
    first_client = True
    first_target = True
    close_reason = "unknown"
    started = time.monotonic()
    try:
        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        stream = accept_websocket(client)
        target = socket.create_connection((target_host, target_port), timeout=10)
        target.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        target.settimeout(None)

        def tcp_to_ws() -> None:
            nonlocal first_target, target_to_client, close_reason
            assert target is not None
            assert stream is not None
            try:
                while True:
                    data = target.recv(16384)
                    if not data:
                        close_reason = "target closed"
                        break
                    target_to_client += len(data)
                    if first_target:
                        first_target = False
                        print(f"[ws-tcp {label}] target->client first {len(data)} bytes: {format_preview(data)}")
                    write_ws_frame(stream, data)
            except Exception as exc:
                close_reason = f"target->client error: {exc}"
            finally:
                try:
                    write_ws_frame(stream, b"", opcode=8)
                except Exception:
                    pass

        thread = threading.Thread(target=tcp_to_ws, daemon=True)
        thread.start()

        while True:
            opcode, payload = read_ws_frame(stream)
            if opcode == 8:
                close_reason = "client closed"
                break
            if opcode == 9:
                write_ws_frame(stream, payload, opcode=10)
                continue
            if opcode in (1, 2):
                client_to_target += len(payload)
                if first_client:
                    first_client = False
                    print(f"[ws-tcp {label}] client->target first {len(payload)} bytes: {format_preview(payload)}")
                target.sendall(payload)
    except Exception as exc:
        close_reason = f"bridge error: {exc}"
        print(f"[ws-tcp {label}] client ended: {exc}")
    finally:
        elapsed = time.monotonic() - started
        print(f"[ws-tcp {label}] closed after {elapsed:.2f}s c2t={client_to_target} t2c={target_to_client} reason={close_reason}")
        for sock in (target, client):
            if sock is None:
                continue
            try:
                sock.close()
            except Exception:
                pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Small WebSocket-to-TCP bridge for local RT4 wrapper testing.")
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=43601)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, default=43595)
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(32)
    print(f"[ws-tcp] ws://{args.listen_host}:{args.listen_port} -> {args.target_host}:{args.target_port}")

    while True:
        client, address = server.accept()
        label = f"{args.listen_port}/{address[0]}:{address[1]}"
        print(f"[ws-tcp {label}] accepted")
        threading.Thread(target=bridge_client, args=(client, args.target_host, args.target_port, label), daemon=True).start()


if __name__ == "__main__":
    main()
