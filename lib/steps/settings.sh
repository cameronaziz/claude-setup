step_settings() {
step "Settings"
node "$REPO_DIR/lib/merge.mjs" "${MERGE_ARGS[@]}"
}
