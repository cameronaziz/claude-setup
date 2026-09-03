step_hooks() {
step "Hooks"
if [[ $UNINSTALL -eq 1 ]]; then
  for f in "$REPO_DIR"/hooks/*.mjs; do
    target="$CLAUDE_DIR/hooks/$(basename "$f")"
    if [[ -f "$target" ]]; then
      [[ $DRY_RUN -eq 1 ]] && say "would remove $target" || { rm "$target"; say "removed $(basename "$f")"; }
    fi
  done
else
  for f in "$REPO_DIR"/hooks/*.mjs; do
    target="$CLAUDE_DIR/hooks/$(basename "$f")"
    if [[ -f "$target" ]] && cmp -s "$f" "$target"; then
      say "unchanged $(basename "$f")"
      continue
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      say "would install $(basename "$f")"
    else
      install -m 755 "$f" "$target"
      say "installed $(basename "$f")"
    fi
  done
fi
}
