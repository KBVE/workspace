#!/usr/bin/env bash
#
# Serves dist/ with the headers the threaded bundles need.
#
# `python3 -m http.server` cannot do this, and that matters more than it looks:
# without Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy the page
# is not cross-origin isolated, SharedArrayBuffer is undefined, and the game
# stops at index.html's isolation check. Testing against a plain static server
# therefore reproduces a failure the real deployment does not have -- so this
# exists to make local and itch behave the same way.
set -euo pipefail

crate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="${crate_dir}/dist"
port="${1:-8080}"

[ -d "${dist}" ] || { echo "error: no dist/. Run tools/build-web.sh first." >&2; exit 1; }

echo "http://localhost:${port}/ (cross-origin isolated)"

python3 - "${dist}" "${port}" <<'PY'
import functools
import http.server
import socketserver
import sys

directory, port = sys.argv[1], int(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    # .wasm is not in the default map on every platform, and
    # instantiateStreaming refuses anything that is not application/wasm --
    # falling back to a slower path and printing a warning that reads like a
    # bug.
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # The bundle is tens of megabytes and changes on every build.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        # One line per asset request is thousands of lines for a map load.
        if not self.path.startswith("/assets/"):
            super().log_message(fmt, *args)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(("", port), functools.partial(Handler, directory=directory)) as httpd:
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
PY
