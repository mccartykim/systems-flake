# xenGrubBootBuilder — called via systemd-boot extraInstallCommands (mkAfter
# the upstream xenBootBuilder). Writes per-generation "Xen via GRUB MB2"
# chainload entries; scrubs the firmware-broken xen UKI entries upstream
# wrote; repairs loader.conf's default. Interface deps (same as upstream):
# nixos-*.conf entry naming + boot.json bootspec v1/v2 extension. If nixpkgs
# changes those, only this file should need updating.

set -euo pipefail
export LC_ALL=C

# Optional CLI override for offline rehearsal against a scratch ESP copy.
esp="${1:-$efiMountPoint}"

# Remove the broken-on-this-firmware UKI entries the upstream builder just
# wrote (xen-*.conf + xen-*.efi), and our own stale artifacts.
rm -f "$esp"/loader/entries/xen-*.conf "$esp"/efi/nixos/xen-*.efi \
      "$esp"/loader/entries/xengrub-*.conf
rm -rf "$esp"/EFI/nixos/xengrub-*

mapfile -t gens < <(find "$esp"/loader/entries -type f -name 'nixos-*.conf' | sort -V)

wrote=0
for gen in "${gens[@]}"; do
    bootspecFile="$(sed -nr 's/^options init=(.*)\/init.*$/\1/p' "$gen")/boot.json"
    grep -sq '"org.xenproject.bootspec.v2"' "$bootspecFile" || continue

    grubGen=$(basename "$gen" | sed 's_^nixos-_xengrub-_;s_\.conf$__')
    dirName="EFI/nixos/$grubGen"
    dir="$esp/$dirName"
    mkdir -p "$dir"

    bootParams=$(jq -re '."org.xenproject.bootspec.v2".params | join(" ")' "$bootspecFile")
    multiboot=$(jq -re '."org.xenproject.bootspec.v2".multibootPath' "$bootspecFile")
    kernel=$(jq -re '."org.nixos.bootspec.v1".kernel | sub("^/nix/store/"; "") | sub("/bzImage"; "-bzImage.efi")' "$bootspecFile")
    kernelParams=$(jq -re '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$bootspecFile")
    initrd=$(jq -re '."org.nixos.bootspec.v1".initrd | sub("^/nix/store/"; "") | sub("/initrd"; "-initrd.efi")' "$bootspecFile")
    init=$(jq -re '."org.nixos.bootspec.v1".init' "$bootspecFile")
    title=$(sed -nr 's/^title (.*)$/\1/p' "$gen")
    version=$(sed -nr 's/^version (.*)$/\1/p' "$gen")
    machineID=$(sed -nr 's/^machine-id (.*)$/\1/p' "$gen")
    sortKey=$(sed -nr 's/^sort-key (.*)$/\1/p' "$gen")

    # xen.gz lives in the per-generation dir next to the GRUB image. The
    # whole config is embedded in the image via --config: searching for
    # xen.gz pins $root to the ESP regardless of drive enumeration, and
    # nothing external needs parsing. Kernel/initrd are referenced at their
    # existing shared locations under EFI/nixos.
    cp "$multiboot" "$dir/xen.gz"

    tmpCfg=$(mktemp)
    cat > "$tmpCfg" <<EOFGRUB
search --no-floppy --file --set=xenroot /$dirName/xen.gz
multiboot2 (\$xenroot)/$dirName/xen.gz $bootParams
module2 (\$xenroot)/EFI/nixos/$kernel init=$init $kernelParams
module2 (\$xenroot)/EFI/nixos/$initrd
boot
EOFGRUB

    # Module list comes from the module's grubModules (unquoted expansion is
    # intentional); note part_msdos is load-bearing for partition-table-less
    # media even though it looks vestigial.
    # shellcheck disable=SC2086
    grub-mkimage -O x86_64-efi -o "$dir/grubx64.efi" -p "/$dirName" \
        --config "$tmpCfg" $grubModules
    rm -f "$tmpCfg"

    cat > "$esp/loader/entries/$grubGen.conf" <<EOFCONF
title $title (with Xen Hypervisor)
version $version
efi /$dirName/grubx64.efi
machine-id $machineID
sort-key $sortKey
EOFCONF
    wrote=1
done

# loader.conf repair: upstream xenBootBuilder already flipped
# 'default nixos-' -> 'default xen-'. Point it at our GRUB path, or back at
# the newest plain entry, depending on setXenDefault. NB: entry filenames
# are content hashes, so 'newest' MUST come from the 'Generation NNN' field
# in the version line — never sort the filenames.
pick_newest() {
    local pattern=$1 best='' bestNum=-1 n f
    for f in "$esp"/loader/entries/$pattern; do
        n=$(sed -nr 's/^version Generation ([0-9]+).*/\1/p' "$f")
        if [[ -n "$n" && "$n" -gt "$bestNum" ]]; then bestNum="$n"; best="$f"; fi
    done
    basename "${best%.conf}"
}
if grep -qs '^default xen-' "$esp"/loader/loader.conf; then
    if [ "$setXenDefault" = "1" ] && [ "$wrote" = "1" ]; then
        newest=$(pick_newest 'xengrub-*.conf')
    else
        newest=$(pick_newest 'nixos-*.conf')
    fi
    [ -n "$newest" ] && sed --in-place "s/^default xen-.*$/default $newest/" "$esp"/loader/loader.conf
fi

[ "$wrote" = "1" ] && echo "xenGrubBoot: wrote GRUB-multiboot2 chainload entries." \
                   || echo "xenGrubBoot: WARNING: no generations carried org.xenproject.bootspec.v2; wrote nothing."
