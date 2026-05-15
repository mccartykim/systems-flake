# Security regression — pins N-2 from docs/security-audit.md.
#
# `services/default.nix` and `modules/kimb-services.nix` together let a
# service be declared with `publicAccess = true; auth = "none";` against
# any subdomain. That is correct for the public blog and Authelia, but
# the topology DSL has no guard against accidentally pointing an
# internal-looking subdomain (admin, prom, hass, vacuum, ...) at a
# `auth = "none"` backend.
#
# The audit fix is to add an `assertions` entry in
# `modules/kimb-services.nix` that rejects this combination unless the
# subdomain is explicitly whitelisted.
#
# This derivation evaluates `kimb-services` against a deliberately bad
# config and asserts that a failing assertion fires. Today (no
# assertion declared anywhere in the module), `config.assertions` is
# empty and the test fails.
{
  pkgs,
  lib,
  ...
}: let
  # Stub providing the `assertions` option (kimb-services is loaded in
  # isolation via lib.evalModules, not inside a real NixOS system).
  assertionsStub = {
    options.assertions = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          assertion = lib.mkOption {type = lib.types.bool;};
          message = lib.mkOption {type = lib.types.str;};
        };
      });
      default = [];
    };
  };

  # Deliberately bad config: an "admin"-looking subdomain marked
  # publicAccess + auth=none. The fix's whitelist should NOT cover this.
  badConfig = {
    kimb.services.admin-panel = {
      enable = true;
      port = 8080;
      subdomain = "admin";
      host = "maitred";
      publicAccess = true;
      auth = "none";
      websockets = false;
    };
  };

  evaluated = lib.evalModules {
    modules = [
      assertionsStub
      ../../modules/kimb-services.nix
      badConfig
    ];
  };

  # Collect any assertion that fails for the bad config.
  failingAssertions =
    builtins.filter (a: !a.assertion) (evaluated.config.assertions or []);

  hasFailingAssertion = failingAssertions != [];
  failingMessages = map (a: a.message) failingAssertions;
in
  pkgs.runCommand "security-regression-auth-none-guard"
  {
    hasGuard =
      if hasFailingAssertion
      then "yes"
      else "no";
    messages = builtins.concatStringsSep "\n" failingMessages;
  } ''
    if [ "$hasGuard" != "yes" ]; then
      cat <<'EOF'
    FAIL: N-2 — kimb-services has no assertion guarding publicAccess=true + auth="none"
          on internal-looking subdomains.

          Reproduction: a service declared with
              { subdomain = "admin"; publicAccess = true; auth = "none"; ... }
          evaluates with config.assertions = [] (or with no failing entries).

          Expected fix: modules/kimb-services.nix should add an assertions
          entry rejecting this combination, with an explicit whitelist for
          the legitimate cases (blog, auth.kimb.dev, ...).

          See docs/security-audit.md section 2, finding N-2.
    EOF
      exit 1
    fi

    echo "PASS: kimb-services rejected the bad publicAccess+auth=none config:"
    echo "$messages" | sed 's/^/  /'
    touch $out
  ''
