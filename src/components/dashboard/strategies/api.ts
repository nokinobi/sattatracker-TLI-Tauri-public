import { invoke } from '@tauri-apps/api/core';
import talents from './talents.json';

// Shapes of the /api/strategy/* answers (player fields are stripped in Rust).
export interface FilterItem { key: string; label: string; count: number; strategyCount: number; hotRate: number }
export interface FilterGroup { totalCount: number; items: FilterItem[] }
export interface TagsData { seasonId: string; stage: string; generatedAt: number; filters: Record<string, FilterGroup> }

export interface StrategyRow {
  rank: number;
  key: string;
  score: number;
  count: number;
  avgEarnings: number;
  avgEfficiency: number;
  avgDuration: number;
  mapLabel: string;
  timeLabel: string;
  talentLabel: string;
}
export interface LeaderboardData { seasonId: string; stage: string; total: number; generatedAt: number; items: StrategyRow[] }

export interface ItemQty { id: string; quantity: number }
export interface DetailTag { type: string; key: string; label: string }
export interface DetailData {
  strategy: StrategyRow;
  items: { loot: ItemQty[]; cost: ItemQty[] };
  talents: { key: string; count: number }[];
  tags: DetailTag[];
}

export interface StageOptions { seasonId: string; options: { value: string; label: string }[] }
export interface Envelope<T> { data: T; fetchedAt: number; stale: boolean }

export interface ItemInfo { name: string; item_type: string; price: number }

export type Query = Record<string, string>;

// Writes to the tracker's log file (logs/tracker.log in its app data folder).
export function logEvent(level: 'info' | 'warn' | 'error', message: string) {
  invoke('log_event', { level, source: 'strategies', message }).catch(() => {});
}

export async function strategyApi<T>(endpoint: 'stage-options' | 'leaderboard' | 'tags' | 'detail', query: Query = {}) {
  try {
    return await invoke<Envelope<T>>('strategy_api', { endpoint, query });
  } catch (e) {
    logEvent('error', `${endpoint} failed in the window: ${String(e)}`);
    throw e;
  }
}

// Details are fetched one by one with a short gap so a page of rows doesn't
// burst the server's rate limit. Results are kept as long as the backend's own cache keeps a
// detail, so reopening a strategy later gets a current one; the oldest go first past the limit.
const DETAIL_KEEP_MS = 30 * 60 * 1000;
const MAX_DETAILS = 300;
const details = new Map<string, { at: number; promise: Promise<DetailData | null> }>();
let queue: Promise<unknown> = Promise.resolve();

export function fetchDetail(stage: string, strategyKey: string): Promise<DetailData | null> {
  const id = `${stage}:${strategyKey}`;
  const known = details.get(id);
  if (known && Date.now() - known.at < DETAIL_KEEP_MS) return known.promise;
  details.delete(id);
  if (details.size >= MAX_DETAILS) {
    const oldest = details.keys().next().value;
    if (oldest !== undefined) details.delete(oldest);
  }
  const p: Promise<DetailData | null> = queue.then(async () => {
    try {
      return (await strategyApi<DetailData>('detail', { stage, strategyKey })).data;
    } catch (e) {
      // A newer request for this strategy may have taken the place by now.
      if (details.get(id)?.promise === p) details.delete(id);
      console.warn('Strategy detail failed', e);
      logEvent('warn', `detail ${strategyKey} gave up: ${String(e)}`);
      return null;
    } finally {
      await new Promise(r => setTimeout(r, 300));
    }
  });
  queue = p;
  details.set(id, { at: Date.now(), promise: p });
  return p;
}

const itemCache = new Map<string, ItemInfo>();

// Always asks again: the prices in the answer change with refreshes and manual prices, and the
// question only goes to the tracker's own tables, not the server.
export async function itemInfo(ids: string[]): Promise<Map<string, ItemInfo>> {
  const wanted = [...new Set(ids)];
  if (wanted.length) {
    try {
      const got = await invoke<Record<string, ItemInfo>>('get_item_info', { ids: wanted });
      Object.entries(got).forEach(([id, info]) => itemCache.set(id, info));
    } catch (e) {
      logEvent('error', `item names for ${wanted.length} items failed: ${String(e)}`);
      throw e;
    }
  }
  return itemCache;
}

// ---- English labels (keys are what the API returns) ----

const TREES: Record<string, string> = {
  装备: 'Gear', 传奇装备: 'Legendary Gear', 罗盘: 'Compass', 通货: 'Commodities', 征战: 'War', 巨力: 'Might',
  狩猎: 'Hunting', 机械: 'Machine', 黑潮: 'Dark Surge', 黑帆: 'Blacksail', 魔方: 'Cube', 迷城: 'Aeterna',
  梦魇: 'Nightmare', 怪谈: 'Folklore', 玩偶: 'Clockwork Ballet', 信标: 'Beacon', 画雪: 'The Frozen Canvas',
  塔罗: 'Arcana', 大亨: 'Sandlord', 通缉: 'Outlaw', 囚笼: 'Cage', 叠界: 'Overrealm', 渴瘾: 'Vorax',
  造物: 'Creation', 明月: 'Lunaria', 幽邃: 'Profound', 守夜: 'Afterlight',
};

const REGIONS: Record<string, string> = {
  '0': 'Glacial Abyss', '1': 'Blistering Lava Sea', '2': 'Steel Forge', '3': 'Thunder Wastes', '4': 'Voidlands',
  冰图: 'Glacial Abyss', 火图: 'Blistering Lava Sea', 钢图: 'Steel Forge', 雷图: 'Thunder Wastes', 暗图: 'Voidlands',
  'Dark Realm': 'Voidlands',
};

const AREAS: Record<string, string> = {
  深空: 'Deep Space', 幽邃: 'Profound', 万界: 'Myriad', 画雪: 'The Frozen Canvas', '-10': 'Myriad Profound',
  dogmatic: 'Dogmatic', tidecaller: 'Tidecaller', tidecallerVoidSeaLord: 'Lord of the Void Sea',
  fogCity: 'Fog City', mysticCity: 'Aeterna',
};

const TIMES: Record<string, string> = {
  '0': 'T1', '1': 'T2', '2': 'T3', '3': 'T4', '4': 'T5', '5': 'T6',
  '6': 'T7-0', '7': 'T7-1', '8': 'T7-2', '9': 'T8-0', '10': 'T8-1', '11': 'T8-2', '12': 'Profound',
  '13': 'Deep Space', 深空: 'Deep Space', 幽邃: 'Profound', K7: 'T7', K8: 'T8',
};

const MECHANICS: Record<string, string> = {
  watcher: 'Watcher', S4LocalMap: 'Aeterna', S6Map: 'Fog City', S8Map: 'The Frozen Canvas', S9Map: 'Arcana',
  S10CampsiteMap: 'Sandlord', S12Map: 'Overrealm', S13FinalMap: 'Vorax', S16FinalMap: 'Season 16 final map',
  k7wanjie: 'Myriad T7', k8wanjie: 'Myriad T8', u8wanjie: 'Myriad Profound',
};

const WATCHER = '监视者';

export function treeName(zh: string): string {
  return TREES[zh] ?? zh;
}

// Strategy title: its mechanic constellations. Profound is left out because nearly every
// strategy has it, and in a title it reads like the Profound timemark.
export function treeList(label: string): string {
  return label.split('、').filter(t => t && t !== '幽邃').map(treeName).join(', ');
}

export function areaName(key: string): string {
  if (key.endsWith(WATCHER)) {
    const region = key.slice(0, -WATCHER.length);
    return `Watcher · ${REGIONS[region] ?? region}`;
  }
  return REGIONS[key] ?? AREAS[key] ?? key;
}

export function timeName(key: string): string {
  // Unlisted keys are boss and season maps, already named by the area.
  return TIMES[key] ?? '';
}

export function mechanicName(key: string): string {
  return MECHANICS[key] ?? key;
}

export function talentText(md5: string): string {
  if (md5 === '__no_main_talent__') return 'No main talent';
  return (talents as Record<string, string>)[md5] ?? `Unknown talent (${md5.slice(0, 6)})`;
}

// Junk keys reported for broken uploads.
export function isJunkKey(key: string): boolean {
  return key === '' || key === 'NaN' || key === 'unknown';
}

export function stageName(value: string): string {
  if (value === 'legacy') return 'All (unstaged)';
  const m = /^(day|week)(\d+)$/.exec(value);
  return m ? `${m[1] === 'day' ? 'Day' : 'Week'} ${m[2]}` : value;
}

export function itemKind(name: string): 'compass' | 'astrolabe' | 'other' {
  if (/astrolabe/i.test(name)) return 'astrolabe';
  // "Compass Profound Probe" is a probe, not a compass.
  if (/compass/i.test(name) && !/probe/i.test(name)) return 'compass';
  return 'other';
}
