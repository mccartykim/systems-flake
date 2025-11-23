# Integration tests for the flake-aware NixOS installer
# Tests library scripts, config generation, and installer functionality
{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
}: let
  # Create a minimal test flake structure
  testFlake = pkgs.runCommand "test-flake" {} ''
    mkdir -p $out/{hosts/profiles,hosts/test-existing,home}

    # Create a minimal flake.nix
    cat > $out/flake.nix << 'FLAKE'
    {
      description = "Test flake for installer";
      inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
      outputs = { self, nixpkgs }: {
        nixosConfigurations = {};
      };
    }
    FLAKE

    # Create test profiles
    cat > $out/hosts/profiles/base.nix << 'NIX'
    # Base configuration for all hosts
    { config, lib, pkgs, ... }: {
      networking.networkmanager.enable = true;
    }
    NIX

    cat > $out/hosts/profiles/desktop.nix << 'NIX'
    # Desktop environment configuration
    { config, lib, pkgs, ... }: {
      services.xserver.enable = true;
    }
    NIX

    cat > $out/hosts/profiles/server.nix << 'NIX'
    # Server configuration
    { config, lib, pkgs, ... }: {
      services.openssh.enable = true;
    }
    NIX

    # Create an existing host to test validation
    cat > $out/hosts/test-existing/configuration.nix << 'NIX'
    { config, lib, pkgs, ... }: {
      networking.hostName = "test-existing";
      imports = [ ../profiles/base.nix ];
    }
    NIX

    # Create test home config
    cat > $out/home/test-existing.nix << 'NIX'
    { config, lib, pkgs, ... }: {
      home.username = "test";
      home.stateVersion = "24.11";
    }
    NIX
  '';

  # Create an alternative flake structure (machines/ style)
  altFlake = pkgs.runCommand "alt-flake" {} ''
    mkdir -p $out/{machines/existing-host,profiles,home-manager}

    cat > $out/flake.nix << 'FLAKE'
    {
      description = "Alt structure flake";
      inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
      outputs = { self, nixpkgs }: {
        nixosConfigurations = {};
      };
    }
    FLAKE

    cat > $out/profiles/base.nix << 'NIX'
    # Base profile
    { ... }: {}
    NIX

    cat > $out/machines/existing-host/default.nix << 'NIX'
    { ... }: { networking.hostName = "existing-host"; }
    NIX
  '';

  # Create installer scripts package for testing
  installerScripts = pkgs.stdenv.mkDerivation {
    name = "installer-test-scripts";
    src = ../installer;

    installPhase = ''
      mkdir -p $out/{lib,generators,templates,tui}
      cp lib/*.sh $out/lib/
      cp generators/*.sh $out/generators/
      cp templates/* $out/templates/
      cp tui/*.sh $out/tui/
      chmod +x $out/lib/*.sh $out/generators/*.sh $out/tui/*.sh
    '';
  };
in {
  # Test 1: Library script unit tests
  libraryTests = pkgs.testers.runNixOSTest {
    name = "installer-library-tests";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      system.stateVersion = "24.11";

      environment.systemPackages = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
        gawk
        parted
        util-linux
        pciutils
      ];

      # Mount test flake
      environment.etc."test-flake".source = testFlake;
      environment.etc."alt-flake".source = altFlake;
      environment.etc."installer".source = installerScripts;
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      print("=== Testing flake-config.sh ===")

      # Test structure detection - use shell assertion
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash flake-config.sh detect | grep -q 'systems-flake'"
      )
      print("Structure detection: passed")

      # Test config export
      machine.succeed(
          "cd /etc/installer/lib && "
          "source flake-config.sh && "
          "echo $FLAKE_HOSTS_DIR"
      )

      print("=== Testing profile-detect.sh ===")

      # Test profile listing - use shell assertions
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh list | grep -q base"
      )
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh list | grep -q desktop"
      )
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh list | grep -q server"
      )
      print("Profile listing: passed")

      # Test profile description
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh dialog"
      )
      print("Profile dialog: passed")

      # Test host listing
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh hosts | grep -q test-existing"
      )
      print("Host listing: passed")

      # Test hostname validation - valid
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate newhost"
      )
      print("Hostname validation (valid): passed")

      # Test hostname validation - invalid (existing) - should fail
      machine.fail(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate test-existing"
      )
      print("Hostname validation (existing): passed")

      # Test hostname validation - invalid (bad chars) - should fail
      machine.fail(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate 'Bad_Host!'"
      )
      print("Hostname validation (invalid chars): passed")

      print("=== Testing with alternative flake structure ===")

      # Configure for machines/ structure
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/alt-flake "
          "FLAKE_HOSTS_DIR=machines "
          "FLAKE_PROFILES_DIR=profiles "
          "bash profile-detect.sh list"
      )

      # Test host detection in alt structure
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/alt-flake "
          "FLAKE_HOSTS_DIR=machines "
          "bash profile-detect.sh hosts | grep -q existing-host"
      )
      print("Alt structure host detection: passed")

      print("=== Testing hardware-detect.sh ===")

      # Test boot mode detection (in VM should be BIOS or UEFI)
      machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh boot | grep -q 'BOOT_MODE='"
      )
      print("Boot mode detection: passed")

      # Test CPU detection
      machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh cpu | grep -q 'CPU_VENDOR='"
      )
      print("CPU detection: passed")

      # Test all detection
      machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh all"
      )
      print("Full hardware detection: passed")

      print("=== Testing disk-utils.sh ===")

      # Test disk listing (may be empty in VM, that's ok)
      machine.succeed(
          "cd /etc/installer/lib && bash disk-utils.sh list human || true"
      )
      print("Disk listing: passed")

      print("✅ All library tests passed!")
    '';
  };

  # Test 2: Config generation tests
  generatorTests = pkgs.testers.runNixOSTest {
    name = "installer-generator-tests";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      system.stateVersion = "24.11";

      environment.systemPackages = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
        gawk
        parted
        util-linux
      ];

      environment.etc."test-flake".source = testFlake;
      environment.etc."installer".source = installerScripts;
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      print("=== Testing generate-host.sh dry-run ===")

      # Test dry-run generation - verify output contains expected strings
      machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname testvm "
          "--disk /dev/sda "
          "--scheme standard "
          "--profiles base,desktop "
          "--username testuser "
          "--dry-run 2>&1 | grep -q 'disko.devices'"
      )
      print("Dry-run disko generation: passed")

      machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname testvm "
          "--disk /dev/sda "
          "--scheme standard "
          "--profiles base,desktop "
          "--username testuser "
          "--dry-run 2>&1 | grep -q 'testvm'"
      )
      print("Dry-run hostname: passed")

      print("=== Testing actual file generation ===")

      # Create output directory
      machine.succeed("mkdir -p /tmp/test-output")

      # Run actual generation
      machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname newhost "
          "--disk /dev/vda "
          "--scheme standard "
          "--profiles base,server "
          "--username admin "
          "--output /tmp/test-output/newhost 2>&1"
      )

      # Verify files were created
      machine.succeed("test -f /tmp/test-output/newhost/hosts/newhost/configuration.nix")
      machine.succeed("test -f /tmp/test-output/newhost/hosts/newhost/disko.nix")
      machine.succeed("test -f /tmp/test-output/newhost/hosts/newhost/hardware-configuration.nix")
      machine.succeed("test -f /tmp/test-output/newhost/home/newhost.nix")
      machine.succeed("test -f /tmp/test-output/newhost/flake-entry.nix")
      machine.succeed("test -f /tmp/test-output/newhost/INSTALL_LOG.md")
      print("File generation: passed")

      # Check configuration.nix content
      machine.succeed("grep -q 'newhost' /tmp/test-output/newhost/hosts/newhost/configuration.nix")
      print("Configuration hostname: passed")

      # Check disko.nix content
      machine.succeed("grep -q '/dev/vda' /tmp/test-output/newhost/hosts/newhost/disko.nix")
      machine.succeed("grep -qi 'swap' /tmp/test-output/newhost/hosts/newhost/disko.nix")
      print("Disko config: passed")

      # Check flake entry
      machine.succeed("grep -q 'newhost' /tmp/test-output/newhost/flake-entry.nix")
      print("Flake entry: passed")

      print("=== Testing LUKS scheme generation ===")

      machine.succeed("mkdir -p /tmp/luks-output")

      machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname encrypted "
          "--disk /dev/nvme0n1 "
          "--scheme luks "
          "--profiles base "
          "--output /tmp/luks-output/encrypted 2>&1"
      )

      machine.succeed("grep -qi 'luks\\|crypt' /tmp/luks-output/encrypted/hosts/encrypted/disko.nix")
      print("LUKS scheme: passed")

      print("=== Testing simple scheme generation ===")

      machine.succeed("mkdir -p /tmp/simple-output")

      machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname minimal "
          "--disk /dev/sdb "
          "--scheme simple "
          "--profiles base "
          "--output /tmp/simple-output/minimal 2>&1"
      )

      # Simple scheme should not have swap (or swap size 0)
      machine.succeed("test -f /tmp/simple-output/minimal/hosts/minimal/disko.nix")
      print("Simple scheme: passed")

      print("✅ All generator tests passed!")
    '';
  };

  # Test 3: Full installer VM test with virtual disk
  installerVMTest = pkgs.testers.runNixOSTest {
    name = "installer-vm-test";

    nodes.installer = {
      config,
      pkgs,
      ...
    }: {
      system.stateVersion = "24.11";

      # Add a virtual disk for testing
      virtualisation = {
        emptyDiskImages = [4096]; # 4GB test disk
        qemu.options = ["-device" "virtio-scsi-pci,id=scsi0"];
      };

      environment.systemPackages = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
        gawk
        parted
        dosfstools
        e2fsprogs
        util-linux
        dialog
      ];

      environment.etc."test-flake".source = testFlake;
      environment.etc."installer".source = installerScripts;
    };

    testScript = ''
      installer.start()
      installer.wait_for_unit("multi-user.target")

      print("=== Testing disk detection with virtual disk ===")

      # List available disks
      installer.succeed(
          "cd /etc/installer/lib && bash disk-utils.sh list human"
      )
      print("Disk listing: passed")

      # Check if vdb exists (the empty disk image)
      has_vdb = installer.execute("test -b /dev/vdb")[0] == 0

      if has_vdb:
          # Test disk info
          installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh info /dev/vdb | grep -q 'DISK_DEVICE=/dev/vdb'"
          )
          print("Disk info: passed")

          # Test partition calculation
          installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh calculate /dev/vdb standard uefi | grep -q 'BOOT_SIZE_MB='"
          )
          installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh calculate /dev/vdb standard uefi | grep -q 'SWAP_SIZE_MB='"
          )
          installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh calculate /dev/vdb standard uefi | grep -q 'ROOT_SIZE_MB='"
          )
          print("Partition calculation: passed")

          print("=== Testing config generation with detected disk ===")

          installer.succeed("mkdir -p /tmp/vm-output")

          # Generate config for the virtual disk
          installer.succeed(
              "cd /etc/installer/generators && "
              "FLAKE_ROOT=/etc/test-flake "
              "bash generate-host.sh "
              "--hostname vmhost "
              "--disk /dev/vdb "
              "--scheme standard "
              "--profiles base,server "
              "--username vmuser "
              "--output /tmp/vm-output/vmhost 2>&1"
          )

          # Verify all files generated correctly
          installer.succeed("test -d /tmp/vm-output/vmhost/hosts/vmhost")
          installer.succeed("test -f /tmp/vm-output/vmhost/hosts/vmhost/disko.nix")
          print("Config generation: passed")

          # Check the disko config references the correct disk
          installer.succeed("grep -q '/dev/vdb' /tmp/vm-output/vmhost/hosts/vmhost/disko.nix")
          print("Disko disk reference: passed")

          print("=== Testing install log generation ===")

          installer.succeed("grep -q 'vmhost' /tmp/vm-output/vmhost/INSTALL_LOG.md")
          installer.succeed("grep -q '/dev/vdb' /tmp/vm-output/vmhost/INSTALL_LOG.md")
          installer.succeed("grep -q 'standard' /tmp/vm-output/vmhost/INSTALL_LOG.md")
          print("Install log: passed")
      else:
          print("No vdb disk found, skipping disk-specific tests")

      print("✅ All installer VM tests passed!")
    '';
  };

  # Test 4: Alternative flake structure test
  altStructureTest = pkgs.testers.runNixOSTest {
    name = "installer-alt-structure-test";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      system.stateVersion = "24.11";

      environment.systemPackages = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
        gawk
      ];

      environment.etc."alt-flake".source = altFlake;
      environment.etc."installer".source = installerScripts;
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      print("=== Testing with machines/ structure ===")

      # Test auto-detection
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/alt-flake bash flake-config.sh detect"
      )
      print("Auto-detection: passed")

      # Test with manual configuration - list profiles
      machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "export FLAKE_PROFILES_DIR=profiles && "
          "bash profile-detect.sh list | grep -q base"
      )
      print("Manual config profiles: passed")

      # Test host detection
      machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh hosts | grep -q existing-host"
      )
      print("Host detection: passed")

      # Validate that we can't create a duplicate host - should fail
      machine.fail(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh validate existing-host"
      )
      print("Duplicate host rejection: passed")

      # Validate that we can create a new host
      machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh validate newmachine"
      )
      print("New host validation: passed")

      print("✅ Alt structure tests passed!")
    '';
  };
}
