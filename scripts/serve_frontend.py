from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Handler(SimpleHTTPRequestHandler):
    # Windows registry associations can otherwise report .js as text/plain.
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      ".js": "application/javascript", ".mjs": "application/javascript",
                      ".wasm": "application/wasm", ".json": "application/json",
                      ".css": "text/css", ".svg": "image/svg+xml",
                      ".ttf": "font/ttf", ".otf": "font/otf"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()


if __name__ == "__main__":
    directory = ROOT / "frontend" / "build" / "web"
    if not (directory / "index.html").exists():
        raise SystemExit("Build Flutter Web first: see README.md.")
    print("Pulsewatch: http://localhost:8080", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8080), partial(Handler, directory=str(directory))).serve_forever()
