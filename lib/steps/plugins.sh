# Each line is "<checkout>|<plugin>@<marketplace>|<url>|<fallback url>". The
# checkout is relative to this repo, so a machine that keeps its repositories
# somewhere other than ~/engineering still resolves it. A plugin brings its own
# MCP servers, so nothing here belongs in mcp/servers.json too.
PLUGINS=(
"../armada-officer|officer@armada|git@ssh.dev.azure.com:v3/precisionfilter/Armada/armada-officer|https://precisionfilter@dev.azure.com/precisionfilter/Armada/_git/armada-officer"
)

# SSH first, since that is what these checkouts use, then HTTPS for a machine
# with a PAT in the keychain but no key loaded.
clone_plugin() {
local dir="$1" url
confirm "Clone $2 into $dir?" || { say "skipped, not cloning $dir"; return 1; }
for url in "$2" "$3"; do
  [[ -z "$url" ]] && continue
  if git clone --quiet "$url" "$dir" 2>/dev/null; then
    say "cloned into $dir"
    return 0
  fi
done
say "could not clone $dir from either $2 or $3"
return 1
}

# A checkout that is behind installs a stale plugin. Only ever fast forward, and
# only from a clean tree on the default branch, so local work is never at risk.
update_plugin() {
local dir="$1" branch
[[ -d "$dir/.git" ]] || return 0
if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
  say "$dir has uncommitted changes, leaving it where it is"
  return 0
fi
branch="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  say "$dir is on '$branch', not main, leaving it where it is"
  return 0
fi
git -C "$dir" fetch --quiet origin main 2>/dev/null || { say "could not reach origin for $dir"; return 0; }
if git -C "$dir" merge --ff-only --quiet FETCH_HEAD 2>/dev/null; then
  say "main is current in $dir"
else
  say "$dir has diverged from origin/main, fix it by hand"
fi
}

# dist/ and node_modules/ are gitignored, so a fresh clone has no built server
# for the plugin's MCP command to point at.
build_plugin() {
local dir="$1"
[[ -f "$dir/package.json" ]] || return 0
[[ -f "$dir/dist/index.js" ]] && return 0
have pnpm || { say "pnpm is missing, cannot build $dir"; return 1; }
if (cd "$dir" && pnpm install --silent >/dev/null 2>&1 && pnpm build >/dev/null 2>&1); then
  say "built $dir"
  return 0
fi
say "build failed in $dir, run 'pnpm install && pnpm build' there to see why"
return 1
}

install_plugin() {
local dir="$1" id="$2"
claude plugin marketplace add "$dir" >/dev/null 2>&1 || true
if claude plugin install --yes --scope user "$id" >/dev/null 2>&1; then
  say "installed: $id"
else
  say "could not install $id, run 'claude plugin install $id' to see why"
fi
}

step_plugins() {
step "Plugins"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving plugins alone, uninstall never removes them"
elif ! have claude; then
  say "claude CLI not on PATH, skipping plugins"
else
  INSTALLED="$(claude plugin list 2>/dev/null || true)"
  for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r rel_dir plugin_id clone_url clone_alt <<<"$entry"
    # Resolve through the parent so the path reads plainly, with no ".." in it.
    source_dir="$(cd "$REPO_DIR/$(dirname "$rel_dir")" && pwd)/$(basename "$rel_dir")"
    if [[ $DRY_RUN -eq 1 ]]; then
      [[ -d "$source_dir" ]] && update_plugin "$source_dir" \
        || say "would ask to clone $clone_url into $source_dir"
      [[ -f "$source_dir/dist/index.js" ]] || say "would build $source_dir"
      grep -q "^\s*❯\? \?${plugin_id%%@*}@" <<<"$INSTALLED" \
        && say "already installed: $plugin_id" || say "would install: $plugin_id"
      continue
    fi
    [[ -d "$source_dir" ]] || clone_plugin "$source_dir" "$clone_url" "$clone_alt" || continue
    update_plugin "$source_dir"
    build_plugin "$source_dir" || continue
    if grep -q "^\s*❯\? \?${plugin_id%%@*}@" <<<"$INSTALLED"; then
      say "already installed: $plugin_id"
      continue
    fi
    install_plugin "$source_dir" "$plugin_id"
  done
fi
}
