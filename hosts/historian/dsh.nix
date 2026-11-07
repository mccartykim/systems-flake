# DeepSeek Harness (dsh) as an always-on Web service on historian.
#
# Binds historian's Nebula address so other overlay hosts can reach the Web UI,
# and nothing else: dsh's `--host` takes one concrete local address and rejects
# wildcards, because binding every interface would expose the agent's shell
# execution to the whole network. Reach it at http://10.100.0.10:3099/ and open
# the token URL the unit prints to the journal.
#
# == Why the route is ollama.com and not the local ollama ==
#
# The obvious wiring points dsh at historian's own ollama (127.0.0.1:11434),
# which does proxy cloud models server-side. That works, but it makes this
# service depend on ollama's imperative sign-in state in ~/.ollama/config.json:
# when that session expires dsh still starts and still lists models, and every
# request then fails at the provider with nothing in this flake able to repair
# it. Talking to ollama.com directly removes that second dependency. Both
# transports were measured to return correct tool calls.
#
# The credential stays in ~/.dsh/.credentials.yaml (the stored credential file,
# which outranks the environment) because DSH_HOME must remain the default for
# the service to find it. That file is host state, not flake state: recreating
# this host needs it restored, or the service fails loud with MISSING_CREDENTIAL.
#
# Nothing here hardcodes a model catalogue beyond the entries below; adding one
# is a rebuild, not a config edit, and that is deliberate for an always-on box.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb.dsh;
  dshHome = "/home/kimb/.dsh";
in {
  options.kimb.dsh.enable = lib.mkEnableOption "the DeepSeek Harness Web UI as a host service";

  config = {
    # The provider patch. dsh reads providers from a Cordis patch overlay, and a
    # `--patch` overlay is applied after the profile layer, so this arrives from
    # the Nix store without dsh ever writing to it.
    #
    # `apiKeyEnv` names the credential reference only; the value lives in dsh's
    # stored credential file. ollama.com needs a real key, so unlike a local-ollama
    # route this one cannot use a placeholder header.
    environment.etc."dsh/ollama.cordis.yml".text = ''
      - id: llm-pi-ai
        config:
          providers:
            ollama:
              displayName: Ollama Cloud
              apiKeyEnv: OLLAMA_LAUNCH_DSH_API_KEY
              api: openai-completions
              baseURL: https://ollama.com/v1
              models:
                - id: deepseek-v4.1-flash
                  name: deepseek-v4.1-flash
                  contextWindow: 1048576
                  maxTokens: 393216
                  input: [text]
                - id: kimi-k3
                  name: kimi-k3
                  contextWindow: 1048576
                  maxTokens: 1048576
                  input: [text, image]
                - id: glm-5.3
                  name: glm-5.3
                  contextWindow: 1048576
                  maxTokens: 1048576
                  input: [text]

      - id: agent-default-model
        config:
          provider: ollama
          model: deepseek-v4.1-flash

      - id: web-search-deepseek
        config:
          baseURL: https://ollama.com/v1
          model: deepseek-v4.1-flash
          apiKeyEnv: OLLAMA_LAUNCH_DSH_API_KEY
    '';

    # Runs as a system unit rather than a user unit: a user unit would need
    # lingering enabled and would not be described by this flake. User is kimb so
    # the agent's tool calls run as the human, which is what the credential file
    # and the workspace permissions already assume.
    systemd.services.dsh = lib.mkIf cfg.enable {
      description = "DeepSeek Harness Web UI";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      # Restart on any exit: this is a long-lived server a person connects to, so
      # a crash should cost one restart, not a silent outage until someone notices.
      startLimitIntervalSec = 0;

      # The bash tool spawns the bare name `bash` (dsh-bash-local builds
      # `['bash', '-c', command]`), and dsh-subprocess-local resolves it against
      # the child PATH, which it derives from this process's environment. The
      # dsh wrapper alone contributes only pnpm, so without this every
      # model-initiated shell call fails with `command "bash" was not found on
      # PATH` and the harness cannot run a single command.
      #
      # This must be a real toolbelt, not just a shell: this is a coding
      # harness, so git/rg/python/node are part of the contract. `path` is a
      # service-level option that systemd turns into PATH, so it belongs here
      # and not inside serviceConfig (where a `path` key is the unrelated
      # systemd Path= filesystem directive).
      #
      # systemd-run is included so dsh-subprocess-local can reach its
      # linux-scope containment. That needs `systemd-run --user` plus
      # XDG_RUNTIME_DIR from a systemd *user* manager; a system unit has
      # neither, so it degrades to unconfined spawn and logs a warning. A
      # lingering-enabled user unit is the way to get real containment.
      path = [
        pkgs.bashInteractive
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.findutils
        pkgs.systemd
        pkgs.git
        pkgs.ripgrep
        pkgs.jq
        pkgs.python3
        pkgs.nodejs_24
        # The host's own profiles, so tools installed outside this list (the
        # user's home-manager profile, system packages) resolve as they do for
        # an interactive login. Last, so the pinned shell above wins a clash.
        # These are named by their prefix: `path` appends /bin and /sbin, so
        # spelling out "/run/current-system/sw/bin" would yield ".../bin/bin".
        "/run/current-system/sw"
        "/etc/profiles/per-user/kimb"
      ];

      serviceConfig = {
        Type = "simple";
        User = "kimb";
        Group = "users";
        Restart = "always";
        RestartSec = 5;

        # The bash tool spawns the bare name `bash` (dsh-bash-local builds
        # `['bash', '-c', command]`), and dsh-subprocess-local resolves it against
        # the child PATH, which it derives from this process's environment. The
        # wrapper alone contributes only pnpm, so without this every
        # model-initiated shell call fails with `command "bash" was not found on
        # PATH` — the harness cannot run a single command.
        #
        # This must be a real toolbelt, not just a shell: this is a coding
        # harness, so git/rg/python/node are part of the contract. The listed
        # entries guarantee the shell and coreutils exist regardless of how the
        # system profile is shaped.
        #
        # systemd-run is included so dsh-subprocess-local can reach its
        # linux-scope containment. That path needs `systemd-run --user` plus
        # XDG_RUNTIME_DIR from a systemd *user* manager; a system unit has
        # neither, so it degrades to unconfined spawn with a logged warning.
        # A lingering-enabled user unit is the way to get real containment.

        # Also expose the host's own profiles, so tools installed outside this
        # list (the user's home-manager profile, system packages) resolve the
        # same way they do for an interactive login. Kept after `path` so the
        # pinned shell above always wins any collision.
        # DSH_HOME stays at its default so the stored credential file is found.
        # HOME is set explicitly because a system unit does not inherit one, and
        # dsh resolves several paths from it.
        Environment = [
          "HOME=/home/kimb"
          "DSH_HOME=${dshHome}"
        ];

        ExecStart = lib.concatStringsSep " " [
          "${pkgs.dsh}/bin/dsh"
          "--profile web"
          "--patch /etc/dsh/ollama.cordis.yml"
          "--no-open"
          "--host 10.100.0.10"
          "--port 3099"
        ];

        # The agent executes commands and writes files under the workspace it is
        # pointed at, so give it a normal writable environment rather than the
        # store: PrivateTmp is off because a temp dir that vanishes mid-session
        # breaks long tool calls.
        WorkingDirectory = "/home/kimb";
      };
    };

    # dsh's `--host` is a concrete address, so the port is opened only on the
    # overlay interface. historian sets `openToPersonalDevices = true`, which
    # already trusts every port from desktops/laptops/mobile; this rule keeps the
    # service reachable from servers too and, more importantly, states the
    # dependency instead of relying on that blanket trust.
    kimb.nebula.extraInboundRules = lib.mkIf cfg.enable [
      {
        port = 3099;
        proto = "tcp";
        group = "servers";
      }
    ];
  };
}
