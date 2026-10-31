<template>
  <div class="sd">
    <div class="sd-top">
      <div class="crumbs">
        <button class="sd-back" @click="$emit('back')">← Strategies</button>
        <span class="faint">#{{ row.rank }} · {{ stageName(stage) }}</span>
      </div>
      <div class="title-row">
        <h2>{{ title }}</h2>
        <span class="muted">{{ place }}</span>
        <button
          :class="['dash-btn', 'sd-fav', { on: !!fav }]"
          :aria-pressed="!!fav"
          :disabled="!fav && (favoritesFull || !seasonId)"
          :title="!fav && favoritesFull ? 'Favorites are full' : !fav && !seasonId ? 'Loading the season…' : ''"
          @click="toggleFavorite(row, stage, seasonId)"
        >
          <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.5l1.9 4.1 4.4.5-3.3 3 .9 4.4L8 11.3l-3.9 2.2.9-4.4-3.3-3 4.4-.5z" /></svg>
          {{ fav ? 'In favorites' : 'Save to favorites' }}
        </button>
        <div class="dash-seg sd-views" role="group" aria-label="Detail view">
          <button :class="{ on: view === 'loot' }" @click="view = 'loot'">Loot & cost</button>
          <button :class="{ on: view === 'talents' }" @click="view = 'talents'">Talent trees</button>
        </div>
      </div>
      <div class="strip">
        <div class="stat">
          <div class="dash-label">Profit per hour · today's prices</div>
          <div :class="['mono', 'val', perHourNow >= 0 ? 'pos' : 'neg']">{{ detail ? fmtInt(perHourNow) : '…' }}</div>
          <div v-if="detail" class="sub">
            <span :class="change >= 0 ? 'pos' : 'neg'">{{ fmtChange(change) }}</span> vs reported {{ fmtInt(perHourReported) }}
            <template v-if="excludedRows.length"> · <b class="without">without {{ excludedLabel }}</b></template>
          </div>
        </div>
        <div class="stat">
          <div class="dash-label">Maps run</div>
          <div class="mono val">{{ row.count }}</div>
        </div>
        <div class="stat">
          <div class="dash-label">Avg map time</div>
          <div class="mono val">{{ fmtDur(row.avgDuration / 1000) }}</div>
        </div>
      </div>
      <div class="kit">
        <div v-for="g in kitGroups" :key="g.kind" class="kit-group">
          <span class="dash-label">{{ g.title }}</span>
          <span class="slots" :aria-label="g.label">
            <span v-for="(s, i) in g.slots" :key="i" :class="['slot', g.kind, { empty: !s.id }]" :title="s.name">
              <img v-if="s.id" :src="getIcon(s.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" />
            </span>
          </span>
          <span class="kit-names">{{ g.label }}</span>
        </div>
      </div>
      <div class="tags">
        <span v-for="t in tagChips" :key="t.kind + t.label" :class="['tag', t.kind]">{{ t.label }}</span>
      </div>
      <label v-if="fav" class="sd-note">
        <span class="dash-label">Your note</span>
        <textarea
          :value="fav.note"
          :maxlength="NOTE_MAX"
          rows="2"
          placeholder="Why you saved it, what to try, how it went…"
          @input="onNote"
        ></textarea>
        <span class="faint">Saved {{ savedText }} · from {{ stageName(fav.stage) }}</span>
      </label>
    </div>

    <div v-if="!detail" class="dash-empty">{{ !failed ? 'Loading strategy…' : fav ? "The server has no details for this strategy any more (it may be from an older period or season). Your note and the numbers saved with it are kept." : "Couldn't load this strategy. Try again in a minute." }}</div>
    <div v-else-if="view === 'talents'" class="sd-trees dash-scroll">
      <TalentTrees :talents="detail.talents" />
    </div>
    <div v-else class="sd-body">
      <div class="sd-side dash-scroll">
        <div class="today">
          <div class="dash-label accent">Same run at today's prices</div>
          <div class="line"><span>Loot per map</span><span class="mono gold">{{ fmtFE(perMap.gross) }}</span></div>
          <div v-if="excludedRows.length" class="line without">
            <span>Without {{ excludedLabel }} <button class="sd-link" @click="clearExcluded">Count all</button></span>
            <span class="mono">{{ fmtFE(-excludedValue) }}</span>
          </div>
          <div class="line"><span>Cost per map</span><span class="mono neg">{{ fmtFE(-perMap.cost) }}</span></div>
          <div class="rule"></div>
          <div class="line total">
            <span>Profit per map <span class="hint">(loot − cost)</span></span>
            <span :class="['mono', perMap.profit >= 0 ? 'pos' : 'neg']">{{ fmtFE(perMap.profit) }}</span>
          </div>
          <div class="line total">
            <span>Profit per hour</span>
            <span :class="['mono', perHourNow >= 0 ? 'pos' : 'neg']">{{ fmtInt(perHourNow) }}</span>
          </div>
          <div class="note">
            When these maps were run: {{ fmtFE(row.avgEarnings) }} per map, {{ fmtInt(perHourReported) }} per hour
            ({{ fmtChange(change) }} now). Same items, same {{ fmtDur(row.avgDuration / 1000) }} per map.
          </div>
        </div>

        <div class="list">
          <div class="col-head"><span class="dash-label">Cost per map</span><span class="dash-label">FE</span></div>
          <div v-for="c in cost" :key="c.id" class="item">
            <span class="dash-icon"><img :src="getIcon(c.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
            <span class="name"><span>{{ c.name }}</span><small>×{{ c.qty }} @ {{ c.price }}</small></span>
            <span class="mono neg strong">−{{ c.value }}</span>
          </div>
        </div>
      </div>

      <div class="sd-loot">
        <div class="loot-head">
          <span class="dash-label">Strategy loot · {{ maps }} maps</span>
          <div class="dash-seg" role="group" aria-label="Loot view">
            <button :class="{ on: lootView === 'all' }" @click="lootView = 'all'">All {{ loot.length }}</button>
            <button :class="{ on: lootView === 'rare' }" @click="lootView = 'rare'">
              <svg width="9" height="9" viewBox="0 0 12 12" aria-hidden="true"><path d="M6 1l5 5-5 5-5-5z" fill="var(--gold)"/></svg>
              Rare drops {{ rareCount }}
            </button>
            <button :class="{ on: lootView === 'excluded' }" @click="lootView = 'excluded'">Excluded {{ excludedRows.length }}</button>
          </div>
          <button v-if="lootView === 'rare' && rareCount > 0" class="dash-btn small rare-all" :disabled="!allRareOut && excludeBlocked" @click="toggleAllRare">{{ allRareOut ? 'Count all rare' : 'Exclude all rare' }}</button>
          <span class="loot-note">{{ lootView === 'rare' ? 'Lucky drops: under 1 of 5 maps' : lootView === 'excluded' ? 'Left out of the profit on the left' : 'All items dropped in these maps · FE shown per map' }}</span>
        </div>
        <div class="loot-cols">
          <span></span>
          <SortHead label="Item" :active="lootSort.key.value === 'name'" :dir="lootSort.dir.value" @sort="lootSort.toggle('name')" />
          <SortHead label="Drops" :active="lootSort.key.value === 'rate'" :dir="lootSort.dir.value" @sort="lootSort.toggle('rate')" />
          <SortHead class="r" label="Total" :active="lootSort.key.value === 'total'" :dir="lootSort.dir.value" @sort="lootSort.toggle('total')" />
          <SortHead class="r" label="FE / map" :active="lootSort.key.value === 'value'" :dir="lootSort.dir.value" @sort="lootSort.toggle('value')" />
          <span></span>
        </div>
        <div class="loot-list dash-scroll">
          <div v-if="!shownLoot.length" class="dash-empty">{{ lootView === 'excluded' ? 'Nothing excluded. Use the minus button on a loot row to leave it out of the profit.' : 'No rare drops in this strategy' }}</div>
          <div v-for="l in shownLoot" :key="l.id" :class="['loot-row', { rare: l.rare, out: excluded.has(l.id) }]">
            <span class="dash-icon"><img :src="getIcon(l.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
            <span class="name">
              <svg v-if="l.rare" width="10" height="10" viewBox="0 0 12 12" role="img" aria-label="Rare drop"><path d="M6 1l5 5-5 5-5-5z" fill="var(--gold)"/></svg>
              <span>{{ l.name }}</span>
            </span>
            <span :class="['mono', 'rate', { rare: l.rare }]">{{ l.rate }}</span>
            <span class="mono r total" :title="`${l.quantity.toLocaleString()} dropped across ${maps.toLocaleString()} maps`">×{{ l.quantity.toLocaleString() }}</span>
            <span class="mono gold strong r amount">{{ l.value }}</span>
            <button
              :class="['exc', { on: excluded.has(l.id) }]"
              :aria-pressed="excluded.has(l.id)"
              :disabled="!excluded.has(l.id) && excludeBlocked"
              :aria-label="`${excluded.has(l.id) ? 'Count in the profit again' : 'Leave out of the profit'}: ${l.name}`"
              :title="excluded.has(l.id) ? 'Count this in the profit again' : excludeBlocked ? 'Too many strategies with excluded loot' : 'Leave this out of the profit'"
              @click="toggleExcluded(l.id)"
            >
              <svg width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 6h6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
            </button>
          </div>
          <button v-if="lootView === 'all' && !allLoot && loot.length > LOOT_ROWS" class="sd-more" @click="allLoot = true">Show all {{ loot.length }} items</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { getIcon } from '../../utils/assets';
import { fmtDate, fmtDur, fmtFE, fmtPrice } from './format';
import SortHead from './SortHead.vue';
import { sortedBy, useSort } from './useSort';
import TalentTrees from './TalentTrees.vue';
import {
  areaName, fetchDetail, itemInfo, itemKind, stageName, timeName, treeList, treeName,
  type DetailData, type ItemInfo, type ItemQty, type StrategyRow,
} from './strategies/api';
import { detailView } from './strategies/state';
import { excludedFor, excludedFull, setExcluded } from './strategies/excluded';
import { NOTE_MAX, favoriteOf, favoritesFull, setNote, toggleFavorite } from './strategies/favorites';

const props = defineProps<{ row: StrategyRow; stage: string; seasonId: string }>();
defineEmits(['back']);

const LOOT_ROWS = 14;
// A map takes up to 4 compasses and 2 astrolabes.
const KIT_SLOTS = { compass: 4, astrolabe: 2 } as const;
// A "rare" drop shows up in fewer than one of five maps but is still worth something per map.
const RARE_SHARE = 0.2;
const RARE_MIN_VALUE = 0.5;

const detail = ref<DetailData | null>(null);
const failed = ref(false);
const info = ref(new Map<string, ItemInfo>());
const allLoot = ref(false);
const lootView = ref<'all' | 'rare' | 'excluded'>('all');
const lootSort = useSort('strategy-loot', { name: 'asc', rate: 'desc', total: 'desc', value: 'desc' }, 'value');
// Items left out of the profit for this strategy and period.
const excluded = ref(excludedFor(props.stage, props.row.key));
// Remembered with the rest of the Strategies tab, so a reopened detail shows the same view.
const view = detailView;

const fav = computed(() => favoriteOf(props.row.key, props.stage));
const savedText = computed(() => (fav.value?.savedAt ? fmtDate(fav.value.savedAt) : ''));

let noteTimer: ReturnType<typeof setTimeout> | null = null;
let pendingNote: string | null = null;
function flushNote() {
  if (noteTimer) clearTimeout(noteTimer);
  noteTimer = null;
  if (pendingNote !== null) setNote(props.row.key, props.stage, pendingNote);
  pendingNote = null;
}
function onNote(e: Event) {
  pendingNote = (e.target as HTMLTextAreaElement).value;
  if (noteTimer) clearTimeout(noteTimer);
  noteTimer = setTimeout(flushNote, 400);
}
onMounted(() => window.addEventListener('pagehide', flushNote));
onUnmounted(() => {
  window.removeEventListener('pagehide', flushNote);
  flushNote();
});

onMounted(async () => {
  const d = await fetchDetail(props.stage, props.row.key);
  if (!d) {
    failed.value = true;
    return;
  }
  info.value = new Map(await itemInfo([...d.items.cost, ...d.items.loot].map(i => i.id)));
  detail.value = d;
});

const title = computed(() => treeList(props.row.talentLabel) || 'No main talent');
const place = computed(() => {
  const area = areaName(props.row.mapLabel);
  const time = timeName(props.row.timeLabel);
  return !time || area === time ? area : `${area} · ${time}`;
});
const maps = computed(() => Math.max(1, detail.value?.strategy.count ?? props.row.count));

function perMapRows(list: ItemQty[]) {
  return list
    .map(i => {
      const it = info.value.get(i.id);
      const price = it?.price ?? 0;
      const perMap = i.quantity / maps.value;
      const total = perMap * price;
      return { id: i.id, name: it?.name || `Item ${i.id}`, quantity: i.quantity, perMap, price, total, rare: perMap < RARE_SHARE && total > RARE_MIN_VALUE };
    })
    .sort((a, b) => b.total - a.total || b.perMap - a.perMap)
    .map(r => ({
      ...r,
      qty: r.perMap >= 10 ? r.perMap.toFixed(0) : r.perMap.toFixed(2),
      price: r.price ? fmtPrice(r.price) : 'no price',
      value: r.total.toFixed(1),
      rate: r.perMap < 0.5 ? `1 in ${Math.round(1 / r.perMap)} maps` : `${r.perMap >= 10 ? r.perMap.toFixed(0) : r.perMap.toFixed(2)} / map`,
    }));
}

// Items used in at least 5% of maps; the rest are one-offs that clutter the list.
const cost = computed(() => perMapRows(detail.value?.items.cost ?? []).filter(c => c.perMap >= 0.05));
const loot = computed(() => perMapRows(detail.value?.items.loot ?? []));
const rareCount = computed(() => loot.value.filter(l => l.rare).length);
const excludedRows = computed(() => loot.value.filter(l => excluded.value.has(l.id)));
const excludedValue = computed(() => excludedRows.value.reduce((s, l) => s + l.total, 0));
const excludedLabel = computed(() => (excludedRows.value.length === 1 ? '1 excluded item' : `${excludedRows.value.length} excluded items`));
// A strategy with nothing excluded yet can't start a new entry when the saved list is full.
const excludeBlocked = computed(() => excludedFull.value && excluded.value.size === 0);
const allRareOut = computed(() => {
  const rare = loot.value.filter(l => l.rare);
  return rare.length > 0 && rare.every(l => excluded.value.has(l.id));
});

function saveExcluded(next: Set<string>) {
  excluded.value = setExcluded(props.stage, props.row.key, next);
}

function toggleExcluded(id: string) {
  const next = new Set(excluded.value);
  if (!next.delete(id)) next.add(id);
  saveExcluded(next);
}

function toggleAllRare() {
  const next = new Set(excluded.value);
  const rare = loot.value.filter(l => l.rare);
  if (allRareOut.value) rare.forEach(l => next.delete(l.id));
  else rare.forEach(l => next.add(l.id));
  saveExcluded(next);
}

function clearExcluded() {
  saveExcluded(new Set());
}

const shownLoot = computed(() => {
  const by = lootSort.key.value;
  const list = lootView.value === 'rare' ? loot.value.filter(l => l.rare)
    : lootView.value === 'excluded' ? excludedRows.value
      : loot.value;
  const sorted = sortedBy(list, l => (by === 'name' ? l.name : by === 'value' ? l.total : l.perMap), lootSort.dir.value);
  return lootView.value === 'all' && !allLoot.value ? sorted.slice(0, LOOT_ROWS) : sorted;
});

const perMap = computed(() => {
  const gross = loot.value.reduce((s, r) => s + r.total, 0);
  const l = gross - excludedValue.value;
  const c = perMapRows(detail.value?.items.cost ?? []).reduce((s, r) => s + r.total, 0);
  return { gross, cost: c, profit: l - c };
});

const hoursPerMap = computed(() => Math.max(1, props.row.avgDuration) / 3_600_000);
const perHourNow = computed(() => perMap.value.profit / hoursPerMap.value);
const perHourReported = computed(() => props.row.avgEfficiency * 60);
const change = computed(() => (perHourReported.value > 0 ? (perHourNow.value / perHourReported.value - 1) * 100 : 0));

function fmtInt(v: number): string {
  return Math.round(v).toLocaleString('en-US');
}

function fmtChange(pct: number): string {
  return `${pct >= 0 ? '+' : '−'}${Math.abs(pct).toFixed(1)}%`;
}

// Compasses and astrolabes used in at least half of the strategy's maps, most used first.
const kitGroups = computed(() => {
  const d = detail.value;
  const used = (d?.items.cost ?? [])
    .filter(c => c.quantity >= maps.value / 2)
    .sort((a, b) => b.quantity - a.quantity)
    .map(c => {
      const name = info.value.get(c.id)?.name || `Item ${c.id}`;
      return { id: c.id, name, kind: itemKind(name) };
    });
  return (['compass', 'astrolabe'] as const).map(kind => {
    const got = used.filter(u => u.kind === kind).slice(0, KIT_SLOTS[kind]);
    const slots = Array.from({ length: KIT_SLOTS[kind] }, (_, i) => got[i] ?? { id: '', name: d ? `No ${kind}` : 'Loading…' });
    return {
      kind,
      title: kind === 'compass' ? 'Compasses' : 'Astrolabes',
      slots,
      label: !d ? 'Loading…' : got.length ? got.map(g => g.name).join(', ') : `No ${kind}s`,
    };
  });
});

const tagChips = computed(() => {
  const chips: { kind: string; label: string }[] = [];
  (detail.value?.tags ?? []).forEach(t => {
    if (t.type === 'mainTalentCluster') {
      const [tree, points] = t.key.split('|');
      chips.push({ kind: 'talent', label: `${treeName(tree)}${points ? ' ' + points : ''}` });
    }
  });
  return chips;
});
</script>

<style scoped>
.sd { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.sd-top { padding: 12px 18px; border-bottom: 1px solid var(--line); display: flex; flex-direction: column; gap: 10px; }
.crumbs { display: flex; align-items: center; gap: 10px; font-size: 11px; }
.sd-back { padding: 0; font-size: 12px; font-weight: 600; background: none; border: none; color: var(--accent); cursor: pointer; }
.title-row { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.title-row h2 { margin: 0; font-size: 17px; font-weight: 700; color: var(--strong); }
.muted { font-size: 12px; color: var(--muted); }
.faint { color: var(--faint); }
.sd-views { margin-left: auto; }
.sd-fav { height: 28px; padding: 0 10px; font-size: 11.5px; align-self: center; }
.sd-fav svg { fill: none; stroke: currentColor; stroke-width: 1.3; stroke-linejoin: round; }
.sd-fav.on { color: var(--gold); border-color: var(--gold); }
.sd-fav.on svg { fill: currentColor; }
.sd-fav:disabled { opacity: 0.5; cursor: default; }
.sd-note { display: flex; flex-direction: column; gap: 4px; font-size: 10.5px; }
.sd-note textarea { box-sizing: border-box; width: 100%; max-width: 720px; resize: vertical; min-height: 40px; padding: 6px 8px; border-radius: 8px; font: inherit; font-size: 12px; line-height: 1.4; color: var(--strong); background: var(--input); border: 1px solid var(--chip-border); outline: none; }
.sd-note textarea:focus { border-color: var(--accent-border); }
.sd-note .faint { color: var(--faint); }
.strip { display: flex; align-items: flex-start; gap: 28px; }
.strip .val { font-size: 16px; font-weight: 700; color: var(--strong); }
.strip .val.pos { color: var(--pos); }
.strip .val.neg { color: var(--neg); }
.strip .sub { font-size: 10px; color: var(--label); }
.strip .sub .pos, .strip .sub .neg { font-weight: 600; }
.kit { display: flex; gap: 24px; flex-wrap: wrap; }
.kit-group { display: flex; align-items: center; gap: 8px; min-width: 0; }
.slots { display: flex; gap: 3px; }
.slot { width: 26px; height: 26px; box-sizing: border-box; border-radius: 6px; display: flex; align-items: center; justify-content: center; overflow: hidden; }
.slot img { width: 22px; height: 22px; object-fit: contain; }
.slot.compass { background: rgba(217,119,6,0.14); border: 1px solid rgba(217,119,6,0.45); }
.slot.astrolabe { background: rgba(139,92,246,0.14); border: 1px solid rgba(139,92,246,0.45); }
.slot.empty { background: transparent; border: 1px dashed var(--chip-border); }
.kit-names { font-size: 11px; color: var(--muted); max-width: 320px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tags { display: flex; gap: 5px; flex-wrap: wrap; }
.tag { font-size: 10.5px; padding: 1px 8px; border-radius: 999px; background: var(--chip); color: var(--muted); }
.tag.talent { background: var(--accent-bg); color: var(--accent-text); }

.sd-trees { flex: 1; min-height: 0; padding: 14px 18px; }
.sd-body { flex: 1; min-height: 0; display: grid; grid-template-columns: 330px minmax(0, 1fr); }
.sd-side { padding: 12px 16px 14px 18px; border-right: 1px solid var(--line); display: flex; flex-direction: column; gap: 12px; }
.today { padding: 10px 12px; border-radius: 12px; background: var(--accent-bg); border: 1px solid var(--accent-border); display: flex; flex-direction: column; gap: 6px; font-size: 12px; color: var(--text); }
.today .accent { color: var(--accent-text); }
.today .line { display: flex; justify-content: space-between; gap: 8px; }
.today .line .mono { font-size: 12.5px; font-weight: 700; }
.today .total { font-weight: 700; }
.today .hint { font-weight: 400; color: var(--label); }
.today .rule { height: 1px; background: var(--accent-border); }
.today .note { font-size: 10.5px; line-height: 1.4; color: var(--muted); }
.list { display: flex; flex-direction: column; gap: 5px; }
.col-head { display: flex; justify-content: space-between; }
.item { flex-shrink: 0; display: grid; grid-template-columns: 30px minmax(0, 1fr) auto; gap: 8px; align-items: center; font-size: 11.5px; }
.item .name { display: flex; flex-direction: column; min-width: 0; color: var(--strong); }
.item .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.item .name small { font-size: 10px; color: var(--label); }

.sd-loot { min-width: 0; min-height: 0; display: flex; flex-direction: column; gap: 8px; padding: 12px 18px 14px 16px; }
.loot-head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.loot-head .dash-seg button { gap: 5px; }
.loot-note { margin-left: auto; font-size: 10.5px; color: var(--label); }
.rare-all { align-self: center; color: var(--gold); border-color: rgba(217,119,6,0.5); }
.rare-all:disabled { opacity: 0.5; cursor: default; }
.loot-cols { display: grid; grid-template-columns: 30px minmax(0, 1fr) 96px 66px 64px 20px; gap: 8px; padding: 0 9px; font-size: 9px; letter-spacing: 1.2px; text-transform: uppercase; color: var(--label); }
.loot-cols .r { text-align: right; }
.without { color: var(--gold); font-weight: 600; }
.today .without { font-size: 10.5px; margin-top: -3px; }
.today .without .mono { font-size: 10.5px; font-weight: 500; }
.sd-link { padding: 0 0 0 4px; font: inherit; font-weight: 600; background: none; border: none; cursor: pointer; color: var(--accent-text); }
.loot-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 3px; }
.loot-row { flex-shrink: 0; display: grid; grid-template-columns: 30px minmax(0, 1fr) 96px 66px 64px 20px; gap: 8px; align-items: center; padding: 3px 8px; border-radius: 8px; font-size: 11.5px; background: var(--panel); border: 1px solid var(--panel-border); }
.loot-row.rare { border-color: rgba(217,119,6,0.45); }
.loot-row .name { display: flex; align-items: center; gap: 6px; min-width: 0; color: var(--strong); }
.loot-row .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.loot-row .rate { font-size: 10.5px; color: var(--muted); }
.loot-row .rate.rare { color: var(--gold); }
.loot-row .total { font-size: 10.5px; color: var(--muted); }
.loot-row.out { opacity: 0.6; }
.loot-row.out .name span, .loot-row.out .amount { text-decoration: line-through; }
.loot-row .exc { width: 20px; height: 20px; padding: 0; display: flex; align-items: center; justify-content: center; border-radius: 5px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.loot-row .exc:hover { border-color: var(--neg); color: var(--neg); }
.loot-row .exc.on { background: var(--neg); border-color: var(--neg); color: #fff; }
.loot-row .exc:disabled { opacity: 0.4; cursor: default; }
.r { text-align: right; }
.strong { font-weight: 700; }
.sd-more { align-self: flex-start; margin-top: 4px; padding: 0; font-size: 11px; background: none; border: none; color: var(--accent); cursor: pointer; }
</style>
