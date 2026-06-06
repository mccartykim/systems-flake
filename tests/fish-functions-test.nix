# Fish functions integration test
#
# Verifies that the fish-functions module correctly defines all convenience
# functions and the jj VCS prompt. Runs in a minimal NixOS VM with fish
# installed and the module enabled.
#
# Run with: nix build .#checks.x86_64-linux.fish-functions-test
{pkgs}: let
  # Import the fish-functions module for testing
  fishFunctionsModule = import ../home/modules/fish-functions.nix;

  # A minimal home-manager config that enables fish-functions
  testHomeManagerConfig = {
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
      # Enable fish as system shell
      programs.fish.enable = true;
      users.users.testuser = {
        isNormalUser = true;
        shell = pkgs.fish;
      };

      # Deploy the home-manager config for testuser
      home-manager.users.testuser = testHomeManagerConfig;

      system.stateVersion = "24.11";
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      # Wait for home-manager activation
      machine.succeed("systemctl --user -M testuser@ wait home-manager-testuser.service || true")

      # Test each fish function by checking it's defined and expands correctly
      # We use `fish -c` to run commands in fish and check the output

      # --- Global convenience functions ---

      # jd: should expand to "jj desc -m" with the argument
      machine.succeed(
          'su - testuser -c "fish -c \'type jd\'" | grep -q "jj desc -m"'
      )
      machine.log("✅ jd function defined correctly")

      # nr: should expand to "nix run nixpkgs#" with the argument
      machine.succeed(
          'su - testuser -c "fish -c \'type nr\'" | grep -q "nix run nixpkgs"'
      )
      machine.log("✅ nr function defined correctly")

      # ns: should expand to "nix shell nixpkgs#"
      machine.succeed(
          'su - testuser -c "fish -c \'type ns\'" | grep -q "nix shell nixpkgs"'
      )
      machine.log("✅ ns function defined correctly")

      # nru: should expand to "NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#"
      machine.succeed(
          'su - testuser -c "fish -c \'type nru\'" | grep -q "NIXPKGS_ALLOW_UNFREE"'
      )
      machine.log("✅ nru function defined correctly")

      # nsu: should expand to "NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#"
      machine.succeed(
          'su - testuser -c "fish -c \'type nsu\'" | grep -q "NIXPKGS_ALLOW_UNFREE"'
      )
      machine.log("✅ nsu function defined correctly")

      # cb: should be defined as a function
      machine.succeed(
          'su - testuser -c "fish -c \'type cb\'" | grep -q "function"'
      )
      machine.log("✅ cb function defined correctly")

      # --- JJ VCS prompt functions ---

      # fish_jj_prompt: should be defined
      machine.succeed(
          'su - testuser -c "fish -c \'type fish_jj_prompt\'" | grep -q "function"'
      )
      machine.log("✅ fish_jj_prompt function defined correctly")

      # fish_vcs_prompt: should override the default and include jj
      machine.succeed(
          'su - testuser -c "fish -c \'type fish_vcs_prompt\'" | grep -q "fish_jj_prompt"'
      )
      machine.log("✅ fish_vcs_prompt function overrides default correctly")

      # --- Verify functions NOT defined when module is disabled ---
      # (This would require a second node, but we can at least verify
      #  the current node has all expected functions)

      # Count all custom functions (should have at least our 8)
      func_count = machine.succeed(
          'su - testuser -c "fish -c \'functions\'" | grep -cE "^(jd|nr|ns|nru|nsu|cb|fish_jj_prompt|fish_vcs_prompt)$"'
      ).strip()
      assert func_count == "8", f"Expected 8 custom functions, got {func_count}"
      machine.log(f"✅ All 8 custom functions present: {func_count}")

      machine.log("🎉 All fish function tests passed!")
    '';
  }