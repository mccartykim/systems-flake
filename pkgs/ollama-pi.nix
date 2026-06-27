# ollama-pi: pi-coding-agent wrapper pinned to a custom Ollama provider.
#
# pi has no base-URL env var (upstream closed issue #8 in favour of
# models.json) and Ollama isn't in `/login` — it's a custom provider configured
# via ~/.pi/agent/models.json. This wrapper points PI_CODING_AGENT_DIR at a
# per-user writable dir, copies a Nix-store models.json (defining the ollama
# provider + the model list) into it on every launch, and runs pi. All listed
# models appear in pi's `/model` picker; the first one is the launch default
# unless the caller passes `--model` themselves. settings.json / trust.json /
# sessions persist in that dir; models.json is fully Nix-managed (refreshed).
#
# apiKey is a placeholder — ollama ignores it, but pi won't list models in
# `/model` until auth is configured. Cloud models (e.g. kimi-k2.7-code:cloud)
# are proxied server-side by the ollama instance, so clients need no secret.
{
  runCommand,
  writeShellScript,
  writeText,
  pi-coding-agent,
  nodejs,
  baseUrl ? "http://localhost:11434/v1",
  models ? ["kimi-k2.7-code:cloud" "glm-5.2:cloud" "glm-5.1:cloud"],
  model ? builtins.head models,
}: let
  modelsJson = writeText "ollama-pi-models.json" (builtins.toJSON {
    providers.ollama = {
      inherit baseUrl;
      api = "openai-completions";
      apiKey = "ollama";
      models = map (id: {inherit id;}) models;
    };
  });

  launcher = writeShellScript "ollama-pi-launcher" ''
    set -euo pipefail
    cfg="''${PI_CODING_AGENT_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/ollama-pi}"
    mkdir -p "$cfg"
    # models.json is fully Nix-managed, so refresh it from the store on every
    # launch. rm -f first so a stale symlink left by an older wrapper (pointing
    # at a read-only store path) is replaced rather than written through.
    # settings.json / trust.json / sessions are the user's and are left alone.
    rm -f "$cfg/models.json"
    cp ${modelsJson} "$cfg/models.json"
    export PI_CODING_AGENT_DIR="$cfg"
    # pi install/update run `npm install` for git packages, and node may not
    # be on the user's PATH (common on Nix). Put a Nix nodejs on PATH so those
    # subcommands — and runtime extensions that spawn node — actually work.
    export PATH="${nodejs}/bin:$PATH"
    # Inject the default model unless the caller already chose one, or is
    # invoking a pi subcommand. Subcommands (install/remove/uninstall/update/
    # list/config) MUST be the first argument — prepending --model makes pi
    # treat them (and their args) as an interactive prompt to the model
    # instead of running the subcommand. e.g. `ollama-pi install git:...`
    # must reach pi as `pi install git:...`, not `pi --model ... install ...`.
    case "''${1:-}" in
      install|remove|uninstall|update|list|config) ;;
      *)
        case " $* " in *" --model "*) ;; *) set -- --model "ollama/${model}" "$@";; esac
        ;;
    esac
    exec ${pi-coding-agent}/bin/pi "$@"
  '';
in
  runCommand "ollama-pi" {} ''
    mkdir -p $out/bin
    cp ${launcher} $out/bin/ollama-pi
    chmod +x $out/bin/ollama-pi
  ''
