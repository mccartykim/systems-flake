# Kimb's System Flake

So, I've been gushing about Nix to anyone who will hear, trying to explain how all the parts fit together, but I was mostly just using it as a way to set up computers with one big config directory with logic and paths I defined.

I loved that garnix could build all my stuff. I liked that I could do things like send an overheating tablet's builds to my gaming pc.

But to get the ultimate configuration experience, it should apply changes to all my machines at once when I decide something else about a shell makes me comfy. So now I'm trying to kludge together a fleet flake.

## Dramatis Personae

* rich-evans: Multimedia server running on an HP mini-pc with some kind of celeron chip that's not a total joke, so hope you like light transcoding (actually I'm having issues with that...)
* bartleby: My college era Thinkpad 131e, a tank of an educational netbook. Bought from some electronics reseller who got it from the Missouri school on ebay.
* total-eclipse: Circa 2020 gaming PC with a GeForce 2040 RTX whatever. I don't know. It played death stranding fine. Now it can run a modest stable diffusion setup. I should put that in a flake. I should focus tho.
* marshmallow: My newest machine. A Thinkpad T490 with an 8th gen i5. Seems nice. Faster than what I was used to, and while it came broken, I fixed everything wrong with it easily. Just a few captive screws and some scary but strong clips and you're in. I'm hoping it can be a cozy long-form typing machine. It's called marshmallow to embody that coziness. My mind was somewhere else when I named this.

Plus a few others. Sweets are portable, anything goes for desktops and servers :)

## To Do
* Figure out a universal home profile for others to inherit from
* Replace imports with modules when I feel comfortable.
* Containers in their own directory
* Automatic deployment from garnix, or at least cron job updates.

## My hive-mindification approach so far:
1. Install NixOS on machine using whatever installer works. I've mostly used the GUI installer but I've also used the manual installer. They're both nice. But both make an opinionated config.
2. Fix up that config to work with flakes and probably also tailscale and garnix
3. Sort out hardware specific issues
4. Copy nixos config files from that machine into this flake's hosts/$HOST directory.
5. Add reference to that host in flake. Ensure it builds.
6. Add import of default nix config. Test again.
7. Strip out redundant components, leaving just the quirks for that machine in the config.

## Nebula Mesh Network

All machines are connected via a [Nebula](https://github.com/slackhq/nebula) mesh network with age-encrypted certificates. The lighthouse runs on Google Cloud.

### Network Layout
- **Subnet**: `10.100.0.0/16`
- **Lighthouse**: Uses centralized registry (`registry.network.lighthouse.ip`)
- **DNS Server**: maitred router at `registry.nodes.maitred.ip` (primary DNS for network)

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
* Create a few simple configs that suit my idea of an archetypal config, for easier installs down the line.
* Steamdeck
* ~~Some kind of clever garnix friendly scheme to autoconfig tailscale from the box, maybe some garbo like agenix?~~ ✅ Done with Nebula + agenix!
