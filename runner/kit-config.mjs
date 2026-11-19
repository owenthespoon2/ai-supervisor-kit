#!/usr/bin/env node
// Prints one value from the project's kit.config.json, merged over the kit defaults.
//   node kit-config.mjs <dotted.key> [fallback]      e.g. node kit-config.mjs hooks.restartCommand
//   node kit-config.mjs --root                       prints the project root in use
// Project root = $KIT_PROJECT, else the current directory. Config = $KIT_CONFIG, else <root>/kit.config.json.
// Arrays print one item per line; missing/empty values print the fallback (or nothing).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const kitDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(process.env.KIT_PROJECT || process.cwd());
const cfgPath = process.env.KIT_CONFIG ? path.resolve(process.env.KIT_CONFIG) : path.join(root, 'kit.config.json');

const read = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return {}; } };
const merge = (a, b) => {
  if (Array.isArray(b) || typeof b !== 'object' || b === null) return b === undefined ? a : b;
  const out = { ...(a ?? {}) };
  for (const [k, v] of Object.entries(b)) out[k] = merge(out[k], v);
  return out;
};
const cfg = merge(read(path.join(kitDir, 'kit.config.example.json')), read(cfgPath));

const [key, fallback = ''] = process.argv.slice(2);
if (!key) { console.error('usage: kit-config.mjs <dotted.key> [fallback] | --root'); process.exit(2); }
if (key === '--root') { console.log(root); process.exit(0); }
let v = key.split('.').reduce((o, k) => (o == null ? undefined : o[k]), cfg);
if (v === undefined || v === null || v === '' || (Array.isArray(v) && !v.length)) v = fallback;
console.log(Array.isArray(v) ? v.join('\n') : typeof v === 'object' ? JSON.stringify(v) : String(v));
