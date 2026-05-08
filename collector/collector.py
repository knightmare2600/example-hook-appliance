#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os

os.makedirs("incoming", exist_ok=True)

class Handler(BaseHTTPRequestHandler):

    def do_POST(self):
        length = int(self.headers["Content-Length"])
        data = self.rfile.read(length)
        payload = json.loads(data)
        serial = payload.get("serial", "unknown")
        with open(f"incoming/{serial}.json", "w") as f:
            json.dump(payload, f, indent=2)
        self.send_response(200)
        self.end_headers()
HTTPServer(("192.168.139.50", 80), Handler).serve_forever()
