#!/usr/bin/env node
// PreToolUse on Write|Edit|NotebookEdit. Exit 2 rejects content containing an
// em or en dash before it reaches disk. Instructions drift as context fills;
// this does not.
import { readFileSync } from "node:fs";

const DASHES = /[—–]/g;

const read = () => {
  try {
    return JSON.parse(readFileSync(0, "utf8") || "{}");
  } catch {
    return {};
  }
};

const { tool_name: tool, tool_input: input = {} } = read();

// Only the fields that carry text the model authored. file_path is excluded on
// purpose: a path with a dash in it is the user's, not ours.
const FIELDS = ["content", "new_string", "new_source"];

const offenders = [];
for (const field of FIELDS) {
  const value = input[field];
  if (typeof value !== "string") continue;
  for (const line of value.split("\n")) {
    if (DASHES.test(line)) offenders.push(line.trim().slice(0, 120));
    DASHES.lastIndex = 0;
  }
}

if (!offenders.length) process.exit(0);

const shown = offenders.slice(0, 5);
console.error(
  `${tool} blocked: em dash (—) or en dash (–) in the content.\n` +
    `Replace each with a comma, colon, full stop, or a rewrite, then retry.\n\n` +
    shown.map((l) => `  ${l}`).join("\n") +
    (offenders.length > shown.length ? `\n  ...and ${offenders.length - shown.length} more` : "")
);
process.exit(2);
