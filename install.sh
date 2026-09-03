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
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.$STAMP"
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
  mkdir -p "$(dirname "$EXCLUDES")"
  touch "$EXCLUDES"
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
    CONFIG="$(node -e 'const s=require(process.argv[1]);process.stdout.write(JSON.stringify(s[process.argv[2]]))' "$REPO_DIR/mcp/servers.json" "$name")"
    if [[ $DRY_RUN -eq 1 ]]; then
      say "would register: $name"
    else
      claude mcp add-json --scope user "$name" "$CONFIG" >/dev/null && say "registered: $name"
    fi
  done < <(node -e 'const s=require(process.argv[1]);console.log(Object.keys(s).join("\n"))' "$REPO_DIR/mcp/servers.json")
fi

step "Done"
if [[ $DRY_RUN -eq 1 ]]; then
  say "dry run, nothing was written"
else
  say "run 'claude doctor' to see anything the CLI rejected"
  say "run '/status' inside a session to confirm the settings source loaded"
fi
