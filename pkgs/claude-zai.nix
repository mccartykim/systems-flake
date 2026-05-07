# claude-zai: claude-code wrapper that points at z.ai's Anthropic-compatible
# endpoint, reads ANTHROPIC_AUTH_TOKEN from an agenix secret at exec-time, and
# pre-wires z.ai's three MCP servers (vision, web search, web reader) so the
# wrapper supports the "full" claude experience (multimodal + web tools).
#
# MCP config is generated at runtime: the agenix-decrypted token is jq'd into
# a tmpfs-backed (XDG_RUNTIME_DIR) tempfile mode 600 and passed via
# `claude --mcp-config <file>`. We do NOT pass --strict-mcp-config, so the
# user's regular ~/.claude.json MCP servers continue to merge in.
#
# z.ai MCP docs:
#   https://docs.z.ai/devpack/mcp/vision-mcp-server
#   https://docs.z.ai/devpack/mcp/search-mcp-server
#   https://docs.z.ai/devpack/mcp/reader-mcp-server
{
  runCommand,
  writeText,
  writeShellScript,
  makeWrapper,
  claude-code,
  nodejs,
  jq,
  coreutils,
  keyFile ? "/run/agenix/zai-api-key",
}: let
  mcpTemplate = writeText "claude-zai-mcp.template.json" (builtins.toJSON {
    mcpServers = {
      zai-vision = {
        type = "stdio";
        command = "${nodejs}/bin/npx";
        args = ["-y" "@z_ai/mcp-server"];
        env = {
          Z_AI_API_KEY = "__ZAI_KEY__";
          Z_AI_MODE = "ZAI";
        };
      };
      zai-web-search = {
        type = "http";
        url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
        headers.Authorization = "Bearer __ZAI_KEY__";
      };
      zai-web-reader = {
        type = "http";
        url = "https://api.z.ai/api/mcp/web_reader/mcp";
        headers.Authorization = "Bearer __ZAI_KEY__";
      };
    };
  });

  launcher = writeShellScript "claude-zai-launcher" ''
    set -euo pipefail

    if [[ ! -r "${keyFile}" ]]; then
      echo "claude-zai: cannot read ${keyFile}" >&2
      exit 1
    fi

    key="$(${coreutils}/bin/cat "${keyFile}")"
    if [[ -z "$key" ]]; then
      echo "claude-zai: ${keyFile} is empty" >&2
      exit 1
    fi

    runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
    cfg="$(${coreutils}/bin/mktemp "$runtime_dir/claude-zai-mcp.XXXXXX.json")"
    ${coreutils}/bin/chmod 600 "$cfg"
    trap '${coreutils}/bin/rm -f "$cfg"' EXIT

    # Substitute the key into the template via jq so we never shell-escape
    # secrets through sed.
    ${jq}/bin/jq --arg k "$key" '
      .mcpServers."zai-vision".env.Z_AI_API_KEY = $k
      | .mcpServers."zai-web-search".headers.Authorization = "Bearer " + $k
      | .mcpServers."zai-web-reader".headers.Authorization = "Bearer " + $k
    ' "${mcpTemplate}" > "$cfg"

    export ANTHROPIC_AUTH_TOKEN="$key"
    exec ${claude-code}/bin/claude --mcp-config "$cfg" "$@"
  '';
in
  runCommand "claude-zai" {
    nativeBuildInputs = [makeWrapper];
  } ''
    mkdir -p $out/bin
    makeWrapper ${launcher} $out/bin/claude-zai \
      --set ANTHROPIC_BASE_URL "https://api.z.ai/api/anthropic" \
      --set API_TIMEOUT_MS "3000000" \
      --set ANTHROPIC_DEFAULT_HAIKU_MODEL "glm-4.5-air" \
      --set ANTHROPIC_DEFAULT_SONNET_MODEL "glm-5-turbo" \
      --set ANTHROPIC_DEFAULT_OPUS_MODEL "glm-5.1" \
      --prefix PATH : ${nodejs}/bin
  ''
