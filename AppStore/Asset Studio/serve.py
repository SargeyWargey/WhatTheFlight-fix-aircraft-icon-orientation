#!/usr/bin/env python3
"""Serves the Asset Studio from AppStore/ and lets its Save buttons write into the repo.

    python3 "AppStore/Asset Studio/serve.py"      (or double-click "Open Asset Studio.command")

Saves only land in Screenshots/Final/ and Header Art/, nowhere else.
"""
import http.server
import json
import os
import struct
import sys
import threading
import urllib.parse
import webbrowser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # AppStore/
WRITABLE = ("Screenshots/Final/", "Header Art/")
PORT = int(os.environ.get("STUDIO_PORT", "8765"))

# The studio page is written for the Artifact viewer, which wraps it in a document skeleton.
SKELETON = (b'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            b'<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
            b'</head><body>')


def raw_index():
    """Every capture in Screenshots/Raw/<slot>/, with its size and what captures.json says it shows."""
    raw_root = os.path.join(ROOT, "Screenshots", "Raw")
    notes = {}
    try:
        with open(os.path.join(raw_root, "captures.json")) as f:
            notes = {c.get("file"): c.get("shows", "") for c in json.load(f)}
    except (OSError, ValueError):
        pass
    index = {}
    if os.path.isdir(raw_root):
        for folder in sorted(os.listdir(raw_root)):
            path = os.path.join(raw_root, folder)
            if not os.path.isdir(path):
                continue
            shots = []
            for name in sorted(os.listdir(path)):
                if not name.lower().endswith(".png"):
                    continue
                with open(os.path.join(path, name), "rb") as f:
                    head = f.read(24)
                if head[:8] != b"\x89PNG\r\n\x1a\n":
                    continue
                w, h = struct.unpack(">II", head[16:24])
                shots.append({"file": name, "w": w, "h": h, "shows": notes.get(f"{folder}/{name}", "")})
            index[folder] = shots
    return "window.STUDIO_RAW = " + json.dumps(index, indent=1) + ";\n"


def safe_path(relative, directory=False):
    relative = relative.lstrip("/")
    if not any(relative.startswith(root) for root in WRITABLE):
        return None
    full = os.path.normpath(os.path.join(ROOT, relative))
    if not full.startswith(ROOT + os.sep):
        return None
    if not directory and not full.endswith(".png"):
        return None
    return full


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):
        if args and "/__" in str(args[0]):
            sys.stderr.write("  " + (fmt % args) + "\n")

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def reply(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/__ping":
            return self.reply(200, "ok")
        if url.path in ("/Asset%20Studio/raw-index.js", "/Asset Studio/raw-index.js"):
            body = raw_index().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if url.path in ("/Asset%20Studio/", "/Asset Studio/", "/Asset%20Studio/index.html"):
            with open(os.path.join(ROOT, "Asset Studio", "index.html"), "rb") as f:
                body = SKELETON + f.read() + b"</body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/__save":
            target = safe_path(query.get("path", [""])[0])
            if not target:
                return self.reply(400, "That path isn't one the studio may write to.")
            length = int(self.headers.get("Content-Length", "0"))
            data = self.rfile.read(length)
            if not data.startswith(b"\x89PNG"):
                return self.reply(400, "Only PNG files can be saved.")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as f:
                f.write(data)
            return self.reply(200, os.path.relpath(target, ROOT))
        if url.path == "/__clear":
            folder = safe_path(query.get("dir", [""])[0].rstrip("/") + "/", directory=True)
            if not folder:
                return self.reply(400, "That folder isn't one the studio may clear.")
            removed = 0
            if os.path.isdir(folder):
                for name in os.listdir(folder):
                    if name.endswith(".png"):
                        os.remove(os.path.join(folder, name))
                        removed += 1
            return self.reply(200, str(removed))
        self.reply(404, "Not found")


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://localhost:{PORT}/Asset%20Studio/"
    print(f"Asset Studio is running at {url}")
    print("Saves go to AppStore/Screenshots/Final and AppStore/Header Art.")
    print("Leave this window open while you work. Press Ctrl+C to stop.")
    if "--no-browser" not in sys.argv:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
