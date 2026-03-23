#!/usr/bin/env python3
"""
llm-proxy.py — rate-limiting reverse proxy for local LLM
Limits to N requests/minute to prevent queue flooding (e.g. from GraphRAG)
Usage: python3 llm-proxy.py --port 6699 --target http://192.168.1.186:6698 --rpm 4
"""
import asyncio
import time
import argparse
import json
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Lock

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=6699)
parser.add_argument("--target", default="http://192.168.1.186:6698")
parser.add_argument("--rpm", type=int, default=4, help="Max requests per minute to /v1/chat/completions")
args = parser.parse_args()

rpm_lock = Lock()
request_times = []

def is_rate_limited():
    now = time.time()
    with rpm_lock:
        cutoff = now - 60
        while request_times and request_times[0] < cutoff:
            request_times.pop(0)
        if len(request_times) >= args.rpm:
            return True
        request_times.append(now)
        return False

class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *a):
        print(f"[proxy] {format % a}")

    def do_request(self):
        path = self.path
        is_chat = path.startswith("/v1/chat/completions")

        if is_chat:
            while is_rate_limited():
                wait = 60 / args.rpm
                print(f"[proxy] rate limit hit, waiting {wait:.1f}s")
                time.sleep(wait)

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        target_url = args.target.rstrip("/") + path
        req = urllib.request.Request(target_url, data=body or None, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length"):
                req.add_header(k, v)
        if body:
            req.add_header("Content-Length", str(len(body)))

        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())

    do_GET = do_POST = do_request

print(f"[proxy] starting on :{args.port} → {args.target} (max {args.rpm} rpm for chat)")
HTTPServer(("0.0.0.0", args.port), ProxyHandler).serve_forever()
