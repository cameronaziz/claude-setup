# claude-setup

Portable global Claude Code config. Clone it, open a session in it, say `look at README.md`, and it brings a machine up to my baseline without stomping on anything already there.

```bash
git clone git@github.com:cameronaziz/claude-setup.git
cd claude-setup
claude
> look at README.md
```

Everything is additive. The installer backs up `~/.claude/settings.json` before touching it, merges module fragments into it, and never deletes keys it did not add. MCP servers, agents, and settings from other sources survive.

The only things it assumes are already installed are `git` and `claude`. Homebrew, node and pnpm are bootstrapped if missing, and it asks before installing Homebrew.

---

## Instructions for Claude

You are running in this repo on a machine that may or may not already have Claude Code configured. Work through these steps in order. Stop and ask me before doing anything destructive.

### Step 1 — Verify before you write

My key names may be stale. Fetch these and check them:

- https://code.claude.com/docs/en/settings-reference
- https://code.claude.com/docs/en/hooks

Confirm, for the installed CLI version (`claude --version`):

- the `model` key and whether `"opus"` is an accepted value or it wants a full model string
- the `sandbox` block: `enabled`, `autoAllowBashIfSandboxed`, `allowUnsandboxedCommands`, `excludedCommands`, `network.*`, `filesystem.*`
- the `worktree` block: `baseRef`, `symlinkDirectories`, `sparsePaths`, `bgIsolation`. Note there is no key for worktree *location*, so do not go looking for one; see [Worktrees](#worktrees).
- hook event names and the stdin JSON shape for `PreToolUse` and `SessionEnd`, including whether matcher regexes are anchored

Where the docs disagree with what is in this repo, follow the docs, fix the repo file, and tell me what changed and why. Do not silently paper over a mismatch.

### Step 2 — Show me the damage first

```bash
./install.sh --dry-run
```

Show me the `changes` array. Call out anything of type `override` or `conflict` in particular, since those are the only ways this can take something away from me. If an override looks wrong, stop and ask.

### Step 3 — Install

```bash
./install.sh
```

The first step is the toolchain. If node is missing it installs it with Homebrew, installing Homebrew first if that is missing too, and prompts before doing so. If I am not at the keyboard, use `--yes`. If I want it to touch nothing, use `--no-bootstrap` and it fails instead of installing.

Then run `claude doctor` and report anything it rejected or dropped.

### Step 4 — Agents

Read `~/.claude/agents/` and tell me what is already there before creating anything. I have an existing orchestrator/worker/reviewer setup on some machines and I do not want it overwritten. The installer already refuses to overwrite, but tell me what it skipped.

Model tiering belongs in agent definitions, not `settings.json`: orchestrator on Opus with no write tools, workers on Sonnet, reviewers on Opus with a separate system prompt.

### Rules

- Do not add a global `CLAUDE.md`. Global standing instructions leak into every unrelated session and eat context.
- Do not add settings I did not ask for. If you think something is missing, tell me instead of adding it.
- Do not modify `~/.claude.json` directly. That file is Claude Code's own. MCP servers go through `claude mcp add-json`.

---

## Layout

```
install.sh                  idempotent installer, supports --dry-run and --uninstall
lib/merge.mjs               additive deep merge with a change report
modules/*.json              one config area per file, applied in filename order
hooks/*.mjs                 hook scripts, copied to ~/.claude/hooks/
mcp/servers.json            MCP servers to register if not already present
agents/*.md                 agent templates, only copied when absent
output-styles/*.md          output styles, copied to ~/.claude/output-styles/
keybindings.json            key bindings, only copied when absent
```

Modules apply in sorted order. A file starting with `_` is ignored, which is how you park one without deleting it.

## Merge semantics

| Incoming | Existing | Result |
| --- | --- | --- |
| object | object | recurse |
| array | array | union, existing order preserved, new entries appended |
| scalar | absent | set |
| scalar | different scalar | overridden, logged as `override` |
| anything | wrong type | skipped, logged as `conflict` |

Nothing is ever deleted on install. `--uninstall` removes only values this repo put there and leaves the rest of the file intact.

## Adding a module

Drop a JSON fragment in `modules/`. Prefix it with a number to control ordering.

```bash
cat > modules/50-statusline.json <<'JSON'
{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
JSON
./install.sh --only statusline --dry-run
```

`{{CLAUDE_DIR}}` in any string is replaced with the resolved `~/.claude` path, which is how the hook module points at absolute script paths without hardcoding a username.

## Adding an MCP server

Add it to `mcp/servers.json`. The installer registers it at user scope only if `claude mcp list` does not already know the name. It never removes or rewrites a server you already have.

```json
{
  "ado": { "command": "npx", "args": ["-y", "@azure-devops/mcp", "precisionfilter"] }
}
```

Run `./install.sh --no-mcp` to skip this step entirely.

## What the hooks do

**block-destructive-bash** (`PreToolUse` on Bash) exits 2 on: recursive `rm` targeting anything outside the working directory, force push without `--force-with-lease`, `git reset --hard` on a dirty tree, `git clean -fd`/`-fx`, `DROP`/`TRUNCATE` SQL, and recursive `chmod`/`chown` on `/` or `~`. It splits compound commands on `&&`, `;`, and `|` and checks each segment.

**block-secret-reads** (`PreToolUse` on Read/Edit/Write/NotebookEdit) exits 2 on `.env`, `secrets/`, `.npmrc`, `.netrc`, SSH keys, `.pem`/`.p12`/`.pfx`/`.key`, `.aws/`, and service account JSON. `.env.example` and friends pass. This duplicates the `permissions.deny` rules on purpose: deny rules can be routed around by indexing, a `PreToolUse` hook cannot.

**block-em-dashes** (`PreToolUse` on Write/Edit/NotebookEdit) exits 2 when the content being written contains an em dash or an en dash, and prints the offending lines. `file_path` is exempt, since a dash in a path is mine, not Claude's. The style rule also lives in the `slim` output style, but an output style is an instruction that drifts as context fills, and a hook does not.

**flag-god-files** (`PostToolUse` on Write/Edit) exits 2 when the file that was just written is over 300 lines, or holds a function over 50 lines. The write has already happened at that point, so this reports rather than prevents: exit 2 is what puts the message in front of Claude. Thresholds match `output-styles/slim.md`. It only looks at known source extensions.

**prune-merged-worktrees** (`SessionEnd`) removes a worktree under `.claude/worktrees/` only when the branch is fully merged into the default branch, the tree is clean, and there are no unpushed commits. Everything else is logged to `~/.claude/logs/worktree-prune.log` and left alone. It never forces and never touches the main checkout.

## Toolchain bootstrap

`install.sh` runs this before it touches any settings:

| Missing | What happens |
| --- | --- |
| node on PATH but installed elsewhere | `nvm`, `fnm`, `volta` and the Homebrew prefixes are checked and put on PATH. Nothing is installed. |
| node absent | Homebrew installs it. Minimum is node 18, which is what `lib/merge.mjs` needs. |
| Homebrew absent | Installed from the official script, after a `[y/N]` prompt. This is the one step that asks for sudo. |
| pnpm absent | `corepack enable pnpm`, falling back to `npm install -g pnpm`. |

`--dry-run` never installs anything. If node is missing it reports what it would install and stops, because the settings preview itself needs node to run.

`--no-bootstrap` installs nothing and exits non-zero if node is missing. `--yes` answers the Homebrew prompt, and is required when stdin is not a TTY.

## Commit attribution

`modules/50-attribution.json` turns off Claude Code's git attribution, so commits are authored by me and nothing else:

```json
{ "attribution": { "commit": "", "pr": "", "sessionUrl": false } }
```

`commit: ""` drops the `Co-Authored-By` trailer, `pr: ""` drops the `Generated with Claude Code` line from pull request descriptions, and `sessionUrl: false` drops the `Claude-Session` trailer that cloud and Remote Control sessions add.

This replaces `includeCoAuthoredBy`, which is deprecated as of v2.0.62. Do not set both: once `attribution.commit` or `attribution.pr` is set, `includeCoAuthoredBy` is ignored.

This only controls what Claude Code appends on its own. Set `user.name` and `user.email` yourself, per repo or globally, or git will guess from the hostname.

## Worktrees

**Worktree location is not configurable, and it is already inside the repo.** Claude Code always creates worktrees at `.claude/worktrees/` and there is no setting that moves them. The `worktree` block is real but its only sub-keys are `baseRef`, `symlinkDirectories`, `sparsePaths`, and `bgIsolation`. The earlier `_30-worktrees.json.template` placeholder was chasing a `worktrees.path` key that does not exist; it has been deleted and replaced by `modules/30-worktree.json`.

`install.sh` adds `**/.claude/worktrees/` to the global git excludes, so worktrees are ignored by default in every repo without touching any project's `.gitignore`.

`symlinkDirectories: ["node_modules"]` symlinks the dependency tree into each new worktree instead of duplicating it, which is the difference between a worktree being instant and being a fresh `pnpm install`.

## Prompt and editor

`keybindings.json` binds `Shift+Enter` to `chat:newline` for multi-line prompts, keeping the default `Ctrl+J` as well. `Shift+Enter` is native in iTerm2, WezTerm, Ghostty, Kitty, Warp, Apple Terminal, and Windows Terminal; `Ctrl+J` works in any terminal with no terminal-side setup, and `\` + `Enter` always works. The installer will not overwrite an existing `~/.claude/keybindings.json`.

## Output style

`output-styles/slim.md` is a custom style, selected by `outputStyle: "slim"` in `modules/60-workflow.json`. It sets `keep-coding-instructions: true`, so it layers on top of the normal engineering behavior rather than replacing it. It covers three things: lead with the result and skip preamble, never use em or en dashes, and split files and functions before they become god objects.

It replaces the built-in **Concise** style rather than sitting alongside it, because output styles do not stack: a session has exactly one. `slim` includes the concision rules, so nothing is lost. To go back to the built-in, set `"outputStyle": "Concise"`.

**An output style does not reach subagents.** Subagents run their own system prompt, so a style shapes the main thread only, and a fork is the sole exception. A global `CLAUDE.md` is the one channel that would reach both, and this repo deliberately does not add one. That is why the em dash and god file rules are also enforced as hooks: a hook fires for every agent, on every write, no matter whose context it is running in. If you add agent templates under `agents/`, repeat the rules in the body of each one.

## Known issues

- **The sandbox is ignored in the VS Code extension.** `sandbox.enabled` is silently dropped there and `/sandbox` does not exist as a command. Same config works from the terminal. If you live in the extension, this repo will not reduce your permission prompts.
- **`model` is read once at session start.** Editing it mid-session does nothing. Use `/model`, and know that switching models re-reads the whole conversation uncached because each model has its own prompt cache.
- **Allow rules wait for workspace trust** in a committed project file. This repo only writes user-scope settings, so that does not apply here, but it will bite you if you copy `modules/20-permissions.json` into a repo.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the settings keys and hook files this repo installed. Leaves MCP servers, agents, git excludes, and anything else you or another tool added. Backups live in `~/.claude/backups/`.
