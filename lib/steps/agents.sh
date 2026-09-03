step_agents() {
step "Agents"
mkdir -p "$CLAUDE_DIR/agents"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving agents alone, uninstall never deletes agent definitions"
elif compgen -G "$REPO_DIR/agents/*.md" >/dev/null; then
  for f in "$REPO_DIR"/agents/*.md; do
    target="$CLAUDE_DIR/agents/$(basename "$f")"
    if [[ -f "$target" ]]; then
      say "kept existing $(basename "$f"), not overwriting"
    elif [[ $DRY_RUN -eq 1 ]]; then
      say "would create $(basename "$f")"
    else
      cp "$f" "$target"
      say "created $(basename "$f")"
    fi
  done
else
  say "no agent templates in repo"
fi
}
