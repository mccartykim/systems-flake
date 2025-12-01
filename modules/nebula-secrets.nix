# Nebula secrets with agenix-rekey generators
# Generates host certificates from the encrypted CA using YubiKey
{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}: let
  cfg = config.kimb.nebula;
  hostName = config.networking.hostName;
  registry = import (outputs + "/hosts/nebula-registry.nix");

  # Check if this host is in the nebula registry
  hasNebulaConfig = registry.nodes ? ${hostName} && registry.nodes.${hostName} ? ip;
  hostInfo = if hasNebulaConfig then registry.nodes.${hostName} else null;
in {
  config = lib.mkIf (cfg.enable && hasNebulaConfig) {
    # CA secret - the master CA encrypted with YubiKeys
    age.secrets.nebula-ca = {
      rekeyFile = outputs + "/secrets/nebula-ca-master.age";
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # Host certificate - generated from CA
    age.secrets.nebula-host-cert = {
      generator = {
        # Dependencies: need the CA to sign the cert
        dependencies = [config.age.secrets.nebula-ca];

        # Generator script that creates the certificate
        script = {pkgs, ...}: ''
          # The CA file contains key first, then cert (concatenated)
          ca_content=$(cat "$1")

          # Split into key and cert (key ends with "-----END NEBULA ED25519 PRIVATE KEY-----")
          ca_key=$(echo "$ca_content" | sed -n '1,/END NEBULA ED25519 PRIVATE KEY/p')
          ca_crt=$(echo "$ca_content" | sed -n '/BEGIN NEBULA CERTIFICATE/,/END NEBULA CERTIFICATE/p')

          # Write temp files for nebula-cert
          key_file=$(mktemp)
          crt_file=$(mktemp)
          echo "$ca_key" > "$key_file"
          echo "$ca_crt" > "$crt_file"

          # Generate the host certificate
          ${pkgs.nebula}/bin/nebula-cert sign \
            -ca-crt "$crt_file" \
            -ca-key "$key_file" \
            -name "${hostName}" \
            -ip "${hostInfo.ip}/16" \
            -groups "${lib.concatStringsSep "," hostInfo.groups}" \
            -out-crt /dev/stdout

          # Cleanup
          rm -f "$key_file" "$crt_file"
        '';
      };
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # Host key - generated alongside the certificate
    age.secrets.nebula-host-key = {
      generator = {
        dependencies = [config.age.secrets.nebula-ca];

        script = {pkgs, ...}: ''
          # The CA file contains key first, then cert
          ca_content=$(cat "$1")

          ca_key=$(echo "$ca_content" | sed -n '1,/END NEBULA ED25519 PRIVATE KEY/p')
          ca_crt=$(echo "$ca_content" | sed -n '/BEGIN NEBULA CERTIFICATE/,/END NEBULA CERTIFICATE/p')

          key_file=$(mktemp)
          crt_file=$(mktemp)
          out_dir=$(mktemp -d)
          echo "$ca_key" > "$key_file"
          echo "$ca_crt" > "$crt_file"

          # Generate cert and key (we want the key)
          ${pkgs.nebula}/bin/nebula-cert sign \
            -ca-crt "$crt_file" \
            -ca-key "$key_file" \
            -name "${hostName}" \
            -ip "${hostInfo.ip}/16" \
            -groups "${lib.concatStringsSep "," hostInfo.groups}" \
            -out-crt "$out_dir/host.crt" \
            -out-key "$out_dir/host.key"

          cat "$out_dir/host.key"

          rm -rf "$key_file" "$crt_file" "$out_dir"
        '';
      };
      mode = "0400";
      owner = "root";
      group = "root";
    };
  };
}
