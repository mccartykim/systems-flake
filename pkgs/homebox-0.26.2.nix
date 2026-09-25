# HomeBox 0.26.2, ahead of what the pinned nixpkgs ships (0.25.0).
#
# ## Why this override exists
#
# The nixpkgs pin for historian (nixos-unstable-small, rev 8c809a146a14) ships homebox **0.25.0**,
# but upstream's latest release is **0.26.2** and the live database on /mnt/media-drive was created
# by 0.26.2 — it has 26 goose migrations applied. HomeBox runs goose migrations on boot and goose
# errors on a migration version newer than it knows, so switching to 0.25.0 would leave HomeBox
# refusing to start against its own data.
#
# That asymmetry is what makes this necessary rather than merely tidy: the database lives on
# /mnt/media-drive, NOT in the Nix store, so `nixos-rebuild --rollback` would revert the *code* and
# leave the *newer schema* in place. A downgrade is not undone by a rollback.
#
# ## The source of the numbers
#
# Everything below is the 0.26.2 package expression from a newer nixpkgs verbatim, hashes included —
# not retyped or guessed:
#
#     fetchFromGitHub.hash  sha256-JUhRpUWbydy28Xw7j6oCKJLBmaOxcruWAdkqm+hvouY=
#     vendorHash            sha256-peQaPSbxGn8M bZPqCi5ptW+dMh9l4W1hB6HqBLTqh4=   (unwrapped below)
#     fetchPnpmDeps.hash    sha256-oHS2uMWyuqpiK7yWznmZ2mgxPJpWsyOZL2wz6zBu0cc=
#
# Verified before writing this that every primitive it needs exists in the *pinned* nixpkgs
# (fetchPnpmDeps, pnpm_10, pnpmConfigHook, buildGoModule) — so this rebuilds the package rather than
# pulling a second nixpkgs input, which would mean fetching a whole nixpkgs tree on historian for
# the sake of one package. `nixpkgs.follows` on the bin_finder_ai input keeps the closure small.
#
# ## Cost
#
# This is a from-source Go + pnpm build because 0.26.2 is not in cache.nixos.org for this rev. The
# upstream nixpkgs expression notes it needs ~1300 MiB to build; historian has 57 GiB. Colmena
# deploys historian with `buildOnTarget = true`, so the build happens on historian — which is the
# right host for it.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs,
  go,
  git,
  cacert,
}:
let
  pname = "homebox";
  version = "0.26.2";
  src = fetchFromGitHub {
    owner = "sysadminsmedia";
    repo = "homebox";
    tag = "v${version}";
    hash = "sha256-JUhRpUWbydy28Xw7j6oCKJLBmaOxcruWAdkqm+hvouY=";
  };
in
buildGoModule {
  inherit pname version src;

  vendorHash = "sha256-peQaPSbxGn8MnbZPqCi5ptW+dMh9l4W1hB6HqBLTqh4=";
  modRoot = "backend";
  # The goModules derivation inherits our buildInputs and buildPhases; since the pnpm steps happen
  # in those, they must be explicitly removed or the modules build fails.
  overrideModAttrs = _: {
    nativeBuildInputs = [
      go
      git
      cacert
    ];
    preBuild = "";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit pname version;
    src = "${src}/frontend";
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-oHS2uMWyuqpiK7yWznmZ2mgxPJpWsyOZL2wz6zBu0cc=";
  };
  pnpmRoot = "../frontend";

  env.NUXT_TELEMETRY_DISABLED = 1;

  preBuild = ''
    pushd ../frontend

    pnpm build

    popd

    mkdir -p ./app/api/static/public
    cp -r ../frontend/.output/public/* ./app/api/static/public
  '';

  nativeBuildInputs = [
    pnpmConfigHook
    pnpm_10
    nodejs
  ];

  env.CGO_ENABLED = 0;
  doCheck = false;

  tags = [ "nodynamic" ];

  ldflags = [
    "-s"
    "-w"
    "-extldflags=-static"
    "-X main.version=${src.tag}"
    "-X main.commit=${src.tag}"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r $GOPATH/bin/api $out/bin/

    runHook postInstall
  '';

  meta = {
    mainProgram = "api";
    homepage = "https://homebox.software/";
    description = "Inventory and organization system built for the Home User";
    license = [
      lib.licenses.agpl3Only
      lib.licenses.mit
    ];
    platforms = lib.platforms.linux;
  };
}
