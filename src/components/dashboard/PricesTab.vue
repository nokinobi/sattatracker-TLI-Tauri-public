<template>
  <div class="pr">
    <nav class="pr-groups" aria-label="Main types">
      <div class="dash-label pr-groups-title">Main type</div>
      <div class="pr-group-list dash-scroll">
        <button
          v-for="g in groups"
          :key="g.id"
          :class="['pr-group', { on: group === g.id }]"
          @click="selectGroup(g.id)"
        >
          <span>{{ g.label }}</span>
          <span class="mono n">{{ g.count.toLocaleString() }}</span>
        </button>
      </div>
      <div class="pr-status">
        <span :class="['line', status.fresh ? 'ok' : 'warn']"><span class="dot"></span>{{ status.text }}</span>
        <span v-if="status.next" class="line">{{ status.next }}</span>
      </div>
    </nav>

    <section class="pr-main">
      <div class="pr-top">
        <div class="pr-title-row">
          <div>
            <div class="pr-title">
              <span :class="{ dim: type !== 'all' }">{{ groupLabel }}</span>
              <template v-if="type !== 'all'"><span class="slash">/</span><span>{{ type }}</span></template>
            </div>
            <div class="pr-sub">{{ subtitle }}</div>
          </div>
          <label class="dash-input pr-search">
            <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.5" fill="none" stroke="var(--label)" stroke-width="1.5"/><path d="M10.5 10.5L14 14" stroke="var(--label)" stroke-width="1.5" stroke-linecap="round"/></svg>
            <input v-model="query" :placeholder="`Search in ${type !== 'all' ? type : groupLabel}`" aria-label="Search prices" />
          </label>
        </div>

        <div v-if="group !== 'all'" class="chips" role="group" aria-label="Sub type">
          <button :class="['dash-chip', { on: type === 'all' }]" @click="type = 'all'">All<span class="n">{{ inGroup.length }}</span></button>
          <button v-for="t in subTypes" :key="t.type" :class="['dash-chip', { on: type === t.type }]" @click="type = t.type">
            {{ t.type }}<span class="n">{{ t.count }}</span>
          </button>
        </div>

        <div class="pr-filters">
          <span>Price</span>
          <input v-model.number="minPrice" class="pr-num mono" type="number" min="0" placeholder="min" aria-label="Minimum price" />
          <span>–</span>
          <input v-model.number="maxPrice" class="pr-num mono" type="number" min="0" placeholder="max" aria-label="Maximum price" />
          <div class="dash-seg" role="group" aria-label="Show items">
            <button :class="{ on: blockedFilter === 'all' }" @click="blockedFilter = 'all'">All</button>
            <button :class="{ on: blockedFilter === 'counted' }" @click="blockedFilter = 'counted'">Counted</button>
            <button :class="{ on: blockedFilter === 'blocked' }" @click="blockedFilter = 'blocked'">Blocked</button>
            <button :class="{ on: blockedFilter === 'manual' }" @click="blockedFilter = 'manual'">Manual {{ manualCount }}</button>
          </div>
        </div>
      </div>

      <div class="pr-head">
        <span></span>
        <SortHead label="Item" :active="sort.key.value === 'name'" :dir="sort.dir.value" @sort="sort.toggle('name')" />
        <SortHead class="r" label="Price" :active="sort.key.value === 'price'" :dir="sort.dir.value" @sort="sort.toggle('price')" />
        <SortHead class="r" label="In bag" :active="sort.key.value === 'bag'" :dir="sort.dir.value" @sort="sort.toggle('bag')" />
        <span></span>
      </div>
      <div class="pr-list dash-scroll">
        <div v-if="loading && prices.length === 0" class="dash-empty">Loading prices…</div>
        <div v-else-if="visible.length === 0" class="dash-empty">{{ blockedFilter === 'manual' ? 'No manual prices right now' : 'No prices match' }}</div>
        <div v-for="p in visible" :key="p.item_id" :class="['pr-item', { owned: p.owned > 0, blocked: p.blocked, manual: p.manual || editing === p.item_id }]">
          <div class="pr-row">
            <span class="dash-icon"><img :src="getIcon(p.item_id)" alt="" loading="lazy" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
            <span class="name">
              <span>{{ p.item_name }}</span>
              <small>{{ p.group }} · {{ p.item_type || 'Unknown type' }}{{ p.blocked ? ' · blocked' : '' }}<template v-if="p.manual"> · <b>Manual price · {{ fmtLeft(p.override_until_ms! - now) }}</b></template></small>
            </span>
            <span class="price">
              <span :class="['mono', 'r', 'strong', p.manual ? 'accent' : 'gold']">{{ fmtPrice(p.price) }}</span>
              <small v-if="p.manual" class="mono market" title="Market price">{{ p.market_price > 0 ? fmtPrice(p.market_price) : 'no price' }}</small>
            </span>
            <span class="mono r" :class="p.owned ? '' : 'faint'">{{ p.owned ? 'x' + p.owned.toLocaleString() : '—' }}</span>
            <button v-if="p.manual" class="dash-btn small act danger" :aria-label="`Reset the price of ${p.item_name}`" @click="resetOverride(p.item_id)">Reset</button>
            <button v-else-if="!p.blocked" class="dash-btn small act" :aria-expanded="editing === p.item_id" :aria-label="`Set a price for ${p.item_name}`" @click="openEditor(p)">Set price</button>
          </div>
          <form v-if="editing === p.item_id" class="pr-edit" @submit.prevent="applyOverride(p.item_id)" @keydown.esc.stop="editing = null">
            <label class="fld">Price
              <input ref="priceInput" v-model="editPrice" class="pr-num mono big" type="text" inputmode="decimal" maxlength="12" aria-label="Manual price in FE" @focus="($event.target as HTMLInputElement).select()" /> FE
            </label>
            <span>for</span>
            <div class="dash-seg" role="group" aria-label="Duration">
              <button v-for="d in DURATIONS" :key="d.minutes" type="button" :class="{ on: !editHours && editMinutes === d.minutes }" :aria-pressed="!editHours && editMinutes === d.minutes" @click="editMinutes = d.minutes; editHours = ''">{{ d.label }}</button>
            </div>
            <label class="fld">or
              <input v-model="editHours" class="pr-num mono hours" type="text" inputmode="decimal" maxlength="5" placeholder="2.5" aria-label="Custom duration in hours" /> h
            </label>
            <button class="dash-btn small primary push" type="submit">Apply</button>
            <button class="dash-btn small" type="button" @click="editing = null">Cancel</button>
            <span v-if="editError" class="err" role="alert">{{ editError }}</span>
            <span class="hint">Used for new drops and your bag value until the time runs out, then the market price is back. Drops already recorded keep their value.</span>
          </form>
        </div>
        <button v-if="filtered.length > visible.length" class="dash-btn pr-more" @click="limit += PAGE">
          Show {{ Math.min(PAGE, filtered.length - visible.length) }} more of {{ filtered.length - visible.length }}
        </button>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { invoke } from '@tauri-apps/api/core';
import { useTrackerStore } from '../../stores/trackerStore';
import { getIcon } from '../../utils/assets';
import { PRICE_GROUPS, priceGroup, type PriceGroup } from './categories';
import { fmtAgo, fmtLeft, fmtPrice, parseDecimal } from './format';
import SortHead from './SortHead.vue';
import { sortedBy, useSort } from './useSort';

interface PriceEntry {
  item_id: string;
  item_name: string;
  item_type: string;
  // The price in use: the manual one while it runs.
  price: number;
  market_price: number;
  override_until_ms: number | null;
}
interface PriceStatus { count: number; last_refresh_ms: number }

const store = useTrackerStore();

const PAGE = 200;
const DURATIONS = [
  { label: '30 min', minutes: 30 },
  { label: '1 h', minutes: 60 },
  { label: '3 h', minutes: 180 },
  { label: '12 h', minutes: 720 },
];
const MAX_HOURS = 7 * 24;
const prices = ref<PriceEntry[]>([]);
const priceStatus = ref<PriceStatus>({ count: 0, last_refresh_ms: 0 });
const loading = ref(true);
const now = ref(Date.now());

const group = ref<PriceGroup | 'all'>('all');
const type = ref('all');
const query = ref('');
const minPrice = ref<number | ''>('');
const maxPrice = ref<number | ''>('');
const blockedFilter = ref<'all' | 'counted' | 'blocked' | 'manual'>('all');
const sort = useSort('prices', { name: 'asc', price: 'desc', bag: 'desc' }, 'price');
const limit = ref(PAGE);

async function load() {
  try {
    const [list, status] = await Promise.all([
      invoke<PriceEntry[]>('get_all_prices'),
      invoke<PriceStatus>('get_price_status'),
    ]);
    prices.value = list;
    priceStatus.value = status;
  } catch (e) {
    console.error('Failed to load prices', e);
  } finally {
    loading.value = false;
    now.value = Date.now();
  }
}

// The item whose price is being set, and the editor's fields.
const editing = ref<string | null>(null);
const editPrice = ref('');
const editMinutes = ref(60);
const editHours = ref('');
const editError = ref('');
const priceInput = ref<HTMLInputElement[] | HTMLInputElement | null>(null);

function openEditor(p: { item_id: string; price: number }) {
  editing.value = p.item_id;
  editPrice.value = String(Math.round(p.price * 100) / 100);
  editMinutes.value = 60;
  editHours.value = '';
  editError.value = '';
  void nextTick(() => {
    const el = Array.isArray(priceInput.value) ? priceInput.value[0] : priceInput.value;
    el?.focus();
  });
}

async function applyOverride(itemId: string) {
  const price = parseDecimal(editPrice.value);
  if (price === null || price <= 0) {
    editError.value = 'Enter a price above 0, like 1500 or 1.5.';
    return;
  }
  let minutes = editMinutes.value;
  if (editHours.value.trim()) {
    const hours = parseDecimal(editHours.value);
    if (hours === null || hours <= 0 || hours > MAX_HOURS) {
      editError.value = `Enter a time up to ${MAX_HOURS} hours (7 days).`;
      return;
    }
    minutes = Math.max(1, Math.round(hours * 60));
  }
  try {
    await invoke('set_price_override', { itemId, price, minutes });
    editing.value = null;
    await load();
  } catch (e) {
    editError.value = String(e);
  }
}

async function resetOverride(itemId: string) {
  try {
    await invoke('clear_price_override', { itemId });
  } catch (e) {
    console.error('Failed to reset the price', e);
  }
  await load();
}

let timer: ReturnType<typeof setInterval> | null = null;
let ticker: ReturnType<typeof setInterval> | null = null;
onMounted(() => {
  void load();
  timer = setInterval(load, 60_000);
  // Keeps "N min left" moving and ends a manual price on time between price reloads.
  ticker = setInterval(() => { now.value = Date.now(); }, 15_000);
});
onUnmounted(() => {
  if (timer) clearInterval(timer);
  if (ticker) clearInterval(ticker);
});

const owned = computed(() => {
  const m = new Map<string, number>();
  store.inventoryItems.forEach(i => m.set(i.item_id, (m.get(i.item_id) ?? 0) + i.qty));
  return m;
});

const enriched = computed(() =>
  prices.value.map(p => {
    const manual = p.override_until_ms !== null && p.override_until_ms > now.value;
    return {
      ...p,
      // A manual price that ended since the last reload is already gone in the backend.
      price: manual ? p.price : p.market_price,
      group: priceGroup(p.item_type),
      owned: owned.value.get(p.item_id) ?? 0,
      blocked: store.isBlocked(p.item_id),
      manual,
    };
  }),
);

const manualCount = computed(() => enriched.value.filter(p => p.manual).length);

const groups = computed(() => [
  { id: 'all' as const, label: 'All prices', count: enriched.value.length },
  ...PRICE_GROUPS.map(g => ({ id: g, label: g, count: enriched.value.filter(p => p.group === g).length })),
]);

const groupLabel = computed(() => (group.value === 'all' ? 'All prices' : group.value));

const inGroup = computed(() =>
  group.value === 'all' ? enriched.value : enriched.value.filter(p => p.group === group.value),
);

const subTypes = computed(() => {
  const counts = new Map<string, number>();
  inGroup.value.forEach(p => counts.set(p.item_type || 'Unknown type', (counts.get(p.item_type || 'Unknown type') ?? 0) + 1));
  return [...counts.entries()].map(([t, count]) => ({ type: t, count })).sort((a, b) => b.count - a.count);
});

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  const lo = typeof minPrice.value === 'number' ? minPrice.value : null;
  const hi = typeof maxPrice.value === 'number' ? maxPrice.value : null;
  const list = inGroup.value.filter(p =>
    (type.value === 'all' || (p.item_type || 'Unknown type') === type.value)
    && (!q || p.item_name.toLowerCase().includes(q))
    && (lo === null || p.price >= lo)
    && (hi === null || p.price <= hi)
    && (blockedFilter.value === 'all'
      || (blockedFilter.value === 'manual' ? p.manual : (blockedFilter.value === 'blocked') === p.blocked)),
  );
  const by = sort.key.value;
  return sortedBy(list, p => (by === 'name' ? p.item_name : by === 'bag' ? p.owned : p.price), sort.dir.value);
});

const visible = computed(() => filtered.value.slice(0, limit.value));

const subtitle = computed(() => {
  const list = filtered.value;
  if (!list.length) return 'No items';
  const ps = list.map(p => p.price);
  const inBag = list.filter(p => p.owned > 0).length;
  return `${list.length.toLocaleString()} items · ${inBag} in your bag · ${fmtPrice(Math.min(...ps))} – ${fmtPrice(Math.max(...ps))} FE`;
});

const status = computed(() => {
  const s = priceStatus.value;
  if (!s.last_refresh_ms) {
    return { fresh: false, text: `Using saved prices (${s.count.toLocaleString()})`, next: 'Refreshes every 10 min while tracking' };
  }
  const nextMin = Math.max(0, 10 - Math.floor((now.value - s.last_refresh_ms) / 60000));
  return { fresh: true, text: `Prices updated ${fmtAgo(s.last_refresh_ms, now.value)}`, next: `Next refresh in about ${nextMin} min` };
});

function selectGroup(id: PriceGroup | 'all') {
  group.value = id;
  type.value = 'all';
}

watch([group, type, query, minPrice, maxPrice, blockedFilter, sort.key, sort.dir], () => { limit.value = PAGE; });
</script>

<style scoped>
.pr { flex: 1; min-height: 0; display: flex; }
.pr-groups { width: 200px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid var(--line); }
.pr-groups-title { padding: 12px 18px 4px; }
.pr-group-list { flex: 1; min-height: 0; padding: 4px 8px 10px; display: flex; flex-direction: column; gap: 2px; }
.pr-group { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 9px 10px; border-radius: 9px; border: none; background: transparent; color: var(--muted); font-size: 12px; font-weight: 600; cursor: pointer; text-align: left; }
.pr-group:hover { color: var(--strong); }
.pr-group.on { background: var(--chip); color: var(--strong); box-shadow: inset 2px 0 0 var(--accent); }
.pr-group .n { font-size: 10px; font-weight: 500; color: var(--label); }
.pr-status { padding: 12px; font-size: 10px; line-height: 1.6; color: var(--label); border-top: 1px solid var(--line); display: flex; flex-direction: column; }
.pr-status .line { display: flex; align-items: center; gap: 6px; }
.pr-status .ok { color: var(--live-text); font-weight: 600; }
.pr-status .warn { color: var(--gold); font-weight: 600; }
.pr-status .dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
.pr-status .line:not(.ok):not(.warn) .dot { display: none; }

.pr-main { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.pr-top { padding: 14px 18px 12px; display: flex; flex-direction: column; gap: 10px; border-bottom: 1px solid var(--line); }
.pr-title-row { display: flex; align-items: center; gap: 12px; }
.pr-title { display: flex; align-items: baseline; gap: 6px; font-size: 16px; font-weight: 700; color: var(--strong); }
.pr-title .dim { color: var(--muted); }
.pr-title .slash { color: var(--faint); font-size: 14px; }
.pr-sub { font-size: 11px; color: var(--label); }
.pr-search { margin-left: auto; width: 240px; }
.chips { display: flex; gap: 4px; flex-wrap: wrap; }
.pr-filters { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--muted); }
.pr-num { width: 64px; font-size: 11px; padding: 4px 8px; border-radius: 6px; background: var(--input); border: 1px solid var(--chip-border); color: var(--text); outline: none; }
.pr-filters .dash-seg { margin-left: 10px; }

.pr-head, .pr-row { display: grid; grid-template-columns: 30px minmax(0, 1fr) 100px 60px 76px; gap: 12px; align-items: center; }
.pr-head { padding: 8px 30px 4px; font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--label); }
.pr-list { flex: 1; min-height: 0; padding: 0 18px 14px; display: flex; flex-direction: column; gap: 4px; }
.pr-item { flex-shrink: 0; padding: 5px 12px; border-radius: 9px; background: var(--panel); border: 1px solid var(--panel-border); font-size: 12px; }
.pr-item.owned, .pr-item.manual { border-color: var(--accent-border); }
.pr-item.blocked { opacity: 0.55; }
.pr-row .name { min-width: 0; display: flex; flex-direction: column; font-weight: 600; color: var(--strong); }
.pr-row .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pr-row .name small { font-size: 10px; font-weight: 400; color: var(--label); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pr-row .name small b { font-weight: 600; color: var(--accent-text); }
.pr-row .price { display: flex; flex-direction: column; align-items: flex-end; }
.pr-row .price .accent { color: var(--accent-text); }
.pr-row .market { font-size: 10px; color: var(--faint); text-decoration: line-through; }
.pr-row .act { justify-self: end; align-self: center; }
.pr-edit { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; margin-top: 8px; padding: 8px 0 3px 42px; border-top: 1px solid var(--line); font-size: 11px; color: var(--muted); }
.pr-edit .fld { display: flex; align-items: center; gap: 6px; }
.pr-edit .big { width: 76px; font-size: 12px; font-weight: 600; text-align: right; color: var(--strong); border-color: var(--accent-border); }
.pr-edit .hours { width: 46px; text-align: right; }
.pr-edit .push { margin-left: auto; }
.pr-edit .dash-btn { align-self: center; }
.pr-edit .err { flex-basis: 100%; color: var(--neg); font-weight: 600; }
.pr-edit .hint { flex-basis: 100%; font-size: 10px; color: var(--label); }
.r { text-align: right; }
.strong { font-weight: 700; font-size: 13px; }
.faint { color: var(--faint); }
.pr-more { align-self: center; margin-top: 6px; }
</style>
