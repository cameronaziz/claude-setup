#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
import { join, sep } from "node:path";
import { homedir } from "node:os";

const LOG_DIR = join(homedir(), ".claude", "logs");
const LOG_FILE = join(LOG_DIR, "worktree-prune.log");

const log = (message) => {
  try {
    mkdirSync(LOG_DIR, { recursive: true });
    appendFileSync(LOG_FILE, `${new Date().toISOString()} ${message}\n`);
  } catch {}
};

const git = (args, cwd) =>
  execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
};

const parseWorktrees = (raw) => {
  const entries = [];
  let current = {};
  for (const line of raw.split("\n")) {
    if (line.startsWith("worktree ")) {
      if (current.path) entries.push(current);
      current = { path: line.slice(9) };
    } else if (line.startsWith("branch ")) {
      current.branch = line.slice(7).replace("refs/heads/", "");
    } else if (line === "bare" || line === "detached") {
      current.skip = true;
    }
  }
  if (current.path) entries.push(current);
  return entries;
};

const defaultBranch = (cwd) => {
  for (const attempt of [
    () => git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd).replace("origin/", ""),
    () => (git(["rev-parse", "--verify", "main"], cwd) ? "main" : null),
    () => (git(["rev-parse", "--verify", "master"], cwd) ? "master" : null),
  ]) {
    try {
      const value = attempt();
      if (value) return value;
    } catch {}
  }
  return null;
};

const main = async () => {
  await readStdin().catch(() => "");

  let root;
  try {
    root = git(["rev-parse", "--show-toplevel"], process.cwd());
  } catch {
    process.exit(0);
  }

  const base = defaultBranch(root);
  if (!base) {
    log(`skip ${root}: could not determine default branch`);
    process.exit(0);
  }

  let entries;
  try {
    entries = parseWorktrees(git(["worktree", "list", "--porcelain"], root));
  } catch {
    process.exit(0);
  }

  for (const entry of entries) {
    if (entry.skip || !entry.branch) continue;
    if (entry.path === root) continue;
    if (!entry.path.includes(`${sep}.worktrees${sep}`)) {
      log(`skip ${entry.path}: not under .worktrees/`);
      continue;
    }

    try {
      if (git(["status", "--porcelain"], entry.path)) {
        log(`keep ${entry.path}: uncommitted changes`);
        continue;
      }

      const merged = git(["branch", "--merged", base, "--format=%(refname:short)"], root)
        .split("\n")
        .map((b) => b.trim())
        .filter(Boolean);
      if (!merged.includes(entry.branch)) {
        log(`keep ${entry.path}: branch ${entry.branch} not merged into ${base}`);
        continue;
      }

      let unpushed = "";
      try {
        unpushed = git(["log", "--oneline", `@{upstream}..HEAD`], entry.path);
      } catch {
        unpushed = git(["log", "--oneline", `${base}..HEAD`], entry.path);
      }
      if (unpushed) {
        log(`keep ${entry.path}: unpushed commits`);
        continue;
      }

      git(["worktree", "remove", entry.path], root);
      log(`removed ${entry.path} (branch ${entry.branch} merged into ${base})`);
    } catch (err) {
      log(`keep ${entry.path}: error while checking (${err.message.split("\n")[0]})`);
    }
  }

  process.exit(0);
};

main();
