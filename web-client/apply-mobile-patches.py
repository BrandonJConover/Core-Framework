#!/usr/bin/env python3
"""
Apply the mobile-friendly OpenRSC web client shell to a built rsc-c tree.

The Hetzner deployment builds upstream rsc-c in /opt/rsc-c, which regenerates
mudclient.html and mudclient.js. This script reapplies the repo's hardened
mobile shell after the build so iOS/Safari gets the same behavior as the
native app bundle.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


FUNCTION_PATTERNS = {
    "get_window_width": re.compile(r"^function get_window_width\(\) \{.*?\}$", re.MULTILINE),
    "get_window_height": re.compile(r"^function get_window_height\(\) \{.*?\}$", re.MULTILINE),
    "browser_trigger_keyboard": re.compile(
        r"^function browser_trigger_keyboard\(text,is_password,x,y,width,height,font,is_centred,is_scaled\) "
        r"\{.*?\}(?=\nfunction browser_is_touch\(\))",
        re.MULTILINE | re.DOTALL,
    ),
    "instantiateArrayBuffer": re.compile(
        r"^async function instantiateArrayBuffer\(binaryFile, imports\) \{.*?\n\}",
        re.MULTILINE | re.DOTALL,
    ),
}


def apply_webgl_compatibility_patch(js_text: str) -> tuple[str, bool]:
    patched = js_text

    disable_pattern = "var _emscripten_glDisable = (x0) => GLctx.disable(x0);"
    disable_replacement = """var _emscripten_glDisable = (x0) => {
      if (x0 == 0x809D /* GL_MULTISAMPLE */) return;
      GLctx.disable(x0);
    };"""
    patched = patched.replace(disable_pattern, disable_replacement, 1)

    tex_parameter_pattern = "var _emscripten_glTexParameteri = (x0, x1, x2) => GLctx.texParameteri(x0, x1, x2);"
    tex_parameter_replacement = """var _emscripten_glTexParameteri = (x0, x1, x2) => {
      if ((x1 == 0x2802 || x1 == 0x2803) && x2 == 0x2900 /* GL_CLAMP */) {
        x2 = 0x812F; /* GL_CLAMP_TO_EDGE */
      }
      GLctx.texParameteri(x0, x1, x2);
    };"""
    patched = patched.replace(tex_parameter_pattern, tex_parameter_replacement, 1)

    tex_parameteriv_pattern = """  var _emscripten_glTexParameteriv = (target, pname, params) => {
      var param = HEAP32[((params)>>2)];
      GLctx.texParameteri(target, pname, param);
    };"""
    tex_parameteriv_replacement = """  var _emscripten_glTexParameteriv = (target, pname, params) => {
      var param = HEAP32[((params)>>2)];
      if ((pname == 0x2802 || pname == 0x2803) && param == 0x2900 /* GL_CLAMP */) {
        param = 0x812F; /* GL_CLAMP_TO_EDGE */
      }
      GLctx.texParameteri(target, pname, param);
    };"""
    patched = patched.replace(tex_parameteriv_pattern, tex_parameteriv_replacement, 1)

    return patched, patched != js_text


def apply_sockfs_diagnostics_patch(js_text: str) -> tuple[str, bool]:
    patched = js_text

    close_pattern = """            peer.socket.onclose = function() {
              SOCKFS.emit('close', sock.stream.fd);
            };"""
    close_replacement = """            peer.socket.onclose = function(event) {
              try {
                console.warn('[mudclient] SOCKFS WebSocket close fd=' + sock.stream.fd +
                  ' code=' + event.code +
                  ' wasClean=' + event.wasClean +
                  (event.reason ? ' reason=' + event.reason : ''));
              } catch (e) {}
              SOCKFS.emit('close', sock.stream.fd);
            };"""
    patched = patched.replace(close_pattern, close_replacement, 1)

    error_pattern = """            peer.socket.onerror = function(error) {
              // The WebSocket spec only allows a 'simple event' to be thrown on error,
              // so we only really know as much as ECONNREFUSED."""
    error_replacement = """            peer.socket.onerror = function(error) {
              try {
                console.error('[mudclient] SOCKFS WebSocket error fd=' + sock.stream.fd +
                  ' readyState=' + peer.socket.readyState, error);
              } catch (e) {}
              // The WebSocket spec only allows a 'simple event' to be thrown on error,
              // so we only really know as much as ECONNREFUSED."""
    patched = patched.replace(error_pattern, error_replacement, 1)

    return patched, patched != js_text


def extract_function(source_js: str, name: str) -> str:
    pattern = FUNCTION_PATTERNS[name]
    match = pattern.search(source_js)
    if not match:
        raise RuntimeError(f"Could not find {name} in source mudclient.js")
    return match.group(0).rstrip("\n")


def replace_function(target_js: str, name: str, replacement: str) -> tuple[str, bool]:
    pattern = FUNCTION_PATTERNS[name]
    patched, count = pattern.subn(replacement, target_js, count=1)
    if count == 0:
        raise RuntimeError(f"Could not find {name} in target mudclient.js")
    return patched, patched != target_js


def apply_patches(rsc_c_dir: Path, source_web_client: Path) -> None:
    source_html = source_web_client / "mudclient.html"
    source_login_html = source_web_client / "mudclient-new-login.html"
    source_js = source_web_client / "mudclient.js"
    target_html = rsc_c_dir / "mudclient.html"
    target_login_html = rsc_c_dir / "mudclient-new-login.html"
    target_js = rsc_c_dir / "mudclient.js"

    for path in (source_html, source_login_html, source_js, target_html, target_js):
        if not path.is_file():
            raise FileNotFoundError(path)

    if source_html.resolve() != target_html.resolve():
        shutil.copyfile(source_html, target_html)
        print(f"Copied mobile mudclient.html to {target_html}")
    else:
        print(f"Keeping existing mobile mudclient.html at {target_html}")

    if source_login_html.resolve() != target_login_html.resolve():
        shutil.copyfile(source_login_html, target_login_html)
        print(f"Copied launcher login HTML to {target_login_html}")
    else:
        print(f"Keeping existing launcher login HTML at {target_login_html}")

    source_js_text = source_js.read_text()
    target_js_text = target_js.read_text()
    patched_js = target_js_text

    changed_functions = []
    for name in FUNCTION_PATTERNS:
        replacement = extract_function(source_js_text, name)
        patched_js, changed = replace_function(patched_js, name, replacement)
        if changed:
            changed_functions.append(name)

    patched_js, webgl_changed = apply_webgl_compatibility_patch(patched_js)
    if webgl_changed:
        changed_functions.append("webgl_compatibility")

    patched_js, sockfs_changed = apply_sockfs_diagnostics_patch(patched_js)
    if sockfs_changed:
        changed_functions.append("sockfs_diagnostics")

    if patched_js != target_js_text:
        target_js.write_text(patched_js)
        print("Patched mudclient.js functions: " + ", ".join(changed_functions))
    else:
        print("mudclient.js already has the mobile function patches.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply mobile web-client patches to a built rsc-c directory")
    parser.add_argument("--rsc-c-dir", default="/opt/rsc-c", help="Built rsc-c output directory")
    parser.add_argument(
        "--source-web-client",
        required=True,
        help="Directory containing the repo's updated mudclient.html and mudclient.js",
    )
    args = parser.parse_args()

    try:
        apply_patches(Path(args.rsc_c_dir), Path(args.source_web_client))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
