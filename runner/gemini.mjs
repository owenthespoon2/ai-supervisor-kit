// Shared free-tier Gemini client for ask-gemini.mjs and research/run-research.mjs.
// FREE ONLY: a Google AI Studio key on a project with billing OFF can never charge. Never enable billing.
// The key comes from the GEMINI_API_KEY environment variable (on Windows, also read from the saved
// user/system variable, because processes started before it was saved don't inherit it).
// The key never goes into a file in any repo.
import { execFileSync } from 'node:child_process';

export const API = 'https://generativelanguage.googleapis.com/v1beta';

export function getKey() {
  if (process.env.GEMINI_API_KEY) return process.env.GEMINI_API_KEY;
  if (process.platform !== 'win32') return undefined;
  for (const hive of ['HKCU\\Environment', 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment']) {
    try {
      const out = execFileSync('reg', ['query', hive, '/v', 'GEMINI_API_KEY'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const m = out.match(/GEMINI_API_KEY\s+REG_(?:EXPAND_)?SZ\s+(\S+)/);
      if (m) return m[1];
    } catch { /* not set in this hive */ }
  }
  return undefined;
}

export async function listModels(key) {
  const res = await fetch(`${API}/models?pageSize=200`, { headers: { 'x-goog-api-key': key } });
  if (!res.ok) throw new Error(`model list failed: HTTP ${res.status}`);
  const data = await res.json();
  return (data.models ?? [])
    .filter((m) => (m.supportedGenerationMethods ?? []).includes('generateContent'))
    .map((m) => m.name.replace(/^models\//, ''));
}

function newest(names) {
  const version = (n) => (n.match(/(\d+(?:\.\d+)?)/) ?? [0, '0'])[1];
  return names
    .filter((n) => !/preview|exp|tts|image|embedding|live|audio/i.test(n))
    .sort((a, b) => parseFloat(version(b)) - parseFloat(version(a)))[0];
}

// tier: lite (most free quota, most reliable) | flash | strong (newest non-flash "pro"-class model, often busy or not free)
export async function pickModel(key, tier) {
  const fromEnv = { lite: process.env.GEMINI_MODEL_LITE, flash: process.env.GEMINI_MODEL_FLASH, strong: process.env.GEMINI_MODEL_STRONG }[tier];
  if (fromEnv) return fromEnv;
  const names = (await listModels(key)).filter((n) => n.startsWith('gemini'));
  const lite = names.filter((n) => /flash-lite/i.test(n));
  const flash = names.filter((n) => /flash/i.test(n) && !/lite/i.test(n));
  const strong = names.filter((n) => !/flash|nano|gemma/i.test(n));
  const choice = tier === 'strong' ? newest(strong) ?? newest(flash)
    : tier === 'lite' ? newest(lite) ?? newest(flash) : newest(flash) ?? newest(lite);
  if (!choice) throw new Error(`no ${tier} model is available to this key`);
  return choice;
}

// Returns { text, model, usage }. Throws Error with .code: 'timeout' | 'busy' | 'quota' | 'http'.
// search=true asks for Google Search grounding (free tier has a small daily allowance on some models);
// if the model refuses it, the call is retried once without search and .grounded=false is returned.
export async function generate({ key, model, parts, maxOutputTokens = 2048, temperature = 0.1, search = false, timeoutMs }) {
  const t = Number(timeoutMs ?? process.env.GEMINI_TIMEOUT_MS ?? 90_000);
  const call = (withSearch) => fetch(`${API}/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'x-goog-api-key': key, 'content-type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts }],
      generationConfig: { temperature, maxOutputTokens },
      ...(withSearch ? { tools: [{ google_search: {} }] } : {})
    }),
    signal: AbortSignal.timeout(t)
  });
  const fail = (code, msg) => Object.assign(new Error(msg), { code });
  let grounded = search;
  let res;
  try { res = await call(grounded); } catch (e) { throw fail('timeout', `${model} did not answer in time (${e.name})`); }
  if (grounded && res.status === 400) { grounded = false; try { res = await call(false); } catch (e) { throw fail('timeout', `${model} did not answer in time`); } }
  for (const wait of [5_000, 20_000]) {          // 503 = Google busy: retry twice, then give up
    if (res.status !== 503) break;
    await new Promise((r) => setTimeout(r, wait));
    try { res = await call(grounded); } catch { throw fail('timeout', `${model} did not answer in time`); }
  }
  if (res.status === 503) throw fail('busy', `${model} is busy (503)`);
  if (res.status === 429) throw fail('quota', `free quota reached for ${model}`);
  if (!res.ok) throw fail('http', `HTTP ${res.status} from ${model}: ${(await res.text()).slice(0, 200)}`);
  const data = await res.json();
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? '').join('').trim();
  return { text, model, grounded, usage: data.usageMetadata ?? {} };
}
