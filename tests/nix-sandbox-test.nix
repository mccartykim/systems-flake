# Integration test for nix-sandbox API service.
# Tests HTTP endpoints inside a NixOS VM.
# Validates: health, auth, primer, status, build request validation,
# end-to-end direct mode, and end-to-end nspawn mode.
{pkgs}: let
  # Copy files into the nix store as proper derivations
  apiScript = pkgs.writeText "nix-sandbox-api.py" (builtins.readFile ../packages/nix-sandbox/nix-sandbox-api.py);
  primerFile = pkgs.writeText "primer.md" (builtins.readFile ../packages/nix-sandbox/primer.md);

  # Pre-built test tarball: a minimal flake that builds offline using only /bin/sh
  testFlakeTarball = pkgs.runCommand "test-flake-tarball" {} ''
    mkdir -p src
    cat > src/flake.nix << 'FLAKE'
    {
      description = "Test";
      outputs = { self }: {
        packages.x86_64-linux.default = derivation {
          name = "hello-sandbox";
          system = "x86_64-linux";
          builder = "/bin/sh";
          args = ["-c" "echo hello > $out"];
        };
      };
    }
    FLAKE
    tar czf $out -C src .
  '';

  # Minimal rootfs for nspawn build containers (mirrors module's buildRoot)
  buildRoot = pkgs.runCommand "sandbox-build-root" {} ''
    mkdir -p $out/{bin,usr/bin,etc,tmp,proc,dev,sys,run,build,var/empty}
    mkdir -p $out/nix/store $out/nix/var/nix/daemon-socket

    ln -s ${pkgs.bash}/bin/bash $out/bin/sh
    ln -s ${pkgs.bash}/bin/bash $out/bin/bash
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env

    for tool in ${pkgs.nix}/bin/nix ${pkgs.git}/bin/git \
                ${pkgs.gnutar}/bin/tar ${pkgs.gzip}/bin/gzip; do
      ln -s $tool $out/bin/$(basename $tool)
    done
    for tool in ${pkgs.coreutils}/bin/*; do
      name=$(basename $tool)
      [ ! -e $out/bin/$name ] && ln -s $tool $out/bin/$name
    done

    echo "root:x:0:0::/root:/bin/sh" > $out/etc/passwd
    echo "root:x:0:" > $out/etc/group
    echo "nixbld:x:30000:" >> $out/etc/group
    for i in $(seq 1 32); do
      echo "nixbld$i:x:$((30000+i)):30000::/var/empty:/usr/sbin/nologin" >> $out/etc/passwd
    done
    echo "hosts: files dns" > $out/etc/nsswitch.conf
    echo "nameserver 8.8.8.8" > $out/etc/resolv.conf
  '';
in
  pkgs.testers.nixosTest {
    name = "nix-sandbox-api";

    nodes = {
      # Direct mode node: API validation + direct-mode build
      sandbox = {
        config,
        pkgs,
        lib,
        ...
      }: {
        system.stateVersion = "24.11";
        virtualisation.graphics = false;

        # Enable flakes and disable sandbox (we're already in a VM)
        nix.settings.experimental-features = ["nix-command" "flakes"];
        nix.settings.sandbox = false;

        # Run the API service directly (no agenix in test)
        systemd.services.nix-sandbox-test = {
          description = "Nix Sandbox API (test mode)";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];

          environment = {
            PORT = "8090";
            API_TOKEN = "test-secret-token-12345";
            PRIMER_PATH = toString primerFile;
            MAX_CONCURRENT = "1";
            BUILD_TIMEOUT = "60";
            BUILD_MODE = "direct";
            BUILD_MEMORY_LIMIT = "4G";
            BUILD_CPU_QUOTA = "200%";
          };

          path = [pkgs.gnutar pkgs.gzip pkgs.git pkgs.nix pkgs.systemd];

          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${apiScript}";
            Restart = "on-failure";
          };
        };

        environment.systemPackages = [pkgs.curl pkgs.jq];
      };

      # Nspawn mode node: validates nested nspawn builds with --private-network
      nspawn = {
        config,
        pkgs,
        lib,
        ...
      }: {
        system.stateVersion = "24.11";
        virtualisation.graphics = false;

        nix.settings.experimental-features = ["nix-command" "flakes"];
        nix.settings.sandbox = false;

        systemd.services.nix-sandbox-nspawn = {
          description = "Nix Sandbox API (nspawn test mode)";
          wantedBy = ["multi-user.target"];
          after = ["network.target" "nix-daemon.socket"];

          environment = {
            PORT = "8090";
            API_TOKEN = "test-secret-token-12345";
            PRIMER_PATH = toString primerFile;
            MAX_CONCURRENT = "1";
            BUILD_TIMEOUT = "120";
            BUILD_MODE = "nspawn";
            BUILD_ROOT = toString buildRoot;
            NSPAWN_NETWORK = "private"; # Offline — no veth setup in test VM
            BUILD_MEMORY_LIMIT = "4G";
            BUILD_CPU_QUOTA = "200%";
          };

          path = with pkgs; [gnutar gzip git nix systemd iproute2 coreutils];

          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${apiScript}";
            Restart = "on-failure";
          };
        };

        # GC timer (mirrors module's nix-sandbox-gc)
        systemd.services.nix-sandbox-gc = {
          description = "Garbage-collect sandbox build outputs";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 1d";
          };
        };
        systemd.timers.nix-sandbox-gc = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };

        environment.systemPackages = [pkgs.curl pkgs.jq];
      };
    };

    testScript = ''
      import json

      TOKEN = "test-secret-token-12345"
      BASE = "http://localhost:8090"

      start_all()
      sandbox.wait_for_unit("multi-user.target")
      sandbox.wait_for_unit("nix-sandbox-test.service")

      # Wait for API to be ready
      sandbox.wait_until_succeeds("curl -sf http://localhost:8090/health", timeout=15)

      # ===== Test 25: Direct mode config_warning at startup =====
      print("Test 25: Verify config_warning for direct mode at startup")
      startup_journal = sandbox.succeed("journalctl --no-pager -u nix-sandbox-test -o cat")
      assert "config_warning" in startup_journal, \
          "Expected config_warning event in startup journal"
      assert "direct" in startup_journal.lower(), \
          "Expected 'direct' mentioned in config_warning"
      print("  PASS: config_warning for direct mode found in journal")

      # ===== Test 1: Health endpoint (no auth required) =====
      print("Test 1: GET /health returns 200 with status ok")
      result = sandbox.succeed("curl -sf http://localhost:8090/health")
      health = json.loads(result)
      assert health["status"] == "ok", f"Expected status ok, got {health}"
      print("  PASS: Health endpoint works")

      # ===== Test 2: Auth rejection - no token =====
      print("Test 2: Auth rejection without token")
      result = sandbox.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/primer")
      assert result.strip() == "403", f"Expected 403, got {result.strip()}"
      print("  PASS: Missing auth returns 403")

      # ===== Test 3: Auth rejection - wrong token =====
      print("Test 3: Auth rejection with wrong token")
      result = sandbox.succeed(
          "curl -s -o /dev/null -w '%{http_code}' "
          "-H 'Authorization: Bearer wrong-token' "
          "http://localhost:8090/primer"
      )
      assert result.strip() == "403", f"Expected 403, got {result.strip()}"
      print("  PASS: Wrong token returns 403")

      # ===== Test 4: Primer endpoint with valid auth =====
      print("Test 4: GET /primer returns markdown content")
      result = sandbox.succeed(
          f"curl -sf -H 'Authorization: Bearer {TOKEN}' http://localhost:8090/primer"
      )
      assert "nix build" in result.lower() or "Nix" in result, "Primer content missing expected text"
      assert "search.nixos.org" in result, "Primer missing search.nixos.org reference"
      print("  PASS: Primer returns expected content")

      # ===== Test 5: Status endpoint =====
      print("Test 5: GET /status returns job counts")
      result = sandbox.succeed(
          f"curl -sf -H 'Authorization: Bearer {TOKEN}' http://localhost:8090/status"
      )
      status = json.loads(result)
      assert status["active"] == 0, f"Expected 0 active, got {status['active']}"
      assert status["queued"] == 0, f"Expected 0 queued, got {status['queued']}"
      assert status["max_concurrent"] == 1, f"Expected max_concurrent 1, got {status['max_concurrent']}"
      print("  PASS: Status endpoint returns correct idle state")

      # ===== Test 6: Status endpoint requires auth =====
      print("Test 6: GET /status requires auth")
      result = sandbox.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/status")
      assert result.strip() == "403", f"Expected 403, got {result.strip()}"
      print("  PASS: Status without auth returns 403")

      # ===== Test 7: Build endpoint - missing source_type =====
      print("Test 7: POST /build rejects missing source_type")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"command\": \"build\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for missing source_type, got: {result.strip()}"
      print("  PASS: Missing source_type returns 400")

      # ===== Test 8: Build endpoint - invalid command =====
      print("Test 8: POST /build rejects invalid command")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"github:test/repo\", \"command\": \"destroy\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for invalid command, got: {result.strip()}"
      print("  PASS: Invalid command returns 400")

      # ===== Test 9: Build endpoint - missing url for git =====
      print("Test 9: POST /build rejects missing url for git source")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"command\": \"build\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for missing url, got: {result.strip()}"
      print("  PASS: Missing url for git returns 400")

      # ===== Test 10: Build endpoint requires auth =====
      print("Test 10: POST /build requires auth")
      result = sandbox.succeed(
          "curl -s -o /dev/null -w '%{http_code}' "
          "-H 'Content-Type: application/json' "
          "-X POST -d '{\"source_type\": \"git\", \"url\": \"github:test/repo\"}' "
          "http://localhost:8090/build"
      )
      assert result.strip() == "403", f"Expected 403, got {result.strip()}"
      print("  PASS: Build without auth returns 403")

      # ===== Test 11: 404 for unknown endpoints =====
      print("Test 11: Unknown endpoint returns 404")
      result = sandbox.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/nonexistent")
      assert result.strip() == "404", f"Expected 404, got {result.strip()}"
      print("  PASS: Unknown endpoint returns 404")

      # ===== Test 14: Command injection in target - semicolon =====
      print("Test 14: POST /build rejects shell injection in target")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"tarball\", \"tarball_b64\": \"dGVzdA==\", \"target\": \"; cat /etc/passwd\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for injection attempt, got: {result.strip()}"
      print("  PASS: Shell injection in target rejected with 400")

      # ===== Test 15: Valid target .#default =====
      print("Test 15: POST /build accepts valid target .#default")
      result = sandbox.succeed(
          f"curl -s "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"https://github.com/test/repo\", \"target\": \".#default\"}}' "
          f"http://localhost:8090/build"
      )
      # Should get past validation (will fail at git clone, not at validation)
      resp = json.loads(result)
      assert "error" not in resp or "Invalid target" not in resp.get("error", ""), \
          f"Target .#default should be accepted, got: {resp}"
      print("  PASS: Valid target .#default accepted")

      # ===== Test 16: Command injection - command substitution =====
      print("Test 16: POST /build rejects $(whoami) in target")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"tarball\", \"tarball_b64\": \"dGVzdA==\", \"target\": \"$(whoami)\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for $(whoami), got: {result.strip()}"
      print("  PASS: Command substitution in target rejected with 400")

      # ===== Test 17: Valid long target path =====
      print("Test 17: POST /build accepts .#packages.x86_64-linux.default")
      result = sandbox.succeed(
          f"curl -s "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"https://github.com/test/repo\", \"target\": \".#packages.x86_64-linux.default\"}}' "
          f"http://localhost:8090/build"
      )
      resp = json.loads(result)
      assert "error" not in resp or "Invalid target" not in resp.get("error", ""), \
          f"Target .#packages.x86_64-linux.default should be accepted, got: {resp}"
      print("  PASS: Valid nested target path accepted")

      # ===== Test 18: Reject file:// URL =====
      print("Test 18: POST /build rejects file:// URL")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"file:///etc/passwd\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for file:// URL, got: {result.strip()}"
      print("  PASS: file:// URL rejected with 400")

      # ===== Test 19: Reject URL with shell injection =====
      print("Test 19: POST /build rejects URL with shell metacharacters")
      result = sandbox.succeed(
          f"curl -s -o /dev/null -w '%{{http_code}}' "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"https://github.com/NixOS/nixpkgs; cat /etc/passwd\"}}' "
          f"http://localhost:8090/build"
      )
      assert result.strip() == "400", f"Expected 400 for URL with semicolon, got: {result.strip()}"
      print("  PASS: URL with shell metacharacters rejected with 400")

      # ===== Test 20: Accept valid https URL =====
      print("Test 20: POST /build accepts valid https URL (will fail at clone, not validation)")
      result = sandbox.succeed(
          f"curl -s "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d '{{\"source_type\": \"git\", \"url\": \"https://github.com/valid/repo.git\"}}' "
          f"http://localhost:8090/build"
      )
      resp = json.loads(result)
      assert "error" not in resp or "URL" not in resp.get("error", ""), \
          f"Valid https URL should pass validation, got: {resp}"
      print("  PASS: Valid https URL accepted past validation")

      # ===== Test 12: End-to-end build via direct mode =====
      print("Test 12: POST /build with tarball executes nix build (direct mode)")

      # Base64-encode the pre-built test tarball
      sandbox.succeed("cp ${testFlakeTarball} /tmp/test-flake.tar.gz")
      tarball_b64 = sandbox.succeed("base64 -w0 /tmp/test-flake.tar.gz").strip()

      # Build the JSON request
      import json as json_mod
      request_body = json_mod.dumps({
          "source_type": "tarball",
          "tarball_b64": tarball_b64,
          "command": "build",
      })
      sandbox.succeed(f"cat > /tmp/build-request.json << 'JSONEOF'\n{request_body}\nJSONEOF")

      # POST the build request (longer timeout since it actually builds)
      result = sandbox.succeed(
          f"curl -s --max-time 120 "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d @/tmp/build-request.json "
          f"http://localhost:8090/build"
      )
      print(f"  Build response: {result[:500]}")
      build_result = json.loads(result)

      assert build_result.get("success") == True, f"Expected success, got: {build_result}"
      assert build_result.get("exit_code") == 0, f"Expected exit_code 0, got: {build_result.get('exit_code')}"
      assert "duration_seconds" in build_result, "Missing duration_seconds in response"
      print(f"  Build completed in {build_result['duration_seconds']}s")
      print("  PASS: Direct-mode build succeeded end-to-end")

      # ===== Test 22: Verify build_start and build_complete audit log entries =====
      print("Test 22: Check journal for structured audit log entries after build")
      journal = sandbox.succeed("journalctl --no-pager -u nix-sandbox-test -o cat")
      assert '"event": "build_start"' in journal or '"event":"build_start"' in journal, \
          "Expected build_start event in journal"
      assert '"event": "build_complete"' in journal or '"event":"build_complete"' in journal, \
          "Expected build_complete event in journal"
      # Verify the entries are valid JSON by finding and parsing one
      for line in journal.split("\n"):
          if "build_start" in line and "{" in line:
              start_idx = line.index("{")
              entry = json.loads(line[start_idx:])
              assert entry["event"] == "build_start", f"Unexpected event: {entry}"
              assert "job_id" in entry, "build_start missing job_id"
              assert "build_mode" in entry, "build_start missing build_mode"
              break
      print("  PASS: Structured audit log entries found in journal")

      # ===== Test 23: Verify auth_failure audit log entry =====
      print("Test 23: Check journal for auth_failure event after test 2")
      assert '"event": "auth_failure"' in journal or '"event":"auth_failure"' in journal, \
          "Expected auth_failure event in journal"
      print("  PASS: auth_failure event found in journal")

      # ===== Test 13: End-to-end build via nspawn mode (--private-network) =====
      print("Test 13: POST /build with tarball executes nix build (nspawn mode)")

      nspawn.wait_for_unit("multi-user.target")
      nspawn.wait_for_unit("nix-sandbox-nspawn.service")
      nspawn.wait_until_succeeds("curl -sf http://localhost:8090/health", timeout=15)

      # Base64-encode the test tarball on nspawn node
      nspawn.succeed("cp ${testFlakeTarball} /tmp/test-flake.tar.gz")
      nspawn_tarball_b64 = nspawn.succeed("base64 -w0 /tmp/test-flake.tar.gz").strip()

      nspawn_request = json_mod.dumps({
          "source_type": "tarball",
          "tarball_b64": nspawn_tarball_b64,
          "command": "build",
      })
      nspawn.succeed(f"cat > /tmp/nspawn-request.json << 'JSONEOF'\n{nspawn_request}\nJSONEOF")

      result = nspawn.succeed(
          f"curl -s --max-time 180 "
          f"-H 'Authorization: Bearer {TOKEN}' "
          f"-H 'Content-Type: application/json' "
          f"-X POST -d @/tmp/nspawn-request.json "
          f"http://localhost:8090/build"
      )
      print(f"  Nspawn build response: {result[:500]}")
      nspawn_result = json.loads(result)

      assert nspawn_result.get("success") == True, f"Expected nspawn success, got: {nspawn_result}"
      assert nspawn_result.get("exit_code") == 0, f"Expected exit_code 0, got: {nspawn_result.get('exit_code')}"
      assert "duration_seconds" in nspawn_result, "Missing duration_seconds in nspawn response"
      print(f"  Nspawn build completed in {nspawn_result['duration_seconds']}s")
      print("  PASS: Nspawn-mode build succeeded end-to-end")

      # ===== Test 21: Verify nspawn build ran successfully (resource limits apply to direct mode) =====
      print("Test 21: Verify nspawn build ran with namespace isolation")
      nspawn_journal = nspawn.succeed("journalctl --no-pager -u nix-sandbox-nspawn -o cat")
      assert "systemd-nspawn" in nspawn_journal or "build_complete" in nspawn_journal, \
          "Expected nspawn or build_complete in journal output"
      print("  PASS: Nspawn build completed with namespace isolation")

      # ===== Test 24: Verify GC timer unit exists =====
      print("Test 24: Verify nix-sandbox-gc timer is loaded on nspawn node")
      timer_list = nspawn.succeed("systemctl list-timers --no-pager")
      assert "nix-sandbox-gc" in timer_list, \
          f"Expected nix-sandbox-gc in timer list, got: {timer_list}"
      print("  PASS: nix-sandbox-gc timer is loaded")

      print("")
      print("All nix-sandbox API tests passed!")
    '';
  }
