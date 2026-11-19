#!/usr/bin/env node
// Free Gemini helper for task sessions (Haiku-level jobs only): locate code in big files, summarise a long
// log or doc, answer a narrow question. CODE AND FICTIONAL DATA ONLY: the free tier may be used by Google to
// improve its products, so anything private stays on the PC. Refuses files outside the project, and any path
// matching gemini.blocked in kit.config.json.
//
//   node <kit>/runner/ask-gemini.mjs [--tier lite|flash|strong] "question" [file ...]   (default: lite)
//   node <kit>/runner/ask-gemini.mjs --list
//
// Exit codes: 0 ok, 3 no key, 4 quota, 5 http, 6 busy, 7 timeout, 1 other. Any non-zero = do the job yourself.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { getKey, listModels, pickModel, generate } from './gemini.mjs';

const kit = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cfg = (k) => execFileSync(process.execPath, [path.join(kit, 'runner', 'kit-config.mjs'), k], { encoding: 'utf8' }).trim();
const root = cfg('--root');
const BLOCKED = cfg('gemini.blocked').split('\n').filter(Boolean).map((s) => new RegExp(s, 'i'));
const usageLog = cfg('gemini.usageLog');
const MAX_FILE_BYTES = 400_000;
const CODES = { quota: 4, http: 5, busy: 6, timeout: 7 };

const args = process.argv.slice(2);
const key = getKey();
if (!key) { console.error('ask-gemini: GEMINI_API_KEY is not set. Skip this helper and do the job yourself.'); process.exit(3); }

function readAllowedFile(p) {
  const full = path.resolve(root, p);
  const rel = path.relative(root, full);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new Error(`refused (outside the project): ${p}`);
  if (BLOCKED.some((re) => re.test(rel))) throw new Error(`refused (private or binary): ${rel}`);
  if (fs.statSync(full).size > MAX_FILE_BYTES) throw new Error(`refused (over ${MAX_FILE_BYTES} bytes): ${rel}`);
  return { rel, text: fs.readFileSync(full, 'utf8') };
}

async function main() {
  if (args[0] === '--list') { for (const n of await listModels(key)) console.log(n); return; }
  let tier = 'lite';
  if (args[0] === '--tier') { tier = ['lite', 'flash', 'strong'].includes(args[1]) ? args[1] : 'lite'; args.splice(0, 2); }
  const [question, ...files] = args;
  if (!question) { console.error('usage: ask-gemini.mjs [--tier lite|flash|strong] "question" [file ...]'); process.exit(2); }

  const parts = [{ text: 'You are a precise code assistant. Answer only from the files given. Be brief: '
    + 'cite file paths and line numbers, no preamble, at most 25 lines.\n\nQuestion: ' + question }];
  for (const f of files) {
    const { rel, text } = readAllowedFile(f);
    parts.push({ text: `\n--- FILE ${rel} ---\n` + text.split('\n').map((l, i) => `${i + 1}: ${l}`).join('\n') });
  }
  const model = await pickModel(key, tier);
  const started = Date.now();
  let out;
  try { out = await generate({ key, model, parts }); }
  catch (e) { console.error(`ask-gemini: ${e.message}. Do the job yourself.`); process.exit(CODES[e.code] ?? 1); }
  try {
    const p = path.resolve(root, usageLog);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.appendFileSync(p, JSON.stringify({ at: new Date().toISOString(), model, tier, files: files.length, ms: Date.now() - started,
      inputTokens: out.usage.promptTokenCount, outputTokens: out.usage.candidatesTokenCount }) + '\n');
  } catch { /* best effort */ }
  console.log(out.text || '(empty answer)');
  console.log(`\n[gemini ${model} · in ${out.usage.promptTokenCount ?? '?'} / out ${out.usage.candidatesTokenCount ?? '?'} tokens · free tier · verify before trusting]`);
}

main().catch((err) => { console.error('ask-gemini:', err.message); process.exit(1); });
