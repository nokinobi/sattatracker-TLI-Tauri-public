import { computed, reactive } from 'vue';

// Loot the user left out of a strategy's profit, per strategy and period, by item id. Saved
// locally. Strategies with nothing excluded take no room.

const KEY = 'tli_strategy_excluded';
const MAX_STRATEGIES = 500;
// More than any strategy's loot list.
const MAX_ITEMS = 2000;

const id = (stage: string, strategyKey: string) => `${stage}|${strategyKey}`;

function load(): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? '{}');
    if (!v || typeof v !== 'object' || Array.isArray(v)) return out;
    Object.entries(v as Record<string, unknown>).slice(0, MAX_STRATEGIES).forEach(([k, items]) => {
      if (k.length > 300 || !Array.isArray(items)) return;
      const ids = items.filter((x): x is string => typeof x === 'string' && x.length <= 20).slice(0, MAX_ITEMS);
      if (ids.length) out[k] = ids;
    });
  } catch {
    // A broken saved list just means nothing is excluded.
  }
  return out;
}

const all = reactive<Record<string, string[]>>(load());

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(all));
  } catch {
    // Storage full or blocked: exclusions stay for this run only.
  }
}

export function excludedFor(stage: string, strategyKey: string): Set<string> {
  return new Set(all[id(stage, strategyKey)] ?? []);
}

// Nothing already saved is dropped to make room: a full list just takes no new strategies.
export const excludedFull = computed(() => Object.keys(all).length >= MAX_STRATEGIES);

// Returns what was saved, which is what the profit must use.
export function setExcluded(stage: string, strategyKey: string, items: Set<string>): Set<string> {
  const k = id(stage, strategyKey);
  if (items.size === 0) delete all[k];
  else if (all[k] || !excludedFull.value) all[k] = [...items].slice(0, MAX_ITEMS);
  save();
  return excludedFor(stage, strategyKey);
}
