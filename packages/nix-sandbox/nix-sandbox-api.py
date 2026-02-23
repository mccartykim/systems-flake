#!/usr/bin/env python3
"""
Nix Sandbox API - Remote nix build service for Claude Code.

Executes nix build/check commands with configurable isolation:
  - 'direct': subprocess builds (no isolation beyond process boundaries)
  - 'nspawn': ephemeral systemd-nspawn containers (PID/mount/network namespaces)
  - 'vm': QEMU VMs with kernel-level isolation (legacy)

Environment variables:
  - PORT: Port to listen on (default 8090)
  - API_TOKEN: Bearer token for authentication
  - PRIMER_PATH: Path to primer.md file
  - MAX_CONCURRENT: Max simultaneous builds (default 2)
  - BUILD_TIMEOUT: Max build time in seconds (default 1800)
  - BUILD_MODE: 'nspawn' (default), 'direct', or 'vm'
  - BUILD_ROOT: Path to minimal rootfs for nspawn containers
  - NSPAWN_NETWORK: 'veth' (default) for internet access, 'private' for offline
  - VM_IMAGE: Path to QEMU VM image (legacy vm mode)
  - VM_MEMORY_MB: VM memory in MB (legacy vm mode, default 8192)
  - VM_CPUS: VM vCPU count (legacy vm mode, default 4)
  - WAN_INTERFACE: Network interface for outbound NAT (default eth0)
"""

import base64
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Configuration from environment
PORT = int(os.environ.get("PORT", "8090"))
API_TOKEN = os.environ.get("API_TOKEN", "")
VM_IMAGE = os.environ.get("VM_IMAGE", "")
PRIMER_PATH = os.environ.get("PRIMER_PATH", "")
MAX_CONCURRENT = int(os.environ.get("MAX_CONCURRENT", "2"))
VM_MEMORY_MB = int(os.environ.get("VM_MEMORY_MB", "8192"))
VM_CPUS = int(os.environ.get("VM_CPUS", "4"))
BUILD_TIMEOUT = int(os.environ.get("BUILD_TIMEOUT", "1800"))
WAN_INTERFACE = os.environ.get("WAN_INTERFACE", "eth0")
BUILD_MODE = os.environ.get("BUILD_MODE", "nspawn")
BUILD_ROOT = os.environ.get("BUILD_ROOT", "")
NSPAWN_NETWORK = os.environ.get("NSPAWN_NETWORK", "veth")
BUILD_MEMORY_LIMIT = os.environ.get("BUILD_MEMORY_LIMIT", "4G")
BUILD_CPU_QUOTA = os.environ.get("BUILD_CPU_QUOTA", "200%")

# Concurrency control
vm_semaphore = threading.Semaphore(MAX_CONCURRENT)
active_jobs = {}
active_jobs_lock = threading.Lock()
queue_depth = 0
queue_depth_lock = threading.Lock()

# Maximum queue depth before rejecting
MAX_QUEUE_DEPTH = 4

# Maximum tarball size (50MB)
MAX_TARBALL_SIZE = 50 * 1024 * 1024

# Valid target pattern: empty, or .#<flake-output-path>
TARGET_PATTERN = re.compile(r"^\.\#[a-zA-Z0-9_\-\.\/]+$")


def validate_target(target):
    """Validate build target. Returns (ok, error_message)."""
    if target == "":
        return True, None
    if TARGET_PATTERN.match(target):
        return True, None
    return False, f"Invalid target: must be empty or match .#<path> (got {target!r})"


# Shell metacharacters that should never appear in URLs
URL_DANGEROUS_CHARS = re.compile(r"[;|$`\n\r\\]")
# Allowed URL schemes for git sources
ALLOWED_URL_SCHEMES = ("https://", "http://")


def validate_git_url(url):
    """Validate git clone URL. Returns (ok, error_message)."""
    if URL_DANGEROUS_CHARS.search(url):
        return False, f"URL contains forbidden characters"
    if url.startswith("file://") or (not url.startswith(("https://", "http://")) and "/" in url):
        # Block file:// and bare paths to prevent local filesystem access
        if url.startswith("file://"):
            return False, "file:// URLs are not allowed"
    if not url.startswith(ALLOWED_URL_SCHEMES):
        return False, f"URL must start with https:// or http://"
    return True, None


def resource_limit_prefix():
    """Return systemd-run scope prefix for cgroup resource limits."""
    return [
        "systemd-run", "--scope", "--quiet",
        f"--property=MemoryMax={BUILD_MEMORY_LIMIT}",
        f"--property=CPUQuota={BUILD_CPU_QUOTA}",
        "--",
    ]


def log_event(event_type, **kwargs):
    """Print a structured JSON audit log entry to stdout (captured by journald)."""
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "event": event_type,
        **kwargs,
    }
    print(json.dumps(entry), flush=True)


def setup_tap(slot):
    """Create TAP device and iptables rules for VM isolation."""
    tap_name = f"sandbox{slot}"
    bridge_ip = f"10.200.{slot}.1"
    vm_ip = f"10.200.{slot}.2"
    subnet = f"10.200.{slot}.0/24"

    # Create TAP device
    subprocess.run(["ip", "tuntap", "add", "dev", tap_name, "mode", "tap"],
                   check=True, capture_output=True)
    subprocess.run(["ip", "addr", "add", f"{bridge_ip}/24", "dev", tap_name],
                   check=True, capture_output=True)
    subprocess.run(["ip", "link", "set", tap_name, "up"],
                   check=True, capture_output=True)

    # NAT for outbound traffic
    subprocess.run(["iptables", "-t", "nat", "-A", "POSTROUTING",
                     "-s", subnet, "-o", WAN_INTERFACE, "-j", "MASQUERADE"],
                   check=True, capture_output=True)

    # FORWARD chain: allow established, block private, allow WAN
    chain = f"SANDBOX_{slot}"
    subprocess.run(["iptables", "-N", chain], capture_output=True)
    subprocess.run(["iptables", "-A", "FORWARD", "-i", tap_name, "-j", chain],
                   check=True, capture_output=True)

    # Allow established/related
    subprocess.run(["iptables", "-A", chain, "-m", "state",
                     "--state", "ESTABLISHED,RELATED", "-j", "ACCEPT"],
                   check=True, capture_output=True)

    # Block all private networks
    for net in ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "100.64.0.0/10"]:
        subprocess.run(["iptables", "-A", chain, "-d", net, "-j", "DROP"],
                       check=True, capture_output=True)

    # Allow outbound to WAN
    subprocess.run(["iptables", "-A", chain, "-o", WAN_INTERFACE, "-j", "ACCEPT"],
                   check=True, capture_output=True)

    # Default deny
    subprocess.run(["iptables", "-A", chain, "-j", "DROP"],
                   check=True, capture_output=True)

    # INPUT: allow DNS from VMs, block everything else from VMs
    subprocess.run(["iptables", "-A", "INPUT", "-i", tap_name,
                     "-p", "udp", "--dport", "53", "-j", "ACCEPT"],
                   check=True, capture_output=True)
    subprocess.run(["iptables", "-A", "INPUT", "-i", tap_name,
                     "-p", "tcp", "--dport", "53", "-j", "ACCEPT"],
                   check=True, capture_output=True)
    subprocess.run(["iptables", "-A", "INPUT", "-i", tap_name, "-j", "DROP"],
                   check=True, capture_output=True)

    return tap_name, bridge_ip, vm_ip


def teardown_tap(slot):
    """Remove TAP device and iptables rules."""
    tap_name = f"sandbox{slot}"
    subnet = f"10.200.{slot}.0/24"
    chain = f"SANDBOX_{slot}"

    # Remove iptables rules (best effort)
    subprocess.run(["iptables", "-D", "FORWARD", "-i", tap_name, "-j", chain],
                   capture_output=True)
    subprocess.run(["iptables", "-F", chain], capture_output=True)
    subprocess.run(["iptables", "-X", chain], capture_output=True)

    subprocess.run(["iptables", "-t", "nat", "-D", "POSTROUTING",
                     "-s", subnet, "-o", WAN_INTERFACE, "-j", "MASQUERADE"],
                   capture_output=True)

    # Remove INPUT rules for this tap
    for proto in ["udp", "tcp"]:
        subprocess.run(["iptables", "-D", "INPUT", "-i", tap_name,
                         "-p", proto, "--dport", "53", "-j", "ACCEPT"],
                       capture_output=True)
    subprocess.run(["iptables", "-D", "INPUT", "-i", tap_name, "-j", "DROP"],
                   capture_output=True)

    # Remove TAP device
    subprocess.run(["ip", "link", "del", tap_name], capture_output=True)


def setup_veth(slot):
    """Create veth pair and iptables rules for nspawn build isolation."""
    host_if = f"sb-h{slot}"
    guest_if = f"sb-g{slot}"
    host_ip = f"10.200.{slot}.1"
    guest_ip = f"10.200.{slot}.2"
    subnet = f"10.200.{slot}.0/24"

    # Create veth pair
    subprocess.run(["ip", "link", "add", host_if, "type", "veth", "peer", "name", guest_if],
                   check=True, capture_output=True)
    subprocess.run(["ip", "addr", "add", f"{host_ip}/24", "dev", host_if],
                   check=True, capture_output=True)
    subprocess.run(["ip", "link", "set", host_if, "up"],
                   check=True, capture_output=True)

    # NAT for outbound traffic
    subprocess.run(["iptables", "-t", "nat", "-A", "POSTROUTING",
                     "-s", subnet, "-o", WAN_INTERFACE, "-j", "MASQUERADE"],
                   check=True, capture_output=True)

    # FORWARD chain: allow established, block private, allow WAN
    chain = f"SANDBOX_{slot}"
    subprocess.run(["iptables", "-N", chain], capture_output=True)
    subprocess.run(["iptables", "-A", "FORWARD", "-i", host_if, "-j", chain],
                   check=True, capture_output=True)

    # Allow established/related
    subprocess.run(["iptables", "-A", chain, "-m", "state",
                     "--state", "ESTABLISHED,RELATED", "-j", "ACCEPT"],
                   check=True, capture_output=True)

    # Block all private networks (LAN isolation)
    for net in ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "100.64.0.0/10"]:
        subprocess.run(["iptables", "-A", chain, "-d", net, "-j", "DROP"],
                       check=True, capture_output=True)

    # Allow outbound to WAN
    subprocess.run(["iptables", "-A", chain, "-o", WAN_INTERFACE, "-j", "ACCEPT"],
                   check=True, capture_output=True)

    # Default deny
    subprocess.run(["iptables", "-A", chain, "-j", "DROP"],
                   check=True, capture_output=True)

    return guest_if, host_ip, guest_ip


def teardown_veth(slot):
    """Remove veth pair and iptables rules for nspawn build."""
    host_if = f"sb-h{slot}"
    subnet = f"10.200.{slot}.0/24"
    chain = f"SANDBOX_{slot}"

    # Remove iptables rules (best effort)
    subprocess.run(["iptables", "-D", "FORWARD", "-i", host_if, "-j", chain],
                   capture_output=True)
    subprocess.run(["iptables", "-F", chain], capture_output=True)
    subprocess.run(["iptables", "-X", chain], capture_output=True)

    subprocess.run(["iptables", "-t", "nat", "-D", "POSTROUTING",
                     "-s", subnet, "-o", WAN_INTERFACE, "-j", "MASQUERADE"],
                   capture_output=True)

    # Deleting one end of veth pair deletes both
    subprocess.run(["ip", "link", "del", host_if], capture_output=True)


def run_build(job_id, source_type, url, tarball_b64, command, target, timeout, slot):
    """Execute a nix build in an ephemeral QEMU VM."""
    workspace = Path(f"/run/nix-sandbox/{job_id}")
    workspace.mkdir(parents=True, exist_ok=True)

    virtiofsd_store = None
    virtiofsd_build = None
    qemu_proc = None
    tap_name = None
    start_time = time.time()

    try:
        # Write metadata for VM build agent
        metadata = {
            "source_type": source_type,
            "command": command,
            "target": target,
            "timeout": timeout,
        }
        if source_type == "git":
            metadata["url"] = url
        elif source_type == "tarball":
            # Decode tarball to workspace
            source_dir = workspace / "source"
            source_dir.mkdir(exist_ok=True)
            tarball_data = base64.b64decode(tarball_b64)
            tarball_path = workspace / "source.tar.gz"
            tarball_path.write_bytes(tarball_data)
            # Will be extracted by VM build agent
            metadata["tarball_path"] = "/build/source.tar.gz"

        (workspace / "metadata.json").write_text(json.dumps(metadata))

        # Setup networking
        tap_name, bridge_ip, vm_ip = setup_tap(slot)

        # Write network config for VM
        metadata["network"] = {"ip": vm_ip, "gateway": bridge_ip, "dns": bridge_ip}
        (workspace / "metadata.json").write_text(json.dumps(metadata))

        # Create overlay image (COW on top of base image)
        overlay_path = workspace / "overlay.qcow2"
        subprocess.run([
            "qemu-img", "create", "-f", "qcow2",
            "-b", VM_IMAGE, "-F", "qcow2",
            str(overlay_path)
        ], check=True, capture_output=True)

        # Start virtiofsd for /nix/store (read-only)
        store_sock = str(workspace / "virtiofs-store.sock")
        virtiofsd_store = subprocess.Popen([
            "virtiofsd",
            f"--socket-path={store_sock}",
            "--shared-dir=/nix/store",
            "--sandbox=chroot",
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Start virtiofsd for /build (workspace)
        build_sock = str(workspace / "virtiofs-build.sock")
        virtiofsd_build = subprocess.Popen([
            "virtiofsd",
            f"--socket-path={build_sock}",
            f"--shared-dir={str(workspace)}",
            "--sandbox=chroot",
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Wait for sockets to appear
        for sock in [store_sock, build_sock]:
            for _ in range(50):
                if os.path.exists(sock):
                    break
                time.sleep(0.1)

        # Launch QEMU
        qemu_cmd = [
            "qemu-system-x86_64",
            "-enable-kvm",
            "-m", str(VM_MEMORY_MB),
            "-smp", str(VM_CPUS),
            "-drive", f"file={overlay_path},format=qcow2,if=virtio",
            "-nographic",
            "-serial", "stdio",
            # virtiofs for /nix/store
            "-chardev", f"socket,id=char-store,path={store_sock}",
            "-device", "vhost-user-fs-pci,chardev=char-store,tag=nix-store",
            # virtiofs for /build
            "-chardev", f"socket,id=char-build,path={build_sock}",
            "-device", "vhost-user-fs-pci,chardev=char-build,tag=build-dir",
            # Networking
            "-netdev", f"tap,id=net0,ifname={tap_name},script=no,downscript=no",
            "-device", "virtio-net-pci,netdev=net0",
            # Memory backend for virtiofs
            "-object", f"memory-backend-memfd,id=mem,size={VM_MEMORY_MB}M,share=on",
            "-numa", "node,memdev=mem",
            # Kernel cmdline for network config
            "-append", f"console=ttyS0 sandbox.ip={vm_ip} sandbox.gw={bridge_ip} sandbox.dns={bridge_ip}",
        ]

        qemu_proc = subprocess.Popen(
            qemu_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            preexec_fn=os.setsid,
        )

        # Capture output until VM exits or timeout
        log_lines = []
        exit_code = None

        try:
            stdout, _ = qemu_proc.communicate(timeout=timeout)
            log_output = stdout.decode("utf-8", errors="replace")
            log_lines.append(log_output)
            exit_code = qemu_proc.returncode
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(qemu_proc.pid), signal.SIGKILL)
            qemu_proc.wait()
            log_lines.append("\n[TIMEOUT] Build exceeded time limit\n")
            exit_code = 124  # Standard timeout exit code

        # Parse exit code from build agent output
        full_log = "".join(log_lines)

        # The build agent writes "BUILD_EXIT_CODE=N" to serial
        agent_exit = None
        for line in full_log.split("\n"):
            if line.startswith("BUILD_EXIT_CODE="):
                try:
                    agent_exit = int(line.split("=")[1].strip())
                except (ValueError, IndexError):
                    pass

        if agent_exit is not None:
            exit_code = agent_exit

        duration = time.time() - start_time

        return {
            "exit_code": exit_code or 0,
            "log": full_log,
            "duration_seconds": round(duration, 1),
            "success": (exit_code or 0) == 0,
        }

    finally:
        # Cleanup
        if qemu_proc and qemu_proc.poll() is None:
            try:
                os.killpg(os.getpgid(qemu_proc.pid), signal.SIGKILL)
                qemu_proc.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass

        if virtiofsd_store and virtiofsd_store.poll() is None:
            virtiofsd_store.terminate()
            virtiofsd_store.wait(timeout=5)

        if virtiofsd_build and virtiofsd_build.poll() is None:
            virtiofsd_build.terminate()
            virtiofsd_build.wait(timeout=5)

        if tap_name:
            teardown_tap(slot)

        # Remove workspace
        shutil.rmtree(workspace, ignore_errors=True)


def run_build_direct(job_id, source_type, url, tarball_b64, command, target, timeout):
    """Execute a nix build directly as a subprocess (no VM isolation)."""
    workspace = Path(f"/run/nix-sandbox/{job_id}")
    workspace.mkdir(parents=True, exist_ok=True)
    src_dir = workspace / "src"
    start_time = time.time()

    log_event("build_start", source_type=source_type, command=command,
              target=target, job_id=job_id, build_mode="direct")
    log_event("build_warning", job_id=job_id,
              message="Running in direct mode (no isolation)")

    try:
        # Prepare source
        if source_type == "git":
            result = subprocess.run(
                ["git", "clone", "--depth", "1", url, str(src_dir)],
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode != 0:
                log_event("build_error", job_id=job_id, error="git clone failed")
                return {
                    "exit_code": result.returncode,
                    "log": f"git clone failed:\n{result.stderr}",
                    "duration_seconds": round(time.time() - start_time, 1),
                    "success": False,
                }
        elif source_type == "tarball":
            src_dir.mkdir(parents=True, exist_ok=True)
            tarball_data = base64.b64decode(tarball_b64)
            tarball_path = workspace / "source.tar.gz"
            tarball_path.write_bytes(tarball_data)
            subprocess.run(
                ["tar", "xzf", str(tarball_path), "-C", str(src_dir)],
                check=True, capture_output=True,
            )

        # Build the nix command
        if command == "build":
            nix_cmd = ["nix", "build", "--no-link"]
            if target:
                nix_cmd.append(target)
        else:
            nix_cmd = ["nix", "flake", "check"]

        # Wrap with resource limits
        full_cmd = resource_limit_prefix() + nix_cmd

        # Run the build
        result = subprocess.run(
            full_cmd,
            cwd=str(src_dir),
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        duration = time.time() - start_time
        log = result.stdout + result.stderr

        log_event("build_complete", job_id=job_id, exit_code=result.returncode,
                  success=result.returncode == 0, duration_seconds=round(duration, 1))

        return {
            "exit_code": result.returncode,
            "log": log,
            "duration_seconds": round(duration, 1),
            "success": result.returncode == 0,
        }

    except subprocess.TimeoutExpired:
        log_event("build_error", job_id=job_id, error="timeout")
        return {
            "exit_code": 124,
            "log": "[TIMEOUT] Build exceeded time limit\n",
            "duration_seconds": round(time.time() - start_time, 1),
            "success": False,
        }

    finally:
        shutil.rmtree(workspace, ignore_errors=True)


def run_build_nspawn(job_id, source_type, url, tarball_b64, command, target, timeout, slot):
    """Execute a nix build in an ephemeral systemd-nspawn container."""
    workspace = Path(f"/run/nix-sandbox/{job_id}")
    workspace.mkdir(parents=True, exist_ok=True)
    src_dir = workspace / "src"
    start_time = time.time()
    use_veth = NSPAWN_NETWORK == "veth"
    veth_setup_done = False

    log_event("build_start", source_type=source_type, command=command,
              target=target, job_id=job_id, build_mode="nspawn", slot=slot)

    try:
        # Prepare source (same as direct mode)
        if source_type == "git":
            result = subprocess.run(
                ["git", "clone", "--depth", "1", url, str(src_dir)],
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode != 0:
                log_event("build_error", job_id=job_id, error="git clone failed")
                return {
                    "exit_code": result.returncode,
                    "log": f"git clone failed:\n{result.stderr}",
                    "duration_seconds": round(time.time() - start_time, 1),
                    "success": False,
                }
        elif source_type == "tarball":
            src_dir.mkdir(parents=True, exist_ok=True)
            tarball_data = base64.b64decode(tarball_b64)
            tarball_path = workspace / "source.tar.gz"
            tarball_path.write_bytes(tarball_data)
            subprocess.run(
                ["tar", "xzf", str(tarball_path), "-C", str(src_dir)],
                check=True, capture_output=True,
            )

        # Build the nix command
        if command == "build":
            nix_cmd = "nix build --no-link"
            if target:
                nix_cmd += f" {shlex.quote(target)}"
        else:
            nix_cmd = "nix flake check"

        # Network configuration
        nspawn_net_args = []
        inner_setup = ""

        if use_veth:
            guest_if, host_ip, guest_ip = setup_veth(slot)
            veth_setup_done = True
            nspawn_net_args = [
                f"--network-interface={guest_if}",
                "--capability=CAP_NET_ADMIN",
            ]
            inner_setup = (
                f"ip addr add {guest_ip}/24 dev {guest_if} && "
                f"ip link set {guest_if} up && "
                f"ip route add default via {host_ip} && "
                f"echo 'nameserver 8.8.8.8' > /etc/resolv.conf && "
            )
        else:
            nspawn_net_args = ["--private-network"]

        nspawn_cmd = resource_limit_prefix() + [
            "systemd-nspawn",
            "--ephemeral",
            f"--directory={BUILD_ROOT}",
            f"--machine=sandbox-{slot}",
            "--register=no",
            "--keep-unit",
            *nspawn_net_args,
            "--bind-ro=/nix/store",
            "--bind=/nix/var/nix/daemon-socket",
            f"--bind={src_dir}:/build",
            "--chdir=/build",
            "--setenv=PATH=/bin:/usr/bin",
            "--setenv=NIX_REMOTE=daemon",
            "--",
            "/bin/sh", "-c", f"{inner_setup}{nix_cmd}",
        ]

        result = subprocess.run(
            nspawn_cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        duration = time.time() - start_time
        log = result.stdout + result.stderr

        log_event("build_complete", job_id=job_id, exit_code=result.returncode,
                  success=result.returncode == 0, duration_seconds=round(duration, 1))

        return {
            "exit_code": result.returncode,
            "log": log,
            "duration_seconds": round(duration, 1),
            "success": result.returncode == 0,
        }

    except subprocess.TimeoutExpired:
        log_event("build_error", job_id=job_id, error="timeout")
        return {
            "exit_code": 124,
            "log": "[TIMEOUT] Build exceeded time limit\n",
            "duration_seconds": round(time.time() - start_time, 1),
            "success": False,
        }

    finally:
        if use_veth and veth_setup_done:
            teardown_veth(slot)
        shutil.rmtree(workspace, ignore_errors=True)


class SandboxHandler(BaseHTTPRequestHandler):
    """HTTP request handler for nix sandbox service."""

    def _check_auth(self):
        """Check Bearer token authentication."""
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {API_TOKEN}":
            log_event("auth_failure", client_ip=self.client_address[0])
            self.send_error(403, "Invalid or missing API token")
            return False
        return True

    def _send_json(self, data, status=200):
        """Send JSON response."""
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, status=200, content_type="text/markdown"):
        """Send text response."""
        body = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        """Read and parse JSON request body."""
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            return {}
        body = self.rfile.read(content_length)
        return json.loads(body)

    def do_GET(self):
        """Handle GET requests."""
        if self.path == "/health":
            self._send_json({"status": "ok"})
            return

        if self.path == "/primer":
            if not self._check_auth():
                return
            try:
                primer_content = Path(PRIMER_PATH).read_text()
                self._send_text(primer_content)
            except FileNotFoundError:
                self.send_error(500, "Primer file not found")
            return

        if self.path == "/status":
            if not self._check_auth():
                return
            with active_jobs_lock:
                active = len(active_jobs)
            with queue_depth_lock:
                queued = queue_depth
            self._send_json({
                "active": active,
                "queued": queued,
                "max_concurrent": MAX_CONCURRENT,
            })
            return

        self.send_error(404, "Not found")

    def do_POST(self):
        """Handle POST requests."""
        if self.path != "/build":
            self.send_error(404, "Not found")
            return

        if not self._check_auth():
            return

        try:
            body = self._read_body()
        except (json.JSONDecodeError, ValueError) as e:
            self._send_json({"error": f"Invalid JSON: {e}"}, 400)
            return

        # Validate request
        source_type = body.get("source_type")
        if source_type not in ("git", "tarball"):
            self._send_json({"error": "source_type must be 'git' or 'tarball'"}, 400)
            return

        command = body.get("command", "build")
        if command not in ("build", "check"):
            self._send_json({"error": "command must be 'build' or 'check'"}, 400)
            return

        if source_type == "git":
            url = body.get("url")
            if not url:
                self._send_json({"error": "url is required for git source_type"}, 400)
                return
            ok, err = validate_git_url(url)
            if not ok:
                log_event("validation_error", field="url", reason=err,
                          client_ip=self.client_address[0])
                self._send_json({"error": err}, 400)
                return
            tarball_b64 = None
        else:
            url = None
            tarball_b64 = body.get("tarball_b64")
            if not tarball_b64:
                self._send_json({"error": "tarball_b64 is required for tarball source_type"}, 400)
                return
            # Check tarball size
            try:
                decoded_size = len(base64.b64decode(tarball_b64))
                if decoded_size > MAX_TARBALL_SIZE:
                    self._send_json({"error": f"Tarball too large ({decoded_size} bytes, max {MAX_TARBALL_SIZE})"}, 400)
                    return
            except Exception:
                self._send_json({"error": "Invalid base64 in tarball_b64"}, 400)
                return

        target = body.get("target", "")
        ok, err = validate_target(target)
        if not ok:
            log_event("validation_error", field="target", reason=err,
                      client_ip=self.client_address[0])
            self._send_json({"error": err}, 400)
            return

        timeout = min(int(body.get("timeout", BUILD_TIMEOUT)), 1800)

        # Check queue depth
        with queue_depth_lock:
            global queue_depth
            if queue_depth >= MAX_QUEUE_DEPTH:
                self._send_json({"error": "Queue full, try again later"}, 503)
                return
            queue_depth += 1

        try:
            # Acquire semaphore (blocks until a VM slot is available)
            vm_semaphore.acquire()

            with queue_depth_lock:
                queue_depth -= 1

            job_id = str(uuid.uuid4())

            # Find available slot
            with active_jobs_lock:
                used_slots = set(active_jobs.values())
                slot = 1
                while slot in used_slots:
                    slot += 1
                active_jobs[job_id] = slot

            try:
                if BUILD_MODE == "direct":
                    result = run_build_direct(job_id, source_type, url,
                                              tarball_b64, command, target,
                                              timeout)
                elif BUILD_MODE == "nspawn":
                    result = run_build_nspawn(job_id, source_type, url,
                                              tarball_b64, command, target,
                                              timeout, slot)
                else:
                    result = run_build(job_id, source_type, url, tarball_b64,
                                       command, target, timeout, slot)
                self._send_json(result)
            finally:
                with active_jobs_lock:
                    active_jobs.pop(job_id, None)
                vm_semaphore.release()

        except Exception as e:
            with queue_depth_lock:
                queue_depth = max(0, queue_depth - 1)
            self._send_json({"error": str(e)}, 500)

    def log_message(self, format, *args):
        """Override default logging with structured event."""
        log_event("http_request", message=args[0] if args else "",
                  client_ip=self.client_address[0])


class ThreadedHTTPServer(HTTPServer):
    """Handle each request in a new thread for concurrent builds."""

    def process_request(self, request, client_address):
        thread = threading.Thread(target=self._handle_request_thread,
                                  args=(request, client_address))
        thread.daemon = True
        thread.start()

    def _handle_request_thread(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            self.handle_error(request, client_address)
        finally:
            self.shutdown_request(request)


def main():
    """Start the nix sandbox service."""
    if not API_TOKEN:
        print("WARNING: API_TOKEN not set, service will reject all authenticated requests")

    if BUILD_MODE == "vm" and not VM_IMAGE:
        print("WARNING: VM_IMAGE not set, VM builds will fail")

    if BUILD_MODE == "nspawn" and not BUILD_ROOT:
        print("WARNING: BUILD_ROOT not set, nspawn builds will fail")

    if BUILD_MODE == "direct":
        log_event("config_warning",
                  message="BUILD_MODE=direct has no isolation; use nspawn for production")

    if not PRIMER_PATH:
        print("WARNING: PRIMER_PATH not set, /primer will fail")

    os.makedirs("/run/nix-sandbox", exist_ok=True)

    server = ThreadedHTTPServer(("0.0.0.0", PORT), SandboxHandler)
    print(f"Nix sandbox service listening on 0.0.0.0:{PORT}")
    print(f"Build mode: {BUILD_MODE}")
    print(f"Max concurrent builds: {MAX_CONCURRENT}")
    if BUILD_MODE == "vm":
        print(f"VM config: {VM_CPUS} vCPUs, {VM_MEMORY_MB}MB RAM")
    elif BUILD_MODE == "nspawn":
        print(f"Nspawn network: {NSPAWN_NETWORK}")
        print(f"Build root: {BUILD_ROOT}")
    print(f"Build timeout: {BUILD_TIMEOUT}s")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

    return 0


if __name__ == "__main__":
    exit(main())
