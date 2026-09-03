step_terminal() {
step "Terminal"
GHOSTTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
FRAGMENT="$REPO_DIR/terminal/ghostty.conf"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving terminal config alone"
elif [[ ! -f "$FRAGMENT" ]]; then
  say "no terminal/ghostty.conf in repo"
elif ! ghostty_present; then
  say "ghostty not detected, skipping"
elif [[ -f "$GHOSTTY_CONF" ]] && grep -q "shift+enter" "$GHOSTTY_CONF" 2>/dev/null; then
  say "kept existing shift+enter binding in $GHOSTTY_CONF"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would add shift+enter binding to $GHOSTTY_CONF"
else
  mkdir -p "$(dirname "$GHOSTTY_CONF")"
  cat "$FRAGMENT" >> "$GHOSTTY_CONF"
  say "added shift+enter binding to $GHOSTTY_CONF"
  say "restart ghostty for it to take effect"
fi
}
