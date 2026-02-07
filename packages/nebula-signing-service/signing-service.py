#!/usr/bin/env python3
"""
Nebula dynamic cert signing service.

Signs short-lived nebula certificates for registered mesh hosts.
Each host authenticates with a bearer token. The service validates
the token, looks up the host's configuration (IP, groups), and
signs a certificate using the CA key.

Replaces the static agenix-encrypted cert model with dynamic
short-lived certs (fetch every 24h, expire every 48h).

Environment variables:
  HOSTS_CONFIG:   JSON mapping sha256(token) -> {name, ip, groups}
  CA_CERT:        Path to Nebula CA certificate
  CA_KEY:         Path to Nebula CA key
  PORT:           Listen port (default 8445)
  CERT_DURATION:  Certificate validity (default "48h")
"""

import hashlib
import json
import os
import subprocess
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

HOSTS_CONFIG = json.loads(os.environ.get("HOSTS_CONFIG", "{}"))
CA_CERT = os.environ.get("CA_CERT", "")
CA_KEY = os.environ.get("CA_KEY", "")
PORT = int(os.environ.get("PORT", "8445"))
CERT_DURATION = os.environ.get("CERT_DURATION", "48h")


def lookup_host(token: str) -> dict | None:
    """Look up host config by bearer token (compared via SHA-256 hash)."""
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    return HOSTS_CONFIG.get(token_hash)


def sign_cert(host: dict) -> tuple[str, str, str]:
    """Sign a certificate for the given host. Returns (ca, cert, key)."""
    ca_pem = Path(CA_CERT).read_text()

    with tempfile.TemporaryDirectory() as tmpdir:
        cert_path = os.path.join(tmpdir, "host.crt")
        key_path = os.path.join(tmpdir, "host.key")

        cmd = [
            "nebula-cert", "sign",
            "-ca-crt", CA_CERT,
            "-ca-key", CA_KEY,
            "-name", host["name"],
            "-ip", host["ip"],
            "-duration", CERT_DURATION,
            "-out-crt", cert_path,
            "-out-key", key_path,
        ]

        if host.get("groups"):
            cmd.extend(["-groups", ",".join(host["groups"])])

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"nebula-cert sign failed: {result.stderr}")

        return ca_pem, Path(cert_path).read_text(), Path(key_path).read_text()


class SigningHandler(BaseHTTPRequestHandler):
    """HTTP handler for cert signing requests."""

    def _send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/v1/sign":
            self.send_error(404, "Not found")
            return

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_error(401, "Missing or invalid Authorization header")
            return

        token = auth[7:]
        host = lookup_host(token)
        if not host:
            self.send_error(403, "Invalid token")
            return

        try:
            ca, cert, key = sign_cert(host)
            self._send_json({"ca": ca, "cert": cert, "key": key})
        except Exception as e:
            self._send_json({"error": str(e)}, 500)

    def do_GET(self):
        if self.path == "/health":
            self._send_json({"status": "ok", "hosts": len(HOSTS_CONFIG)})
            return
        self.send_error(404, "Not found")

    def log_message(self, format, *args):
        # Include client IP but not full request details for security
        print(f"[{self.log_date_time_string()}] {self.client_address[0]} {format % args}")


def main():
    if not HOSTS_CONFIG:
        print("ERROR: HOSTS_CONFIG not set or empty")
        return 1

    for name, path in [("CA_CERT", CA_CERT), ("CA_KEY", CA_KEY)]:
        if not path:
            print(f"ERROR: {name} not set")
            return 1
        if not Path(path).exists():
            print(f"ERROR: {name} not found at: {path}")
            return 1

    server = HTTPServer(("0.0.0.0", PORT), SigningHandler)
    print(f"Nebula signing service on 0.0.0.0:{PORT}")
    print(f"Registered hosts: {len(HOSTS_CONFIG)}")
    print(f"Cert duration: {CERT_DURATION}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

    return 0


if __name__ == "__main__":
    exit(main())
