# claude-zai: claude-code wrapper that points at z.ai's Anthropic-compatible
# endpoint and reads ANTHROPIC_AUTH_TOKEN from an agenix secret at exec-time.
{
  runCommand,
  makeWrapper,
  claude-code,
  keyFile ? "/run/agenix/zai-api-key",
}:
runCommand "claude-zai" {
  nativeBuildInputs = [makeWrapper];
} ''
  mkdir -p $out/bin
  makeWrapper ${claude-code}/bin/claude $out/bin/claude-zai \
    --set ANTHROPIC_BASE_URL "https://api.z.ai/api/anthropic" \
    --set API_TIMEOUT_MS "3000000" \
    --run 'export ANTHROPIC_AUTH_TOKEN="$(cat ${keyFile})"'
''
