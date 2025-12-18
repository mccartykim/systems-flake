#!/usr/bin/env python3
"""
Ephemeral Nebula cert allocation service.

Allocates short-lived nebula certificates for ephemeral nodes
like Claude Code sandboxes and containers.

Environment variables:
  - NETWORKS_CONFIG: JSON config for networks (from NixOS module)
  - PORT: Port to listen on (default 8444)
  - STATE_DIR: Directory for tracking allocations
  - API_TOKEN: API token for authentication
"""

import json
import os
import subprocess
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Optional

# Configuration from environment
NETWORKS_CONFIG = json.loads(os.environ.get("NETWORKS_CONFIG", "{}"))
PORT = int(os.environ.get("PORT", "8444"))
STATE_DIR = Path(os.environ.get("STATE_DIR", "/var/lib/ephemeral-certs"))
API_TOKEN = os.environ.get("API_TOKEN", "")


def get_used_ips(network: str) -> set[int]:
    """Get set of currently allocated IP suffixes for a network."""
    network_dir = STATE_DIR / network
    network_dir.mkdir(parents=True, exist_ok=True)

    used = set()
    for f in network_dir.glob("*.json"):
        try:
            data = json.loads(f.read_text())
            # Check if allocation is still valid (not expired)
            if data.get("expires_at", 0) > time.time():
                ip = f.stem  # filename is the IP suffix
                used.add(int(ip))
        except (json.JSONDecodeError, ValueError):
            pass
    return used


def allocate_ip(network: str) -> Optional[str]:
    """Allocate next available IP from pool."""
    config = NETWORKS_CONFIG.get(network)
    if not config:
        return None

    used = get_used_ips(network)
    pool_start = config["pool_start"]
    pool_end = config["pool_end"]
    subnet = config["subnet"]

    for i in range(pool_start, pool_end + 1):
        if i not in used:
            return f"{subnet}.{i}"

    return None  # Pool exhausted


def sign_cert(network: str, ip: str, name: str, duration: Optional[str] = None, groups: Optional[list[str]] = None) -> tuple[str, str]:
    """Sign a new cert for the given IP using nebula-cert."""
    config = NETWORKS_CONFIG.get(network)
    if not config:
        raise ValueError(f"Unknown network: {network}")

    duration = duration or config["default_duration"]
    groups = groups or config["default_groups"]

    # Create temp files for cert output
    network_dir = STATE_DIR / network
    network_dir.mkdir(parents=True, exist_ok=True)

    ip_suffix = ip.split(".")[-1]
    cert_path = network_dir / f"{ip_suffix}.crt"
    key_path = network_dir / f"{ip_suffix}.key"

    # Run nebula-cert sign
    cmd = [
        "nebula-cert", "sign",
        "-ca-crt", config["ca_cert"],
        "-ca-key", config["ca_key"],
        "-name", name,
        "-ip", f"{ip}/16",
        "-groups", ",".join(groups),
        "-duration", duration,
        "-out-crt", str(cert_path),
        "-out-key", str(key_path),
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"nebula-cert failed: {result.stderr}")

    cert = cert_path.read_text()
    key = key_path.read_text()

    # Parse duration to calculate expiry
    duration_seconds = parse_duration(duration)
    expires_at = time.time() + duration_seconds

    # Save allocation metadata
    meta_path = network_dir / f"{ip_suffix}.json"
    meta_path.write_text(json.dumps({
        "ip": ip,
        "name": name,
        "groups": groups,
        "allocated_at": time.time(),
        "expires_at": expires_at,
    }))

    return cert, key


def parse_duration(duration: str) -> int:
    """Parse duration string (e.g., '24h', '168h') to seconds."""
    if duration.endswith("h"):
        return int(duration[:-1]) * 3600
    elif duration.endswith("m"):
        return int(duration[:-1]) * 60
    elif duration.endswith("s"):
        return int(duration[:-1])
    else:
        return int(duration)


def renew_cert(network: str, current_ip: str) -> tuple[str, str, str]:
    """Renew an existing allocation."""
    config = NETWORKS_CONFIG.get(network)
    if not config:
        raise ValueError(f"Unknown network: {network}")

    ip_suffix = current_ip.split(".")[-1]
    network_dir = STATE_DIR / network
    meta_path = network_dir / f"{ip_suffix}.json"

    if not meta_path.exists():
        raise ValueError(f"No allocation found for IP {current_ip}")

    meta = json.loads(meta_path.read_text())
    name = meta["name"]
    groups = meta["groups"]

    # Sign new cert with same IP and name
    cert, key = sign_cert(network, current_ip, name, groups=groups)

    return current_ip, cert, key


class CertServiceHandler(BaseHTTPRequestHandler):
    """HTTP request handler for cert service."""

    def _check_auth(self) -> bool:
        """Check API token authentication."""
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {API_TOKEN}":
            self.send_error(403, "Invalid or missing API token")
            return False
        return True

    def _send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        """Read and parse JSON request body."""
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            return {}
        body = self.rfile.read(content_length)
        return json.loads(body)

    def do_POST(self):
        """Handle POST requests."""
        if not self._check_auth():
            return

        path_parts = self.path.strip("/").split("/")
        if len(path_parts) < 2:
            self.send_error(400, "Invalid path")
            return

        network = path_parts[0]
        action = path_parts[1]

        if network not in NETWORKS_CONFIG:
            self.send_error(404, f"Unknown network: {network}")
            return

        try:
            if action == "allocate":
                self._handle_allocate(network)
            elif action == "renew":
                self._handle_renew(network)
            else:
                self.send_error(404, f"Unknown action: {action}")
        except Exception as e:
            self.send_error(500, str(e))

    def _handle_allocate(self, network: str):
        """Allocate a new cert."""
        body = self._read_body()

        # Allocate IP
        ip = allocate_ip(network)
        if not ip:
            self.send_error(503, "IP pool exhausted")
            return

        # Generate name
        name = f"ephemeral-{ip.replace('.', '-')}-{int(time.time())}"

        # Optional custom duration and groups
        duration = body.get("duration")
        groups = body.get("groups")

        # Sign cert
        cert, key = sign_cert(network, ip, name, duration, groups)

        # Read CA cert
        config = NETWORKS_CONFIG[network]
        ca = Path(config["ca_cert"]).read_text()

        self._send_json({
            "ip": ip,
            "name": name,
            "ca": ca,
            "cert": cert,
            "key": key,
        })

    def _handle_renew(self, network: str):
        """Renew an existing allocation."""
        body = self._read_body()
        current_ip = body.get("current_ip")

        if not current_ip:
            self.send_error(400, "Missing current_ip")
            return

        ip, cert, key = renew_cert(network, current_ip)

        # Read CA cert
        config = NETWORKS_CONFIG[network]
        ca = Path(config["ca_cert"]).read_text()

        self._send_json({
            "ip": ip,
            "ca": ca,
            "cert": cert,
            "key": key,
        })

    def do_DELETE(self):
        """Handle DELETE requests (release allocation)."""
        if not self._check_auth():
            return

        path_parts = self.path.strip("/").split("/")
        if len(path_parts) < 2:
            self.send_error(400, "Invalid path")
            return

        network = path_parts[0]
        ip = path_parts[1]

        if network not in NETWORKS_CONFIG:
            self.send_error(404, f"Unknown network: {network}")
            return

        # Remove allocation files
        ip_suffix = ip.split(".")[-1] if "." in ip else ip
        network_dir = STATE_DIR / network

        for ext in [".crt", ".key", ".json"]:
            (network_dir / f"{ip_suffix}{ext}").unlink(missing_ok=True)

        self._send_json({"status": "released", "ip": ip})

    def do_GET(self):
        """Handle GET requests (status/health)."""
        if self.path == "/health":
            self._send_json({"status": "ok"})
            return

        if self.path == "/status":
            if not self._check_auth():
                return

            status = {}
            for network, config in NETWORKS_CONFIG.items():
                used = get_used_ips(network)
                pool_size = config["pool_end"] - config["pool_start"] + 1
                status[network] = {
                    "allocated": len(used),
                    "available": pool_size - len(used),
                    "pool_size": pool_size,
                }

            self._send_json(status)
            return

        self.send_error(404, "Not found")


def main():
    """Start the cert service."""
    if not NETWORKS_CONFIG:
        print("ERROR: NETWORKS_CONFIG not set")
        return 1

    if not API_TOKEN:
        print("WARNING: API_TOKEN not set, service will reject all requests")

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    server = HTTPServer(("0.0.0.0", PORT), CertServiceHandler)
    print(f"Cert service listening on 0.0.0.0:{PORT}")
    print(f"Networks: {list(NETWORKS_CONFIG.keys())}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

    return 0


if __name__ == "__main__":
    exit(main())
