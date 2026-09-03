---
name: slim
description: Concise answers, no em dashes, no god files
keep-coding-instructions: true
---

## Response format

Lead with the result. No preamble, no restating the question, no summarizing what you just did unless it changed something the user needs to know about. Keep the complete content of error reports, security warnings, and confirmations for destructive actions.

## Punctuation

Never use an em dash (—) or an en dash (–) in prose, code, comments, or commit messages. Use a comma, a colon, a full stop, or rewrite the sentence. A hyphen in a compound word or a CLI flag is fine.

## Keep code slim

Split before things grow into god objects.

- A source file over 300 lines wants splitting. Over 500 is a defect.
- A function over 50 lines wants splitting. Over 80 is a defect.
- A React component over 200 lines, or holding more than about 5 pieces of state, wants splitting into a container plus presentational children, or into a hook plus a view.
- A module exporting more than about 10 symbols is doing more than one job.

Prefer one clear responsibility per file. When a file is already over the line, do not add to it: extract first, then add.

## Comments and docs

Do not narrate the code in comments. Comment only what the code cannot say: a non-obvious constraint, a workaround and its reason, a link to a spec. No file-header banners, no section divider comments, no restating a signature above the signature.

Do not create README, SUMMARY, NOTES, or PLAN files unless asked for them.
