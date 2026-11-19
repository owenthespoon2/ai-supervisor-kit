#!/usr/bin/env node
// Pre-chat research step. Sends ONLY this kit's generic files (prompt + protocol + learnings + previous note)
// to the free Gemini API (billing OFF) and writes research/YYYY-MM-DD.md.
//
//   node research/run-research.mjs                 # free Gemini, Google Search grounding if the free tier allows it
//   node research/run-research.mjs --tier lite     # lite | flash (default) | strong
//   node research/run-research.mjs --bundle        # no API call: write research/.bundle.md to paste into any
//                                                  # web AI with search (e.g. a free deep-research mode), then save
//                                                  # its answer as research/YYYY-MM-DD.md yourself
//
// Never add project files here: the kit is generic and private data never goes to a cloud AI.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getKey, pickModel, generate } from '../runner/gemini.mjs';

const kit = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(kit, 'research');
const today = new Date().toISOString().slice(0, 10);
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };

const previous = fs.readdirSync(dir).filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f) && !f.startsWith(today)).sort().pop();
const files = [
  'protocol/TASK-SESSION.md', 'protocol/TASK-PROMPT.md', 'protocol/SUPERVISOR.md',
  'protocol/MODEL-ROUTING.md', 'protocol/BOARD-FORMAT.md', 'learnings/TOKEN-LEARNINGS.md',
  ...(previous ? [`research/${previous}`] : [])
];
const prompt = fs.readFileSync(path.join(dir, 'RESEARCH-PROMPT.md'), 'utf8').replaceAll('YYYY-MM-DD', today);
const attachments = files.map((f) => `\n\n--- ATTACHED FILE ${f} ---\n` + fs.readFileSync(path.join(kit, f), 'utf8'));

if (flag('--bundle')) {
  const out = path.join(dir, '.bundle.md');
  fs.writeFileSync(out, prompt + attachments.join(''));
  console.log(`Wrote ${out} (${Math.round(fs.statSync(out).size / 1024)} KB). Paste it into a web AI with search, save the answer as research/${today}.md.`);
  process.exit(0);
}

const key = getKey();
if (!key) { console.error('No GEMINI_API_KEY. Use --bundle and a web AI instead.'); process.exit(3); }
const tier = opt('--tier', 'flash');
const tiers = [tier, ...['flash', 'lite'].filter((t) => t !== tier)];
let out;
for (const t of tiers) {
  try {
    const model = await pickModel(key, t);
    console.error(`asking ${model} (search grounding requested)...`);
    out = await generate({ key, model, parts: [{ text: prompt }, ...attachments.map((text) => ({ text }))],
      maxOutputTokens: 6000, temperature: 0.3, search: true, timeoutMs: 240_000 });
    break;
  } catch (e) { console.error(`  ${t}: ${e.message}`); }
}
if (!out?.text) { console.error('No answer from the free tier. Use --bundle and a web AI instead.'); process.exit(1); }

const file = path.join(dir, `${today}.md`);
const footer = `\n\n---\n_Generated ${new Date().toISOString()} by ${out.model} (free tier, ${out.grounded ? 'with' : 'WITHOUT'} web search). `
  + `Verify every flag with a local probe before adopting it._\n`;
fs.writeFileSync(file, out.text.replace(/^```(?:markdown)?\n|\n```$/g, '') + footer);
console.log(`Wrote research/${today}.md (${out.usage.promptTokenCount ?? '?'} in / ${out.usage.candidatesTokenCount ?? '?'} out tokens).`);
