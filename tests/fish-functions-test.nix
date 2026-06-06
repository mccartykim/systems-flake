# Fish functions integration test
#
# Verifies that the fish-functions module correctly defines all convenience
# functions and the jj VCS prompt. Runs in a minimal NixOS VM with fish
# installed and home-manager configured.
#
# Run with: nix build .#checks.x86_64-linux.fish-functions-test
{
  pkgs,
  inputs,
}: let
  # Import the fish-functions module
  fishFunctionsModule = import ../home/modules/fish-functions.nix;

  # A minimal home-manager config that enables fish-functions
  testHomeConfig = {
    imports = [fishFunctionsModule];
    modules.fish-functions = {
      enable = true;
      includeJjPrompt = true;
    };
    programs.fish.enable = true;
    home.username = "testuser";
    home.homeDirectory = "/home/testuser";
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
  };
in
  pkgs.testers.runNixOSTest {
    name = "fish-functions";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      imports = [inputs.home-manager.nixosModules.home-manager];

      # Enable fish as system shell
      programs.fish.enable = true;

      users.users.testuser = {
        isNormalUser = true;
        shell = pkgs.fish;
      };

      # Deploy home-manager config for testuser
      home-manager = {
        backupFileExtension = "backup";
        useGlobalPkgs = true;
        useUserPackages = true;
        users.testuser = testHomeConfig;
      };

      system.stateVersion = "24.11";
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      # Wait for home-manager activation
      machine.succeed("systemctl --user -M testuser@ wait-home-manager-testuser.service 2>/dev/null || true")
      machine.execute("sleep 3")

      # Helper: check that a fish function is defined and its body contains expected text
      def check_fish_func(name, expected_text):
          result = machine.succeed(
              f'su - testuser -c "fish -c \'type {name}\'"'
          )
          if expected_text not in result:
              raise Exception(f"Function {name}: expected '{expected_text}' in output, got: {result}")
          machine.log(f"✅ {name} function defined correctly")

      # --- Global convenience functions ---
      check_fish_func("jd", "jj desc -m")
      check_fish_func("nr", "nix run nixpkgs")
      check_fish_func("ns", "nix shell nixpkgs")
      check_fish_func("nru", "NIXPKGS_ALLOW_UNFREE")
      check_fish_func("nsu", "NIXPKGS_ALLOW_UNFREE")
      check_fish_func("cb", "fish_clipboard_copy")

      # --- JJ VCS prompt functions ---
      # fish_jj_prompt: defined and contains "jj log"
      check_fish_func("fish_jj_prompt", "jj log")

      # fish_vcs_prompt: overrides default, includes fish_jj_prompt
      check_fish_func("fish_vcs_prompt", "fish_jj_prompt")

      # --- Verify all 8 expected functions are present ---
      func_list = machine.succeed(
          'su - testuser -c "fish -c \'functions\'" 2>/dev/null'
      )
      for name in ["jd", "nr", "ns", "nru", "nsu", "cb", "fish_jj_prompt", "fish_vcs_prompt"]:
          assert name in func_list, f"Function {name} not found in fish functions list"
      machine.log("✅ All 8 custom functions present in fish functions list")

      machine.log("🎉 All fish function tests passed!")
    '';
  }