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

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --dry-run        Print what would change. Writes nothing.
  --uninstall      Remove only what this repo added. Leaves everything else.
  --only <name>    Apply a single module (model, sandbox, permissions, hooks, worktrees).
  --skip <a,b>     Skip named modules.
  --no-mcp         Do not touch MCP server registration.
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
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

say() { printf '  %s\n' "$1"; }
step() { printf '\n%s\n' "$1"; }

command -v node >/dev/null 2>&1 || { echo "node is required and was not found on PATH." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required and was not found on PATH." >&2; exit 1; }

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
  for pattern in ".worktrees/" "**/.claude/settings.local.json"; do
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
