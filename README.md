# Kimb's System Flake

So, I've been gushing about Nix to anyone who will hear, trying to explain how all the parts fit together, but I was mostly just using it as a way to set up computers with one big config directory with logic and paths I defined.

I loved that garnix could build all my stuff. I liked that I could do things like send an overheating tablet's builds to my gaming pc.

But to get the ultimate configuration experience, it should apply changes to all my machines at once when I decide something else about a shell makes me comfy. So now I'm trying to kludge together a fleet flake.

## Dramatis Personae

* rich-evans: Retired hp micropc multimedia server with some kind of celeron chip that's not a total joke. A light utility general server now.
* bartleby: My college era Thinkpad 131e, a tank of an educational netbook. Bought from some electronics reseller who got it from the Missouri school on ebay.
* total-eclipse: Circa 2020 gaming PC with a GeForce 4060 RTX whatever. I don't know. It played death stranding fine. Now it can run a modest stable diffusion setup. I should put that in a flake. I should focus tho.
* marshmallow: My favorite laptop. A Thinkpad T490 with an 8th gen i5. Seems nice. Faster than what I was used to, and while it came broken, I fixed everything wrong with it easily. Just a few captive screws and some scary but strong clips and you're in. I'm hoping it can be a cozy long-form typing machine. It's called marshmallow to embody that coziness. My mind was somewhere else when I named this.
* donut: My steamdeck. Was going to call it creampuff but accidentally gave that name to
* creampuff: My Surface 3 Go tablet that I'm trying to make usable without constant overheating. x86 processors shouldn't be passively cooled but I'm hoping Linux can make the most of it.
* historian: A server I bought hoping for AI inference with a Strix Point processor, but rocm isn't fantastic so I'm using it as a build machine and multimedia device for now. Also my primary remote dev machine.
* maitred: My bespoke Datto box turned router, that bridges the WAN to my LAN and runs a few small services of its own.

Plus a few others. Sweets are portable, anything goes for desktops and servers :)

## Services off the top of my head
Having a declarative mesh network and single config for my fleet makes this system very ammenable to setting up a few home services. I suppose this is self-host/homelabbing stuff, but I just consider it a kind of DIY home improvement.

* Caddy, my reverse proxy that runs on maitred (so far it's fine), paired with some cloudflare dedyn thing. Hosts kimb.dev and internal services.
* Nebula, abstracts away lan/remote machines and allows my laptop to function well wherever. I also like it as a tool to get around level 3 networking for tiny/weird machines and hope to get it really straightforward for nebula.
* Authelia, for authentification
* Home Assistant via the NixOS Configuration options instead of Docker. Runs on rich evans.
   * See also: ESPHome configs that use HA to add a bunch of ESP32 based buttons around the house to remind me of things.
   * TODO: Add valetudo vacuum
* My blog, under mist-blog. Runs under gleam so I have it run on maitred to test its vaunted efficiency.
* Ollama, for local VLM inference on total-eclipse
* Life Coach Agent, a rich-evans based agent that helps me keep up with routines and tasks.
* A dual webcam endpoint for stills from rich-evans for lifecoach to use.
* Syncthing, a delightful tool for keeping folders synced between computers
* Restic, for lightly compressed regular backups

## To Do
* Get agenix rekeying working reliably on computers I actually use, I keep resorting to manual age rotations that still work fine.
* Add room presence for my phone/watch to HA via one of the ESP32 presence libraries
* Add bedroom led strip to esphome via the tasmoda reflash mod
* Add valetudo vacuum to HA
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

I've dabbled with building custom installers but without the whole SSH pubkey copy routine, building a flake with private inputs kinda sucks... I might have to open source stuff, maybe move my blog content to a separate repo/bucket so I still have private drafts. But I'm just thinking out loud!

(I really wish NixOS anywhere worked consistently on the VPS' that fit in my cheap-as-free budget for the rare cloud machine I want)

## Nebula Mesh Network

All machines are connected via a [Nebula](https://github.com/slackhq/nebula) mesh network with age-encrypted certificates. The lighthouse runs on Oracle and there's another running on my domain.

### Network Layout
- **Subnet**: `10.100.0.0/16`
- **Lighthouse**: Uses centralized registry (`registry.network.lighthouse.ip`)
- **DNS Server**: maitred router at `registry.nodes.maitred.ip` (primary DNS for network)

I'm also experimenting with a buildnet and containernet parallel nebula networks, but I'm starting to realize that might just be awful compared to creating a certbot to add ephemeral machines to a group. That's for later!

### Adding New Devices

1. **Add to registry**: Edit `hosts/nebula-registry.nix` and add your device:
   ```nix
   my-new-device = {
     ip = networkIPs.nebula.hosts.my-new-device;  # Define in network-ips.nix first
     isLighthouse = false;
     role = "laptop";  # or "desktop", "server"
     publicKey = null;  # Will be filled in step 3
   };
   ```

2. **Add NixOS config**: Create `hosts/my-new-device/configuration.nix` and add to `flake.nix`:
   ```nix
   nixosConfigurations.my-new-device = nixpkgs.lib.nixosSystem {
     specialArgs = {inherit inputs outputs;};
     modules = [
       ./hosts/my-new-device/configuration.nix
       # ... other modules
     ];
   };
   ```

3. **Get SSH host key**: Deploy the basic config, then run:
   ```bash
   ./scripts/collect-age-keys.sh
   ```
   Update the `publicKey` field in the registry with the output.

4. **Generate certificates**: The system automatically creates encrypted Nebula certs for all devices in the registry.

5. **Deploy**: Build and deploy your config. The device will automatically join the mesh!

### DNS Resolution
- `hostname.nebula` - Nebula mesh IPs (e.g., `historian.nebula` → `10.100.0.10`)
- `hostname.local` - LAN IPs (e.g., `rich-evans.local` → `192.168.68.200`)

## Wish list
* Create a few simple configs that suit my idea of an archetypal config, for easier installs down the line. Maybe templates but honestly flake templates never work like i hope.
* See if I can get off flakes and try [Nixtamal](https://nixtamel.toast.al/). Not sure if that works well with my flake parts impl. However, flakes are indeed annoying and set rules I'm not sure I need.
