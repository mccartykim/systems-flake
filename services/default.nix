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
      homepage = {
        enable = true;
        port = 8082;
        subdomain = "home-rich";
        host = "rich-evans";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "rich-evans";
        auth = "builtin";
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
      # Knitwork — lexicon host + firehose indexer. Runs HERE as a host
      # service (see hosts/rich-evans/knitwork.nix, which imports the
      # knitwork flake's NixOS module). maitred only reverse-proxies to
      # it (the duplicate `knit` entry under the maitred bucket below,
      # with host = "rich-evans" and no containerIP, drives Caddy's vhost
      # + maitred's socat forwarder to this host's Nebula IP:port).
      knit = {
        enable = true;
        port = 8080;
        subdomain = "knit";
        host = "rich-evans";
        auth = "none";
        publicAccess = true;
        # The lexicon host / AppView is plain HTTP; the firehose indexer's
        # WebSocket is an *outbound* wss to the relay, so no inbound websockets.
        websockets = false;
      };
      # Knitwork BFF — ATProto OAuth write relay, runs HERE as a host service
      # (hosts/rich-evans/knitwork-bff.nix imports the knitwork flake's BFF
      # module and reads this entry for port/enable). The duplicate `knit-bff`
      # entry under the maitred bucket drives maitred's socat forwarder +
      # the /api/* routing; this entry just feeds the rich-evans host config.
      # publicAccess=false (mirrored in maitred): the BFF has no subdomain of
      # its own — it's reached via /api/* on knit.kimb.dev.
      knit-bff = {
        enable = true;
        port = 8787;
        subdomain = "knit-bff";
        host = "rich-evans";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      # Borges — EPUB-first ebook server. Runs HERE as a host service (see
      # hosts/rich-evans/borges.nix, which imports the borges flake's NixOS
      # module). maitred only reverse-proxies to it (the duplicate `borges`
      # entry under the maitred bucket below, with host = "rich-evans" and no
      # containerIP, drives Caddy's vhost + maitred's socat forwarder to this
      # host's Nebula IP:port).
      borges = {
        enable = true;
        port = 7171;
        subdomain = "borges";
        host = "rich-evans";
        auth = "none";
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
        host = "rich-evans";
        auth = "none";
        publicAccess = true;
        # No containerIP: knit runs on rich-evans (rich-evans bucket
        # above), not as a maitred container. This entry exists only so
        # maitred's reverse-proxy generates the knit.kimb.dev vhost and
        # the socat forwarder (containerBridge:8080 → rich-evans Nebula
        # 10.100.0.40:8080) engages via the `host != "maitred"` filter.
        websockets = false;
      };
      # Knitwork BFF — the ATProto OAuth write relay, also on rich-evans (host
      # service, see hosts/rich-evans/knitwork-bff.nix). publicAccess=false so
      # this drives ONLY the socat forwarder (containerBridge:8787 → rich-evans
      # Nebula 10.100.0.40:8787), NOT a vhost: the BFF is reached via /api/* on
      # the hand-written knit.kimb.dev vhost in reverse-proxy.nix, not its own
      # subdomain. Mirrors how the `knit` entry above works, minus the vhost.
      knit-bff = {
        enable = true;
        port = 8787;
        subdomain = "knit-bff";
        host = "rich-evans";
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
      # These services run on rich-evans but are proxied through maitred
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "rich-evans";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      matrix = {
        enable = true;
        port = 6167;
        subdomain = "matrix";
        host = "rich-evans";
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
      # Borges — EPUB-first ebook server, running on rich-evans. No containerIP:
      # borges runs on rich-evans (the `borges` entry under the rich-evans
      # bucket above), not as a maitred container. This entry exists only so
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
        host = "rich-evans";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
    };
  };
in {
  kimb.services = hostServices.${config.networking.hostName} or {};
}
