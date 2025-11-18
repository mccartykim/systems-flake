# Minimal VM test to figure out syntax
{pkgs}:
pkgs.nixosTest {
  name = "minimal-test";

  nodes.machine = {
    system.stateVersion = "24.11";
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    print("✅ Minimal test passed!")
  '';
}
