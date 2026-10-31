<template>
  <div class="ss">
    <div class="ss-toolbar">
      <select :value="scope" aria-label="Session" @change="pickScope">
        <option value="current">Current session · {{ fmtTime(store.sessionStartedAt) }}</option>
        <option value="all">All time</option>
        <option v-for="s in sessionOptions" :key="s.id" :value="s.id">{{ s.label }}</option>
        <option v-if="sessionOptions.length" value="manage">Manage saved sessions…</option>
      </select>
      <div class="dash-seg" role="group" aria-label="View">
        <button :class="{ on: view === 'maps' }" @click="view = 'maps'">Maps</button>
        <button :class="{ on: view === 'loot' }" @click="view = 'loot'">Loot</button>
      </div>
      <div class="ss-summary">
        <div v-for="c in view === 'loot' ? lootSummary : summary" :key="c.label">
          <div class="dash-label">{{ c.label }}</div>
          <div class="mono val" :class="c.tone">{{ c.value }}</div>
        </div>
      </div>
    </div>

    <div v-if="savedSession" class="ss-saved">
      <span>Saved session · {{ savedSession.mapsLabel }} · {{ fmtFE(savedSession.profit) }} FE</span>
      <button
        ref="deleteBtn"
        :class="['dash-btn', 'small', 'danger', { armed: deleteArmed }]"
        @click="deleteSavedSession"
      >
        {{ deleteArmed ? `Delete ${savedSession.mapsLabel}?` : 'Delete session' }}
      </button>
    </div>

    <div v-if="view === 'maps'" class="ss-maps">
      <aside class="ss-list dash-scroll">
        <div v-if="rows.length === 0" class="dash-empty">No maps recorded yet</div>
        <button
          v-for="r in rows"
          :key="r.id"
          :class="['ss-row', { on: selectedId === r.id }]"
          @click="selectedId = r.id"
        >
          <span class="stripe" :class="r.live ? 'live' : r.profit >= 0 ? 'up' : 'down'"></span>
          <span class="body">
            <span class="top">
              <span class="title">
                {{ mapTitle(r) }}
                <span v-if="r.live" class="live-tag">LIVE</span>
              </span>
              <span class="mono profit" :class="r.profit >= 0 ? 'pos' : 'neg'">{{ fmtFE(r.profit) }}</span>
            </span>
            <span class="sub">
              <span>{{ fmtWhen(r.startedAt) }} · {{ fmtDur(r.durationSec) }}</span>
              <span>{{ r.lootCount }} items{{ r.expenseValue > 0 ? ' · −' + r.expenseValue.toFixed(0) : '' }}{{ hasEdits(r) ? ' · edited' : '' }}</span>
            </span>
          </span>
        </button>
      </aside>

      <section class="ss-detail">
        <div v-if="!selected" class="dash-empty">Select a map to see details</div>
        <template v-else>
          <div class="ss-detail-head">
            <div class="ss-title-row">
              <h2>{{ mapTitle(selected) }}</h2>
              <span v-if="selected.live" class="live-pill">IN PROGRESS</span>
              <span class="when">{{ fmtFull(selected.startedAt) }}</span>
            </div>
            <div class="ss-cells">
              <div v-for="c in detailCells" :key="c.label">
                <div class="dash-label">{{ c.label }}</div>
                <div class="mono val" :class="c.tone">{{ c.value }}</div>
              </div>
            </div>
          </div>

          <div class="ss-detail-body dash-scroll">
            <div class="dash-label">Net profit over time</div>
            <div class="dash-panel ss-chart">
              <svg
                :viewBox="`0 0 ${CW} ${CH}`"
                width="100%"
                :height="CH"
                @mousemove="onChartMove"
                @mouseleave="hover = null"
              >
                <line
                  v-for="g in chart.grid"
                  :key="g.y"
                  :x1="PAD_L" :x2="CW - PAD_R" :y1="g.y" :y2="g.y"
                  :stroke="g.zero ? 'var(--faint)' : 'var(--line)'"
                  :stroke-dasharray="g.zero ? '4 3' : ''"
                />
                <text v-for="g in chart.grid" :key="'l' + g.y" :x="PAD_L - 6" :y="g.y + 3" text-anchor="end" font-size="9" fill="var(--label)">{{ g.label }}</text>
                <text v-for="tk in chart.ticks" :key="'t' + tk.x" :x="tk.x" :y="CH - 5" :text-anchor="tk.anchor" font-size="9" fill="var(--label)">{{ tk.label }}</text>
                <path :d="chart.area" :fill="chart.color" fill-opacity="0.12" />
                <path :d="chart.line" fill="none" :stroke="chart.color" stroke-width="2" stroke-linejoin="round" />
                <template v-if="hover">
                  <line :x1="hover.x" :x2="hover.x" :y1="PAD_T" :y2="CH - PAD_B" stroke="var(--faint)" />
                  <circle :cx="hover.x" :cy="hover.y" r="3.5" :fill="chart.color" />
                  <text :x="hover.x > CW / 2 ? hover.x - 8 : hover.x + 8" :y="PAD_T + 10" :text-anchor="hover.x > CW / 2 ? 'end' : 'start'" font-size="10" fill="var(--strong)">{{ hover.label }}</text>
                </template>
              </svg>
            </div>

            <div v-if="editCount > 0" class="ss-edits">
              <b>{{ editCount === 1 ? '1 price edited for this map' : `${editCount} prices edited for this map` }}</b>
              <span>Profit is recalculated; the chart keeps the prices recorded during the run.</span>
              <button class="dash-btn small" @click="revertAll">Revert all</button>
            </div>

            <button class="ss-sec" :aria-expanded="isOpen('expenses')" @click="toggleSection('expenses')">
              <svg :class="['chev', { shut: !isOpen('expenses') }]" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
              <span class="dash-label">Expenses ({{ selectedExpenses.length }}) · consumed in this map</span>
              <span class="mono total neg">−{{ selected.expenseValue.toFixed(1) }} FE</span>
            </button>
            <template v-if="isOpen('expenses')">
              <div v-if="selectedExpenses.length === 0" class="ss-none">Nothing consumed</div>
              <MapItemRow
                v-for="e in selectedExpenses"
                :key="e.id"
                :item-id="e.id"
                :name="e.name || e.id"
                :detail="`x${e.qty} @ ${fmtPrice(e.unit)}`"
                :value="'−' + e.total.toFixed(1)"
                tone="neg"
                :unit="e.unit"
                :edited="e.was !== undefined"
                :was="e.was"
                :editable="!selected.live && e.qty > 0"
                :editing="editing === 'e:' + e.id"
                :error="editError"
                @edit="editing = 'e:' + e.id"
                @cancel="editing = ''"
                @apply="setPrice('expense', e.id, $event)"
                @revert="setPrice('expense', e.id, null)"
              />
            </template>

            <button class="ss-sec" :aria-expanded="isOpen('loot')" @click="toggleSection('loot')">
              <svg :class="['chev', { shut: !isOpen('loot') }]" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
              <span class="dash-label">Loot ({{ selectedLoot.length }}) · value share</span>
              <span class="mono total gold">{{ fmtFE(selected.lootValue) }} FE</span>
            </button>
            <template v-if="isOpen('loot')">
              <div v-if="selectedLoot.length === 0" class="ss-none">No loot recorded</div>
              <MapItemRow
                v-for="d in selectedLoot"
                :key="d.item_id"
                :item-id="d.item_id"
                :name="d.item_name"
                :detail="`x${d.qty} @ ${fmtPrice(d.price)} · ${d.share.toFixed(0)}% of loot`"
                :value="fmtValue(d.value)"
                tone="gold"
                :unit="d.price"
                :share="d.share"
                :edited="d.originalPrice !== undefined"
                :was="d.originalPrice"
                :editable="!selected.live"
                :editing="editing === 'd:' + d.item_id"
                :error="editError"
                :after-tax="store.applyTax"
                @edit="editing = 'd:' + d.item_id"
                @cancel="editing = ''"
                @apply="setPrice('drop', d.item_id, $event)"
                @revert="setPrice('drop', d.item_id, null)"
              />
            </template>
          </div>
        </template>
      </section>
    </div>

    <div v-else class="ss-lootview">
      <div v-if="lootGroups.length > 1 || lootScopeSession === null || lootEditCount > 0" class="ss-loot-tools">
        <div v-if="lootGroups.length > 1" class="ss-chips" role="group" aria-label="Item group">
          <button :class="['dash-chip', { on: lootGroup === 'all' }]" @click="pickLootGroup('all')">All<span class="n">{{ scopeLoot.length }}</span></button>
          <button v-for="g in lootGroups" :key="g.id" :class="['dash-chip', { on: lootGroup === g.id }]" @click="pickLootGroup(g.id)">{{ g.id }}<span class="n">{{ g.n }}</span></button>
        </div>
        <div v-if="lootGroup !== 'all'" class="ss-chips" role="group" aria-label="Item type">
          <button :class="['dash-chip', { on: lootType === 'all' }]" @click="lootType = 'all'">All<span class="n">{{ inLootGroup.length }}</span></button>
          <button v-for="t in lootTypes" :key="t.id" :class="['dash-chip', { on: lootType === t.id }]" @click="lootType = t.id">{{ t.id }}<span class="n">{{ t.n }}</span></button>
        </div>
        <div v-if="lootScopeSession === null" class="ss-loot-note">All time spans several sessions, so prices can't be edited here. Pick one session to change a price.</div>
        <div v-if="lootEditCount > 0" class="ss-edits">
          <b>{{ lootEditCount === 1 ? '1 price edited in this session' : `${lootEditCount} prices edited in this session` }}</b>
          <span>This session's totals and its maps' profit are recalculated. Other sessions don't change.</span>
          <button class="dash-btn small" @click="revertLootAll">Revert all</button>
        </div>
      </div>
      <div class="ss-loot-head">
        <span></span>
        <SortHead label="Item · everything dropped" :active="lootSort.key.value === 'name'" :dir="lootSort.dir.value" @sort="lootSort.toggle('name')" />
        <SortHead label="Share of loot" :active="lootSort.key.value === 'share'" :dir="lootSort.dir.value" @sort="lootSort.toggle('share')" />
        <SortHead class="r" label="Value" :active="lootSort.key.value === 'value'" :dir="lootSort.dir.value" @sort="lootSort.toggle('value')" />
        <span></span>
      </div>
      <div v-if="shownLoot.length === 0" class="dash-empty">Nothing dropped in this selection</div>
      <div v-else class="ss-loot-list dash-scroll">
        <div v-for="d in shownLoot" :key="d.item_id" :class="['ss-loot-item', { edited: d.was !== undefined, open: lootEditing === d.item_id }]">
          <div class="ss-loot-line">
            <span class="dash-icon"><img :src="getIcon(d.item_id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
            <span class="name">
              <span>{{ d.item_name }}</span>
              <small>{{ d.type ? `${d.type} · ` : '' }}x{{ d.qty }} @ {{ fmtPrice(d.value / (d.qty || 1)) }}{{ d.maps ? ` · dropped in ${d.maps} ${d.maps === 1 ? 'map' : 'maps'}` : '' }}<template v-if="d.was !== undefined"> · <b>edited, was {{ fmtPrice(d.was) }}</b></template></small>
            </span>
            <span class="bar"><span><i :style="{ width: d.bar + '%' }"></i></span><b class="mono">{{ d.share.toFixed(0) }}%</b></span>
            <span :class="['mono', 'r', d.was !== undefined ? 'accent' : 'gold']">{{ fmtValue(d.value) }} FE</span>
            <span class="act">
              <button v-if="d.was !== undefined && lootScopeSession !== null" class="dash-btn small" title="Back to the recorded prices in this session" @click="revertLootPrice(d.item_id)">Revert</button>
              <button
                v-else-if="d.editable"
                class="pencil"
                :aria-expanded="lootEditing === d.item_id"
                :aria-label="`Edit the price of ${d.item_name} in this session`"
                title="Edit the price in this session"
                @click="lootEditing = d.item_id"
              >
                <svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path d="M11 2.5l2.5 2.5L6 12.5l-3.2.7.7-3.2z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>
              </button>
            </span>
          </div>
          <PriceEditor
            v-if="lootEditing === d.item_id && d.editable"
            :unit="d.unit"
            label="Price per item in this session"
            :hint="`Applies to this item in ${d.stored === 1 ? 'the 1 finished map' : `all ${d.stored} finished maps`} of this session only. Other sessions and its price everywhere else don't change.${store.applyTax ? ' Enter the price after market tax, like the recorded one.' : ''}`"
            :error="lootEditError"
            @cancel="lootEditing = ''"
            @apply="applyLootPrice(d.item_id, $event)"
          />
        </div>
      </div>
    </div>

    <div v-if="managing" class="dash-confirm ss-manage" @click.self="closeManage">
      <section class="dash-confirm-box ss-manage-box" role="dialog" aria-label="Manage saved sessions">
        <div class="head">
          <span class="title">Saved sessions</span>
          <span class="count">{{ sessionOptions.length }} saved · {{ picked.length }} selected</span>
        </div>
        <div class="tools">
          <button class="dash-btn small" @click="selectOld">Select older than 30 days</button>
          <button class="dash-btn small" @click="setPicked([])">Select none</button>
        </div>
        <div class="list dash-scroll">
          <div v-if="sessionOptions.length === 0" class="ss-none">No saved sessions</div>
          <label v-for="s in sessionOptions" :key="s.id" :class="['row', { on: picked.includes(s.id) }]">
            <input type="checkbox" :checked="picked.includes(s.id)" @change="togglePick(s.id)" />
            <span class="name">
              <span>{{ s.name || `Session ${fmtWhen(s.startedAt)}` }}</span>
              <small>{{ fmtDay(s.startedAt) }}{{ ageLabel(s.startedAt) }}</small>
            </span>
            <span class="mono maps">{{ s.mapsLabel }}</span>
            <span class="mono profit" :class="s.profit >= 0 ? 'pos' : 'neg'">{{ fmtFE(s.profit) }}</span>
          </label>
        </div>
        <p class="hint">Deleting removes the session and its maps from history.</p>
        <div class="actions">
          <button class="dash-btn" @click="closeManage">Close</button>
          <button
            ref="bulkBtn"
            :class="['dash-btn', 'danger', { armed: bulkArmed }]"
            :disabled="picked.length === 0"
            @click="deletePicked"
          >
            {{ bulkLabel }}
          </button>
        </div>
        <p v-if="doneText" class="done">{{ doneText }}</p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useTrackerStore } from '../../stores/trackerStore';
import { getIcon } from '../../utils/assets';
import type { MapRecord, RecordDrop } from '../../types/history';
import { priceGroup } from './categories';
import { fmtDur, fmtFE, fmtFull, fmtPrice, fmtTime, fmtValue, fmtWhen } from './format';
import MapItemRow from './MapItemRow.vue';
import PriceEditor from './PriceEditor.vue';
import SortHead from './SortHead.vue';
import { itemInfo } from './strategies/api';
import { sortedBy, useSort } from './useSort';

const props = defineProps<{ focusMapId: string }>();

const store = useTrackerStore();

type Row = MapRecord & { live?: boolean };

const scope = ref('current');
const view = ref<'maps' | 'loot'>('maps');
const selectedId = ref('');

const CW = 600;
const CH = 170;
const PAD_L = 46;
const PAD_R = 12;
const PAD_T = 10;
const PAD_B = 22;

function mapTitle(r: Row): string {
  return `Map ${r.levelId}`;
}

const liveRow = computed<Row | null>(() => {
  const meta = store.currentMapMeta;
  if (!meta) return null;
  return {
    id: 'live',
    live: true,
    sessionId: store.sessionId,
    levelType: meta.levelType,
    levelId: meta.levelId,
    startedAt: meta.startedAt,
    endedAt: Date.now(),
    durationSec: store.mapTimeSec,
    profit: store.currentMapProfit,
    lootValue: store.currentMapDrops.reduce((a, d) => a + d.price * d.qty, 0),
    expenseValue: store.mapExpenses.reduce((a, e) => a + e.total, 0),
    lootCount: store.currentMapDrops.reduce((a, d) => a + d.qty, 0),
    drops: store.currentMapDrops.map(d => ({ item_id: d.item_id, item_name: d.item_name, qty: d.qty, price: d.price })),
    expenses: store.mapExpenses.map(e => ({ id: e.id, name: e.name, qty: e.qty, total: e.total })),
    timeline: store.mapTimeline.length ? [...store.mapTimeline] : [{ t: 0, v: 0 }],
  };
});

const sessionOptions = computed(() => {
  const counts = new Map<string, number>();
  store.mapHistory.forEach(m => counts.set(m.sessionId, (counts.get(m.sessionId) ?? 0) + 1));
  return [...store.archivedSessions]
    .sort((a, b) => b.startedAt - a.startedAt)
    .map(s => {
      const maps = counts.get(s.id) ?? s.maps;
      const mapsLabel = `${maps} ${maps === 1 ? 'map' : 'maps'}`;
      const stats = `${fmtWhen(s.startedAt)} · ${mapsLabel} · ${fmtFE(s.profit)} FE`;
      return {
        id: s.id,
        name: s.name ?? '',
        startedAt: s.startedAt,
        profit: s.profit,
        mapsLabel,
        label: s.name ? `${s.name} · ${stats}` : stats,
      };
    });
});

const savedSession = computed(() => sessionOptions.value.find(s => s.id === scope.value) ?? null);

const deleteArmed = ref(false);
const deleteBtn = ref<HTMLButtonElement | null>(null);

const managing = ref(false);
const picked = ref<string[]>([]);
const bulkArmed = ref(false);
const bulkBtn = ref<HTMLButtonElement | null>(null);
const doneText = ref('');

const OLD_SESSION_MS = 30 * 24 * 3600 * 1000;
const DAY_MS = 24 * 3600 * 1000;

onClickOutside(deleteBtn, () => { deleteArmed.value = false; });
onClickOutside(bulkBtn, () => { bulkArmed.value = false; });

function pickScope(e: Event) {
  const el = e.target as HTMLSelectElement;
  if (el.value === 'manage') {
    el.value = scope.value;
    openManage();
    return;
  }
  scope.value = el.value;
}

function deleteSavedSession() {
  const s = savedSession.value;
  if (!s) return;
  if (!deleteArmed.value) {
    deleteArmed.value = true;
    return;
  }
  store.deleteSessions([s.id]);
  scope.value = 'current';
}

function openManage() {
  setPicked([]);
  managing.value = true;
}

function closeManage() {
  managing.value = false;
  setPicked([]);
}

function setPicked(ids: string[]) {
  picked.value = ids;
  bulkArmed.value = false;
  doneText.value = '';
}

function togglePick(id: string) {
  setPicked(picked.value.includes(id) ? picked.value.filter(x => x !== id) : [...picked.value, id]);
}

function selectOld() {
  const cutoff = Date.now() - OLD_SESSION_MS;
  setPicked(sessionOptions.value.filter(s => s.startedAt < cutoff).map(s => s.id));
}

const bulkLabel = computed(() => {
  const n = picked.value.length;
  if (n === 0) return 'Delete selected';
  return bulkArmed.value ? `Delete ${n} ${n === 1 ? 'session' : 'sessions'}?` : `Delete selected (${n})`;
});

function deletePicked() {
  const n = picked.value.length;
  if (n === 0) return;
  if (!bulkArmed.value) {
    bulkArmed.value = true;
    return;
  }
  store.deleteSessions(picked.value);
  setPicked([]);
  doneText.value = n === 1 ? 'Deleted 1 session and its maps.' : `Deleted ${n} sessions and their maps.`;
}

function fmtDay(ms: number): string {
  return `${new Date(ms).toLocaleDateString([], { day: '2-digit', month: '2-digit', year: 'numeric' })} ${fmtTime(ms)}`;
}

function ageLabel(ms: number): string {
  const days = Math.floor((Date.now() - ms) / DAY_MS);
  if (new Date(ms).toDateString() === new Date().toDateString()) return ' · today';
  return days >= 2 ? ` · ${days} days ago` : '';
}

watch(scope, () => { deleteArmed.value = false; });

watch(sessionOptions, (list) => {
  if (scope.value !== 'current' && scope.value !== 'all' && !list.find(s => s.id === scope.value)) scope.value = 'current';
});

const rows = computed<Row[]>(() => {
  let list: Row[];
  if (scope.value === 'all') list = [...store.mapHistory];
  else if (scope.value === 'current') list = store.mapHistory.filter(m => m.sessionId === store.sessionId);
  else list = store.mapHistory.filter(m => m.sessionId === scope.value);
  list.sort((a, b) => b.startedAt - a.startedAt);
  const live = liveRow.value;
  if (live && (scope.value === 'current' || scope.value === 'all')) list.unshift(live);
  return list;
});

const selected = computed<Row | null>(() => rows.value.find(r => r.id === selectedId.value) ?? null);

watch(rows, (list) => {
  if (!list.find(r => r.id === selectedId.value)) selectedId.value = list[0]?.id ?? '';
}, { immediate: true });

watch(() => props.focusMapId, (id) => {
  if (!id) return;
  view.value = 'maps';
  if (!rows.value.find(r => r.id === id)) scope.value = 'current';
  selectedId.value = id;
}, { immediate: true });

const summary = computed(() => {
  const list = rows.value;
  const profit = list.reduce((a, r) => a + r.profit, 0);
  const secs = list.reduce((a, r) => a + r.durationSec, 0);
  const perHour = secs > 0 ? (profit / secs) * 3600 : 0;
  const avg = list.length ? secs / list.length : 0;
  return [
    { label: 'Maps', value: String(list.length), tone: '' },
    { label: 'Profit', value: fmtFE(profit), tone: profit >= 0 ? 'pos' : 'neg' },
    { label: 'Per hour', value: fmtFE(perHour), tone: perHour >= 0 ? 'pos' : 'neg' },
    { label: 'Avg map', value: list.length ? fmtDur(avg) : '—', tone: '' },
  ];
});

const detailCells = computed(() => {
  const r = selected.value;
  if (!r) return [];
  return [
    { label: 'Time', value: fmtDur(r.durationSec), tone: '' },
    { label: 'Profit', value: fmtFE(r.profit), tone: r.profit >= 0 ? 'pos' : 'neg' },
    { label: 'Loot', value: fmtValue(r.lootValue), tone: 'gold' },
    { label: 'Cost', value: r.expenseValue > 0 ? '−' + fmtValue(r.expenseValue) : '0', tone: r.expenseValue > 0 ? 'cost' : '' },
  ];
});

const selectedExpenses = computed(() => {
  const r = selected.value;
  if (!r) return [];
  return r.expenses.map(e => ({
    ...e,
    unit: e.qty > 0 ? e.total / e.qty : 0,
    was: e.originalTotal !== undefined && e.qty > 0 ? e.originalTotal / e.qty : undefined,
  }));
});

const hasEdits = (r: Row) => r.drops.some(d => d.originalPrice !== undefined) || r.expenses.some(e => e.originalTotal !== undefined);

const editCount = computed(() => {
  const r = selected.value;
  if (!r) return 0;
  return r.drops.filter(d => d.originalPrice !== undefined).length + r.expenses.filter(e => e.originalTotal !== undefined).length;
});

// The row whose price editor is open: 'd:<item id>' for loot, 'e:<item id>' for an expense.
const editing = ref('');
watch(selectedId, () => { editing.value = ''; });

const editError = ref('');
watch(editing, () => { editError.value = ''; });

function setPrice(kind: 'drop' | 'expense', itemId: string, price: number | null) {
  if (selected.value && !store.setMapItemPrice(selected.value.id, kind, itemId, price)) {
    editError.value = 'That price is too high for this quantity.';
    return;
  }
  editing.value = '';
}

function revertAll() {
  const r = selected.value;
  if (!r) return;
  r.drops.filter(d => d.originalPrice !== undefined).forEach(d => store.setMapItemPrice(r.id, 'drop', d.item_id, null));
  r.expenses.filter(e => e.originalTotal !== undefined).forEach(e => store.setMapItemPrice(r.id, 'expense', e.id, null));
  editing.value = '';
}

// Collapsed sections of the map detail, remembered between runs.
const CLOSED_KEY = 'tli_session_closed_sections';
type Section = 'expenses' | 'loot';
function loadClosed(): Section[] {
  try {
    const v = JSON.parse(localStorage.getItem(CLOSED_KEY) ?? '[]');
    return Array.isArray(v) ? v.filter((x): x is Section => x === 'expenses' || x === 'loot') : [];
  } catch {
    return [];
  }
}
const closed = ref(new Set<Section>(loadClosed()));
const isOpen = (section: Section) => !closed.value.has(section);
function toggleSection(section: Section) {
  const next = new Set(closed.value);
  if (!next.delete(section)) next.add(section);
  closed.value = next;
  try {
    localStorage.setItem(CLOSED_KEY, JSON.stringify([...next]));
  } catch {
    // Remembering collapsed sections is a convenience; ignore storage errors.
  }
}

const lootSort = useSort('session-loot', { name: 'asc', share: 'desc', value: 'desc' }, 'value');

const selectedLoot = computed(() => {
  const r = selected.value;
  if (!r) return [];
  const total = r.drops.reduce((a, d) => a + d.price * d.qty, 0) || 1;
  return [...r.drops]
    .map(d => ({ ...d, value: d.price * d.qty, share: (d.price * d.qty / total) * 100 }))
    .sort((a, b) => b.value - a.value);
});

const scopeLoot = computed(() => {
  const byId = new Map<string, RecordDrop & { value: number; maps: number }>();
  const add = (d: RecordDrop, countMap: boolean) => {
    const cur = byId.get(d.item_id);
    if (cur) {
      cur.qty += d.qty;
      cur.value += d.price * d.qty;
      if (countMap) cur.maps += 1;
    } else {
      byId.set(d.item_id, { ...d, value: d.price * d.qty, maps: countMap ? 1 : 0 });
    }
  };
  if (scope.value === 'current') {
    store.sessionDrops.forEach(d => add(d, false));
    const perMap = new Map<string, number>();
    rows.value.forEach(r => r.drops.forEach(d => perMap.set(d.item_id, (perMap.get(d.item_id) ?? 0) + 1)));
    byId.forEach((v, id) => { v.maps = perMap.get(id) ?? 0; });
  } else {
    rows.value.forEach(r => r.drops.forEach(d => add(d, true)));
  }
  const list = [...byId.values()].sort((a, b) => b.value - a.value);
  const total = list.reduce((a, d) => a + d.value, 0) || 1;
  const top = list[0]?.value || 1;
  const by = lootSort.key.value;
  const stored = storedLoot.value;
  const session = lootScopeSession.value;
  return sortedBy(list, d => (by === 'name' ? d.item_name : d.value), lootSort.dir.value)
    .map(d => {
      const s = stored.get(d.item_id);
      const type = lootItemTypes.value.get(d.item_id);
      return {
        ...d,
        share: (d.value / total) * 100,
        bar: (d.value / top) * 100,
        type: type ?? '',
        group: type === undefined ? '' : priceGroup(type),
        stored: s?.maps ?? 0,
        // What the finished maps hold: the editor starts from this, not from drops of the running map.
        unit: s && s.qty > 0 ? s.value / s.qty : 0,
        was: s?.edited ? s.original / (s.qty || 1) : undefined,
        editable: session !== null && !!s && s.qty > 0,
      };
    });
});

// The session a price in the Loot view would change. All time spans several, so it has none.
const lootScopeSession = computed(() => {
  if (scope.value === 'all') return null;
  return scope.value === 'current' ? store.sessionId : scope.value;
});

// The drops of the finished maps in the selection, per item. Only these can be repriced.
const storedLoot = computed(() => {
  const byId = new Map<string, { qty: number; value: number; original: number; maps: number; edited: boolean }>();
  rows.value.filter(r => !r.live).forEach(r => r.drops.forEach(d => {
    const cur = byId.get(d.item_id) ?? { qty: 0, value: 0, original: 0, maps: 0, edited: false };
    cur.qty += d.qty;
    cur.value += d.price * d.qty;
    cur.original += (d.originalPrice ?? d.price) * d.qty;
    cur.maps += 1;
    cur.edited = cur.edited || d.originalPrice !== undefined;
    byId.set(d.item_id, cur);
  }));
  return byId;
});

const lootEditCount = computed(() => {
  if (lootScopeSession.value === null) return 0;
  let n = 0;
  storedLoot.value.forEach(s => { if (s.edited) n += 1; });
  return n;
});

const lootSummary = computed(() => {
  const items = scopeLoot.value.reduce((a, d) => a + d.value, 0);
  const current = scope.value === 'current';
  const earned = current ? store.totalProfit : rows.value.reduce((a, r) => a + r.profit, 0);
  // Stored maps keep only their most valuable drops, so outside the current session the rows can't
  // give the full total. It comes from the exact profit and expenses instead.
  const spent = current ? Math.max(0, items - earned) : rows.value.reduce((a, r) => a + r.expenseValue, 0);
  const dropped = current ? items : earned + spent;
  return [
    { label: 'Dropped', value: fmtValue(dropped), tone: 'gold' },
    { label: 'Spent', value: spent > 0 ? '−' + fmtValue(spent) : '0', tone: spent > 0 ? 'neg' : '' },
    { label: 'Earned', value: fmtFE(earned), tone: earned >= 0 ? 'pos' : 'neg' },
    { label: 'Item types', value: String(scopeLoot.value.length), tone: '' },
  ];
});

// Item types come from the tracker's own tables; without them the list simply has no chips.
const lootItemTypes = ref(new Map<string, string>());
const lootIds = computed(() => (view.value === 'loot' ? [...new Set(rawLootIds())].sort().join(',') : ''));

function rawLootIds(): string[] {
  const ids = rows.value.flatMap(r => r.drops.map(d => d.item_id));
  return scope.value === 'current' ? ids.concat(store.sessionDrops.map(d => d.item_id)) : ids;
}

watch(lootIds, async (joined) => {
  const known = lootItemTypes.value;
  const missing = joined ? joined.split(',').filter(id => !known.has(id)) : [];
  if (missing.length === 0) return;
  try {
    const info = await itemInfo(missing);
    const next = new Map(lootItemTypes.value);
    missing.forEach(id => {
      const type = info.get(id)?.item_type;
      if (type !== undefined) next.set(id, type);
    });
    lootItemTypes.value = next;
  } catch {
    // Logged by itemInfo. The chips stay away and the next change of the list asks again.
  }
}, { immediate: true });

const lootGroup = ref('all');
const lootType = ref('all');

function countBy(values: string[]): Array<{ id: string; n: number }> {
  const counts = new Map<string, number>();
  values.filter(Boolean).forEach(v => counts.set(v, (counts.get(v) ?? 0) + 1));
  return [...counts].map(([id, n]) => ({ id, n })).sort((a, b) => b.n - a.n || a.id.localeCompare(b.id));
}

function pickLootGroup(group: string) {
  lootGroup.value = group;
  lootType.value = 'all';
}

const lootGroups = computed(() => countBy(scopeLoot.value.map(d => d.group)));
const inLootGroup = computed(() => scopeLoot.value.filter(d => lootGroup.value === 'all' || d.group === lootGroup.value));
const lootTypes = computed(() => countBy(inLootGroup.value.map(d => d.type)));
const shownLoot = computed(() => inLootGroup.value.filter(d => lootType.value === 'all' || d.type === lootType.value));

// Another session can have none of the picked group or type.
watch([lootGroups, lootTypes], () => {
  if (lootGroup.value !== 'all' && !lootGroups.value.some(g => g.id === lootGroup.value)) pickLootGroup('all');
  else if (lootType.value !== 'all' && !lootTypes.value.some(t => t.id === lootType.value)) lootType.value = 'all';
});

const lootEditing = ref('');
const lootEditError = ref('');
watch(lootEditing, () => { lootEditError.value = ''; });
watch([scope, view], () => { lootEditing.value = ''; });

function applyLootPrice(itemId: string, price: number) {
  const session = lootScopeSession.value;
  if (session === null || !store.setSessionItemPrice(session, itemId, price)) {
    lootEditError.value = 'That price is too high for this quantity.';
    return;
  }
  lootEditing.value = '';
}

function revertLootPrice(itemId: string) {
  const session = lootScopeSession.value;
  if (session !== null) store.setSessionItemPrice(session, itemId, null);
  lootEditing.value = '';
}

function revertLootAll() {
  const session = lootScopeSession.value;
  if (session === null) return;
  storedLoot.value.forEach((s, id) => { if (s.edited) store.setSessionItemPrice(session, id, null); });
  lootEditing.value = '';
}

interface ChartPoint { x: number; y: number; t: number; v: number }

const chart = computed(() => {
  const r = selected.value;
  const empty = { line: '', area: '', color: 'var(--accent)', grid: [] as Array<{ y: number; label: string; zero: boolean }>, ticks: [] as Array<{ x: number; label: string; anchor: string }>, points: [] as ChartPoint[] };
  if (!r) return empty;

  const raw = r.timeline.length ? r.timeline : [{ t: 0, v: 0 }];
  const tMax = Math.max(r.durationSec, raw[raw.length - 1].t, 1);
  const vals = raw.map(p => p.v).concat([0, r.profit]);
  let vMin = Math.min(...vals);
  let vMax = Math.max(...vals);
  if (vMax - vMin < 1) { vMax += 1; vMin -= 1; }
  const margin = (vMax - vMin) * 0.08;
  vMin -= margin;
  vMax += margin;

  const w = CW - PAD_L - PAD_R;
  const h = CH - PAD_T - PAD_B;
  const sx = (t: number) => PAD_L + (t / tMax) * w;
  const sy = (v: number) => PAD_T + (1 - (v - vMin) / (vMax - vMin)) * h;

  const pts: ChartPoint[] = raw.map(p => ({ x: sx(p.t), y: sy(p.v), t: p.t, v: p.v }));
  const lastV = raw[raw.length - 1].v;
  pts.push({ x: sx(tMax), y: sy(lastV), t: tMax, v: lastV });

  let line = `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
  for (let i = 1; i < pts.length; i++) line += ` H ${pts[i].x.toFixed(1)} V ${pts[i].y.toFixed(1)}`;
  const zeroY = sy(0);
  const area = `${line} V ${zeroY.toFixed(1)} H ${pts[0].x.toFixed(1)} Z`;

  const color = lastV >= 0 ? 'var(--pos)' : 'var(--neg)';
  const levels = [vMax - margin, 0, vMin + margin];
  const grid = levels.map((v, i) => ({ y: sy(v), label: fmtFE(v).replace('+', ''), zero: i === 1 }));
  const ticks = [
    { x: sx(0), label: '00:00', anchor: 'start' },
    { x: sx(tMax / 2), label: fmtDur(tMax / 2), anchor: 'middle' },
    { x: sx(tMax), label: fmtDur(tMax), anchor: 'end' },
  ];
  return { line, area, color, grid, ticks, points: pts };
});

const hover = ref<{ x: number; y: number; label: string } | null>(null);

function onChartMove(e: MouseEvent) {
  const svg = e.currentTarget as SVGSVGElement;
  const rect = svg.getBoundingClientRect();
  if (rect.width === 0) return;
  const px = ((e.clientX - rect.left) / rect.width) * CW;
  const pts = chart.value.points;
  if (!pts.length) return;
  let best = pts[0];
  for (const p of pts) {
    if (Math.abs(p.x - px) < Math.abs(best.x - px)) best = p;
  }
  hover.value = { x: best.x, y: best.y, label: `${fmtDur(best.t)}  ${fmtFE(best.v)} FE` };
}
</script>

<style scoped>
.ss { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.ss-toolbar { display: flex; align-items: center; gap: 12px; padding: 12px 18px; border-bottom: 1px solid var(--line); }
.ss-toolbar select { width: 260px; }
.ss-summary { margin-left: auto; display: flex; gap: 22px; }
.ss-summary .val { font-size: 14px; font-weight: 700; color: var(--strong); }

.ss-maps { flex: 1; min-height: 0; display: flex; }
.ss-list { width: 320px; flex-shrink: 0; padding: 10px; display: flex; flex-direction: column; gap: 4px; border-right: 1px solid var(--line); }
.ss-row { flex-shrink: 0; display: flex; align-items: stretch; border-radius: 10px; overflow: hidden; cursor: pointer; text-align: left; padding: 0; background: var(--panel); border: 1px solid var(--panel-border); color: inherit; }
.ss-row.on { background: var(--accent-bg); border-color: var(--accent-border); }
.ss-row .stripe { width: 3px; flex-shrink: 0; }
.ss-row .stripe.up { background: var(--pos); }
.ss-row .stripe.down { background: var(--neg); }
.ss-row .stripe.live { background: var(--accent); }
.ss-row .body { flex: 1; min-width: 0; padding: 6px 10px; display: flex; flex-direction: column; gap: 2px; }
.ss-row .top { display: flex; justify-content: space-between; gap: 8px; }
.ss-row .title { font-size: 12px; font-weight: 600; color: var(--strong); display: flex; align-items: center; gap: 6px; }
.ss-row .profit { font-size: 12px; font-weight: 700; }
.ss-row .sub { display: flex; justify-content: space-between; font-size: 10px; color: var(--label); }
.live-tag { font-size: 9px; font-weight: 700; padding: 1px 6px; border-radius: 999px; background: var(--accent-bg); color: var(--accent-text); }

.ss-detail { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.ss-detail-head { padding: 14px 18px 12px; border-bottom: 1px solid var(--line); }
.ss-title-row { display: flex; align-items: center; gap: 10px; }
.ss-title-row h2 { margin: 0; font-size: 16px; font-weight: 700; color: var(--strong); }
.ss-title-row .when { margin-left: auto; font-size: 11px; color: var(--label); }
.live-pill { font-size: 10px; font-weight: 700; padding: 1px 8px; border-radius: 999px; background: var(--accent-bg); border: 1px solid var(--accent-border); color: var(--accent-text); }
.ss-cells { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin-top: 12px; }
.ss-cells .val { font-size: 14px; font-weight: 700; color: var(--strong); }
.ss-cells .val.pos, .ss-summary .val.pos { color: var(--pos); }
.ss-cells .val.neg, .ss-summary .val.neg { color: var(--neg); }
.ss-cells .val.gold { color: var(--gold); }
.ss-cells .val.cost { color: var(--neg-soft); }
.ss-detail-body { flex: 1; min-height: 0; padding: 12px 18px; display: flex; flex-direction: column; gap: 8px; }
.ss-chart { padding: 6px; }
.ss-none { font-size: 12px; color: var(--label); }
.ss-edits { flex-shrink: 0; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 6px 12px; border-radius: 8px; font-size: 11px; color: var(--muted); background: var(--accent-bg); border: 1px solid var(--accent-border); }
.ss-edits b { font-weight: 600; color: var(--accent-text); }
.ss-edits .dash-btn { margin-left: auto; align-self: center; }
.ss-sec { flex-shrink: 0; display: flex; align-items: center; gap: 6px; padding: 2px 0; background: none; border: none; cursor: pointer; color: var(--label); text-align: left; }
.ss-sec .chev { flex-shrink: 0; transition: transform 0.15s; }
.ss-sec .chev.shut { transform: rotate(-90deg); }
.ss-sec .total { margin-left: auto; font-size: 11px; font-weight: 700; }
.ss-loot-line .name { position: relative; flex: 1; min-width: 0; display: flex; flex-direction: column; font-size: 12px; font-weight: 600; color: var(--strong); }
.ss-loot-line .name span, .ss-loot-line .name small { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ss-loot-line .name small { font-size: 10px; font-weight: 400; color: var(--label); }
.ss-loot-line .name b { font-weight: 600; color: var(--accent-text); }

.ss-lootview { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.ss-loot-tools { display: flex; flex-direction: column; gap: 6px; padding: 10px 18px 0; }
.ss-chips { display: flex; flex-wrap: wrap; gap: 4px; }
.ss-loot-note { font-size: 11px; color: var(--label); }
.ss-loot-head, .ss-loot-line { display: grid; grid-template-columns: 30px minmax(0, 1fr) 150px 90px 62px; gap: 12px; align-items: center; }
.ss-loot-head { padding: 8px 30px 4px; font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--label); }
.ss-loot-list { flex: 1; min-height: 0; padding: 0 18px 14px; display: flex; flex-direction: column; gap: 4px; }
.ss-loot-item { flex-shrink: 0; border-radius: 10px; overflow: hidden; background: var(--panel); border: 1px solid var(--panel-border); }
.ss-loot-item.edited, .ss-loot-item.open { border-color: var(--accent-border); }
.ss-loot-line { padding: 6px 12px; }
.ss-loot-line .accent { color: var(--accent-text); }
.ss-loot-line .act { display: flex; justify-content: flex-end; }
.ss-loot-line .act .dash-btn { align-self: center; }
.pencil { flex-shrink: 0; width: 24px; height: 24px; padding: 0; display: flex; align-items: center; justify-content: center; border-radius: 6px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.pencil:hover { border-color: var(--accent-border); color: var(--strong); }
.ss-summary .val.gold { color: var(--gold); }
.ss-loot-line .bar { display: flex; align-items: center; gap: 8px; }
.ss-loot-line .bar > span { flex: 1; height: 6px; border-radius: 3px; background: var(--chip-border); overflow: hidden; }
.ss-loot-line .bar i { display: block; height: 100%; background: var(--gold); }
.ss-loot-line .bar b { width: 32px; text-align: right; font-size: 10px; font-weight: 500; color: var(--muted); }
.r { text-align: right; }
.ss-loot-line .r { font-size: 13px; font-weight: 700; }

.ss-saved { display: flex; align-items: center; gap: 8px; margin: 10px 18px 0; padding: 6px 10px; border-radius: 8px; font-size: 11px; color: var(--muted); background: var(--panel); border: 1px solid var(--chip-border); }
.ss-saved span { flex: 1; min-width: 0; }
.ss-saved .dash-btn { align-self: center; }

.ss-manage { z-index: 6; }
.ss-manage-box { width: 520px; display: flex; flex-direction: column; gap: 12px; }
.ss-manage-box .head { display: flex; align-items: baseline; justify-content: space-between; }
.ss-manage-box .count { font-size: 11px; color: var(--label); }
.ss-manage-box .tools { display: flex; gap: 6px; }
.ss-manage-box .list { max-height: 300px; display: flex; flex-direction: column; gap: 4px; }
.ss-manage-box .row { flex-shrink: 0; display: grid; grid-template-columns: 18px minmax(0, 1fr) 70px 60px; gap: 10px; align-items: center; padding: 7px 10px; border-radius: 8px; cursor: pointer; background: var(--panel); border: 1px solid var(--panel-border); }
.ss-manage-box .row.on { background: color-mix(in srgb, var(--neg) 8%, transparent); border-color: color-mix(in srgb, var(--neg) 40%, transparent); }
.ss-manage-box .row input { margin: 0; accent-color: var(--neg); }
.ss-manage-box .name { min-width: 0; display: flex; flex-direction: column; font-size: 12px; font-weight: 600; color: var(--strong); }
.ss-manage-box .name > span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ss-manage-box .name small { font-size: 10px; font-weight: 400; color: var(--label); }
.ss-manage-box .maps { text-align: right; font-size: 11px; color: var(--muted); }
.ss-manage-box .profit { text-align: right; font-size: 11px; font-weight: 700; }
.ss-manage-box p.hint { margin: 0; }
.ss-manage-box .dash-btn:disabled { color: var(--faint); border-color: var(--chip-border); cursor: default; }
.ss-manage-box p.done { margin: 0; padding: 8px 10px; border-radius: 8px; font-size: 11px; background: var(--accent-bg); color: var(--accent-text); }
</style>
