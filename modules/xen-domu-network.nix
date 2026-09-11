# Xen domU networking — NAT bridge for vif-* guest interfaces.
#
# WHY THIS EXISTS (a3j.3): nixpkgs' xen-dom0 module REMOVED all bridge options
# (mkRemovedOptionModule: "The Xen Network Bridge options are currently
# unavailable. Please set up your own bridge manually"), and guests need a
# network the moment they exist. This module is that bridge, done the
# historian way.
#
# DESIGN (mirrors maitred's kimb-container pattern: 192.168.100.0/24 + NAT
# for ve-+, but adapted to historian's reality):
#
# • STANDALONE bridge, no physical enslavement. historian is a desktop whose
#   uplinks (enp100s0 today; eno1 + enp100s0 at the a3j.8 router phase) are
#   owned by NetworkManager. Enslaving a NIC would mean moving the LAN IP to
#   the bridge and re-plumbing NM — not wanted here. domUs get a private
#   /24 on this bridge and reach the world via NAT, so the module survives
#   any WAN/LAN port rewiring without config changes.
#   If LAN L2 visibility for domUs is ever needed (a3j.8 router domU), build
#   a SEPARATE bridge and enslave the physical NIC there — don't repurpose
#   this one: this bridge is NAT-space, that one is the LAN.
#
# • NAT is NFTABLES, not `networking.nat`. historian's base profile sets
#   networking.nftables.enable = true, which makes the iptables-based
#   networking.nat module INERT (nat-iptables.nix is mkIf !nftables.enable).
#   iptables isn't even installed (nftables module blacklists ip_tables).
#   So the NAT rules live in their own nftables table below. maitred's
#   iptables tricks (extraCommands) would fail the firewall's assertions.
#
# • FORWARD policy: the nftables firewall's forward chain only exists with
#   networking.firewall.filterForward = true; we turn it on and explicitly
#   accept the domU net, matching maitred's explicit-accept discipline
#   (maitred sets iptables -P FORWARD DROP + accepts). DNAT'ed connections
#   (port forwards) are auto-accepted by the firewall's `ct status dnat`
#   rule, so forwards need no filter rules of their own.
#
# • domU attach: xl.cfg uses vif = [ "bridge=xenbr0" ]. The Xen vif-bridge
#   hotplug script enslaves the vif to the named bridge; if bridge= is
#   omitted it auto-detects "the first bridge", so ALWAYS name the bridge
#   explicitly in guest configs.
#
# • Addressing: dnsmasq hands out DHCP in the upper half (.100–.200 by
#   default); .10–.99 stays free for static per-guest configs. DNS is
#   dnsmasq itself (it forwards to dom0's upstream resolv.conf — maitred's
#   unbound today, whatever historian uses after a3j.8 — so guest DNS
#   follows dom0 automatically). resolveLocalQueries=false keeps dom0's own
#   resolver untouched (NM stays authoritative for the host).
#
# • NAT egress is deliberately NOT pinned to one interface (no
#   `externalInterface`): guest traffic masquerades out of ANY uplink
#   (LAN, WAN, nebula1). Before a domU joins nebula itself (a3j.7 plan),
#   its mesh-bound traffic appears as historian's identity (10.100.0.10) —
#   acceptable, and nebula identity is cert-based anyway. This is what
#   makes the module correct today (enp100s0 cabled) and at 5c (eno1=WAN).
#
# • Port forwards (mesh/LAN clients → domU services, needed by a3j.5/6/7):
#   kimb.xenDomuNetwork.portForwards. Connections from `nebula1` or the LAN
#   get DNAT'ed to a domU ip:port; replies are rewritten by conntrack.
{
  config,
  lib,
  ...
}: let
  cfg = config.kimb.xenDomuNetwork;

  bridgeIP = lib.head (lib.splitString "/" cfg.bridgeAddressV4);
  bridgeOctets = lib.splitString "." bridgeIP;
  bridgePrefix = lib.elemAt (lib.splitString "/" cfg.bridgeAddressV4) 1;
  # The /24 the guests live in, derived from the bridge address.
  guestSubnet = "${lib.head bridgeOctets}.${lib.elemAt bridgeOctets 1}.${lib.elemAt bridgeOctets 2}.0/24";

  # dnsmasq-style range "start,end,lease" → the start address's first 3
  # octets, to assert the pool sits inside the bridge subnet.
  dhcpStart = lib.head (lib.splitString "," cfg.dhcpRange);
  dhcpOctets = lib.splitString "." dhcpStart;

  # Port-forward rules for the NAT table's prerouting chain. Empty
  # `interfaces` = any ingress EXCEPT the bridge itself (a guest curling
  # dom0's forwarded port shouldn't be reflexively DNAT'ed back into the
  # guest net). Replies are handled by conntrack, and the firewall's
  # forward chain accepts DNAT'ed flows via `ct status dnat accept` with no
  # extra filter rules.
  dnatRules = lib.concatStringsSep "\n" (
    map (
      fwd: let
        ifaceMatch =
          if fwd.interfaces == []
          then "iifname != \"${cfg.bridgeName}\" "
          else "iifname { ${lib.concatStringsSep ", " (map (i: ''"${i}"'') fwd.interfaces)} } ";
      in "${ifaceMatch}${fwd.proto} dport ${toString fwd.port} dnat to ${fwd.destination}"
    )
    cfg.portForwards
  );
in {
  options.kimb.xenDomuNetwork = {
    enable = lib.mkEnableOption "NAT bridge networking for Xen domU vif-* interfaces";

    bridgeName = lib.mkOption {
      type = lib.types.str;
      default = "xenbr0";
      description = "Name of the standalone bridge domU vifs attach to.";
    };

    bridgeAddressV4 = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.1/24";
      description = "dom0's address on the domU bridge (must be a /24).";
    };

    dhcpRange = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.100,192.168.101.200,12h";
      description = "dnsmasq DHCP pool for guests. Addresses .10–.99 are left free for static per-guest configs.";
    };

    portForwards = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          proto = lib.mkOption {
            type = lib.types.enum ["tcp" "udp"];
            default = "tcp";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = "External (dom0) port to forward.";
          };
          destination = lib.mkOption {
            type = lib.types.str;
            example = "192.168.101.20:8080";
            description = "domU ip:port the traffic is DNAT'ed to.";
          };
          interfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Ingress interfaces to forward from. Empty = all external ingress (nebula1, LAN/WAN uplinks) except the guest bridge.";
          };
        };
      });
      default = [];
      description = "Port forwards from dom0 ingress into a domU. Add one per domU service as migrations land.";
    };

    # Interfaces whose forwarding must keep working once filterForward=true
    # closes the (previously non-existent, i.e. default-accept) forward
    # chain. libvirt's virbr* and podman's netavark bridges NAT via their
    # own tables but still traverse this chain.
    extraTrustedForwardInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["virbr*" "podman*"];
      description = "Additional ingress interfaces allowed to forward (glob suffixes allowed).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.nftables.enable;
        message = "kimb.xenDomuNetwork is nftables-based (historian profile); the iptables `networking.nat` module is inert when networking.nftables.enable = true, and absent when it's false.";
      }
      {
        assertion = lib.length bridgeOctets == 4 && bridgePrefix == "24";
        message = "kimb.xenDomuNetwork.bridgeAddressV4 must be a /24 (got ${cfg.bridgeAddressV4})";
      }
      {
        assertion = lib.take 3 bridgeOctets == lib.take 3 dhcpOctets;
        message = "kimb.xenDomuNetwork.dhcpRange (${cfg.dhcpRange}) must live in the bridge's /24 (${guestSubnet})";
      }
    ];

    # Forwarding for the NAT path (mkDefault so hosts/routers can tune).
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = lib.mkDefault true;
      "net.ipv4.conf.default.forwarding" = lib.mkDefault true;
    };

    # --- The bridge (systemd-networkd; NM owns the physical NICs) ---
    systemd.network = {
      enable = lib.mkDefault true;

      netdevs."40-${cfg.bridgeName}" = {
        netdevConfig = {
          Name = cfg.bridgeName;
          Kind = "bridge";
        };
        # A dumb NAT bridge for guests: no spanning-tree, so vifs forward
        # immediately instead of waiting out the listening/learning delay.
        bridgeConfig.STP = false;
      };

      networks."40-${cfg.bridgeName}" = {
        matchConfig.Name = cfg.bridgeName;
        address = [cfg.bridgeAddressV4];
        networkConfig = {
          # A bridge with zero enslaved ports still reports no-carrier;
          # configure it anyway so the address (and dnsmasq) are ready
          # before the first vif appears.
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
          IPv6SendRA = false;
        };
        # Never gate boot/wait-online on guest-network readiness.
        linkConfig.RequiredForOnline = "no";
      };
      # vif-* interfaces get NO networkd config at all: the Xen vif-bridge
      # hotplug script enslaves them to the bridge, and unmatching links
      # are left unmanaged (by both networkd and NM — see below).
    };

    # NM must never touch the bridge or claim vifs (NM auto-creates
    # "Wired connection" profiles for appearing ethernet-ish devices, which
    # would fight the vif-bridge enslavement).
    networking.networkmanager.unmanaged = [
      "interface-name:${cfg.bridgeName}"
      "interface-name:vif*"
    ];

    # --- Firewall: forward filtering + INPUT trust for the guest net ---
    networking.firewall = {
      # The forward chain (policy drop + explicit accepts) exists only with
      # filterForward; without it, forwarding is default-accept. We turn it
      # on for the maitred-style explicit discipline and re-allow the
      # virtual nets that relied on the open default.
      filterForward = true;

      # dom0 ↔ domU traffic is INPUT on the bridge — trusted like maitred
      # trusts ve-+.
      trustedInterfaces = [cfg.bridgeName];

      extraForwardRules = ''
        # domU egress (NAT) + domU↔domU (bridge-internal, if ever filtered)
        iifname { "${cfg.bridgeName}", "vif*" } accept
        ip saddr ${guestSubnet} accept
        # Keep local virtual nets forwarding (they were default-accept
        # before this chain existed): libvirt virbr* / podman netavark.
        ${lib.optionalString (cfg.extraTrustedForwardInterfaces != []) ''
          iifname { ${lib.concatStringsSep ", " (map (i: ''"${i}"'') cfg.extraTrustedForwardInterfaces)} } accept comment "pre-existing virtual NAT nets"
        ''}
      '';
    };

    # --- NAT + DNAT (own nftables table; independent of nixos-fw reloads) ---
    networking.nftables.tables."xen-domu" = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          # Masquerade guest traffic out of ANY uplink (LAN, WAN, nebula1).
          # Deliberately not pinned to one interface: the a3j.8 router
          # phase swaps which port carries WAN/LAN and this must not care.
          # oifname != bridge keeps bridge-internal (L2) traffic unNAT'ed.
          ip saddr ${guestSubnet} oifname != "${cfg.bridgeName}" masquerade comment "domU NAT"
        }

        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ${dnatRules}
        }
      '';
    };

    # --- DHCP + DNS for guests (bound to the bridge only) ---
    services.dnsmasq = {
      enable = true;
      # dom0 keeps NM's resolv.conf; dnsmasq serves ONLY the guests.
      resolveLocalQueries = false;
      settings = {
        interface = [cfg.bridgeName];
        # xenbr0 may come up after dnsmasq starts (networkd creates it);
        # bind-dynamic re-binds as interfaces appear/disappear instead of
        # failing at startup. Also keeps us from wild-binding :53 and
        # colliding with libvirt's per-bridge dnsmasq if that ever runs.
        bind-dynamic = true;
        dhcp-range = [cfg.dhcpRange];
        domain-needed = true;
        # Upstream DNS = dom0's /etc/resolv.conf (default): follows
        # maitred's unbound today and historian's own DNS after a3j.8
        # without touching this module.
      };
    };
  };
}
