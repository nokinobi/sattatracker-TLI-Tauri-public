<template>
  <div class="ov">
    <section class="ov-kpis" aria-label="Session summary">
      <div v-for="k in kpis" :key="k.label" class="dash-panel ov-kpi">
        <div class="dash-label">{{ k.label }}</div>
        <div class="mono ov-kpi-value" :class="k.tone">{{ k.value }}</div>
        <div class="ov-kpi-sub">{{ k.sub }}</div>
      </div>
    </section>

    <div class="ov-main">
      <section class="dash-panel ov-chart" aria-label="Profit over session">
        <div class="ov-head">
          <span class="dash-label">Profit over session</span>
          <span class="ov-hint">one dot per map · click to open it</span>
        </div>
        <div v-if="chart.dots.length === 0" class="dash-empty">No maps in this session yet</div>
        <svg
          v-else
          :viewBox="`0 0 ${CW} ${CH}`"
          width="100%"
          height="100%"
          preserveAspectRatio="xMidYMin meet"
          role="img"
          :aria-label="`Session profit over ${chart.dots.length} maps`"
        >
          <line
            v-for="g in chart.grid"
            :key="g.y"
            :x1="PAD_L" :x2="CW - PAD_R" :y1="g.y" :y2="g.y"
            :stroke="g.zero ? 'var(--faint)' : 'var(--line)'"
            :stroke-dasharray="g.zero ? '4 3' : ''"
          />
          <text
            v-for="g in chart.grid"
            :key="'l' + g.y"
            :x="PAD_L - 6" :y="g.y + 3"
            text-anchor="end" font-size="10" fill="var(--label)"
          >{{ g.label }}</text>
          <text :x="PAD_L" :y="CH - 6" font-size="10" fill="var(--label)">{{ chart.startLabel }}</text>
          <text :x="CW - PAD_R" :y="CH - 6" text-anchor="end" font-size="10" fill="var(--label)">{{ chart.endLabel }}</text>
          <path :d="chart.area" fill="var(--pos)" fill-opacity="0.08" />
          <path :d="chart.line" fill="none" stroke="var(--pos)" stroke-width="2" stroke-linejoin="round" />
          <g
            v-for="d in chart.dots"
            :key="d.id"
            class="ov-dot"
            @mouseenter="hoverId = d.id"
            @mouseleave="hoverId = ''"
            @click="$emit('open-map', d.id)"
          >
            <circle :cx="d.x" :cy="d.y" r="10" fill="transparent" />
            <circle
              :cx="d.x" :cy="d.y"
              :r="hoverId === d.id ? 5 : 3.5"
              :fill="d.live ? 'var(--accent)' : d.profit >= 0 ? 'var(--pos)' : 'var(--neg)'"
              :stroke="hoverId === d.id ? 'var(--accent-text)' : 'none'"
              stroke-width="2"
            />
          </g>
          <template v-if="hovered">
            <line :x1="hovered.x" :x2="hovered.x" :y1="hovered.y" :y2="chart.zeroY" stroke="var(--faint)" stroke-dasharray="2 3" />
            <rect :x="tipX" y="8" width="190" height="38" rx="6" fill="var(--tooltip)" stroke="var(--accent-border)" />
            <text :x="tipX + 10" y="24" font-size="11" font-weight="700" fill="var(--strong)">{{ hovered.title }} · {{ fmtFE(hovered.profit) }}</text>
            <text :x="tipX + 10" y="38" font-size="10" fill="var(--accent-text)">{{ hovered.when }} · click to open in Session</text>
          </template>
        </svg>
      </section>

      <section class="dash-panel ov-loot" aria-label="Session loot">
        <div class="ov-head">
          <span class="dash-label">Session loot</span>
          <span class="ov-hint">{{ loot.length }} item types</span>
        </div>
        <div class="ov-totals">
          <span>Dropped <b class="mono gold">{{ fmtValue(dropped) }}</b></span>
          <span>Spent <b class="mono neg">{{ spent > 0 ? '−' + fmtValue(spent) : '0' }}</b></span>
          <span>Earned <b class="mono" :class="store.totalProfit >= 0 ? 'pos' : 'neg'">{{ fmtFE(store.totalProfit) }}</b></span>
        </div>
        <div class="ov-sep"></div>
        <div v-if="loot.length === 0" class="dash-empty">Nothing dropped yet</div>
        <div v-else class="ov-list dash-scroll">
          <div v-for="d in loot" :key="d.item_id" class="ov-item">
            <img :src="getIcon(d.item_id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" />
            <span class="name">{{ d.item_name }}</span>
            <span class="mono qty">x{{ d.qty }}</span>
            <span class="mono gold value">{{ fmtValue(d.value) }}</span>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useTrackerStore } from '../../stores/trackerStore';
import { getIcon } from '../../utils/assets';
import { fmtDur, fmtFE, fmtTime, fmtValue } from './format';

defineEmits<{ (e: 'open-map', id: string): void }>();

const store = useTrackerStore();

const CW = 560;
const CH = 300;
const PAD_L = 36;
const PAD_R = 14;
const PAD_T = 54;
const PAD_B = 26;

const sessionMaps = computed(() =>
  store.mapHistory
    .filter(m => m.sessionId === store.sessionId)
    .sort((a, b) => a.startedAt - b.startedAt),
);

const kpis = computed(() => {
  const maps = sessionMaps.value;
  const avg = maps.length ? maps.reduce((a, m) => a + m.durationSec, 0) / maps.length : 0;
  const fastest = maps.length ? Math.min(...maps.map(m => m.durationSec)) : 0;
  const perHour = Number(store.profitPerHour);
  return [
    { label: 'Profit', value: fmtFE(store.totalProfit), sub: 'FE this session', tone: store.totalProfit >= 0 ? 'pos' : 'neg' },
    { label: 'Per hour', value: fmtFE(perHour), sub: 'FE / hour', tone: perHour >= 0 ? 'pos' : 'neg' },
    { label: 'Session', value: store.formattedSessionTimer, sub: `since ${fmtTime(store.sessionStartedAt)}`, tone: '' },
    { label: 'Maps', value: String(maps.length), sub: store.currentMapMeta ? '+1 running' : 'finished', tone: '' },
    { label: 'Avg map time', value: maps.length ? fmtDur(avg) : '—', sub: maps.length ? `fastest ${fmtDur(fastest)}` : 'no maps yet', tone: '' },
  ];
});

interface Dot { id: string; x: number; y: number; profit: number; title: string; when: string; live: boolean }

const chart = computed(() => {
  const maps = sessionMaps.value;
  const entries = maps.map(m => ({ id: m.id, profit: m.profit, startedAt: m.startedAt, levelId: m.levelId, live: false }));
  if (store.currentMapMeta) {
    entries.push({
      id: 'live',
      profit: store.currentMapProfit,
      startedAt: store.currentMapMeta.startedAt,
      levelId: store.currentMapMeta.levelId,
      live: true,
    });
  }

  let sum = 0;
  const cumulative = entries.map(e => (sum += e.profit));
  const vals = [0, ...cumulative];
  let vMin = Math.min(...vals);
  let vMax = Math.max(...vals);
  if (vMax - vMin < 1) vMax += 1;

  const w = CW - PAD_L - PAD_R;
  const h = CH - PAD_T - PAD_B;
  const n = entries.length;
  const sx = (i: number) => PAD_L + (n ? (i / n) * w : 0);
  const sy = (v: number) => PAD_T + (1 - (v - vMin) / (vMax - vMin)) * h;

  const dots: Dot[] = entries.map((e, i) => ({
    id: e.id,
    x: sx(i + 1),
    y: sy(cumulative[i]),
    profit: e.profit,
    title: `Map ${e.levelId}`,
    when: fmtTime(e.startedAt),
    live: e.live,
  }));

  let line = `M ${sx(0).toFixed(1)} ${sy(0).toFixed(1)}`;
  for (const d of dots) line += ` L ${d.x.toFixed(1)} ${d.y.toFixed(1)}`;
  const zeroY = sy(0);
  const lastX = dots.length ? dots[dots.length - 1].x : sx(0);
  const area = `${line} L ${lastX.toFixed(1)} ${zeroY.toFixed(1)} Z`;

  const grid = [vMax, 0, vMin]
    .filter((v, i, a) => a.indexOf(v) === i)
    .map(v => ({ y: sy(v), label: (v < 0 ? '−' : '') + fmtValue(Math.abs(v)), zero: v === 0 }));

  return {
    dots,
    line,
    area,
    grid,
    zeroY,
    startLabel: entries.length ? fmtTime(entries[0].startedAt) : '',
    endLabel: entries.length ? fmtTime(entries[entries.length - 1].startedAt) : '',
  };
});

const hoverId = ref('');
const hovered = computed(() => chart.value.dots.find(d => d.id === hoverId.value) ?? null);
const tipX = computed(() => {
  const x = hovered.value?.x ?? 0;
  return Math.min(Math.max(x - 95, PAD_L), CW - PAD_R - 190);
});

const loot = computed(() =>
  store.sessionDrops
    .map(d => ({ ...d, value: d.price * d.qty }))
    .sort((a, b) => b.value - a.value),
);

const dropped = computed(() => loot.value.reduce((a, d) => a + d.value, 0));
const spent = computed(() => Math.max(0, dropped.value - store.totalProfit));
</script>

<style scoped>
.ov { flex: 1; min-height: 0; padding: 16px; display: flex; flex-direction: column; gap: 14px; }
.ov-kpis { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 10px; }
.ov-kpi { padding: 10px 14px; }
.ov-kpi-value { font-size: 22px; font-weight: 700; color: var(--strong); margin-top: 2px; }
.ov-kpi-sub { font-size: 10px; color: var(--label); }
.ov-main { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr); gap: 12px; }
.ov-chart, .ov-loot { min-height: 0; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; overflow: hidden; }
.ov-head { display: flex; justify-content: space-between; align-items: baseline; }
.ov-hint { font-size: 10px; color: var(--label); }
.ov-dot { cursor: pointer; }
.ov-totals { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; font-size: 10px; color: var(--label); }
.ov-totals b { display: block; font-size: 16px; }
.ov-sep { height: 1px; background: var(--line); }
.ov-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 6px; padding-right: 4px; }
.ov-item { display: flex; align-items: center; gap: 8px; font-size: 12px; }
.ov-item img { width: 18px; height: 18px; object-fit: contain; flex-shrink: 0; }
.ov-item .name { flex: 1; min-width: 0; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ov-item .qty { font-size: 10px; color: var(--label); }
.ov-item .value { width: 48px; text-align: right; font-weight: 700; }
</style>
