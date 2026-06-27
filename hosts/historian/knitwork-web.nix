# Knitwork webApp SPA container.
#
# A NixOS nspawn container on historian (the beefy 8-core/64GB always-on
# Beelink) that builds the KMP wasmJs distribution AT CONTAINER START (not at
# Nix build time) and serves it with nginx. Rationale: maitred is the edge
# router — a 4-core Atom box with 8GB — and a Gradle/Kotlin/webpack build would
# starve routing; rich-evans already carries the BFF + AppView + a dozen other
# services, so the SPA build is offloaded to historian's idle Ryzen cores
# instead, isolating the ~8min build spike from the BFF/AppView it depends on.
# The Kotlin wasm plugin downloads a prebuilt Node.js whose ELF needs glibc's
# /lib64/ld-linux-x86-64.so.2 (absent in the Nix sandbox) but programs.nix-ld
# provides it here; a persistent bindMount caches Gradle's deps across restarts.
# maitred's socat forwarder (containerBridge:8088 → historian Nebula
# 10.100.0.10:8088) bridges Caddy to this box (nebula1 is trusted on historian,
# so no firewall hole is needed). The BFF/AppView stay on rich-evans.
#
# Host networking (no privateNetwork): the container shares historian's netns,
# so Gradle's Maven/Node downloads ride the host's internet and nginx binds
# 0.0.0.0:8088 directly — dropping the privateNetwork + host NAT + DNS-via-
# bridge plumbing the maitred containers (blog/reverse-proxy) need. The source
# comes from the knitwork-frontend flake input (inputs.knitwork-frontend.outPath).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kimb;
  knitWeb = cfg.services.knit-web;
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
    # No privateNetwork → host networking: shares historian's netns, so no
    # hostAddress/localAddress, no ve-+ NAT, no per-container DNS bridge.

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

      # Host networking gives the container historian's internet for Gradle's
      # Maven/Node downloads; bypass nscd/nsncd and point DNS at a resolver the
      # host can actually reach (1.1.1.1) so the static resolv.conf is honored.
      services.nscd.enable = false;
      system.nssModules = lib.mkForce [];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver 1.1.1.1
      '';

      environment.systemPackages = [corretto pkgs.gradle];

      # Build the wasmJs dist once at container start, before nginx serves.
      # Marks the dist with the pinned source's store path and skips the build
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
          # cp --no-preserve=mode stripped the exec bit from the gradlew
          # wrapper (source had it; our copy is 0644) and chmod +w doesn't add
          # execute — restore it so ./gradlew runs.
          chmod +x gradlew

          # Point Gradle's JDK toolchain at the bundled Corretto 21; no
          # auto-download. Leading \n: tracked gradle.properties has no
          # trailing newline.
          printf '\norg.gradle.java.installations.paths=%s\norg.gradle.java.installations.auto-download=false\n' \
            "${corretto}" >> gradle.properties

          # Skip the build if the dist already matches this (pinned, read-only)
          # source tree — a restart of the same container is instant; a new-image
          # deploy rebuilds once. The marker is the store path itself
          # (inputs.knitwork-frontend.outPath): it changes iff the flake input's
          # content changes, i.e. iff the source changes. (Replaces a
          # find|xargs sha256 fingerprint that broke on iOS asset paths with
          # spaces — xargs split them into non-existent path fragments.)
          if [ -f "$WEB_ROOT/index.html" ] && [ -f "$WEB_ROOT/.knit-src" ] \
             && [ "$(cat "$WEB_ROOT/.knit-src")" = "$SRC" ]; then
            echo "knit-web-build: dist present, source unchanged ($SRC); skipping"
            exit 0
          fi

          echo "knit-web-build: building wasmJs SPA (source $SRC)..."
          ./gradlew :webApp:wasmJsBrowserDistribution \
            --no-daemon --console=plain -Dorg.gradle.warning.mode=none

          rm -rf "$WEB_ROOT"
          mkdir -p "$WEB_ROOT"
          cp -r "$WORK"/webApp/build/dist/wasmJs/productionExecutable/. "$WEB_ROOT/"
          echo "$SRC" > "$WEB_ROOT/.knit-src"
          echo "knit-web-build: build complete; dist at $WEB_ROOT"
        '';
      };

      services.nginx = {
        enable = true;
        virtualHosts.knit = {
          # Host networking: bind on the host's stack so maitred's socat
          # forwarder (→ historian Nebula IP) reaches nginx directly.
          listen = [{addr = "0.0.0.0"; port = knitWeb.port;}];
          root = "/var/lib/knitwork/web";
          # SPA fallback: deep links / client routes load the app shell.
          locations."/".tryFiles = "$uri /index.html";
        };
      };

      system.stateVersion = "24.11";
    };
  };
}