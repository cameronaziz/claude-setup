#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { join, basename } from "node:path";
import { homedir } from "node:os";

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};
const has = (name) => args.includes(name);

const settingsPath = flag("--settings", join(homedir(), ".claude", "settings.json"));
const modulesDir = flag("--modules", "modules");
const manifestPath = flag("--manifest", join(homedir(), ".claude", ".claude-setup.json"));
const claudeDir = flag("--claude-dir", join(homedir(), ".claude"));
const only = flag("--only");
const skip = (flag("--skip") || "").split(",").filter(Boolean);
const dryRun = has("--dry-run");
const uninstall = has("--uninstall");

const substitute = (value) => {
  if (typeof value === "string") return value.replaceAll("{{CLAUDE_DIR}}", claudeDir);
  if (Array.isArray(value)) return value.map(substitute);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, substitute(v)]));
  }
  return value;
};

const isPlainObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

const sameEntry = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const changes = [];

const merge = (target, source, path = []) => {
  for (const [key, incoming] of Object.entries(source)) {
    const here = [...path, key];
    const label = here.join(".");
    const current = target[key];

    if (isPlainObject(incoming)) {
      if (current !== undefined && !isPlainObject(current)) {
        changes.push({ type: "conflict", key: label, from: current, to: incoming });
        continue;
      }
      target[key] = merge(isPlainObject(current) ? current : {}, incoming, here);
      continue;
    }

    if (Array.isArray(incoming)) {
      const base = Array.isArray(current) ? [...current] : [];
      const added = [];
      for (const entry of incoming) {
        if (!base.some((existing) => sameEntry(existing, entry))) {
          base.push(entry);
          added.push(entry);
        }
      }
      if (added.length) changes.push({ type: "append", key: label, added });
      target[key] = base;
      continue;
    }

    if (current === undefined) {
      changes.push({ type: "set", key: label, to: incoming });
      target[key] = incoming;
    } else if (current !== incoming) {
      changes.push({ type: "override", key: label, from: current, to: incoming });
      target[key] = incoming;
    }
  }
  return target;
};

const removeApplied = (target, source, path = []) => {
  for (const [key, incoming] of Object.entries(source)) {
    const here = [...path, key];
    const label = here.join(".");
    const current = target[key];
    if (current === undefined) continue;

    if (isPlainObject(incoming) && isPlainObject(current)) {
      removeApplied(current, incoming, here);
      if (Object.keys(current).length === 0) {
        delete target[key];
        changes.push({ type: "remove", key: label });
      }
      continue;
    }

    if (Array.isArray(incoming) && Array.isArray(current)) {
      const kept = current.filter((entry) => !incoming.some((e) => sameEntry(e, entry)));
      if (kept.length !== current.length) changes.push({ type: "prune", key: label });
      if (kept.length) target[key] = kept;
      else delete target[key];
      continue;
    }

    if (sameEntry(current, incoming)) {
      delete target[key];
      changes.push({ type: "remove", key: label });
    }
  }
  return target;
};

const loadModules = () => {
  const files = readdirSync(modulesDir)
    .filter((f) => f.endsWith(".json") && !f.startsWith("_"))
    .sort();
  const selected = files.filter((f) => {
    const name = basename(f, ".json");
    if (only && name !== only && !name.endsWith(`-${only}`)) return false;
    if (skip.some((s) => name === s || name.endsWith(`-${s}`))) return false;
    return true;
  });
  return selected.map((f) => ({
    name: basename(f, ".json"),
    body: substitute(JSON.parse(readFileSync(join(modulesDir, f), "utf8"))),
  }));
};

let settings = {};
if (existsSync(settingsPath)) {
  const raw = readFileSync(settingsPath, "utf8").trim();
  if (raw) {
    try {
      settings = JSON.parse(raw);
    } catch (err) {
      console.error(`Refusing to touch ${settingsPath}: it is not valid JSON.`);
      console.error(`Fix it by hand first. Parser said: ${err.message}`);
      process.exit(1);
    }
  }
}

const modules = loadModules();
for (const mod of modules) {
  if (uninstall) removeApplied(settings, mod.body);
  else merge(settings, mod.body);
}

const report = {
  settingsPath,
  modules: modules.map((m) => m.name),
  changes,
};

if (dryRun) {
  console.log(JSON.stringify({ ...report, result: settings }, null, 2));
  process.exit(0);
}

writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`);

const manifest = existsSync(manifestPath)
  ? JSON.parse(readFileSync(manifestPath, "utf8"))
  : { history: [] };
manifest.history.push({
  at: new Date().toISOString(),
  action: uninstall ? "uninstall" : "install",
  modules: modules.map((m) => m.name),
  changes,
});
manifest.history = manifest.history.slice(-20);
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(JSON.stringify(report, null, 2));
