#!/usr/bin/env node
import { basename } from "node:path";

const PATTERNS = [
  /(^|\/)\.env($|\.)/,
  /(^|\/)secrets?\//,
  /(^|\/)\.npmrc$/,
  /(^|\/)\.netrc$/,
  /(^|\/)id_(rsa|ecdsa|ed25519)(\.pub)?$/,
  /\.pem$/,
  /\.p12$/,
  /\.pfx$/,
  /\.key$/,
  /(^|\/)credentials$/,
  /(^|\/)\.aws\//,
  /(^|\/)\.ssh\//,
  /service[-_]?account.*\.json$/i,
];

const ALLOWLIST = [/\.env\.example$/, /\.env\.sample$/, /\.env\.template$/];

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
};

const main = async () => {
  let payload;
  try {
    payload = JSON.parse(await readStdin());
  } catch {
    process.exit(0);
  }

  const input = payload?.tool_input ?? {};
  const candidates = [input.file_path, input.path, input.notebook_path].filter(
    (v) => typeof v === "string" && v.length > 0
  );
  if (candidates.length === 0) process.exit(0);

  for (const candidate of candidates) {
    const normalized = candidate.replaceAll("\\", "/");
    if (ALLOWLIST.some((re) => re.test(normalized))) continue;
    if (PATTERNS.some((re) => re.test(normalized))) {
      process.stderr.write(
        `Blocked: ${basename(normalized)} matches a secrets pattern. If you need a value from it, ask me for the specific key and I will paste it.\n`
      );
      process.exit(2);
    }
  }

  process.exit(0);
};

main();
