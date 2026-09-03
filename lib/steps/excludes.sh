step_excludes() {
step "Git excludes"
EXCLUDES="$(git config --global core.excludesFile || true)"
case "$EXCLUDES" in
  "~/"*) EXCLUDES="$HOME/${EXCLUDES#\~/}" ;;
  /*) ;;
  *) EXCLUDES="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore" ;;
esac
if [[ $UNINSTALL -eq 0 ]]; then
  # A dry run must not create the excludes file it is only reporting on.
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$(dirname "$EXCLUDES")"
    touch "$EXCLUDES"
  fi
  for pattern in "**/.claude/worktrees/" "**/.claude/settings.local.json"; do
    if grep -qxF "$pattern" "$EXCLUDES" 2>/dev/null; then
      say "already excluded: $pattern"
    elif [[ $DRY_RUN -eq 1 ]]; then
      say "would add to $EXCLUDES: $pattern"
    else
      printf '%s\n' "$pattern" >> "$EXCLUDES"
      say "added to $EXCLUDES: $pattern"
    fi
  done
else
  say "leaving git excludes alone"
fi

# git is in sandbox.excludedCommands, so it can reach the Keychain. That is the
# only credential store the sandbox does not deny reading.
}
