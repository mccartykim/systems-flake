# Centralized service configuration for kimb.dev infrastructure
# Auto-injected via commonModules — each host picks up its services
# based on config.networking.hostName, so no per-host wiring is needed.
{config, ...}: let
  hostServices = {
    # Rich Evans services
    rich-evans = {
      copyparty = {
        enable = true;
        port = 3923;
        subdomain = "files";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      life-coach-dashboard = {
        enable = true;
        # lifecoach-organism dashboard runs on 8586; the old
        # org-life-coach dashboard on 8585 is now mkForce-disabled.
        port = 8586;
        subdomain = "coach";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
    };

    # Historian services (the beefy always-on Beelink)
    historian = {
      # Knitwork webApp SPA — the KMP wasmJs bundle, built at container start
      # inside a nixos-container (see hosts/historian/knitwork-web.nix) on this
      # box, offloading the build from rich-evans/the router. publicAccess=
      # false: no auto-vhost — the hand-written knit.kimb.dev vhost in
      # reverse-proxy.nix reverse_proxies via maitred's socat forwarder to this
      # host's Nebula IP:8088.
      knit-web = {
        enable = true;
        port = 8088;
        subdomain = "knit-web";
        host = "historian";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };

      # === a3j.5 low-risk migrations (from rich-evans) — placeholders OFF
      # until each cutover push flips enable here and removes the entry
      # from the rich-evans bucket below. The host files
      # (hosts/historian/{borges,knitwork,knitwork-bff,homepage}.nix) are
      # mkIf-gated on these, so they are inert while enable=false. maitred's
      # duplicate entries (maitred bucket below) keep pointing at rich-evans
      # until each cutover flips their `host` to historian — that repoints
      # the socat forwarders + vhosts. ===

      borges = {
        enable = true;
        port = 7171;
        subdomain = "borges";
        host = "historian";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      knit = {
        enable = true;
        port = 8080;
        subdomain = "knit";
        host = "historian";
        auth = "none";
        publicAccess = true;
        # The lexicon host / AppView is plain HTTP; the firehose indexer's
        # WebSocket is an *outbound* wss to the relay, so no inbound websockets.
        websockets = false;
      };
      knit-bff = {
        enable = true;
        port = 8787;
        subdomain = "knit-bff";
        host = "historian";
        auth = "none";
        # No subdomain of its own — reached via /api/* on knit.kimb.dev
        # (publicAccess=false drives only maitred's socat forwarder).
        publicAccess = false;
        websockets = false;
      };
      homepage = {
        enable = true;
        port = 8082;
        subdomain = "home-rich";
        host = "historian";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      # Home Assistant — the a3j.6 phase-6a migration from rich-evans (with
      # mosquitto; see hosts/historian/home-assistant.nix). auth="builtin":
      # HA does its own login; maitred's socat forwarder bridges hass.kimb.dev
      # to this host's Nebula IP (registry-driven repoint).
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "historian";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
    };

    # Maitred services (router + reverse proxy)
    maitred = {
      authelia = {
        enable = true;
        port = 9091;
        subdomain = "auth";
        host = "maitred";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      grafana = {
        enable = true;
        port = 3000;
        subdomain = "grafana";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      prometheus = {
        enable = true;
        port = 9090;
        subdomain = "prometheus";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      homepage = {
        enable = true;
        port = 8082;
        subdomain = "home";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      blog = {
        enable = true;
        port = 8080;
        subdomain = "blog";
        host = "maitred";
        containerIP = "192.168.100.3";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      knit = {
        enable = true;
        port = 8080;
        subdomain = "knit";
        host = "historian";
        auth = "none";
        publicAccess = true;
        # No containerIP: knit runs as a host service on historian (a3j.5;
        # the entry under the historian bucket above), not as a maitred
        # container. This entry exists only so maitred's reverse-proxy
        # generates the knit.kimb.dev vhost and the socat forwarder
        # (containerBridge:8080 → historian Nebula 10.100.0.10:8080) engages
        # via the `host != "maitred"` filter.
        websockets = false;
      };
      # Knitwork BFF — the ATProto OAuth write relay, now on historian (a3j.5;
      # hosts/historian/knitwork-bff.nix). publicAccess=false so this drives
      # ONLY the socat forwarder (containerBridge:8787 → historian Nebula
      # 10.100.0.10:8787), NOT a vhost: the BFF is reached via /api/* on
      # the hand-written knit.kimb.dev vhost in reverse-proxy.nix, not its own
      # subdomain. Mirrors how the `knit` entry above works, minus the vhost.
      knit-bff = {
        enable = true;
        port = 8787;
        subdomain = "knit-bff";
        host = "historian";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      # Knitwork webApp SPA — the KMP wasmJs bundle, built at container start
      # inside a nixos-container on historian (see hosts/historian/knitwork-
      # web.nix; the real entry is under the historian bucket above). This
      # duplicate exists only to drive maitred's socat forwarder
      # (containerBridge:8088 → historian Nebula 10.100.0.10:8088) via the
      # `host != "maitred"` filter and feed the port to the hand-written
      # knit.kimb.dev vhost. No containerIP (remote host) → the vhost reverse-
      # proxies to containerBridge, where the socat forwarder listens.
      knit-web = {
        enable = true;
        port = 8088;
        subdomain = "knit-web";
        host = "historian";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      reverse-proxy = {
        enable = true;
        port = 80;
        subdomain = "www";
        host = "maitred";
        containerIP = "192.168.100.2";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      # These services run on remote hosts but are proxied through maitred
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "historian";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      matrix = {
        enable = true;
        port = 6167;
        subdomain = "matrix";
        host = "historian"; # a3j.6: Tuwunel moved from rich-evans (hosts/historian/matrix.nix)
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      jellyfin = {
        enable = true;
        port = 8096;
        subdomain = "media";
        host = "historian";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      # buildbot master+worker disabled 2026-06-22 (abandoned the buildbot-nix
      # effort vs private-repo flake inputs). Entry kept disabled so the
      # buildbot.kimb.dev DNS record + Caddy vhost stop pointing at nothing.
      buildbot = {
        enable = false;
        port = 80;
        subdomain = "buildbot";
        host = "rich-evans";
        auth = "none";
        publicAccess = true;
        websockets = true;
      };
      life-coach-dashboard = {
        enable = true;
        # lifecoach-organism dashboard runs on 8586; the old
        # org-life-coach dashboard on 8585 is now mkForce-disabled.
        port = 8586;
        subdomain = "coach";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      # Borges — EPUB-first ebook server, running on historian (a3j.5; the entry under the
      # historian bucket above). No containerIP:
      # borges runs as a host service on historian, not as a maitred
      # container. This entry exists only so
      # maitred's reverse-proxy generates the borges.kimb.dev vhost and the
      # socat forwarder (containerBridge:7171 -> rich-evans Nebula
      # 10.100.0.40:7171) engages via the `host != "maitred"` filter.
      # auth = "none": borges does its own HTTP Basic + session auth; an
      # Authelia gate would break the e-reader clients (KOReader/CrossPoint
      # speak Basic + x-auth-user, not an interactive SSO flow).
      borges = {
        enable = true;
        port = 7171;
        subdomain = "borges";
        host = "historian";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
    };
  };
in {
  kimb.services = hostServices.${config.networking.hostName} or {};
}
