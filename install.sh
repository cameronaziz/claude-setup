#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

DRY_RUN=0
UNINSTALL=0
ONLY=""
SKIP=""
NO_MCP=0
BOOTSTRAP=1
ASSUME_YES=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --dry-run        Print what would change. Writes nothing.
  --uninstall      Remove only what this repo added. Leaves everything else.
  --only <name>    Apply a single module (model, sandbox, permissions, hooks,
                   worktree, attribution, workflow).
  --skip <a,b>     Skip named modules.
  --no-mcp         Do not touch MCP server registration.
  --no-bootstrap   Do not install anything. Fail if node is missing.
  --yes            Answer yes to install prompts. Required non-interactively.
  -h, --help       This.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --no-mcp) NO_MCP=1; shift ;;
    --no-bootstrap) BOOTSTRAP=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

say() { printf '  %s\n' "$1"; }
step() { printf '\n%s\n' "$1"; }

NODE_MIN=18

have() { command -v "$1" >/dev/null 2>&1; }

# git and claude are the only things this script assumes are already present.
have git || { echo "git is required and was not found on PATH." >&2; exit 1; }

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    echo "Refusing to install without confirmation in a non-interactive shell. Re-run with --yes." >&2
    return 1
  fi
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Homebrew, node and pnpm may all be installed but absent from this shell's PATH.
# Each adopt_* only puts an existing install on PATH. Installing is a separate,
# prompted step.
adopt_brew() {
  have brew && return 0
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew \
                   /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [[ -x "$candidate" ]]; then
      eval "$("$candidate" shellenv)"
      have brew && return 0
    fi
  done
  return 1
}

install_brew() {
  confirm "Homebrew is not installed. Install it? It will ask for your sudo password." || return 1
  have curl || { echo "curl is required to install Homebrew." >&2; return 1; }
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  adopt_brew
}

node_ok() {
  have node || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [[ "$major" =~ ^[0-9]+$ ]] && (( major >= NODE_MIN ))
}

adopt_node() {
  node_ok && return 0
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    set +u
    . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
    nvm use --lts >/dev/null 2>&1 || true
    set -u
    node_ok && return 0
  fi
  if have fnm; then
    eval "$(fnm env 2>/dev/null)" || true
    node_ok && return 0
  fi
  local d
  for d in "$HOME/.volta/bin" /opt/homebrew/bin /usr/local/bin; do
    [[ -x "$d/node" ]] && PATH="$d:$PATH"
    node_ok && return 0
  done
  return 1
}

need_brew() {
  adopt_brew && return 0
  [[ $BOOTSTRAP -eq 0 ]] && { echo "Homebrew is missing and --no-bootstrap was passed." >&2; return 1; }
  install_brew
}

step "Toolchain"

NODE_PENDING=0
if adopt_node; then
  say "node $(node -v)"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  echo "node >= $NODE_MIN was not found and --no-bootstrap was passed." >&2
  exit 1
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would install node >= $NODE_MIN via homebrew"
  NODE_PENDING=1
else
  need_brew || {
    cat >&2 <<'MSG'
Could not get Homebrew. Install node >= 18 another way, then re-run:
  https://nodejs.org/en/download
  curl -fsSL https://fnm.vercel.app/install | bash
MSG
    exit 1
  }
  say "homebrew $(brew --version | head -1 | awk '{print $2}')"
  say "installing node via homebrew"
  brew install node
  adopt_node || { echo "brew install node finished but node >= $NODE_MIN is still not on PATH." >&2; exit 1; }
  say "node $(node -v) installed"
fi

if [[ $NODE_PENDING -eq 1 ]]; then
  say "pnpm check deferred, it needs node"
elif have pnpm; then
  say "pnpm $(pnpm -v)"
elif [[ $BOOTSTRAP -eq 0 ]]; then
  say "pnpm missing, --no-bootstrap passed, leaving it alone"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would enable pnpm via corepack"
elif have corepack && corepack enable pnpm >/dev/null 2>&1 && have pnpm; then
  say "pnpm $(pnpm -v) enabled via corepack"
elif have npm; then
  npm install -g pnpm >/dev/null 2>&1 || { echo "npm install -g pnpm failed." >&2; exit 1; }
  have pnpm || { echo "pnpm installed but is not on PATH." >&2; exit 1; }
  say "pnpm $(pnpm -v) installed via npm"
else
  echo "Neither corepack nor npm is available to install pnpm." >&2
  exit 1
fi

if [[ $NODE_PENDING -eq 1 ]]; then
  step "Done"
  say "dry run stops here: the settings preview needs node, which is not installed yet"
  say "re-run without --dry-run to bootstrap the toolchain, or install node and dry-run again"
  exit 0
fi

step "Target: $CLAUDE_DIR"

mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR" "$CLAUDE_DIR/hooks"

if [[ -f "$SETTINGS" ]]; then
  if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")||"{}")' "$SETTINGS" 2>/dev/null; then
    echo "$SETTINGS is not valid JSON. Fix it by hand before running this. Nothing was changed." >&2
    exit 1
  fi
  if [[ $DRY_RUN -eq 0 ]]; then
    STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    if ! cp "$SETTINGS" "$BACKUP_DIR/settings.json.$STAMP" 2>/dev/null; then
      cat >&2 <<MSG
Could not write a backup to $BACKUP_DIR, so nothing was changed.
$SETTINGS is untouched.

The usual cause is running this from inside a Claude Code session, where the
Bash sandbox denies writes to ~/.claude. Run it from a plain terminal instead.
MSG
      exit 1
    fi
    say "backed up existing settings to backups/settings.json.$STAMP"
  fi
else
  say "no existing settings.json, starting fresh"
fi

MERGE_ARGS=(--settings "$SETTINGS" --modules "$REPO_DIR/modules" --claude-dir "$CLAUDE_DIR")
[[ -n "$ONLY" ]] && MERGE_ARGS+=(--only "$ONLY")
[[ -n "$SKIP" ]] && MERGE_ARGS+=(--skip "$SKIP")
[[ $DRY_RUN -eq 1 ]] && MERGE_ARGS+=(--dry-run)
[[ $UNINSTALL -eq 1 ]] && MERGE_ARGS+=(--uninstall)

step "Settings"
node "$REPO_DIR/lib/merge.mjs" "${MERGE_ARGS[@]}"

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
step "Git credentials"
CRED_HELPER="$(git config --global credential.helper || true)"
if [[ $UNINSTALL -eq 1 ]]; then
  say "leaving credential.helper alone"
elif [[ "$(uname -s)" != "Darwin" ]]; then
  say "not macOS, skipping osxkeychain"
elif [[ -n "$CRED_HELPER" ]]; then
  say "credential.helper already set to '$CRED_HELPER', not overwriting"
elif [[ $DRY_RUN -eq 1 ]]; then
  say "would set credential.helper to osxkeychain"
else
  git config --global credential.helper osxkeychain
  say "set credential.helper to osxkeychain"
fi

if [[ $UNINSTALL -eq 0 && "$(uname -s)" == "Darwin" ]]; then
  if printf 'protocol=https\nhost=dev.azure.com\n\n' \
     | git credential-osxkeychain get 2>/dev/null | grep -q '^password='; then
    say "dev.azure.com credential found in Keychain"
  else
    say "no dev.azure.com credential yet, first clone will prompt for a PAT:"
    say "  git clone https://dev.azure.com/precisionfilter/ERP/_git/<repo>"
  fi
fi

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

step "Plugins"
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

step "Done"
if [[ $DRY_RUN -eq 1 ]]; then
  say "dry run, nothing was written"
else
  say "run 'claude doctor' to see anything the CLI rejected"
  say "run '/status' inside a session to confirm the settings source loaded"
fi
