# claude-setup

Portable global Claude Code config. Clone it, open a session in it, say `look at README.md`, and it brings a machine up to my baseline without stomping on anything already there.

```bash
git clone git@github.com:cameronaziz/claude-setup.git
cd claude-setup
claude
> look at README.md
```

Everything is additive. The installer backs up `~/.claude/settings.json` before touching it, merges module fragments into it, and never deletes keys it did not add. MCP servers, agents, and settings from other sources survive.

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
- the **git worktree configuration key**, which I have not verified. `modules/_30-worktrees.json.template` is a disabled placeholder. Find the real key, fill it in so worktrees land in `.worktrees/` inside the repo, and rename the file to `30-worktrees.json` so the installer picks it up.
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

**prune-merged-worktrees** (`SessionEnd`) removes a worktree under `.worktrees/` only when the branch is fully merged into the default branch, the tree is clean, and there are no unpushed commits. Everything else is logged to `~/.claude/logs/worktree-prune.log` and left alone. It never forces and never touches the main checkout.

## Known issues

- **The sandbox is ignored in the VS Code extension.** `sandbox.enabled` is silently dropped there and `/sandbox` does not exist as a command. Same config works from the terminal. If you live in the extension, this repo will not reduce your permission prompts.
- **`model` is read once at session start.** Editing it mid-session does nothing. Use `/model`, and know that switching models re-reads the whole conversation uncached because each model has its own prompt cache.
- **Allow rules wait for workspace trust** in a committed project file. This repo only writes user-scope settings, so that does not apply here, but it will bite you if you copy `modules/20-permissions.json` into a repo.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the settings keys and hook files this repo installed. Leaves MCP servers, agents, git excludes, and anything else you or another tool added. Backups live in `~/.claude/backups/`.
