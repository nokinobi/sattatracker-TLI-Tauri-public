import { reactive, ref, watch } from 'vue';
import type { LeaderboardData, StrategyRow, TagsData } from './api';

// The Strategies tab is unmounted whenever the dashboard closes (F6) or another tab is picked.
// Its state lives here instead, so it comes back as it was; the filters, the page and the open
// strategy are also saved, so they survive an app restart.

export type PickState = 'in' | 'out';
export type Kind = 'compass' | 'astrolabe';
export type Section = Kind | 'timemark' | 'mechanic';
export type DetailView = 'loot' | 'talents';

const STATE_KEY = 'tli_strategies_state';
const CLOSED_KEY = 'tli_strategies_closed_sections';
const SECTIONS: Section[] = ['timemark', 'mechanic', 'compass', 'astrolabe'];
const SORT_VALUES = ['avgEfficiency', 'totalCount'];

interface Saved {
  stage: string;
  timemark: string;
  sort: string;
  minCount: number;
  page: number;
  itemQuery: string;
  picks: Record<string, PickState>;
  mechPicks: Record<string, PickState>;
  selected: StrategyRow | null;
  selectedStage: string;
  showFavorites: boolean;
  detailView: DetailView;
}

const str = (v: unknown, max = 200) => (typeof v === 'string' ? v.slice(0, max) : '');
const int = (v: unknown, lo: number, hi: number, fallback: number) =>
  typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi ? v : fallback;

function pickMap(v: unknown): Record<string, PickState> {
  const out: Record<string, PickState> = {};
  if (v && typeof v === 'object') {
    Object.entries(v as Record<string, unknown>).slice(0, 50).forEach(([k, s]) => {
      if ((s === 'in' || s === 'out') && k.length <= 64) out[k] = s;
    });
  }
  return out;
}

export function validRow(v: unknown): StrategyRow | null {
  if (!v || typeof v !== 'object') return null;
  const r = v as Record<string, unknown>;
  const num = (x: unknown) => (typeof x === 'number' && Number.isFinite(x) ? x : 0);
  if (typeof r.key !== 'string' || !r.key) return null;
  return {
    rank: num(r.rank), key: r.key.slice(0, 200), score: num(r.score), count: num(r.count),
    avgEarnings: num(r.avgEarnings), avgEfficiency: num(r.avgEfficiency), avgDuration: num(r.avgDuration),
    mapLabel: str(r.mapLabel), timeLabel: str(r.timeLabel), talentLabel: str(r.talentLabel, 500),
  };
}

function loadSaved(): Partial<Saved> {
  try {
    const v = JSON.parse(localStorage.getItem(STATE_KEY) ?? '{}');
    if (!v || typeof v !== 'object') return {};
    return {
      stage: str(v.stage, 40),
      timemark: str(v.timemark, 8),
      sort: SORT_VALUES.includes(v.sort) ? v.sort : undefined,
      minCount: int(v.minCount, 1, 99999, 30),
      page: int(v.page, 1, 50, 1),
      itemQuery: str(v.itemQuery, 100),
      picks: pickMap(v.picks),
      mechPicks: pickMap(v.mechPicks),
      selected: validRow(v.selected),
      selectedStage: str(v.selectedStage, 40),
      showFavorites: v.showFavorites === true,
      detailView: v.detailView === 'talents' ? 'talents' : 'loot',
    };
  } catch {
    return {};
  }
}

function loadClosed(): Section[] {
  try {
    const v = JSON.parse(localStorage.getItem(CLOSED_KEY) ?? '[]');
    return Array.isArray(v) ? v.filter((x): x is Section => SECTIONS.includes(x)) : [];
  } catch {
    return [];
  }
}

const saved = loadSaved();

// Filters and view, saved between runs.
export const stage = ref(saved.stage ?? '');
export const timemark = ref(saved.timemark ?? '');
export const sort = ref(saved.sort ?? 'avgEfficiency');
export const minCount = ref(saved.minCount ?? 30);
export const page = ref(saved.page ?? 1);
export const itemQuery = ref(saved.itemQuery ?? '');
// Picked compasses and astrolabes (cost item id -> include / exclude).
export const picks = reactive<Record<string, PickState>>(saved.picks ?? {});
// Picked mechanics (constellation, by its Chinese tree key -> include / exclude).
export const mechPicks = reactive<Record<string, PickState>>(saved.mechPicks ?? {});
export const selected = ref<StrategyRow | null>(saved.selected ?? null);
// Period the open strategy was opened from; favorites can be from an older one.
export const selectedStage = ref(saved.selectedStage || saved.stage || '');
export const showFavorites = ref(saved.showFavorites ?? false);
export const detailView = ref<DetailView>(saved.detailView ?? 'loot');
export const closed = reactive(new Set<Section>(loadClosed()));

// Loaded data, kept for this run only (the server's answers are cached for 5 minutes anyway).
export const stages = ref<string[]>([]);
export const seasonId = ref('');
export const baseTags = ref<TagsData | null>(null);
export const tags = ref<TagsData | null>(null);
export const board = ref<LeaderboardData | null>(null);
export const fetchedAt = ref(0);
export const stale = ref(false);
export const itemNames = ref(new Map<string, string>());
// True when the whole filtered list was fetched and pages are cut locally.
export const localPages = ref(false);
// Query the visible results belong to, so a failed refresh can say they are older.
export const shownFor = ref('');
export const expanded = reactive(new Set<Kind | 'mechanic'>());

export function openStrategy(row: StrategyRow, fromStage: string) {
  selected.value = row;
  selectedStage.value = fromStage;
}

export function saveClosed() {
  try {
    localStorage.setItem(CLOSED_KEY, JSON.stringify([...closed]));
  } catch {
    // Remembering collapsed sections is a convenience; ignore storage errors.
  }
}

let saveTimer: ReturnType<typeof setTimeout> | null = null;
function persist() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(saveNow, 300);
}

function saveNow() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = null;
  const data: Saved = {
    stage: stage.value, timemark: timemark.value, sort: sort.value, minCount: minCount.value, page: page.value,
    itemQuery: itemQuery.value, picks: { ...picks }, mechPicks: { ...mechPicks },
    selected: selected.value, selectedStage: selectedStage.value,
    showFavorites: showFavorites.value, detailView: detailView.value,
  };
  try {
    localStorage.setItem(STATE_KEY, JSON.stringify(data));
  } catch {
    // Restoring the tab is a convenience; ignore storage errors.
  }
}

// Don't lose a change made just before the window closes.
window.addEventListener('pagehide', () => { if (saveTimer) saveNow(); });

watch(
  [stage, timemark, sort, minCount, page, itemQuery, () => JSON.stringify(picks), () => JSON.stringify(mechPicks),
    selected, selectedStage, showFavorites, detailView],
  persist,
);
