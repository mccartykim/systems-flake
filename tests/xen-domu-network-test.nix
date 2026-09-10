# VM test for modules/xen-domu-network.nix (a3j.3 — domU networking).
#
# Xen can't run inside a KVM test VM (no guaranteed nested VMX), so the
# "guest" is simulated the way the real stack will see it: a veth whose
# host-side end is renamed to the vif-* naming pattern and enslaved to the
# bridge by hand (exactly what the Xen vif-bridge hotplug script does),
# with the guest side in a network namespace. This exercises the plumbing
# the module owns:
#
#   bridge exists with the dom0 address (networkd, carrier-less config)
#   → DHCP from dnsmasq on the bridge
#   → DNS via dnsmasq (hosts-file answer — no internet dependency)
#   → dom0 ↔ guest reachability (trusted bridge INPUT)
#   → guest → lanhost forwarding + MASQUERADE (lanhost's access log must
#     show dom0's uplink IP, NOT the guest's 192.168.101.x address)
#   → port forward: lanhost → dom0:8080 → DNAT → guest :80 (proves
#     prerouting DNAT + `ct status dnat` forward accept + reply rewriting)
#   → nftables rules as declared (xen-domu table, nixos-fw forward chain)
#
# NOTE: no `virtualisation.xen.enable` here — the module's networking
# machinery is independent of Xen (that assertion would also fail on
# bootloader-less test VMs). The bridge/NAT/DHCP/forward contract is what's
# tested.
{pkgs}:
pkgs.testers.nixosTest {
  name = "xen-domu-network";

  nodes = {
    dom0 = {
      config,
      lib,
      ...
    }: {
      imports = [../modules/xen-domu-network.nix];

      kimb.xenDomuNetwork = {
        enable = true;
        # A wildcard forward (any ingress except the guest bridge) — the
        # shape a3j.5/6/7 will use for nebula1/LAN reach into guests.
        portForwards = [
          {
            proto = "tcp";
            port = 8080;
            destination = "192.168.101.100:80";
          }
        ];
      };

      # Tools used by testScript (binaries resolve on dom0; `ip netns exec`
      # only switches the network namespace).
      environment.systemPackages = with pkgs; [
        iproute2
        bind # dig
        busybox # udhcpc, httpd
        curl
      ];

      networking = {
        hostName = "dom0";
        # Match historian's firewall backend (the module requires it — the
        # iptables networking.nat module would be inert otherwise).
        nftables.enable = true;
        # The uplink stays under scripted/networkd config like the real
        # host's NM-owned NICs; the guest bridge must coexist with it.
        interfaces.eth1.ipv4.addresses = [
          {
            address = "10.200.0.50";
            prefixLength = 16;
          }
        ];
      };

      system.stateVersion = "24.11";
    };

    # A stand-in for "another host on the uplink network": proves NAT
    # (masquerade) and receives port-forwarded traffic.
    lanhost = {
      config,
      lib,
      ...
    }: {
      networking = {
        hostName = "lanhost";
        firewall.enable = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = "10.200.0.60";
            prefixLength = 16;
          }
        ];
      };

      # Serves a body + logs the remote address so the test can PROVE the
      # masquerade (guest traffic must arrive as dom0's uplink IP).
      services.nginx = {
        enable = true;
        virtualHosts."nattest" = {
          listen = [{addr = "0.0.0.0"; port = 80;}];
          locations."/" = {
            return = "200 'behind dom0 NAT!'";
            extraConfig = "add_header Content-Type text/plain;";
          };
        };
      };

      system.stateVersion = "24.11";
    };
  };

  testScript = ''
    start_all()

    dom0.wait_for_unit("multi-user.target")
    lanhost.wait_for_unit("multi-user.target")
    lanhost.wait_for_unit("nginx.service")

    # --- bridge exists with the configured address, before any vif ---
    dom0.wait_for_unit("systemd-networkd")
    dom0.succeed("ip link show xenbr0")
    # ConfigureWithoutCarrier: the address must apply even with zero ports
    dom0.wait_until_succeeds("ip -4 addr show dev xenbr0 | grep '192.168.101.1/24'")

    # --- dnsmasq up, offering DHCP on the bridge ---
    dom0.wait_for_unit("dnsmasq")
    dom0.succeed("ss -lun | grep ':67'")

    # --- simulated guest: veth with a vif-* name, enslaved to the bridge ---
    dom0.succeed("ip netns add guest")
    dom0.succeed("ip link add vif-test.0 type veth peer name guest0")
    dom0.succeed("ip link set vif-test.0 master xenbr0")
    dom0.succeed("ip link set vif-test.0 up")
    dom0.succeed("ip link set guest0 netns guest")
    dom0.succeed("ip netns exec guest ip link set guest0 up")
    dom0.succeed("ip netns exec guest ip link set lo up")

    # --- DHCP: guest gets an address from the pool (.100–.200) ---
    dom0.succeed(
      "cat > /tmp/dhcp-script <<'EOF'\n"
      "#!/bin/sh\n"
      "case \"$1\" in bound|renew)\n"
      "  ip -4 addr add \"$ip/24\" dev \"$interface\" 2>/dev/null\n"
      "  ip route add default via 192.168.101.1 2>/dev/null\n"
      "  ;;\n"
      "esac\n"
      "EOF\n"
      "chmod +x /tmp/dhcp-script"
    )
    dom0.succeed("ip netns exec guest busybox udhcpc -i guest0 -n -q -s /tmp/dhcp-script -t 10 -T 3")
    dom0.succeed("ip netns exec guest ip -4 addr show dev guest0 | grep -E '192\\.168\\.101\\.1[0-9][0-9]'")

    # --- dom0 ↔ guest (trusted bridge INPUT path) ---
    guest_ip = dom0.succeed(
      "ip netns exec guest ip -4 addr show dev guest0 | grep -oP '(?<=inet )192\\.168\\.101\\.[0-9]+' | head -1"
    ).strip()
    dom0.succeed(f"ping -c1 -W2 {guest_ip}")
    dom0.succeed("ip netns exec guest ping -c1 -W2 192.168.101.1")

    # --- DNS: dnsmasq serves guests (hosts-file answer, no internet) ---
    dom0.succeed(
      "ip netns exec guest dig +short +time=2 +tries=2 @192.168.101.1 dom0 A "
      "| grep -E '^([0-9]{1,3}\\.){3}[0-9]{1,3}$'"
    )

    # --- NAT: guest → lanhost must arrive masqueraded as dom0's uplink IP ---
    dom0.succeed("ip netns exec guest curl -sf --max-time 5 http://10.200.0.60/ | grep 'behind dom0 NAT'")
    lanhost.wait_until_succeeds("grep -q '10.200.0.50' /var/log/nginx/access.log")
    lanhost.fail("grep -q '192.168.101.' /var/log/nginx/access.log")

    # --- port forward: lanhost → dom0:8080 → DNAT → guest :80 ---
    # Guest serves HTTP on :80; DNAT target 192.168.101.100 must exist on
    # the guest end (DHCP may already have leased .100 — guard the add).
    dom0.succeed("echo natted > /tmp/index.html")
    dom0.succeed(
      "ip netns exec guest ip -4 addr show dev guest0 | grep -q '192.168.101.100 ' "
      "|| ip netns exec guest ip addr add 192.168.101.100/24 dev guest0"
    )
    dom0.succeed(
      "ip netns exec guest sh -c 'nohup busybox httpd -p 80 -h /tmp >/dev/null 2>&1 &'"
    )
    lanhost.succeed("curl -sf --max-time 5 http://10.200.0.50:8080/ | grep natted")

    # --- declared nftables rules are live ---
    dom0.succeed("nft list table ip xen-domu | grep -q masquerade")
    dom0.succeed("nft list table ip xen-domu | grep -q 'dnat to 192.168.101.100:80'")
    dom0.succeed("nft list chain inet nixos-fw forward | tee /tmp/fw-forward.txt")
    # the domU accept rules live in the forward-allow chain
    dom0.succeed("nft list chain inet nixos-fw forward-allow | tee /tmp/fw-fa.txt")
    dom0.succeed(
      "grep -F 'vif*' /tmp/fw-fa.txt || "
      "(echo '=== NIXOS-FW FORWARD-ALLOW ==='; cat /tmp/fw-fa.txt; exit 1)"
    )
  '';
}