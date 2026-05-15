# Security Regression Tests (designed to fail)

Each test in this directory pins one HIGH-severity finding from
`docs/security-audit.md` (sf-h30). **These tests are designed to FAIL on
current `main`.** That is the point: CI surfaces the gap until the
corresponding fix lands, at which point the test flips to passing.

This mirrors the pattern used by the `lo-0xw` bead: capture the gap as an
executable check rather than a free-text TODO.

## Mapping: finding → test

| Audit ID | Section                                                | Test file                       |
| -------- | ------------------------------------------------------ | ------------------------------- |
| N-1      | `vacuum.kimb.dev` public with 1FA only                 | `vacuum-ip-restriction.nix`     |
| N-2      | `kimb-services` has no guard against `publicAccess=true` + `auth="none"` on internal-looking subdomains | `auth-none-guard.nix`           |
| N-3      | `buildbot.kimb.dev` public, GitHub OAuth only          | `buildbot-ip-restriction.nix`   |
| H-1      | `webcam@` socket-activated service has zero hardening  | `webcam-hardening.nix`          |

## Test shapes

- **`webcam-hardening.nix`** is a true `pkgs.testers.nixosTest` (single
  node). It boots a VM that imports `hosts/rich-evans/camera.nix` and
  inspects `systemctl show 'webcam@<inst>.service'` for expected hardening
  directives.

- **`vacuum-ip-restriction.nix`** and **`buildbot-ip-restriction.nix`**
  are `pkgs.runCommand` derivations. They evaluate
  `self.nixosConfigurations.maitred` and inspect the rendered Caddy
  `virtualHosts.<name>.extraConfig` string for the `remote_ip` IP-allowlist
  pattern. A proper end-to-end VM test (boot maitred-equivalent + a
  non-LAN client and curl the URL) would require unwinding the nested
  NixOS container that hosts Caddy — out of scope here; see follow-up
  beads in the audit document.

- **`auth-none-guard.nix`** is a `pkgs.runCommand` derivation that
  evaluates `modules/kimb-services.nix` against a deliberately bad config
  (`publicAccess = true`, `auth = "none"`, internal-looking subdomain)
  and asserts that a guarding assertion fires. Today there is no such
  assertion, so the test fails.

## Running

The tests are wired into `flake.nix` `checks` so:

```bash
nix flake check                                                # runs them all
nix build .#checks.x86_64-linux.security-webcam-hardening      # one test
nix build .#checks.x86_64-linux.security-vacuum-ip-restriction
nix build .#checks.x86_64-linux.security-buildbot-ip-restriction
nix build .#checks.x86_64-linux.security-auth-none-guard
```

All four will fail on current `main`. Each prints a one-line `FAIL: ...`
explaining which audit finding it pins.

## When a fix lands

Removing the test is the wrong move: leave it in place so the regression
is caught if the fix is ever reverted. The test simply flips from RED to
GREEN.

If the audit finding is later marked WONTFIX (e.g., a deliberate
acceptance of the risk), then the test should be deleted *together* with
the audit-document edit explaining why, and a note added to this README.
