# Kimb's System Flake

So, I've been gushing about Nix to anyone who will hear. I started out just using it as a way to set up computers with one big config directory with logic and paths I defined — liked that garnix could build all my stuff, liked that I could send an overheating tablet's builds to my gaming PC. But to get the ultimate configuration experience, it should apply changes to all my machines at once when I decide something else about a shell makes me comfy. So now I'm kludging together a fleet flake.

## Dramatis Personae

* rich-evans: Retired hp micropc multimedia server with some kind of celeron chip that's not a total joke. A light utility general server now.
* bartleby: My college era Thinkpad 131e, a tank of an educational netbook. Bought from some electronics reseller who got it from the Missouri school on ebay.
* total-eclipse: Circa 2020 gaming PC with a GeForce 4060 RTX whatever. I don't know. It played death stranding fine. Now it can run a modest stable diffusion setup. I should put that in a flake. I should focus tho.
* marshmallow: My favorite laptop. A Thinkpad T490 with an 8th gen i5. Seems nice. Faster than what I was used to, and while it came broken, I fixed everything wrong with it easily. Just a few captive screws and some scary but strong clips and you're in. I'm hoping it can be a cozy long-form typing machine. It's called marshmallow to embody that coziness. My mind was somewhere else when I named this.
* donut: My steamdeck.
* cheesecake: My Surface 3 Go tablet that I'm trying to make usable without constant overheating. x86 processors shouldn't be passively cooled but I'm hoping Linux can make the most of it.
* historian: A server I bought hoping for AI inference with a Strix Point processor, but rocm isn't fantastic so I'm using it as a build machine and multimedia device for now. Also my primary remote dev machine.
* maitred: My bespoke Datto box turned router, that bridges the WAN to my LAN and runs a few small services of its own.
* mochi: My Pixel 9 Pro running a tiny Debian VM via the Android Virtualization Framework. Joins the mesh via system-manager since it's not really NixOS.
* oracle: A free-tier Oracle Cloud Ubuntu VM. Mostly just a nebula lighthouse with a stable public IP. Also via system-manager (see the gripe at the bottom of the install section).

Plus a few others. Sweets are portable, anything goes for desktops and servers :)

## Services off the top of my head
Having a declarative mesh network and single config for my fleet makes this system very amenable to setting up a few home services. I suppose this is self-host/homelabbing stuff, but I just consider it a kind of DIY home improvement.

* Caddy, my reverse proxy that runs on maitred, paired with some cloudflare dedyn thing. Hosts kimb.dev and internal services.
* Nebula, abstracts away lan/remote machines and allows my laptop to function well wherever. I also like it as a tool to get around level 3 networking for tiny/weird machines and hope to get it really straightforward for nebula.
* Authelia, for authentification
* Home Assistant via the NixOS Configuration options instead of Docker. Runs on rich evans.
   * See also: ESPHome configs that use HA to add a bunch of ESP32 based buttons around the house to remind me of things.
   * Valetudo vacuum integration, with a vacuum-organism sidecar that nags me to put away chairs before it runs.
* My blog, under mist-blog. Runs under gleam so I have it run on maitred to test its vaunted efficiency.
* Ollama, for local VLM inference on total-eclipse and historian (historian runs the rocm build).
* Life Coach Agent, a rich-evans based agent that helps me keep up with routines and tasks.
* A dual webcam endpoint for stills from rich-evans for lifecoach to use.
* Syncthing, for keeping folders synced between computers
* Restic, for regular backups
* Buildbot CI on rich-evans (master) and historian (worker). Took over the role garnix used to play; I miss garnix's UI but at least this one runs on hardware I own.
* Matrix (conduit) on rich-evans for self-hosted chat
* Kokoro and Qwen3-TTS for the life-coach's voice. Kokoro is the small fast one; Qwen3 is the zero-shot voice cloning one.
* Eden, the Switch emulator, built from master with a per-host profile (znver2 for the Steam Deck, x86-64-v3 for total-eclipse)

## Modules broken out into their own flakes

A handful of services live in their own little repos and get pulled in here as flake inputs. The pattern is: the upstream flake exports a generic NixOS module with options; this repo imports it and supplies the kimb-specific bits (my domain, my paths, my agenix secrets). I think this is the right shape for things other people might want to copy out without inheriting my specifics.

* `kokoro-flake` — TTS for the life-coach
* `qwen3-tts-cuda-flake` — Qwen3-TTS via CUDA, runs on total-eclipse
* `restic-b2-backup-flake` — restic to Backblaze B2 with sensible defaults
* `cloudflare-ddns-flake` — inadyn wrapper for Cloudflare DDNS
* `eden-nightly-flake` — the Switch emulator built from upstream master. donut pulls the `eden-nightly-steamdeck` (znver2) package, total-eclipse pulls `eden-nightly` (x86-64-v3). This *is* the from-source path, not an AppImage extraction.

I'm not sold on every extraction sticking — once tried pulling out a nebula wrapper and it turned out nixpkgs's `services.nebula` was already doing 90% of it, so that one came back inline.

## To Do
* Get agenix rekeying working reliably on computers I actually use, I keep resorting to manual age rotations that still work fine.
* Add room presence for my phone/watch to HA via one of the ESP32 presence libraries
* Add bedroom led strip to esphome via the tasmoda reflash mod
* Maybe move lifecoach to the faster historian once I'm confident in the migration/ports.
* Document colmena deployment better.
* Consider: Maybe direnv does make sense for my projects/this repo but every time I do it I get annoyed at speed + everything else.
* Local wiki for roomies. 

## My hive-mindification approach so far:
1. Install NixOS on machine using whatever installer works. I've mostly used the GUI installer but I've also used the manual installer. They're both nice. But both make an opinionated config I need to then install over.
2. Fix up that config to work with flakes and probably also tailscale and garnix
3. Sort out hardware specific issues
4. Copy nixos config files from that machine into this flake's hosts/$HOST directory.
5. Add reference to that host in flake. Ensure it builds.
6. Add import of default nix config. Test again.
7. Strip out redundant components, leaving just the quirks for that machine in the config.

I've dabbled with building custom installers but without the whole SSH pubkey copy routine, building a flake with private inputs kinda sucks. (I really wish NixOS anywhere worked consistently on the VPS' that fit in my cheap-as-free budget for the rare cloud machine I want.)

## Nebula Mesh Network

All machines are connected via a [Nebula](https://github.com/slackhq/nebula) mesh network with age-encrypted certificates. The lighthouse runs on Oracle and there's another running on my domain.

### Network Layout
- **Subnet**: `10.100.0.0/16`
- **DNS Server**: maitred router at `registry.nodes.maitred.ip` (primary DNS for network)

### DNS Resolution
- `hostname.nebula` - Nebula mesh IPs (e.g., `historian.nebula` → `10.100.0.10`)
- `hostname.local` - LAN IPs (e.g., `maitred.local` → `192.168.69.1`). Only maitred has a fixed LAN IP in the registry; other hosts get their LAN address via DHCP.

### Adding a host

The annoying part is that nebula certs need the host's SSH pubkey, which doesn't exist until after first install. So this is a two-pass dance:

1. Add the host to `hosts/nebula-registry.nix` — IP, groups (e.g. `["laptops" "nixos"]`), `publicKey = null` for now. The registry's the source of truth; everything else derives from it.
2. Wire it up in `flake-modules/nixos-configurations.nix`. Most hosts go through the `mkDesktop` / `mkServer` helpers in `flake-modules/helpers.nix`. The weird ones (donut on Jovian, maitred the router, mochi on AVF) call `nixpkgs.lib.nixosSystem` themselves.
3. First deploy without nebula. Install NixOS however, copy this flake in, `nixos-rebuild switch --flake .#<host>`. Most things come up; nebula won't because there's no cert yet, that's fine.
4. Run `./scripts/collect-age-keys.sh` to grab the new host's SSH host pubkey. Paste it into the registry's `publicKey` field.
5. `nix run .#generate-nebula-certs` — wants my YubiKey to decrypt the CA. Outputs per-host certs/keys re-encrypted against each host's SSH pubkey.
6. Deploy again, this time via colmena (`nix develop -c colmena apply --on <hostname>`). Mesh should be live.

Most of the friction here is the YubiKey ceremony — one day I'll get agenix-rekey working reliably and that'll smooth out a lot.