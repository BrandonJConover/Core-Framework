#!/usr/bin/env python3
from __future__ import annotations

import argparse
import mimetypes
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class RangeRequestHandler(SimpleHTTPRequestHandler):
    def send_common_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Accept-Ranges", "bytes")

    def send_head(self):
        path = Path(self.translate_path(self.path))
        if path.is_dir():
            for index in ("index.html", "index.htm"):
                index_path = path / index
                if index_path.exists():
                    path = index_path
                    break
            else:
                return self.list_directory(str(path))

        if not path.exists():
            self.send_error(404, "File not found")
            return None

        file_size = path.stat().st_size
        range_header = self.headers.get("Range")
        content_type = self.guess_type(str(path))

        if not range_header:
            self.send_response(200)
            self.send_header("Content-type", content_type)
            self.send_header("Content-Length", str(file_size))
            self.send_common_headers()
            self.end_headers()
            return path.open("rb")

        if not range_header.startswith("bytes="):
            self.send_error(416, "Invalid range")
            return None

        start_text, _, end_text = range_header[6:].partition("-")
        try:
            if start_text:
                start = int(start_text)
                end = int(end_text) if end_text else file_size - 1
            else:
                suffix_len = int(end_text)
                start = max(file_size - suffix_len, 0)
                end = file_size - 1
        except ValueError:
            self.send_error(416, "Invalid range")
            return None

        if start < 0 or end < start or start >= file_size:
            self.send_error(416, "Requested range not satisfiable")
            return None

        end = min(end, file_size - 1)
        length = end - start + 1
        f = path.open("rb")
        f.seek(start)
        self.range_remaining = length

        self.send_response(206)
        self.send_header("Content-type", content_type)
        self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Content-Length", str(length))
        self.send_common_headers()
        self.end_headers()
        return f

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "range_remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)

        while remaining > 0:
            chunk = source.read(min(64 * 1024, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the RT4 wrapper spike with HTTP Range support.")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--directory", default=None)
    args = parser.parse_args()

    if args.directory:
        os.chdir(args.directory)

    mimetypes.add_type("application/java-archive", ".jar")
    server = ThreadingHTTPServer((args.host, args.port), RangeRequestHandler)
    print(f"Serving range-capable HTTP on http://{args.host}:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
