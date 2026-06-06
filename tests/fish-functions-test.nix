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

      # --- Global convenience functions ---

      # jd: should be defined as a function wrapping "jj desc -m"
      machine.succeed(
          'su - testuser -c "fish -c \'type jd\'" | grep -q "jj desc -m"'
      )
      machine.log("✅ jd function defined and wraps jj desc -m")

      # nr: should expand to "nix run nixpkgs#"
      machine.succeed(
          'su - testuser -c "fish -c \'type nr\'" | grep -q "nix run nixpkgs"'
      )
      machine.log("✅ nr function defined correctly")

      # ns: should expand to "nix shell nixpkgs#"
      machine.succeed(
          'su - testuser -c "fish -c \'type ns\'" | grep -q "nix shell nixpkgs"'
      )
      machine.log("✅ ns function defined correctly")

      # nru: should contain NIXPKGS_ALLOW_UNFREE
      machine.succeed(
          'su - testuser -c "fish -c \'type nru\'" | grep -q "NIXPKGS_ALLOW_UNFREE"'
      )
      machine.log("✅ nru function defined correctly")

      # nsu: should contain NIXPKGS_ALLOW_UNFREE
      machine.succeed(
          'su - testuser -c "fish -c \'type nsu\'" | grep -q "NIXPKGS_ALLOW_UNFREE"'
      )
      machine.log("✅ nsu function defined correctly")

      # cb: should be defined as a function (clipboard helper)
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

      # fish_vcs_prompt: should override default and include jj
      machine.succeed(
          'su - testuser -c "fish -c \'type fish_vcs_prompt\'" | grep -q "fish_jj_prompt"'
      )
      machine.log("✅ fish_vcs_prompt overrides default and includes jj")

      # --- Verify all 8 expected functions are present ---
      func_count = machine.succeed(
          'su - testuser -c "fish -c \'functions\'" 2>/dev/null | grep -cE "^(jd|nr|ns|nru|nsu|cb|fish_jj_prompt|fish_vcs_prompt)$"'
      ).strip()
      assert func_count == "8", f"Expected 8 custom functions, got {func_count}"
      machine.log(f"✅ All 8 custom functions present: {func_count}")

      machine.log("🎉 All fish function tests passed!")
    '';
  }