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
ONLY_STEPS=""
WITHOUT=""
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
  --steps <a,b>    Run only these steps.
  --without <a,b>  Run everything except these steps.
  --no-mcp         Alias for --without mcp.
  --no-bootstrap   Do not install anything. Fail if node is missing.
  --yes            Answer yes to install prompts. Required non-interactively.
  -h, --help       This.

Steps: toolchain, az, jj, settings, hooks, excludes, credentials, agents,
keybindings, styles, terminal, global, mcp, plugins.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --steps) ONLY_STEPS="$2"; shift 2 ;;
    --without) WITHOUT="$2"; shift 2 ;;
    --no-mcp) WITHOUT="${WITHOUT:+$WITHOUT,}mcp"; shift ;;
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


STEPS=(toolchain az jj settings hooks excludes credentials agents keybindings styles terminal global mcp plugins)

for _s in "${STEPS[@]}"; do
  # shellcheck source=/dev/null
  . "$REPO_DIR/lib/steps/$_s.sh"
done

# Every step is opt out with --without, or opt in with --steps. Unknown names are
# an error rather than a silent no-op, since a typo would quietly skip the work.
known_step() {
  local s
  for s in "${STEPS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

for _s in ${WITHOUT//,/ } ${ONLY_STEPS//,/ }; do
  known_step "$_s" || { echo "Unknown step: $_s. Known: ${STEPS[*]}" >&2; exit 1; }
done

want() {
  [[ ",$WITHOUT," == *",$1,"* ]] && return 1
  [[ -z "$ONLY_STEPS" ]] && return 0
  [[ ",$ONLY_STEPS," == *",$1,"* ]]
}

run_step() {
  want "$1" || return 0
  "step_$1"
}

for _s in toolchain az jj; do run_step "$_s"; done
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


for _s in settings hooks excludes credentials agents keybindings styles terminal global mcp plugins; do
  run_step "$_s"
done
step "Done"
if [[ $DRY_RUN -eq 1 ]]; then
  say "dry run, nothing was written"
else
  say "run 'claude doctor' to see anything the CLI rejected"
  say "run '/status' inside a session to confirm the settings source loaded"
fi
