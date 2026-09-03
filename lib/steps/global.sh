step_global() {
step "Global config"
GLOBAL_JSON="$HOME/.claude.json"
GLOBAL_FRAGMENT="$REPO_DIR/global-config.json"
# Some keys, defaultToAgentsView among them, are read from ~/.claude.json rather
# than settings.json. Only absent keys are written, and never on a dry run.
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving $GLOBAL_JSON alone"
elif [[ ! -f "$GLOBAL_FRAGMENT" ]]; then
  say "no global-config.json in repo"
else
  node "$REPO_DIR/lib/global-config.mjs" "$GLOBAL_JSON" "$GLOBAL_FRAGMENT" "$DRY_RUN" "$BACKUP_DIR" \
    | while IFS= read -r l; do say "$l"; done
fi
}
