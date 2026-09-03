step_keybindings() {
step "Keybindings"
KEYBINDS="$CLAUDE_DIR/keybindings.json"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving keybindings alone"
elif [[ ! -f "$REPO_DIR/keybindings.json" ]]; then
  say "no keybindings.json in repo"
elif [[ -f "$KEYBINDS" ]]; then
  say "kept existing keybindings.json, not overwriting"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would create keybindings.json"
else
  cp "$REPO_DIR/keybindings.json" "$KEYBINDS"
  say "created keybindings.json"
fi
}
