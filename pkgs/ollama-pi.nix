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
    # launch — a plain copy beats a symlink (no stale-link drift when the
    # model list / endpoint changes). settings.json / trust.json / sessions
    # are the user's and are left untouched.
    cp ${modelsJson} "$cfg/models.json"
    export PI_CODING_AGENT_DIR="$cfg"
    # Inject the default model unless the caller already chose one.
    case " $* " in *" --model "*) ;; *) set -- --model "ollama/${model}" "$@";; esac
    exec ${pi-coding-agent}/bin/pi "$@"
  '';
in
  runCommand "ollama-pi" {} ''
    mkdir -p $out/bin
    cp ${launcher} $out/bin/ollama-pi
    chmod +x $out/bin/ollama-pi
  ''