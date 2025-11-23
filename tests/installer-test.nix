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

      # Test structure detection
      result = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash flake-config.sh detect"
      )
      print(f"Structure detection: {result}")
      assert "systems-flake" in result, "Should detect systems-flake structure"

      # Test config export
      machine.succeed(
          "cd /etc/installer/lib && "
          "source flake-config.sh && "
          "echo $FLAKE_HOSTS_DIR"
      )

      print("=== Testing profile-detect.sh ===")

      # Test profile listing
      profiles = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh list"
      )
      print(f"Profiles found: {profiles}")
      assert "base" in profiles, "Should find base profile"
      assert "desktop" in profiles, "Should find desktop profile"
      assert "server" in profiles, "Should find server profile"

      # Test profile description
      desc = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh dialog"
      )
      print(f"Profile dialog output: {desc}")

      # Test host listing
      hosts = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh hosts"
      )
      print(f"Hosts found: {hosts}")
      assert "test-existing" in hosts, "Should find existing host"

      # Test hostname validation - valid
      machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate newhost"
      )

      # Test hostname validation - invalid (existing)
      result = machine.execute(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate test-existing"
      )
      assert result[0] != 0, "Should reject existing hostname"

      # Test hostname validation - invalid (bad chars)
      result = machine.execute(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/test-flake bash profile-detect.sh validate 'Bad_Host!'"
      )
      assert result[0] != 0, "Should reject invalid hostname characters"

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
      alt_hosts = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/alt-flake "
          "FLAKE_HOSTS_DIR=machines "
          "bash profile-detect.sh hosts"
      )
      print(f"Alt structure hosts: {alt_hosts}")
      assert "existing-host" in alt_hosts, "Should find host in machines/ structure"

      print("=== Testing hardware-detect.sh ===")

      # Test boot mode detection (in VM should be BIOS or UEFI)
      boot_mode = machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh boot"
      )
      print(f"Boot mode: {boot_mode}")
      assert "BOOT_MODE=" in boot_mode, "Should detect boot mode"

      # Test CPU detection
      cpu_info = machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh cpu"
      )
      print(f"CPU info: {cpu_info}")
      assert "CPU_VENDOR=" in cpu_info, "Should detect CPU vendor"

      # Test all detection
      all_hw = machine.succeed(
          "cd /etc/installer/lib && bash hardware-detect.sh all"
      )
      print(f"All hardware: {all_hw}")

      print("=== Testing disk-utils.sh ===")

      # Test disk listing (may be empty in VM)
      disks = machine.succeed(
          "cd /etc/installer/lib && bash disk-utils.sh list human || true"
      )
      print(f"Disks: {disks}")

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

      # Test dry-run generation
      output = machine.succeed(
          "cd /etc/installer/generators && "
          "FLAKE_ROOT=/etc/test-flake "
          "bash generate-host.sh "
          "--hostname testvm "
          "--disk /dev/sda "
          "--scheme standard "
          "--profiles base,desktop "
          "--username testuser "
          "--dry-run 2>&1"
      )
      print(f"Dry-run output:\n{output}")

      # Verify generated content
      assert "disko.devices" in output, "Should generate disko config"
      assert "testvm" in output, "Should include hostname"
      assert "testuser" in output, "Should include username"

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

      # Check configuration.nix content
      config_content = machine.succeed("cat /tmp/test-output/newhost/hosts/newhost/configuration.nix")
      print(f"Generated configuration.nix:\n{config_content}")
      assert "newhost" in config_content, "Config should have hostname"
      assert "profiles/base.nix" in config_content or "base" in config_content, "Config should import base profile"

      # Check disko.nix content
      disko_content = machine.succeed("cat /tmp/test-output/newhost/hosts/newhost/disko.nix")
      print(f"Generated disko.nix:\n{disko_content}")
      assert "/dev/vda" in disko_content, "Disko should reference correct disk"
      assert "swap" in disko_content, "Standard scheme should have swap"

      # Check flake entry
      flake_entry = machine.succeed("cat /tmp/test-output/newhost/flake-entry.nix")
      print(f"Generated flake entry:\n{flake_entry}")
      assert "newhost" in flake_entry, "Flake entry should have hostname"

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

      luks_disko = machine.succeed("cat /tmp/luks-output/encrypted/hosts/encrypted/disko.nix")
      print(f"LUKS disko config:\n{luks_disko}")
      assert "luks" in luks_disko.lower() or "crypt" in luks_disko.lower(), "LUKS scheme should have encryption"

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

      simple_disko = machine.succeed("cat /tmp/simple-output/minimal/hosts/minimal/disko.nix")
      print(f"Simple disko config:\n{simple_disko}")
      assert "swap" not in simple_disko.lower() or "size = \"0" in simple_disko.lower(), "Simple scheme should not have swap partition"

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
      disks = installer.succeed(
          "cd /etc/installer/lib && bash disk-utils.sh list human"
      )
      print(f"Available disks:\n{disks}")

      # The empty disk image should appear as vdb
      disks_simple = installer.succeed(
          "cd /etc/installer/lib && bash disk-utils.sh list simple"
      )
      print(f"Disk devices: {disks_simple}")

      # Test disk info
      if "vdb" in disks_simple:
          disk_info = installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh info /dev/vdb"
          )
          print(f"Disk info:\n{disk_info}")
          assert "DISK_DEVICE=/dev/vdb" in disk_info

          # Test partition calculation
          parts = installer.succeed(
              "cd /etc/installer/lib && bash disk-utils.sh calculate /dev/vdb standard uefi"
          )
          print(f"Partition calculation:\n{parts}")
          assert "BOOT_SIZE_MB=" in parts
          assert "SWAP_SIZE_MB=" in parts
          assert "ROOT_SIZE_MB=" in parts

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

      # Check the disko config references the correct disk
      disko = installer.succeed("cat /tmp/vm-output/vmhost/hosts/vmhost/disko.nix")
      assert "/dev/vdb" in disko, "Disko should reference /dev/vdb"

      print("=== Testing install log generation ===")

      log = installer.succeed("cat /tmp/vm-output/vmhost/INSTALL_LOG.md")
      print(f"Install log:\n{log}")
      assert "vmhost" in log
      assert "/dev/vdb" in log
      assert "standard" in log

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
      detected = machine.succeed(
          "cd /etc/installer/lib && "
          "FLAKE_ROOT=/etc/alt-flake bash flake-config.sh detect"
      )
      print(f"Detected structure: {detected}")

      # Test with manual configuration
      profiles = machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "export FLAKE_PROFILES_DIR=profiles && "
          "bash profile-detect.sh list"
      )
      print(f"Profiles in alt structure: {profiles}")
      assert "base" in profiles

      hosts = machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh hosts"
      )
      print(f"Hosts in alt structure: {hosts}")
      assert "existing-host" in hosts

      # Validate that we can't create a duplicate host
      result = machine.execute(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh validate existing-host"
      )
      assert result[0] != 0, "Should reject existing hostname"

      # Validate that we can create a new host
      machine.succeed(
          "cd /etc/installer/lib && "
          "export FLAKE_ROOT=/etc/alt-flake && "
          "export FLAKE_HOSTS_DIR=machines && "
          "bash profile-detect.sh validate newmachine"
      )

      print("✅ Alt structure tests passed!")
    '';
  };
}
