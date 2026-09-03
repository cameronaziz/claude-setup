import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const [target, fragmentPath, dryRun, backupDir] = process.argv.slice(2);
const dry = dryRun === "1";

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8") || "{}");
  } catch (err) {
    if (fallback !== undefined && err.code === "ENOENT") return fallback;
    console.log(`could not read ${path}, leaving it alone`);
    process.exit(0);
  }
}

const current = readJson(target, {});
const wanted = readJson(fragmentPath);
const missing = Object.entries(wanted).filter(([key]) => current[key] === undefined);

if (!missing.length) {
  for (const key of Object.keys(wanted)) console.log(`already set: ${key}`);
  process.exit(0);
}
if (dry) {
  for (const [key, value] of missing) console.log(`would set ${key} to ${value}`);
  process.exit(0);
}

// This file is Claude Code's own, so back it up before touching it.
mkdirSync(backupDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z");
try {
  copyFileSync(target, `${backupDir}/claude.json.${stamp}`);
} catch (err) {
  if (err.code !== "ENOENT") {
    console.log(`could not back up ${target}, nothing was changed`);
    process.exit(0);
  }
}

for (const [key, value] of missing) current[key] = value;
writeFileSync(target, `${JSON.stringify(current, null, 2)}\n`);
for (const [key, value] of missing) console.log(`set ${key} to ${value}`);
