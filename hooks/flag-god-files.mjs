#!/usr/bin/env node
// PostToolUse on Write|Edit. The write already happened, so this reports rather
// than prevents: exit 2 puts the message in front of Claude so it splits the
// file on the next turn. Thresholds match output-styles/slim.md.
import { readFileSync, existsSync } from "node:fs";
import { extname } from "node:path";

const FILE_WARN = 300;
const FILE_FAIL = 500;
const FUNC_WARN = 50;
const FUNC_FAIL = 80;

const CODE = new Set([
  ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts",
  ".py", ".go", ".rs", ".rb", ".java", ".kt", ".swift", ".c", ".h", ".cc", ".cpp", ".hpp",
]);

const read = () => {
  try {
    return JSON.parse(readFileSync(0, "utf8") || "{}");
  } catch {
    return {};
  }
};

const { tool_input: input = {} } = read();
const path = input.file_path;

if (!path || !CODE.has(extname(path)) || !existsSync(path)) process.exit(0);

let lines;
try {
  lines = readFileSync(path, "utf8").split("\n");
} catch {
  process.exit(0);
}

// Brace depth is a rough proxy for function extent, and it is deliberately
// rough: this only needs to be right often enough to catch a 200-line function.
const longFunctions = () => {
  const found = [];
  let depth = 0;
  let start = null;
  let name = "";
  const SIGNATURE =
    /(?:function\s+([A-Za-z0-9_$]+)|(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:async\s*)?\(|([A-Za-z0-9_$]+)\s*\([^)]*\)\s*\{|def\s+([A-Za-z0-9_$]+)|func\s+([A-Za-z0-9_$]+)|fn\s+([A-Za-z0-9_$]+))/;

  lines.forEach((line, i) => {
    if (depth === 0) {
      const m = line.match(SIGNATURE);
      if (m) {
        name = m.slice(1).find(Boolean) || "anonymous";
        start = i;
      }
    }
    depth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
    if (depth <= 0 && start !== null) {
      const length = i - start + 1;
      if (length > FUNC_WARN) found.push({ name, line: start + 1, length });
      start = null;
      depth = 0;
    }
  });
  return found;
};

const problems = [];

if (lines.length > FILE_WARN) {
  const verdict = lines.length > FILE_FAIL ? "over the hard limit" : "past the split threshold";
  problems.push(`${path} is ${lines.length} lines, ${verdict} of ${lines.length > FILE_FAIL ? FILE_FAIL : FILE_WARN}.`);
}

for (const fn of longFunctions()) {
  const verdict = fn.length > FUNC_FAIL ? "over the hard limit" : "past the split threshold";
  problems.push(`${path}:${fn.line} ${fn.name}() is ${fn.length} lines, ${verdict} of ${fn.length > FUNC_FAIL ? FUNC_FAIL : FUNC_WARN}.`);
}

if (!problems.length) process.exit(0);

console.error(
  `Slim this down before moving on:\n\n${problems.map((p) => `  ${p}`).join("\n")}\n\n` +
    `Extract the distinct responsibility into its own file or function. ` +
    `If the size is genuinely warranted here, say why and continue.`
);
process.exit(2);
