# Knitwork webApp SPA container.
#
# A NixOS nspawn container that builds the KMP wasmJs distribution AT CONTAINER
# START (not at Nix build time) and serves it with nginx. Rationale: the Kotlin
# wasm plugin downloads a prebuilt Node.js whose ELF needs glibc's
# /lib64/ld-linux-x86-64.so.2, which the Nix sandbox lacks but
# programs.nix-ld provides here; and a persistent bindMount caches Gradle's
# deps across restarts (which a Nix derivation can't, given the rotating
# nixbld* users). Caddy in the reverse-proxy container reverse_proxies
# knit.kimb.dev's SPA paths here (see reverse-proxy.nix).
#
# Mirrors blog-service.nix: same veth + DNS-via-unbound shape. The source comes
# from the knitwork-frontend flake input (inputs.knitwork-frontend.outPath), so
# the frontend flake ships nothing here but its tree.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kimb;
  knitWeb = cfg.services.knit-web;
  # Host-side endpoint of this container's veth (unique per container; blog
  # uses .11, reverse-proxy uses .1 = containerBridge).
  hostAddress = "192.168.100.12";
  corretto = pkgs.corretto21;
in {
  # Host dirs backing the container's persistent bindMounts (must exist before
  # the container starts or nspawn refuses the mount).
  systemd.tmpfiles.rules = [
    "d /var/lib/knit-web/gradle 0755 root root -"
    "d /var/lib/knit-web/web 0755 root root -"
  ];

  containers.knit-web = lib.mkIf knitWeb.enable {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress;
    localAddress = knitWeb.containerIP;

    # Gradle deps cache + built dist persist on the host, so a restart of the
    # same image skips the build (the service fingerprints the source) and a
    # new-image deploy rebuilds exactly once.
    bindMounts = {
      "/var/cache/gradle" = {
        hostPath = "/var/lib/knit-web/gradle";
        isReadOnly = false;
      };
      "/var/lib/knitwork/web" = {
        hostPath = "/var/lib/knit-web/web";
        isReadOnly = false;
      };
    };

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # The downloaded Node's ELF wants the FHS loader; nix-ld provides it.
      programs.nix-ld.enable = true;

      # DNS through unbound on maitred (same NSS-bypass as blog-service /
      # reverse-proxy). Gradle's deps fetch needs working resolution.
      networking.nameservers = [cfg.networks.containerBridge];
      services.nscd.enable = false;
      system.nssModules = lib.mkForce [];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${cfg.networks.containerBridge}
      '';

      environment.systemPackages = [corretto pkgs.gradle];

      # Build the wasmJs dist once at container start, before nginx serves.
      # Fingerprints the (pinned, read-only) source tree and skips the build
      # when the dist on the volume already matches it — so a restart of the
      # same container is instant, and a new-image deploy rebuilds once.
      systemd.services.knit-web-build = {
        description = "Build the knitwork wasmJs SPA into the web root";
        wantedBy = ["nginx.service"];
        before = ["nginx.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        environment = {
          JAVA_HOME = "${corretto}";
          GRADLE_USER_HOME = "/var/cache/gradle";
          # programs.nix-ld.enable sets environment.ldso → /lib64/ld-linux so
          # the Kotlin-downloaded Node's ELF interpreter resolves to the nix-ld
          # interceptor automatically. But systemd units don't inherit
          # environment.sessionVariables, so set the two vars the interceptor
          # reads (the real loader + the curated lib path) explicitly.
          NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
          NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
        };
        path = [
          corretto
          pkgs.gradle
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.which
        ];
        script = ''
          set -euo pipefail
          WEB_ROOT=/var/lib/knitwork/web
          SRC=${inputs.knitwork-frontend.outPath}
          WORK=/tmp/knit-src

          # Copy the pinned source to a writable tree (the flake input is
          # read-only in the nix store).
          rm -rf "$WORK"
          cp -r --no-preserve=mode "$SRC"/. "$WORK"/
          chmod -R +w "$WORK"
          cd "$WORK"

          # Point Gradle's JDK toolchain at the bundled Corretto 21; no
          # auto-download. Leading \n: tracked gradle.properties has no
          # trailing newline.
          printf '\norg.gradle.java.installations.paths=%s\norg.gradle.java.installations.auto-download=false\n' \
            "${corretto}" >> gradle.properties

          # Fingerprint the source (excluding build outputs / caches).
          hash=$(find . -type f \
            -not -path './build/*' -not -path '*/build/*' \
            -not -path './.gradle/*' -not -path '*/.gradle/*' \
            -not -path './kotlin-js-store/*' \
            -not -path './node_modules/*' \
            | LC_ALL=C sort | xargs -r sha256sum | sha256sum | cut -d' ' -f1)

          if [ -f "$WEB_ROOT/index.html" ] && [ -f "$WEB_ROOT/.knit-src-hash" ] \
             && [ "$(cat "$WEB_ROOT/.knit-src-hash")" = "$hash" ]; then
            echo "knit-web-build: dist present, source unchanged ($hash); skipping"
            exit 0
          fi

          echo "knit-web-build: building wasmJs SPA (source hash $hash)..."
          ./gradlew :webApp:wasmJsBrowserDistribution \
            --no-daemon --console=plain -Dorg.gradle.warning.mode=none

          rm -rf "$WEB_ROOT"
          mkdir -p "$WEB_ROOT"
          cp -r "$WORK"/webApp/build/dist/wasmJs/productionExecutable/. "$WEB_ROOT/"
          echo "$hash" > "$WEB_ROOT/.knit-src-hash"
          echo "knit-web-build: build complete; dist at $WEB_ROOT"
        '';
      };

      services.nginx = {
        enable = true;
        virtualHosts.knit = {
          listen = [{addr = "0.0.0.0"; port = knitWeb.port;}];
          root = "/var/lib/knitwork/web";
          # SPA fallback: deep links / client routes load the app shell.
          locations."/".tryFiles = "$uri /index.html";
        };
      };

      networking.firewall.allowedTCPPorts = [knitWeb.port];
      system.stateVersion = "24.11";
    };
  };
}