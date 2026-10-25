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
        <div v-for="c in summary" :key="c.label">
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
              <span>{{ r.lootCount }} items{{ r.expenseValue > 0 ? ' · −' + r.expenseValue.toFixed(0) : '' }}</span>
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

            <div class="dash-label">Loot ({{ selectedLoot.length }}) · value share</div>
            <div v-if="selectedLoot.length === 0" class="ss-none">No loot recorded</div>
            <div v-for="d in selectedLoot" :key="d.item_id" class="ss-loot-row">
              <span class="share" :style="{ width: d.share + '%' }"></span>
              <span class="dash-icon"><img :src="getIcon(d.item_id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
              <span class="name">
                <span>{{ d.item_name }}</span>
                <small>x{{ d.qty }} @ {{ fmtPrice(d.price) }} · {{ d.share.toFixed(0) }}% of loot</small>
              </span>
              <span class="mono gold value">{{ fmtValue(d.value) }} FE</span>
            </div>

            <template v-if="selected.expenses.length > 0">
              <div class="dash-label">Expenses</div>
              <div v-for="e in selected.expenses" :key="e.id" class="ss-expense">
                <span class="name">{{ e.name || e.id }}</span>
                <span class="mono qty">x{{ e.qty }}</span>
                <span class="mono neg">−{{ e.total.toFixed(1) }} FE</span>
              </div>
            </template>
          </div>
        </template>
      </section>
    </div>

    <div v-else class="ss-lootview">
      <div class="ss-loot-head">
        <span></span><span>Item · everything dropped</span><span>Share of loot</span><span class="r">Value</span>
      </div>
      <div v-if="scopeLoot.length === 0" class="dash-empty">Nothing dropped in this selection</div>
      <div v-else class="ss-loot-list dash-scroll">
        <div v-for="d in scopeLoot" :key="d.item_id" class="ss-loot-line">
          <span class="dash-icon"><img :src="getIcon(d.item_id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
          <span class="name">
            <span>{{ d.item_name }}</span>
            <small>x{{ d.qty }}{{ d.maps ? ` · dropped in ${d.maps} maps` : '' }}</small>
          </span>
          <span class="bar"><span><i :style="{ width: d.bar + '%' }"></i></span><b class="mono">{{ d.share.toFixed(0) }}%</b></span>
          <span class="mono gold r">{{ fmtValue(d.value) }} FE</span>
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
import { fmtDur, fmtFE, fmtFull, fmtPrice, fmtTime, fmtValue, fmtWhen } from './format';

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
  return list.map(d => ({ ...d, share: (d.value / total) * 100, bar: (d.value / top) * 100 }));
});

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
.ss-loot-row { position: relative; display: flex; align-items: center; gap: 12px; padding: 6px 12px; border-radius: 10px; overflow: hidden; background: var(--panel); border: 1px solid var(--panel-border); flex-shrink: 0; }
.ss-loot-row .share { position: absolute; left: 0; top: 0; bottom: 0; background: var(--gold); opacity: 0.08; }
.ss-loot-row .name, .ss-loot-line .name { position: relative; flex: 1; min-width: 0; display: flex; flex-direction: column; font-size: 12px; font-weight: 600; color: var(--strong); }
.ss-loot-row .name small, .ss-loot-line .name small { font-size: 10px; font-weight: 400; color: var(--label); }
.ss-loot-row .value { position: relative; font-size: 13px; font-weight: 700; }
.ss-expense { display: flex; align-items: center; gap: 12px; padding: 6px 12px; border-radius: 10px; font-size: 12px; background: var(--panel); border: 1px solid var(--panel-border); flex-shrink: 0; }
.ss-expense .name { flex: 1; color: var(--text); }
.ss-expense .qty { font-size: 10px; color: var(--label); }

.ss-lootview { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.ss-loot-head, .ss-loot-line { display: grid; grid-template-columns: 30px minmax(0, 1fr) 160px 90px; gap: 12px; align-items: center; }
.ss-loot-head { padding: 8px 30px 4px; font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--label); }
.ss-loot-list { flex: 1; min-height: 0; padding: 0 18px 14px; display: flex; flex-direction: column; gap: 4px; }
.ss-loot-line { flex-shrink: 0; padding: 6px 12px; border-radius: 10px; background: var(--panel); border: 1px solid var(--panel-border); }
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
