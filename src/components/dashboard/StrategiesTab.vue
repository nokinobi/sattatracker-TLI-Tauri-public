<template>
  <StrategyDetail v-if="selected" :row="selected" :stage="stage" @back="selected = null" />
  <div v-else class="st">
    <aside class="st-filters" aria-label="Filters">
      <div class="st-side dash-scroll">
        <section class="st-sec">
          <button class="st-sec-head" :aria-expanded="isOpen('timemark')" @click="toggleSection('timemark')">
            <svg :class="['chev', { shut: !isOpen('timemark') }]" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span class="dash-label">Timemark</span>
            <span v-if="!isOpen('timemark')" class="picked">{{ timemarkLabel }}</span>
          </button>
          <div v-if="isOpen('timemark')" class="st-marks" role="group" aria-label="Timemark">
            <button
              v-for="t in timemarks"
              :key="t.key"
              :class="['st-mark', { on: timemark === t.key }]"
              :disabled="t.disabled"
              @click="timemark = t.key"
            >
              {{ t.label }}<span v-if="t.share" class="mono">{{ t.share }}</span>
            </button>
          </div>
        </section>

        <div class="st-pair">
          <div class="st-sec rank">
            <span class="dash-label">Rank by</span>
            <div class="dash-seg" role="group" aria-label="Rank by">
              <button v-for="s in SORTS" :key="s.value" :class="{ on: sort === s.value }" @click="sort = s.value">{{ s.label }}</button>
            </div>
          </div>
          <div class="st-sec">
            <span class="dash-label">Maps run</span>
            <label class="ctl">at least
              <input v-model.lazy.number="minCount" class="st-num mono" type="number" min="1" aria-label="Minimum maps run" />
            </label>
          </div>
        </div>

        <label class="dash-input">
          <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.5" fill="none" stroke="var(--label)" stroke-width="1.5"/><path d="M10.5 10.5L14 14" stroke="var(--label)" stroke-width="1.5" stroke-linecap="round"/></svg>
          <input v-model="itemQuery" placeholder="Search mechanics, compasses, astrolabes" aria-label="Search mechanics, compasses and astrolabes" />
        </label>

        <div v-if="!tags && loading" class="dash-empty">Loading filters…</div>
        <section v-if="tags" class="st-sec">
          <button class="st-sec-head" :aria-expanded="isOpen('mechanic')" @click="toggleSection('mechanic')">
            <svg :class="['chev', { shut: !isOpen('mechanic') }]" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span class="dash-label">Mechanics</span>
            <span v-if="!isOpen('mechanic') && mechanics.picked" class="picked">{{ mechanics.picked }} selected</span>
            <span v-else class="note">{{ mechanics.total }} constellations · % of strategies</span>
          </button>
          <template v-if="isOpen('mechanic')">
            <div
              v-for="v in mechanics.values"
              :key="v.key"
              :class="['st-value', v.state]"
              role="button"
              tabindex="0"
              :aria-pressed="v.state === 'in'"
              :title="v.state === 'in' ? 'Click to remove from filters' : 'Click to show only strategies with points in this constellation'"
              @click="toggleMech(v.key, 'in')"
              @keydown.enter.prevent="toggleMech(v.key, 'in')"
            >
              <span class="bar" :style="{ width: Math.min(100, v.share) + '%' }"></span>
              <span class="label">{{ v.label }}</span>
              <span class="mono share">{{ v.share.toFixed(1) }}%</span>
              <button
                :class="['exc', { on: v.state === 'out' }]"
                aria-label="Exclude"
                title="Hide strategies with points in this constellation"
                @click.stop="toggleMech(v.key, 'out')"
              >
                <svg width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 6h6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
              </button>
            </div>
            <button v-if="mechanics.hidden > 0" class="st-more" @click="expanded.add('mechanic')">Show all {{ mechanics.total }}</button>
            <div v-if="!mechanics.values.length" class="none">{{ itemQuery ? 'No matches' : 'None reported' }}</div>
          </template>
        </section>
        <section v-for="g in itemGroups" :key="g.kind" class="st-sec">
          <button class="st-sec-head" :aria-expanded="isOpen(g.kind)" @click="toggleSection(g.kind)">
            <svg :class="['chev', { shut: !isOpen(g.kind) }]" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span class="dash-label">{{ g.title }}</span>
            <span v-if="!isOpen(g.kind) && g.picked" class="picked">{{ g.picked }} selected</span>
            <span v-else class="note">{{ g.total }} used · up to {{ g.perMap }} per map</span>
          </button>
          <template v-if="isOpen(g.kind)">
            <div
              v-for="v in g.values"
              :key="v.key"
              :class="['st-value', v.state]"
              role="button"
              tabindex="0"
              :aria-pressed="v.state === 'in'"
              :title="v.state === 'in' ? 'Click to remove from filters' : 'Click to show only strategies that use this'"
              @click="toggle(v.key, 'in')"
              @keydown.enter.prevent="toggle(v.key, 'in')"
            >
              <span class="bar" :style="{ width: Math.min(100, v.share * 2) + '%' }"></span>
              <span class="dash-icon tiny"><img :src="getIcon(v.key)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
              <span class="label">{{ v.label }}</span>
              <span class="mono share">{{ v.share.toFixed(1) }}%</span>
              <button
                :class="['exc', { on: v.state === 'out' }]"
                aria-label="Exclude"
                title="Hide strategies that use this"
                @click.stop="toggle(v.key, 'out')"
              >
                <svg width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 6h6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
              </button>
            </div>
            <button v-if="g.hidden > 0" class="st-more" @click="expanded.add(g.kind)">Show all {{ g.total }}</button>
            <div v-if="!g.values.length" class="none">{{ itemQuery ? 'No matches' : 'None reported' }}</div>
          </template>
        </section>
      </div>
      <div class="st-foot">Click a value to add it to the filters, minus to exclude it. Several mechanics: strategies must use all of them; several compasses: any of them. Community data, refreshed every 5 min.</div>
    </aside>

    <section class="st-main" aria-label="Strategy ladder">
      <div class="st-top">
        <div class="row">
          <span class="heading">{{ heading }}</span>
          <span class="sub">{{ board ? `${board.total} strategies · ranked by ${sort === 'totalCount' ? 'maps run' : 'profit per hour'}` : '' }}</span>
          <span class="status">
            <template v-if="seasonId">Season {{ seasonId }} · </template>
            <span v-if="stale && !error" class="warn">Server unreachable, showing saved data · </span>
            {{ fetchedAt ? `updated ${fmtAgo(fetchedAt, now)}` : '' }}
          </span>
          <label class="ctl">Period
            <select v-model="stage" aria-label="Period">
              <option v-for="s in stages" :key="s" :value="s">{{ stageName(s) }}</option>
            </select>
          </label>
        </div>
        <div v-if="error && board" class="st-failed" role="alert">
          <span>Couldn't load {{ heading.toLowerCase() }}{{ retrying ? ', trying again…' : '.' }} {{ error }}</span>
          <span v-if="shownFor !== query" class="faint">The list below still shows the previous results.</span>
          <button v-if="!retrying" class="st-link" @click="load">Retry</button>
        </div>
        <div v-if="active.length" class="row chips">
          <span class="faint">Filters:</span>
          <button
            v-for="a in active"
            :key="a.key + a.state"
            :class="['st-active', a.state]"
            :title="a.label"
            @click="a.mech ? toggleMech(a.key, a.state) : toggle(a.key, a.state)"
          >
            <span class="txt">{{ a.state === 'out' ? 'Not: ' : '' }}{{ a.label }}</span> <span aria-label="Remove">×</span>
          </button>
          <button class="st-link" @click="clearFilters">Clear</button>
        </div>
      </div>

      <div :class="['st-progress', { on: loading }]" role="progressbar" aria-label="Loading strategies" :aria-hidden="!loading"><span></span></div>
      <div class="st-head">
        <span>#</span><span>Strategy</span><span>Profit / hour</span><span class="r">Maps</span><span class="r">FE / map</span><span class="r">Time</span>
      </div>
      <div class="st-list dash-scroll">
        <div v-if="error && !board && !retrying" class="dash-empty">
          <div>
            <div>Couldn't load strategies: {{ error }}</div>
            <button class="dash-btn small retry" @click="load">Try again</button>
          </div>
        </div>
        <div v-else-if="!board" class="dash-empty">Loading strategies…</div>
        <div v-else-if="rows.length === 0" class="dash-empty">No strategies match these filters</div>
        <button v-for="r in rows" :key="r.key" class="st-row" @click="selected = r.raw">
          <span class="mono rank">{{ r.rank }}</span>
          <span class="who">
            <span class="title" :title="r.title">{{ r.title }}</span>
            <span class="meta">
              <span class="tag">{{ r.area }}</span>
              <span v-if="r.time && r.time !== r.area" class="tag time">{{ r.time }}</span>
              <span class="slots" :aria-label="r.slotsLabel">
                <span
                  v-for="(s, i) in r.slots"
                  :key="i"
                  :class="['slot', s.kind, { empty: !s.id, gap: i === COMPASS_SLOTS }]"
                  :title="s.name"
                >
                  <img v-if="s.id" :src="getIcon(s.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" />
                </span>
              </span>
            </span>
          </span>
          <span class="rate">
            <span class="track"><span :style="{ width: r.rateBar }"></span></span>
            <span class="mono pos">{{ r.perHour }}</span>
          </span>
          <span class="mono r">{{ r.maps }}</span>
          <span class="mono r gold strong">{{ r.perMap }}</span>
          <span class="mono r faint">{{ r.dur }}</span>
        </button>
      </div>
      <div v-if="board && pages > 1" class="st-pager">
        <button class="dash-btn small" :disabled="page <= 1" @click="page--">Previous</button>
        <span class="mono">Page {{ page }} of {{ pages }}</span>
        <button class="dash-btn small" :disabled="page >= pages" @click="page++">Next</button>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue';
import { getIcon } from '../../utils/assets';
import { fmtAgo, fmtDur, fmtValue } from './format';
import StrategyDetail from './StrategyDetail.vue';
import { PROFOUND, TREES } from './strategies/trees';
import {
  areaName, strategyApi, fetchDetail, itemInfo, itemKind, stageName, timeName, treeList, treeName,
  type FilterItem, type LeaderboardData, type Query, type StageOptions, type StrategyRow, type TagsData,
} from './strategies/api';

type State = 'in' | 'out';
type Kind = 'compass' | 'astrolabe';
type Section = Kind | 'timemark' | 'mechanic';

const PAGE_SIZE = 10;
const ITEM_ROWS = 8;
// The leaderboard returns at most 500 strategies, 100 per request.
const MAX_STRATEGIES = 500;
const BIG_PAGE = 100;
const COMPASS_SLOTS = 4;
const ASTROLABE_SLOTS = 2;
const CLOSED_KEY = 'tli_strategies_closed_sections';
const SORTS = [
  { value: 'avgEfficiency', label: 'Profit / hour' },
  { value: 'totalCount', label: 'Maps' },
];
const GROUPS: { kind: Kind; title: string; perMap: number }[] = [
  { kind: 'compass', title: 'Compasses', perMap: COMPASS_SLOTS },
  { kind: 'astrolabe', title: 'Astrolabes', perMap: ASTROLABE_SLOTS },
];
const TIMEMARKS = [
  { key: '', label: 'All' },
  { key: '7', label: 'T7-1' },
  { key: '8', label: 'T7-2' },
  { key: '10', label: 'T8-1' },
  { key: '11', label: 'T8-2' },
  { key: '12', label: 'Profound' },
  { key: '13', label: 'Deep Space' },
];

const stages = ref<string[]>([]);
const stage = ref('');
const seasonId = ref('');
const timemark = ref('');
const sort = ref('avgEfficiency');
const minCount = ref(30);
const page = ref(1);
// Picked compasses and astrolabes (cost item id -> include / exclude).
const picks = reactive<Record<string, State>>({});
const itemQuery = ref('');
// Picked mechanics (constellation, by its Chinese tree key -> include / exclude).
const mechPicks = reactive<Record<string, State>>({});
const expanded = reactive(new Set<Kind | 'mechanic'>());
const closed = reactive(new Set<Section>(loadClosed()));

const baseTags = ref<TagsData | null>(null);
const tags = ref<TagsData | null>(null);
const board = ref<LeaderboardData | null>(null);
const loading = ref(false);
const error = ref('');
const stale = ref(false);
const fetchedAt = ref(0);
const now = ref(Date.now());
const selected = ref<StrategyRow | null>(null);
const itemNames = ref(new Map<string, string>());
const kits = reactive(new Map<string, { id: string; name: string; kind: 'compass' | 'astrolabe' }[]>());

const mechIn = computed(() => Object.keys(mechPicks).filter(k => mechPicks[k] === 'in'));

function mechNodes(tree: string): string[] {
  return [...new Set((TREES[tree]?.n ?? []).map(n => n[3]).filter(Boolean))];
}

// The server ORs values of one type and ANDs types together. A mechanic is sent as all of its
// talent nodes, which means "has points in it"; only the first included mechanic fits that way,
// the others are checked on the returned rows (see loadAll).
function tagList(state: State): string {
  const out: string[] = [];
  if (state === 'in' && timemark.value) out.push(`timeIndex:${timemark.value}`);
  Object.entries(picks).forEach(([key, s]) => { if (s === state) out.push(`costItem:${key}`); });
  const mechs = state === 'in' ? mechIn.value.slice(0, 1) : Object.keys(mechPicks).filter(k => mechPicks[k] === 'out');
  mechs.forEach(tree => mechNodes(tree).forEach(md5 => out.push(`mainTalent:${md5}`)));
  return out.join(',');
}

// Several mechanics: fetch every strategy the server narrows to (up to 500) and keep the rows
// whose constellations include the other picked mechanics too; paging then happens locally.
async function loadAll(q: Query, extra: string[]) {
  const first = await strategyApi<LeaderboardData>('leaderboard', { ...q, sort: sort.value, limit: String(BIG_PAGE), offset: '0' });
  const items = [...first.data.items];
  const total = Math.min(first.data.total, MAX_STRATEGIES);
  for (let offset = BIG_PAGE; offset < total; offset += BIG_PAGE) {
    const next = await strategyApi<LeaderboardData>('leaderboard', { ...q, sort: sort.value, limit: String(BIG_PAGE), offset: String(offset) });
    items.push(...next.data.items);
  }
  const keep = items.filter(r => {
    const trees = r.talentLabel.split('、');
    return extra.every(t => trees.includes(t));
  });
  return { ...first, data: { ...first.data, items: keep, total: keep.length } };
}

function filterQuery(): Query {
  return { stage: stage.value, minCount: String(minCount.value), tags: tagList('in'), excludeTags: tagList('out') };
}

let generation = 0;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
const retrying = ref(false);
// Query the visible results belong to, so a failed refresh can say they are older.
const shownFor = ref('');
const query = computed(() => JSON.stringify([stage.value, timemark.value, sort.value, minCount.value, picks, mechPicks, page.value]));
// True when the whole filtered list was fetched and pages are cut locally.
const localPages = ref(false);

async function load() {
  if (!stage.value) {
    loading.value = false;
    return;
  }
  const gen = ++generation;
  const forQuery = query.value;
  loading.value = true;
  if (retryTimer) clearTimeout(retryTimer);
  try {
    const q = filterQuery();
    const extra = mechIn.value.slice(1);
    const [b, t, base] = await Promise.all([
      extra.length
        ? loadAll(q, extra)
        : strategyApi<LeaderboardData>('leaderboard', { ...q, sort: sort.value, limit: String(PAGE_SIZE), offset: String((page.value - 1) * PAGE_SIZE) }),
      strategyApi<TagsData>('tags', q),
      strategyApi<TagsData>('tags', { stage: stage.value, minCount: String(minCount.value) }),
    ]);
    if (gen !== generation) return;
    localPages.value = extra.length > 0;
    error.value = '';
    retrying.value = false;
    shownFor.value = forQuery;
    board.value = b.data;
    tags.value = t.data;
    baseTags.value = base.data;
    seasonId.value = b.data.seasonId;
    stale.value = b.stale || t.stale;
    fetchedAt.value = Math.min(b.fetchedAt, t.fetchedAt);
    void nameCostItems(t.data);
    void loadKits(visibleItems.value, stage.value);
  } catch (e) {
    if (gen !== generation) return;
    error.value = String(e);
    // The server often sheds load for a moment; try once more before giving up.
    if (!retrying.value) {
      retrying.value = true;
      retryTimer = setTimeout(() => { if (gen === generation) void load(); }, 4000);
    } else {
      retrying.value = false;
    }
  } finally {
    if (gen === generation) loading.value = false;
  }
}

async function loadStages() {
  try {
    const r = await strategyApi<StageOptions>('stage-options');
    stages.value = r.data.options.map(o => o.value);
    seasonId.value = r.data.seasonId;
    const latest = [...stages.value].reverse().find(s => s.startsWith('week')) ?? stages.value[stages.value.length - 1];
    stage.value = latest ?? 'legacy';
  } catch (e) {
    error.value = String(e);
  }
}

async function nameCostItems(t: TagsData) {
  const ids = [...new Set([...(t.filters.costItem?.items ?? []).map(i => i.key), ...Object.keys(picks)])];
  const info = await itemInfo(ids);
  const m = new Map(itemNames.value);
  ids.forEach(id => m.set(id, info.get(id)?.name || `Item ${id}`));
  itemNames.value = m;
}

// Compasses and astrolabes a strategy uses in at least half of its maps.
async function loadKits(items: StrategyRow[], st: string) {
  for (const row of items) {
    if (kits.has(`${st}:${row.key}`)) continue;
    const d = await fetchDetail(st, row.key);
    if (!d || st !== stage.value) continue;
    const info = await itemInfo(d.items.cost.map(c => c.id));
    const used = d.items.cost
      .filter(c => c.quantity >= d.strategy.count / 2)
      .sort((a, b) => b.quantity - a.quantity)
      .map(c => {
        const name = info.get(c.id)?.name || `Item ${c.id}`;
        return { id: c.id, name, kind: itemKind(name) };
      });
    kits.set(`${st}:${row.key}`, used.filter((u): u is { id: string; name: string; kind: 'compass' | 'astrolabe' } => u.kind !== 'other'));
  }
}

function slotsFor(key: string) {
  const kit = kits.get(`${stage.value}:${key}`);
  const fill = (kind: 'compass' | 'astrolabe', n: number) => {
    const got = (kit ?? []).filter(k => k.kind === kind).slice(0, n);
    return Array.from({ length: n }, (_, i) => got[i]
      ? { ...got[i] }
      : { id: '', name: kit ? `No ${kind}` : 'Loading…', kind });
  };
  return [...fill('compass', COMPASS_SLOTS), ...fill('astrolabe', ASTROLABE_SLOTS)];
}

const visibleItems = computed(() => {
  const items = board.value?.items ?? [];
  return localPages.value ? items.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE) : items;
});

const rows = computed(() => {
  const items = visibleItems.value;
  const top = Math.max(1, ...items.map(r => r.avgEfficiency));
  return items.map(r => {
    const slots = slotsFor(r.key);
    const used = slots.filter(s => s.id).map(s => s.name);
    return {
      raw: r,
      key: r.key,
      rank: r.rank,
      title: treeList(r.talentLabel) || 'No main talent',
      area: areaName(r.mapLabel),
      time: timeName(r.timeLabel),
      slots,
      slotsLabel: used.length ? used.join(', ') : 'No compasses or astrolabes',
      perHour: fmtValue(r.avgEfficiency * 60),
      rateBar: Math.round((r.avgEfficiency / top) * 100) + '%',
      maps: r.count,
      perMap: '+' + Math.round(r.avgEarnings),
      dur: fmtDur(r.avgDuration / 1000),
    };
  });
});

const pages = computed(() => Math.max(1, Math.ceil((board.value?.total ?? 0) / PAGE_SIZE)));

const itemName = (key: string) => itemNames.value.get(key) ?? `Item ${key}`;

const itemGroups = computed(() => {
  const q = itemQuery.value.trim().toLowerCase();
  const items: FilterItem[] = [...(tags.value?.filters.costItem?.items ?? [])];
  // Keep picked items visible even when the current filters leave them no maps.
  Object.keys(picks).forEach(key => {
    if (!items.some(i => i.key === key)) items.push({ key, label: key, count: 0, strategyCount: 0, hotRate: 0 });
  });
  return GROUPS.map(g => {
    const all = items
      .filter(i => itemNames.value.has(i.key) && itemKind(itemName(i.key)) === g.kind)
      .map(i => ({ key: i.key, label: itemName(i.key), share: i.hotRate || 0, state: picks[i.key] ?? '' }));
    const matches = all.filter(v => !q || v.label.toLowerCase().includes(q));
    const limit = q || expanded.has(g.kind) ? matches.length : ITEM_ROWS;
    const values = matches.filter((v, i) => i < limit || v.state);
    return { ...g, total: all.length, values, hidden: matches.length - values.length, picked: all.filter(v => v.state).length };
  });
});

const timemarks = computed(() => {
  const items = baseTags.value?.filters.timeIndex?.items ?? [];
  return TIMEMARKS.map(t => {
    const hit = items.find(i => i.key === t.key);
    const share = t.key === '' ? '' : hit ? `${hit.hotRate.toFixed(1)}%` : baseTags.value ? 'no data' : '';
    return { ...t, share, disabled: t.key !== '' && !!baseTags.value && !hit && timemark.value !== t.key };
  });
});

const timemarkLabel = computed(() => TIMEMARKS.find(t => t.key === timemark.value)?.label ?? 'All');
const heading = computed(() => (timemark.value ? `${timemarkLabel.value} strategies` : 'All strategies'));

const mechanics = computed(() => {
  const f = tags.value?.filters;
  // Every strategy has one timemark, so their counts add up to the strategies in view.
  const total = (f?.timeIndex?.items ?? []).reduce((sum, i) => sum + (i.strategyCount || 0), 0) || 1;
  const counts = new Map<string, number>();
  (f?.mainTalentCluster?.items ?? []).forEach(i => {
    const tree = i.key.split('|')[0];
    counts.set(tree, (counts.get(tree) ?? 0) + (i.strategyCount || 0));
  });
  Object.keys(mechPicks).forEach(tree => { if (!counts.has(tree)) counts.set(tree, 0); });
  const q = itemQuery.value.trim().toLowerCase();
  const all = [...counts]
    .filter(([tree]) => tree !== PROFOUND && TREES[tree])
    .map(([tree, n]) => ({ key: tree, label: treeName(tree), share: (n / total) * 100, state: mechPicks[tree] ?? '' }))
    .sort((a, b) => b.share - a.share);
  const matches = all.filter(v => !q || v.label.toLowerCase().includes(q));
  const limit = q || expanded.has('mechanic') ? matches.length : ITEM_ROWS;
  const values = matches.filter((v, i) => i < limit || v.state);
  return { total: all.length, values, hidden: matches.length - values.length, picked: all.filter(v => v.state).length };
});

const active = computed(() => [
  ...Object.entries(mechPicks).map(([key, state]) => ({ key, state, label: treeName(key), mech: true })),
  ...Object.entries(picks).map(([key, state]) => ({ key, state, label: itemName(key), mech: false })),
]);

function toggleMech(tree: string, state: State) {
  if (mechPicks[tree] === state) delete mechPicks[tree];
  else mechPicks[tree] = state;
}

function toggle(key: string, state: State) {
  if (picks[key] === state) delete picks[key];
  else picks[key] = state;
}

function clearFilters() {
  Object.keys(picks).forEach(k => delete picks[k]);
  Object.keys(mechPicks).forEach(k => delete mechPicks[k]);
}

function loadClosed(): Section[] {
  try {
    const v = JSON.parse(localStorage.getItem(CLOSED_KEY) ?? '[]');
    return Array.isArray(v) ? v.filter((x): x is Section => ['timemark', 'mechanic', 'compass', 'astrolabe'].includes(x)) : [];
  } catch {
    return [];
  }
}

const isOpen = (section: Section) => !closed.has(section);

function toggleSection(section: Section) {
  if (closed.has(section)) closed.delete(section);
  else closed.add(section);
  try {
    localStorage.setItem(CLOSED_KEY, JSON.stringify([...closed]));
  } catch {
    // Remembering collapsed sections is a convenience; ignore storage errors.
  }
}

let debounce: ReturnType<typeof setTimeout> | null = null;
function scheduleLoad() {
  if (debounce) clearTimeout(debounce);
  retrying.value = false;
  loading.value = true;
  debounce = setTimeout(load, 250);
}

watch([stage, timemark, sort, minCount, () => JSON.stringify(picks), () => JSON.stringify(mechPicks)], () => {
  if (!Number.isFinite(minCount.value) || minCount.value < 1) minCount.value = 1;
  page.value = 1;
  scheduleLoad();
});
watch(page, () => {
  if (!localPages.value) return scheduleLoad();
  shownFor.value = query.value;
  void loadKits(visibleItems.value, stage.value);
});

let ticker: ReturnType<typeof setInterval> | null = null;
onMounted(async () => {
  ticker = setInterval(() => { now.value = Date.now(); }, 30_000);
  await loadStages();
});
onUnmounted(() => {
  if (ticker) clearInterval(ticker);
  if (debounce) clearTimeout(debounce);
  if (retryTimer) clearTimeout(retryTimer);
});
</script>

<style scoped>
.st { flex: 1; min-height: 0; display: flex; }
.st-filters { width: 310px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid var(--line); }
.st-side { flex: 1; min-height: 0; padding: 12px; display: flex; flex-direction: column; gap: 14px; }
.st-sec { display: flex; flex-direction: column; gap: 6px; }
.st-sec-head { display: flex; align-items: center; gap: 6px; width: 100%; padding: 0; background: none; border: none; cursor: pointer; color: var(--label); text-align: left; }
.st-sec-head .chev { flex-shrink: 0; transition: transform 0.15s; }
.st-sec-head .chev.shut { transform: rotate(-90deg); }
.st-sec-head .picked { margin-left: auto; font-size: 10.5px; font-weight: 600; color: var(--accent-text); }
.st-sec-head .note { margin-left: auto; font-size: 10px; color: var(--faint); }
.st-pair { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 10px; }
.st-pair .dash-seg button { flex: 1; white-space: nowrap; }
.st-side .ctl { font-size: 11px; color: var(--muted); }
.st-failed { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; padding: 6px 10px; border-radius: 8px; font-size: 11px; color: var(--gold); background: rgba(217,119,6,0.08); border: 1px solid rgba(217,119,6,0.35); }
.st-failed .st-link { padding: 0; }
.none { font-size: 11px; color: var(--faint); padding: 2px 6px; }
.st-value { position: relative; display: flex; align-items: center; gap: 6px; padding: 4px 6px; border-radius: 6px; overflow: hidden; cursor: pointer; background: var(--panel); border: 1px solid var(--panel-border); }
.st-value:hover { border-color: var(--accent-border); }
.st-value.in { background: var(--accent-bg); border-color: var(--accent-border); }
.st-value.out { border-color: var(--neg); }
.st-value .bar { position: absolute; left: 0; top: 0; bottom: 0; background: var(--accent-bg); opacity: 0.6; }
.st-value .tiny { position: relative; width: 20px; height: 20px; border-radius: 5px; }
.st-value .tiny img { width: 16px; height: 16px; }
.st-value .label { position: relative; flex: 1; min-width: 0; font-size: 11.5px; line-height: 1.3; color: var(--strong); overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.st-value.out .label { color: var(--faint); text-decoration: line-through; }
.st-value .share { position: relative; font-size: 10px; color: var(--label); }
.st-value .exc { position: relative; flex-shrink: 0; width: 18px; height: 18px; padding: 0; display: flex; align-items: center; justify-content: center; border-radius: 4px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.st-value .exc:hover { border-color: var(--neg); color: var(--neg); }
.st-value .exc.on { background: var(--neg); border-color: var(--neg); color: #fff; }
.st-more, .st-link { align-self: flex-start; padding: 2px 6px; font-size: 11px; background: none; border: none; color: var(--accent); cursor: pointer; }
.st-foot { padding: 10px 12px; border-top: 1px solid var(--line); font-size: 10px; line-height: 1.5; color: var(--label); }

.st-main { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.st-top { padding: 12px 16px 10px; border-bottom: 1px solid var(--line); display: flex; flex-direction: column; gap: 10px; }
.st-top .row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; font-size: 11px; color: var(--muted); }
.st-marks { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 4px; }
.st-mark { display: flex; flex-direction: column; align-items: center; gap: 1px; font-size: 12px; font-weight: 600; padding: 5px 4px; border-radius: 8px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--text); }
.st-mark .mono { font-size: 9.5px; font-weight: 500; opacity: 0.75; }
.st-mark.on { background: var(--accent-bg); border-color: var(--accent-border); color: var(--accent-text); }
.st-mark:disabled { cursor: default; opacity: 0.45; }
.ctl { display: flex; align-items: center; gap: 6px; }
.st-num { width: 46px; font-size: 12px; padding: 4px 6px; border-radius: 6px; background: var(--input); border: 1px solid var(--chip-border); color: var(--strong); text-align: center; outline: none; }
.heading { font-size: 15px; font-weight: 700; color: var(--strong); }
.sub { font-size: 11px; color: var(--label); }
.status { margin-left: auto; font-size: 10px; color: var(--label); }
.status .warn { color: var(--gold); }
.st-active { display: flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: 999px; font-size: 11px; cursor: pointer; background: var(--accent-bg); border: 1px solid var(--accent-border); color: var(--accent-text); max-width: 100%; box-sizing: border-box; white-space: nowrap; }
.st-active .txt { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.st-active.out { background: transparent; border-color: var(--neg); color: var(--neg); }

.st-progress { position: relative; height: 2px; margin-top: -1px; overflow: hidden; }
.st-progress span { position: absolute; top: 0; bottom: 0; left: 0; width: 35%; background: var(--accent); opacity: 0; transform: translateX(-100%); }
.st-progress.on span { opacity: 1; animation: st-sweep 1.1s ease-in-out infinite; }
@keyframes st-sweep { from { transform: translateX(-100%); } to { transform: translateX(290%); } }
@media (prefers-reduced-motion: reduce) { .st-progress.on span { animation: none; width: 100%; transform: none; opacity: 0.6; } }
.st-head, .st-row { display: grid; grid-template-columns: 26px minmax(0, 1fr) 120px 52px 64px 50px; gap: 10px; align-items: center; }
.st-head { padding: 8px 28px 4px; font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--label); }
.st-list { flex: 1; min-height: 0; padding: 0 16px 8px; display: flex; flex-direction: column; gap: 4px; }
.st-row { flex-shrink: 0; padding: 6px 12px; border-radius: 9px; text-align: left; font: inherit; font-size: 12px; color: var(--text); cursor: pointer; background: var(--panel); border: 1px solid var(--panel-border); }
.st-row:hover { border-color: var(--accent-border); }
.st-row .rank { font-weight: 700; color: var(--label); }
.st-row .who { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.st-row .title { font-weight: 600; color: var(--strong); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.st-row .meta { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
.st-row .tag { font-size: 10px; padding: 0 6px; border-radius: 999px; background: rgba(217,119,6,0.12); color: var(--gold); }
.st-row .tag.time { background: var(--chip); color: var(--muted); }
.slots { display: flex; gap: 3px; margin-left: 4px; }
.slot { width: 20px; height: 20px; box-sizing: border-box; border-radius: 5px; display: flex; align-items: center; justify-content: center; overflow: hidden; }
.slot img { width: 16px; height: 16px; object-fit: contain; }
.slot.compass { background: rgba(217,119,6,0.14); border: 1px solid rgba(217,119,6,0.45); }
.slot.astrolabe { background: rgba(139,92,246,0.14); border: 1px solid rgba(139,92,246,0.45); }
.slot.empty { background: transparent; border: 1px dashed var(--chip-border); }
.slot.gap { margin-left: 5px; }
.st-row .rate { display: flex; align-items: center; gap: 6px; }
.st-row .track { flex: 1; height: 5px; border-radius: 3px; background: var(--chip-border); overflow: hidden; }
.st-row .track span { display: block; height: 100%; background: var(--accent); }
.st-row .rate .mono { width: 42px; text-align: right; font-size: 11px; font-weight: 700; }
.r { text-align: right; }
.strong { font-weight: 700; }
.faint { color: var(--faint); }
.retry { margin: 10px auto 0; }
.st-pager { display: flex; justify-content: flex-end; align-items: center; gap: 8px; padding: 8px 16px 12px; font-size: 11px; color: var(--muted); }
.st-pager button:disabled { opacity: 0.45; cursor: default; }
</style>
