step_styles() {
step "Output styles"
mkdir -p "$CLAUDE_DIR/output-styles"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving output styles alone"
elif compgen -G "$REPO_DIR/output-styles/*.md" >/dev/null; then
  for f in "$REPO_DIR"/output-styles/*.md; do
    target="$CLAUDE_DIR/output-styles/$(basename "$f")"
    if [[ -f "$target" ]] && cmp -s "$f" "$target"; then
      say "unchanged $(basename "$f")"
    elif [[ $DRY_RUN -eq 1 ]]; then
      say "would install $(basename "$f")"
    else
      cp "$f" "$target"
      say "installed $(basename "$f")"
    fi
  done
else
  say "no output styles in repo"
fi

# TERM and TERM_PROGRAM are lost through tmux, ssh and Claude Code's own shell,
# so an installed app bundle or an existing config counts as present too.
ghostty_present() {
  [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]] && return 0
  [[ "${TERM_PROGRAM:-}" == "ghostty" ]] && return 0
  [[ "${TERM:-}" == "xterm-ghostty" ]] && return 0
  have ghostty && return 0
  [[ -d /Applications/Ghostty.app ]] && return 0
  [[ -d "$HOME/Applications/Ghostty.app" ]] && return 0
  [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty" ]] && return 0
  return 1
}
}
