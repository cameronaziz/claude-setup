step_mcp() {
step "MCP servers"
if [[ $NO_MCP -eq 1 || $UNINSTALL -eq 1 ]]; then
  say "skipped, existing servers untouched"
elif ! command -v claude >/dev/null 2>&1; then
  say "claude CLI not on PATH, skipping MCP registration"
elif [[ ! -f "$REPO_DIR/mcp/servers.json" ]]; then
  say "no mcp/servers.json"
else
  EXISTING="$(claude mcp list 2>/dev/null || true)"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if grep -q "^${name}\b" <<<"$EXISTING"; then
      say "already registered: $name"
      continue
    fi
    CONFIG="$(node -e 'const s=require(process.argv[1]);const j=JSON.stringify(s[process.argv[2]]);process.stdout.write(j.split("{{HOME}}").join(process.argv[3]).split("{{CLAUDE_DIR}}").join(process.argv[4]))' "$REPO_DIR/mcp/servers.json" "$name" "$HOME" "$CLAUDE_DIR")"
    if [[ $DRY_RUN -eq 1 ]]; then
      say "would register: $name"
    else
      claude mcp add-json --scope user "$name" "$CONFIG" >/dev/null && say "registered: $name"
    fi
  done < <(node -e 'const s=require(process.argv[1]);console.log(Object.keys(s).join("\n"))' "$REPO_DIR/mcp/servers.json")
fi
}
