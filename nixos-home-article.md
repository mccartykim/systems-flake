---
date: 2025-12-16T22:03:25-04:00
modified:
title: The Compositional Benefits of a NixOS Home
draft: true
---

> *Code samples link to [`4784662` on main](https://github.com/mccartykim/systems-flake/tree/4784662da027b254a71ef6470f9caf9c8ab5dec2). For the latest versions, see the [repository root](https://github.com/mccartykim/systems-flake).*

## Nix, the tool that would declare the world

I really, really like Nix. There are a lot of "worst parts" to programming, but the worst worst part is getting stuff to work before you can do the fun part of your project. You must change your environment by adding software, and we've all seen what an iffy python install [can become](https://xkcd.com/1987/). Nix is my favorite cure for this, because Nix is a drydock for building bespoke environments from rugged components. Whether you want to generate a text file or an entire Linux image, Nix lets you adjust every detail.

To have a nix configuration is to know a computer's pristine state and immutable parts, with your secrets and mutable data woven in at runtime. Some people even have Nix symlink their system from [scratch on every boot](https://github.com/nix-community/impermanence).

## Known Hosts

This lead to me installing NixOS on every computer I could get my hands on because it felt wonderful to know them so specifically. Shortly after that, Claude Code started getting good with the Sonnet 3.7 model, and the models that followed blow it out of the water. After I reminded Claude to always consult the nixpkgs source code to understand how modules and packages work, and had it try checking and building nix flakes, it became a handy tool for updating my configs in natural language. This gets rid of the need for me to do the old cross referencing across the Arch wiki, Nixpkgs, and the Nix manuals. It helped that I understood nix at an intermediate level first, but my point stands!

Instead of giving each system its own isolated flake/repository, I put them in one big flake. Helper functions keep the boilerplate to a minimum — adding a new desktop or server is a few lines:

[`flake-modules/helpers.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/flake-modules/helpers.nix)

```nix
# Helper to create a desktop NixOS configuration
mkDesktop = {
  hostname,
  system ? "x86_64-linux",
  extraModules ? [],
  hardwareModules ? [],
  homeConfig ? (self + "/home/${hostname}.nix"),
}:
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; outputs = self; };
    modules =
      desktopModules
      ++ commonModules
      ++ hardwareModules
      ++ [(self + "/hosts/${hostname}/configuration.nix")]
      ++ mkHomeManager {inherit homeConfig;}
      ++ extraModules;
  };

# Helper to create a server NixOS configuration
mkServer = {
  hostname,
  system ? "x86_64-linux",
  extraModules ? [],
}:
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; outputs = self; };
    modules =
      serverModules
      ++ commonModules
      ++ [(self + "/hosts/${hostname}/configuration.nix")]
      ++ extraModules;
  };
```

I also replaced my dinky TP Link router with a Datto network appliance that came with PFSense. I wiped that guy, and set up NixOS on it to manage routing. A Linux system is a very capable router that can handle any sort of complex configuration, and I'm simply more familiar with how NixOS manages a firewall compared to a complex industry tool.

Having my own router, but not wanting to get in the weeds of subnets and setting up vLANS or expose too many ports to the broader internet, I could instead use the wonderful Nebula open source overlay network. This basically replaces the Level 3 part of the OSI internet model. Each machine gets its own nebula ip and access rules, like a firewall. I made my blog's domain serve as a lighthouse for them with a free Oracle Cloud lighthouse instance running as a backup.

All of this lives in a single registry file — every host's IP, role, SSH key, and group membership. Adding a new machine to the network means adding an entry here and regenerating certs:

[`hosts/nebula-registry.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/hosts/nebula-registry.nix)

```nix
let
  networks = {
    nebula = { subnet = "10.100.0.0/16"; };
    lan = {
      subnet = "192.168.69.0/24";
      gateway = "192.168.69.1";
      dhcp = { start = "192.168.69.100"; end = "192.168.69.199"; };
    };
    containers = {
      subnet = "192.168.100.0/24";
      bridge = "192.168.100.1";
      hosts = {
        reverse-proxy = "192.168.100.2";
        blog-service = "192.168.100.3";
        authelia = "192.168.100.4";
      };
    };
    tailscale.subnet = "100.64.0.0/10";
  };

  hosts = {
    oracle = {
      ip = "10.100.0.2";
      external = "150.136.155.204:4242";
      isLighthouse = true;
      isRelay = true;
      role = "lighthouse";
      groups = ["lighthouse" "system-manager"];
      publicKey = "ssh-ed25519 AAAAC3...";
      meta = {
        hardware = "Oracle Cloud VM (x86_64)";
        purpose = "External Nebula lighthouse + relay for redundancy";
      };
    };

    maitred = {
      ip = "10.100.0.50";
      lanIp = "192.168.69.1";
      isLighthouse = true;
      isRelay = true;
      external = "kimb.dev:4242";
      role = "router";
      groups = ["routers" "nixos"];
    };

    historian = {
      ip = "10.100.0.10";
      role = "desktop";
      groups = ["desktops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3...";
      meta = {
        hardware = "Beelink SER5 Max (Ryzen 7 5800H APU)";
        purpose = "Daily driver desktop, future local AI inference";
      };
    };

    # ... more hosts
  };
in { inherit networks hosts; /* ... */ }
```

[Don't worry, I'm actually costing Mr. Ellison money. All developers with a heart must claim their free ARM and micro x86 instances and never, ever recommend Oracle at work!]{.sidenote}

Nebula is great at working around network weirdness in general, and lets you define a firewall for each machine on the network with its configs. NixOS has a module that carefully builds each nebula config from your options. My consolidated module reads the registry and derives each host's view of the network automatically:

[`modules/nebula-node.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/modules/nebula-node.nix)

```nix
# Lighthouses and relays derived from registry, excluding self
allLighthouses =
  filter (n: (n.isLighthouse or false) && n ? external)
  (attrValues registry.nodes);

lighthouseIps =
  if isLighthouse then []
  else map (n: n.ip) allLighthouses;

staticHosts = listToAttrs (map (n: nameValuePair n.ip [n.external]) allLighthouses);

# ...

services.nebula.networks.mesh = {
  enable = true;
  inherit isLighthouse;

  ca = config.age.secrets.nebula-ca.path;
  cert = config.age.secrets.nebula-cert.path;
  key = config.age.secrets.nebula-key.path;

  lighthouses = lighthouseIps;
  staticHostMap = staticHosts;

  settings = {
    punchy = { punch = true; respond = true; };

    # Prefer direct LAN connections over relay/lighthouse routing
    local_range = registry.networks.lan.subnet;
    preferred_ranges = [registry.networks.lan.subnet];

    relay = {
      relays = relayIps;
      am_relay = isRelay;
      use_relays = true;
    };
  };

  firewall = {
    outbound = [{ port = "any"; proto = "any"; host = "any"; }];
    inbound = [
      { port = "any"; proto = "icmp"; host = "any"; }
      { port = 22; proto = "tcp"; host = "any"; }
    ]
    # Optional: open all ports to personal devices
    ++ optionals cfg.openToPersonalDevices [
      { port = "any"; proto = "any"; group = "desktops"; }
      { port = "any"; proto = "any"; group = "laptops"; }
    ]
    ++ cfg.extraInboundRules;
  };
};
```

I also used agenix and a script to generate certs and keys for each host, then encrypt them with age, an open source and robust encryption tool that works with SSH keys. This let me put those secrets safely in the nix store, for the actual hosts to decode with systemd services while the machine boots.

The secrets file itself derives from the registry — each host's SSH public key determines what it can decrypt, so there's no manual key management:

[`secrets/secrets.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/secrets/secrets.nix)

```nix
let
  registry = import ../hosts/nebula-registry.nix;
  inherit (registry) hostKeys bootstrap;
  oracleKey = registry.nodes.oracle.publicKey;
  workingMachines = (builtins.attrValues hostKeys) ++ [bootstrap oracleKey];

  # Helper to create node cert/key secrets for a host
  createNodeSecrets = name: {
    "nebula-${name}-cert.age".publicKeys = [hostKeys.${name} bootstrap];
    "nebula-${name}-key.age".publicKeys = [hostKeys.${name} bootstrap];
  };

  # Generate nebula secrets for all NixOS hosts
  allNebulaSecrets =
    builtins.foldl' (acc: name: acc // createNodeSecrets name) {}
    (builtins.attrNames hostKeys);
in
  {
    # Shared CA certificate - all working systems
    "nebula-ca.age".publicKeys = workingMachines;

    # Cloudflare API token - only maitred needs this
    "cloudflare-api-token.age".publicKeys = [hostKeys.maitred bootstrap];

    # Life Coach Agent HA token
    "ha-life-coach-token.age".publicKeys = [
      hostKeys.rich-evans hostKeys.historian hostKeys.marshmallow bootstrap
    ];
  }
  // allNebulaSecrets
```

Then, I set up a recursive dns server on my custom router and added each host as both a local hostname and a nebula routed vpn hostname. This is a real force multiplier for managing machines over ssh and setting up webservices. Instead of writing each by hand, Nix builds it by simply iterating over a list of nebula hosts in a "single source of truth" registry file.

[`hosts/maitred/configuration.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/hosts/maitred/configuration.nix) (unbound DNS section)

```nix
services.unbound = {
  enable = true;
  settings.server = {
    interface = ["0.0.0.0" "127.0.0.1"];
    access-control = [
      "192.168.69.0/24 allow"
      "192.168.100.0/24 allow"  # Container network
      "127.0.0.0/8 allow"
    ];
    # Local DNS entries for Nebula hosts and enabled services
    local-data = let
      registry = import ../nebula-registry.nix;
      cfg = config.kimb;

      # Every nebula host gets a .nebula DNS entry
      nebula-hosts =
        builtins.map (name: "\"${name}.nebula. A ${registry.nodes.${name}.ip}\"")
        (builtins.attrNames registry.nodes);

      # Enabled public services get subdomains pointing to router
      serviceDomains =
        lib.mapAttrsToList (name: service:
          "\"${service.subdomain}.${cfg.domain}. A 192.168.69.1\""
        ) (lib.filterAttrs (name: service:
            service.enable && service.publicAccess
          ) cfg.services);

      rootDomain = ["\"${cfg.domain}. A 192.168.69.1\""];
    in
      nebula-hosts ++ rootDomain ++ serviceDomains;
  };
};
```

The upshot of all this was a version of Tailscale, where I own all my keys and can trust machines not to need me to log back in on Tailscale's schedule.

Then, I hooked web services I'd like linked to my intranet to a Caddy reverse proxy on my router that uses nebula ips to robustly access the devices. Even if they somehow lost their access via lan, they could still fix it with a tunnel, and it simplifies migrating my services to new cloud providers so long as I regenerate the certs with the local ssh keys.

The reverse proxy runs in a NixOS container and generates its Caddy config from the same service definitions that drive DNS, monitoring, and auth:

[`hosts/maitred/reverse-proxy.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/hosts/maitred/reverse-proxy.nix)

```nix
# Generate Caddy virtual host for a service
mkServiceVirtualHost = serviceName: service: let
  domain = "${service.subdomain}.${cfg.domain}";
  needsAuth = service.auth == "authelia";

  # Determine target: container IP or bridge (socat forwards to remote hosts)
  targetIP =
    if service.containerIP != null
    then service.containerIP
    else cfg.networks.containerBridge;

  authConfig = lib.optionalString needsAuth ''
    forward_auth ${cfg.networks.containerBridge}:${toString cfg.services.authelia.port} {
      uri /api/verify?rd=https://auth.${cfg.domain}
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
  '';
in
  lib.nameValuePair domain {
    extraConfig = ''
      ${authConfig}
      reverse_proxy ${targetIP}:${toString service.port}
    '';
  };

# The container itself
containers.reverse-proxy = lib.mkIf cfg.services.reverse-proxy.enable {
  autoStart = true;
  privateNetwork = true;
  hostAddress = cfg.networks.containerBridge;
  localAddress = cfg.services.reverse-proxy.containerIP;

  config = { config, pkgs, lib, ... }: {
    services.caddy = {
      enable = true;
      virtualHosts = serviceVirtualHosts // {
        ${cfg.domain} = lib.mkIf cfg.services.blog.enable {
          extraConfig = ''
            reverse_proxy ${cfg.services.blog.containerIP}:${toString cfg.services.blog.port}
          '';
        };

        # Robot vacuum (Valetudo) - protected by Authelia SSO
        "vacuum.${cfg.domain}" = {
          extraConfig = ''
            forward_auth ${cfg.networks.containerBridge}:${toString cfg.services.authelia.port} {
              uri /api/verify?rd=https://auth.${cfg.domain}
              copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
            }
            reverse_proxy 192.168.69.177:80
          '';
        };
      };
    };
  };
};
```

I'm sure that's all configurable with Tailscale or Zeroconf, but Nebula cleanly let me describe all that within a single Nix flake, where machines and services can cross reference other machines' configs and so on. I even configured the Oracle lighthouse that's too tiny for a full nixos install to deploy Nebula with a [System Manager](https://github.com/numtide/system-manager) config. Since system-manager lacks NixOS's agenix module, secrets are stored encrypted in `/etc` and decrypted at boot by a oneshot systemd service:

[`hosts/oracle/configuration.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/hosts/oracle/configuration.nix)

```nix
# Oracle Cloud VM - managed via system-manager (not NixOS)
# Runs 3 nebula networks: mainnet (10.100), buildnet (10.101), containernet (10.102)
{pkgs, ...}: let
  encryptedSecrets = {
    mainnet = {
      ca = ../../secrets/nebula-ca.age;
      cert = ../../secrets/nebula-oracle-cert.age;
      key = ../../secrets/nebula-oracle-key.age;
    };
    # buildnet and containernet follow the same pattern...
  };
in {
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";

    # Encrypted secrets placed in /etc (from Nix store — safe, they're encrypted)
    environment.etc."nebula/mainnet/encrypted/ca.age".source = encryptedSecrets.mainnet.ca;
    environment.etc."nebula/mainnet/encrypted/cert.age".source = encryptedSecrets.mainnet.cert;
    environment.etc."nebula/mainnet/encrypted/key.age".source = encryptedSecrets.mainnet.key;

    # Oneshot service decrypts before nebula starts
    systemd.services.nebula-secrets = {
      description = "Decrypt Nebula secrets for all networks";
      wantedBy = ["multi-user.target"];
      before = ["nebula-mainnet.service" "nebula-buildnet.service" "nebula-containernet.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "decrypt-nebula-secrets" ''
          set -euo pipefail
          mkdir -p /run/nebula-secrets/mainnet
          ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
            -o /run/nebula-secrets/mainnet/ca.crt \
            /etc/nebula/mainnet/encrypted/ca.age
          # ... cert and key follow the same pattern for each network
          chmod -R 600 /run/nebula-secrets/*/
        '';
      };
    };

    systemd.services.nebula-mainnet = {
      description = "Nebula mainnet (10.100.0.0/16)";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nebula-secrets.service"];
      requires = ["nebula-secrets.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/nebula/mainnet/config.yml";
        Restart = "always";
      };
    };
  };
}
```

With Nebula, I own the features and abstractions.

This means my network infrastructure is now declarative, and can expand to include any computers I care to include.

## Context Windows and Fixing Things

Users install and remove software on their machines, and it's hard to keep track of. This is why Windows computers can end up so dysfunctional, as odd changes pile up and fail to clean themselves up with uninstalls and updates. And frankly, every kind of user eventually forgets what they even did to make their computer the way it is.

Like I mentioned before, a NixOS machine is a known entity with the rigid parts clearly specified. A constellation of NixOS machines becomes a fleet with known relationships and services working across hosts.

This is very useful for debugging problems with Claude Code, as it can see the whole configuration and the source code in nixpkgs. Coding AIs are already quite familiar with Linux, too.

For me as a user, I also like the cleanly organized context because truthfully, I will never remember every program I installed and how they were set up. Code as Infrastructure with Nix is wonderful.

## Cybernetics

At that point, my machines were all in a cheerful hivemind. Having stable ips, it was time to try AI agents to help me out with my assorted smarthome gadgets.

Lately, I've been messing with my rooted Dreame L10S robot vacuum. These days, Chinese robot vacuums run Linux on an SOC, with enough resources to handle mapping and routing with capacity to spare. They're really rolling servers full of fun sensors. You can even get a video stream out of it, if you know where to look. I've had fun installing [Valetudo](https://github.com/Hypfer/Valetudo) on it, as well as some of my own software. That's for a future post! But I have prototype agents built around Claude Code trying to move it between waypoints, observe images, and speak through Piper TTS, with the AIs running on my home server. These behaviors could be packaged as Claude Skills (which I've also practiced defining in Nix), so an agent could navigate my home and comment on things for whatever reason. Nix was extremely useful in setting up services that can run across machines so that I could have this relatively low powered embedded device work with fascinating things like modern TTS and AI vision beyond obstacle avoidance.

That cross-machine coordination is possible because clients can offload heavy builds to a beefy server over the nebula mesh — any host can transparently fall back to local builds if the builder is unreachable:

[`modules/distributed-builds.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/modules/distributed-builds.nix) (client config)

```nix
# === CLIENT CONFIG (all non-builder hosts) ===
(mkIf (!cfg.isBuilder) {
  nix.buildMachines = [
    {
      hostName = historianIP;       # 10.100.0.10 via nebula
      system = "x86_64-linux";
      sshUser = "root";
      sshKey = "/etc/ssh/ssh_host_ed25519_key";
      inherit (cfg) maxJobs speedFactor;
      supportedFeatures = ["nixos-test" "big-parallel" "kvm"];
    }
    {
      hostName = totalEclipseIP;    # 10.100.0.6 via nebula
      system = "x86_64-linux";
      sshUser = "root";
      sshKey = "/etc/ssh/ssh_host_ed25519_key";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["nixos-test" "kvm"];
    }
  ];

  nix.distributedBuilds = true;
  nix.settings.connect-timeout = cfg.connectTimeout;  # 10s before fallback

  programs.ssh.knownHosts.historian = {
    hostNames = [historianIP "historian"];
    publicKey = historianKey;
  };
})
```

I do have one practical agent working, that I might weave the vacuum into in a future iteration. With my Google Home smart speaker, lamp on a Tapo outlet, and a few webcams in my room, I have a service loop over having a Claude agent look at the time and the cameras and tell me via Piper TTS if I'm staying up too late or not getting out of bed in the morning, with an ai-set wait time after each iteration until it next looks around. It yells louder and louder and strobes the lights if I don't do what it says, and killing the service on my server is more of a pain than going to bed. As a lifelong insomniac who shamelessly will stay up for a fun project and can ignore alarms, this helps. Even if I ignore the alarms, the ai has context of what I'm doing and how effective it's been. This might not be the most privacy conscious setups, but at least I'm just trusting Anthropic instead of a fly-by-night startup. Last I checked, they say they don't train on Claude Code sessions, and I'm having so much fun I don't want to hear if that changed! Remarkably, this has given me a somewhat normal sleep cycle, even when it's not a workday.

The whole thing is a NixOS service definition with cameras, smart outlets, Home Assistant integration, and even a hybrid mode that uses a fast model for routine checks with a smarter model for oversight:

[`hosts/rich-evans/life-coach.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/hosts/rich-evans/life-coach.nix)

```nix
# Life Coach Agent
# AI-powered sleep schedule monitor that watches via webcam and yells at you

# Create dedicated user for the agent
users.users.life-coach = {
  isNormalUser = true;
  group = "life-coach";
  home = "/var/lib/life-coach-agent";
};
users.groups.life-coach = {
  members = ["hass"];  # Allow Home Assistant to write interrupt events
};

services.life-coach-agent = {
  enable = true;
  user = "life-coach";

  # Camera URLs - webcam server on same host
  cameraBedUrl = "http://127.0.0.1:8554/cam0";
  cameraDeskUrl = "http://127.0.0.1:8554/cam1";

  # Smart lamp on LAN
  lampIP = "192.168.69.152";

  # Home Assistant for presence sensor
  homeAssistantUrl = "http://127.0.0.1:8123";
  homeAssistantTokenFile = config.age.secrets.ha-life-coach-token.path;

  stateDir = "/var/lib/life-coach-agent";

  # Hybrid mode: Haiku for speed/cost, Sonnet oversight every 30 min
  hybridMode = {
    enable = true;
    fastModel = "haiku";
    oversightModel = "sonnet";
    interval = 1800;
  };

  # Daily oversight reviews at 4 AM
  s3Manager = {
    enable = true;
    schedule = "04:00";
    reportDir = "/var/lib/life-coach-agent/reports";
  };
};

# HA can signal button presses and location changes into the agent's state DB
environment.etc."life-coach-agent/signal_button_press.sh" = {
  mode = "0755";
  text = ''
    #!${pkgs.bash}/bin/bash
    DB_PATH="/var/lib/life-coach-agent/state.db"
    ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
      "INSERT INTO interrupt_events (event_type, payload)
       VALUES ('button_press', '{\"button\": \"$1\"}');"
  '';
};
```

This works so well because AI agents are code that runs LLMs in a loop to modify their environment. Nix defined my entire home's digital environment in a single flake repo, so I can see every firewall rule, every installed package, every IP, and every software version. I can then limit Claude's exposure to that environment by defining a nixos-container with limited permissions in the larger systems/networks. This won't solve prompt injection or weird ai behavior, but at least it reduces the surface area.

## Monotropism

I'm on the spectrum, and some researchers believe the core trait that leads to all other autistic traits is [_monotropism_](https://en.wikipedia.org/wiki/Monotropism), a tendency to fixate on one or a few details instead of the big picture. To me, learning a tool I'm not excited about can be hell, and if I have to cross-reference a lot to code something, I lose track. When I hear about serious infrastructure software like Ansible or Kubernetes, an adult part of me knows they're popular for a reason, but I can't bring myself to read about them.

And frankly, Nix lets me decide if I want to treat my machines like livestock or pets. My computers _are_ pets, they have histories and I have good memories with them. They deserve bespoke configuration. It's my services that nixos lets me containerize and abstract away from arbitrary contexts. As a Quaker, I'd like to note that some people use Nix to treat their computers as munitions. I'd prefer you didn't.

Nix works because it's a minimal core language with just the abstractions needed for a theoretically hermetic system (nix haters will pass out while telling me how I'm wrong in practice), but _system_ does not mean an _operating system_. You can define how to assemble a text file or an entire network with those same abstractions, and the scope of Nix's domain grows with my fascination. I jump between hobbies a lot, but Nix has been my thing for two years. I don't have to smear my attention across five different YAML files. If I need a YAML file, I can do the responsible thing and never use YAML with nix's builtin toYAML function and embed it into whatever wants it.

In practice, one service definition module drives the reverse proxy, DNS records, monitoring scrape configs, and auth policy all at once — a single `enable = true` wires everything up:

[`modules/kimb-services.nix`](https://github.com/mccartykim/systems-flake/blob/4784662da027b254a71ef6470f9caf9c8ab5dec2/modules/kimb-services.nix)

```nix
serviceType = types.submodule ({name, config, ...}: {
  options = {
    enable = mkOption { type = types.bool; default = false; };
    port = mkOption { type = types.port; };
    subdomain = mkOption { type = types.str; default = name; };
    host = mkOption { type = types.str; default = "maitred"; };
    containerIP = mkOption { type = types.nullOr types.str; default = null; };
    publicAccess = mkOption { type = types.bool; default = true; };
    auth = mkOption {
      type = types.enum ["none" "authelia" "builtin"];
      default = "authelia";
    };
    websockets = mkOption { type = types.bool; default = false; };
  };
});

# Computed/derived values available to other modules
config.kimb.computed = {
  enabledServices = filterAttrs (name: service: service.enable) cfg.services;

  publicServices = filterAttrs (name: service:
    service.enable && service.auth == "none"
  ) cfg.services;

  # All domains that need DNS records
  allDomains = [cfg.domain]
    ++ (attrValues (mapAttrs (name: service:
      "${service.subdomain}.${cfg.domain}"
    ) (filterAttrs (name: service: service.enable) cfg.services)));

  websocketServices = filterAttrs (name: service:
    service.enable && service.websockets
  ) cfg.services;
};
```

In my mind, my flake is one beautiful object with facets for all my computers, letting my small, fleeting interests compose into something whole and good.

I've gone from a casual linux user to someone really curious how a Linux system fits together and works because NixOS makes it elegant and satisfying. I get to look at how a master watchmaker builds and sets up my watch in terse, functional code. If you solve a problem in Nix, chances are it's solved for good and git log will say how you did it forever.

Honestly, get yourself a netbook or boot up an old machine, [install NixOS following this book](https://nixos-and-flakes.thiscute.world/), and see what you can do after the initial pain. Eventually, Nix will feel less weird and you'll wonder how you ever ran a system without it.
