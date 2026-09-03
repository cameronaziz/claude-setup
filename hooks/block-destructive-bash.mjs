#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { resolve, relative, isAbsolute } from "node:path";
import { homedir } from "node:os";

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
};

const block = (reason) => {
  process.stderr.write(`${reason}\n`);
  process.exit(2);
};

const allow = () => process.exit(0);

const segments = (command) =>
  command
    .split(/(?:&&|\|\||;|\n|\|)/g)
    .map((s) => s.trim())
    .filter(Boolean);

const tokenize = (segment) => segment.split(/\s+/).filter(Boolean);

const escapesCwd = (target, cwd) => {
  const cleaned = target.replace(/^["']|["']$/g, "");
  if (cleaned === "/" || cleaned === "~" || cleaned === "~/" || cleaned === "." || cleaned === "..") return true;
  if (cleaned === "*" || cleaned === "./*" || cleaned === "$HOME") return true;
  const expanded = cleaned.startsWith("~") ? cleaned.replace("~", homedir()) : cleaned;
  const absolute = isAbsolute(expanded) ? expanded : resolve(cwd, expanded);
  if (absolute === homedir() || absolute === "/") return true;
  const rel = relative(cwd, absolute);
  return rel.startsWith("..") || isAbsolute(rel);
};

const gitIsDirty = (cwd) => {
  try {
    const out = execFileSync("git", ["status", "--porcelain"], { cwd, encoding: "utf8" });
    return out.trim().length > 0;
  } catch {
    return false;
  }
};

const checks = [
  (tokens, raw, cwd) => {
    if (tokens[0] !== "rm") return null;
    const flags = tokens.filter((t) => t.startsWith("-")).join("");
    if (!/r/.test(flags)) return null;
    const targets = tokens.slice(1).filter((t) => !t.startsWith("-"));
    if (targets.length === 0) return null;
    const offending = targets.filter((t) => escapesCwd(t, cwd));
    if (offending.length === 0) return null;
    return `Blocked: recursive rm targeting ${offending.join(", ")}, which is outside the working directory. Delete inside the repo, or ask me to run it myself.`;
  },
  (tokens, raw) => {
    if (tokens[0] !== "git" || tokens[1] !== "push") return null;
    if (raw.includes("--force-with-lease")) return null;
    if (!tokens.includes("--force") && !tokens.includes("-f")) return null;
    return "Blocked: force push. Use --force-with-lease so you cannot clobber commits you have not seen.";
  },
  (tokens, raw, cwd) => {
    if (tokens[0] !== "git" || tokens[1] !== "reset") return null;
    if (!tokens.includes("--hard")) return null;
    if (!gitIsDirty(cwd)) return null;
    return "Blocked: git reset --hard on a dirty tree. Uncommitted work would be destroyed. Stash or commit first.";
  },
  (tokens) => {
    if (tokens[0] !== "git" || tokens[1] !== "clean") return null;
    const flags = tokens.filter((t) => t.startsWith("-")).join("");
    if (!/f/.test(flags) || !/[dx]/.test(flags)) return null;
    return "Blocked: git clean with -fd or -fx removes untracked and ignored files. Run it yourself if you mean it.";
  },
  (tokens, raw) => {
    if (!/^(drop|truncate)$/i.test(tokens[0] || "") && !/\b(drop\s+(database|table|schema)|truncate\s+table)\b/i.test(raw)) return null;
    return "Blocked: destructive SQL (DROP or TRUNCATE). Run schema changes through a migration.";
  },
  (tokens) => {
    if (tokens[0] !== "chmod" && tokens[0] !== "chown") return null;
    const flags = tokens.filter((t) => t.startsWith("-")).join("");
    if (!/R/.test(flags)) return null;
    const targets = tokens.slice(1).filter((t) => !t.startsWith("-"));
    if (!targets.some((t) => t === "/" || t === "~" || t === homedir())) return null;
    return `Blocked: recursive ${tokens[0]} on a root or home path.`;
  },
];

const main = async () => {
  let payload;
  try {
    payload = JSON.parse(await readStdin());
  } catch {
    allow();
  }

  const command = payload?.tool_input?.command;
  if (typeof command !== "string" || !command.trim()) allow();
  const cwd = payload?.cwd || process.cwd();

  for (const segment of segments(command)) {
    const tokens = tokenize(segment);
    for (const check of checks) {
      const reason = check(tokens, segment, cwd);
      if (reason) block(reason);
    }
  }

  allow();
};

main();
