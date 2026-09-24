"""Synthetic OpenAI-shaped protocol fixture for Kubernetes wiring tests only."""
import argparse
import hmac
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--api-key", required=True)
args, _ = parser.parse_known_args()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            status, body = 200, {"status": "fixture-ready"}
        elif not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + args.api_key):
            status, body = 401, {"error": "unauthorized"}
        elif self.path == "/v1/models":
            status, body = 200, {"object": "list", "data": [{"id": "synthetic-fixture-no-model"}]}
        else:
            status, body = 404, {"error": "fixture route not implemented"}
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
