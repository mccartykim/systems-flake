# Security regression — pins H-1 from docs/security-audit.md.
#
# `hosts/rich-evans/camera.nix` declares `systemd.services."webcam@"` with no
# hardening directives. This test boots a VM importing that module and asserts
# that the instantiated unit has the expected hardening properties.
#
# Designed to FAIL today: until camera.nix gains `NoNewPrivileges`,
# `ProtectSystem`, `PrivateTmp`, etc., this test exits non-zero.
{pkgs}:
pkgs.testers.nixosTest {
  name = "security-regression-webcam-hardening";

  nodes.machine = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [../../hosts/rich-evans/camera.nix];

    # camera.nix opens TCP 8554 in the firewall, fine for a test VM.
    networking.firewall.enable = false;

    virtualisation.graphics = false;

    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Template service: instantiate a concrete name to inspect.
    # `systemctl show` works on uninstantiated templates too, but using a
    # concrete instance keeps the output closer to runtime behavior.
    inst = "webcam@cam0.service"

    # Each property is the smallest demonstrable hardening assertion for
    # H-1. Mapping: docs/security-audit.md section 3 H-1 "Fix" block.
    checks = [
        ("NoNewPrivileges", "yes"),
        ("PrivateTmp", "yes"),
        ("ProtectHome", "yes"),
        # ProtectSystem returns "strict" / "full" / "true" / "no"; the
        # audit's fix sets it to "strict".
        ("ProtectSystem", "strict"),
        ("LockPersonality", "yes"),
        ("RestrictRealtime", "yes"),
    ]

    failures = []
    for prop, want in checks:
        got = machine.succeed(
            f"systemctl show '{inst}' -p {prop} --value"
        ).strip()
        if got != want:
            failures.append(f"  {prop}: got {got!r}, want {want!r}")

    if failures:
        msg = (
            "FAIL: H-1 webcam@ hardening regression — "
            f"{len(failures)} property mismatch(es):\n"
            + "\n".join(failures)
            + "\nSee docs/security-audit.md section 3, finding H-1."
        )
        raise Exception(msg)

    print("PASS: webcam@ has expected systemd hardening")
  '';
}
