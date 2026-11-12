<template>
  <section class="dash-panel ms" aria-label="Profit per map">
    <div class="ms-head">
      <span class="dash-label">Last {{ values.length }} {{ values.length === 1 ? 'map' : 'maps' }}</span>
      <div class="ms-controls">
        <div class="dash-seg" role="group" aria-label="Chart view">
          <button v-for="v in VIEWS" :key="v.id" :class="{ on: view === v.id }" :aria-pressed="view === v.id" @click="pickView(v.id)">{{ v.label }}</button>
        </div>
        <div class="dash-seg" role="group" aria-label="Number of maps">
          <button v-for="c in COUNTS" :key="c" :class="{ on: count === c }" :aria-pressed="count === c" @click="pickCount(c)">{{ c }}</button>
        </div>
      </div>
    </div>

    <div v-if="values.length < 2" class="dash-empty">Finish at least 2 maps to see the average and dispersion</div>
    <template v-else>
      <div class="ms-stats">
        <div v-for="t in tiles" :key="t.label" class="ms-stat" :title="t.help">
          <div class="label">{{ t.label }}</div>
          <div class="mono value" :class="t.tone">{{ t.value }}</div>
        </div>
      </div>
      <div class="ms-sentence">{{ sentence }}</div>

      <div class="ms-plot">
        <svg
          v-if="view === 'map'"
          :viewBox="`0 0 ${W} ${H}`"
          width="100%"
          height="100%"
          preserveAspectRatio="xMidYMin meet"
          role="group"
          :aria-label="`Profit of each of the last ${values.length} maps`"
        >
          <rect :x="perMap.L" :y="perMap.bandTop" :width="perMap.R - perMap.L" :height="perMap.bandH" class="band" />
          <template v-for="g in perMap.grid" :key="g.y">
            <line :x1="perMap.L" :x2="perMap.R" :y1="g.y" :y2="g.y" :class="g.zero ? 'axis' : 'grid'" />
            <text :x="perMap.L - 6" :y="g.y + 3" text-anchor="end" class="tick">{{ g.label }}</text>
          </template>
          <path v-for="b in perMap.bars" :key="b.id" :d="b.d" :class="b.loss ? 'loss' : 'profit'" />
          <line :x1="perMap.L" :x2="perMap.R" :y1="perMap.avgY" :y2="perMap.avgY" class="avg" />
          <text :x="perMap.R + 6" :y="perMap.avgY - 3" class="tick">average</text>
          <text :x="perMap.R + 6" :y="perMap.avgY + 10" class="strong">{{ fmtFE(stats.avg) }}</text>
          <text v-for="e in perMap.edges" :key="e.y" :x="perMap.R + 6" :y="e.y + 3" class="tick">{{ e.text }}</text>
          <text v-for="n in perMap.notes" :key="n.text" :x="n.x" :y="n.y" text-anchor="middle" class="strong small">{{ n.text }}</text>
          <template v-if="perMap.seam !== null">
            <line :x1="perMap.seam" :x2="perMap.seam" :y1="perMap.T" :y2="perMap.B" class="axis" />
            <text :x="perMap.seam - 4" :y="perMap.B + 16" text-anchor="end" class="tick">this session →</text>
          </template>
          <text :x="perMap.L" :y="perMap.B + 16" class="tick">{{ values.length }} maps ago</text>
          <text :x="perMap.R" :y="perMap.B + 16" text-anchor="end" class="tick">latest</text>
          <g
            v-for="(h, i) in perMap.hits"
            :key="h.id"
            class="hit"
            role="button"
            tabindex="0"
            :aria-label="`${h.title}, open in Session`"
            @mouseenter="hover = i"
            @mouseleave="hover = null"
            @focus="hover = i"
            @blur="hover = null"
            @click="$emit('open-map', h.id)"
            @keydown.enter="$emit('open-map', h.id)"
          >
            <rect :x="h.x" :y="perMap.T" :width="h.w" :height="perMap.B - perMap.T" :class="hover === i ? 'hit-on' : 'hit-off'" />
          </g>
          <g v-if="perMapTip" class="tip">
            <rect :x="perMapTip.x" :y="perMap.T + 2" width="208" height="38" rx="6" />
            <text :x="perMapTip.x + 10" :y="perMap.T + 18" class="strong">{{ perMapTip.title }}</text>
            <text :x="perMapTip.x + 10" :y="perMap.T + 32" class="link">{{ perMapTip.sub }}</text>
          </g>
        </svg>

        <svg
          v-else-if="view === 'spread'"
          :viewBox="`0 0 ${W} ${H}`"
          width="100%"
          height="100%"
          preserveAspectRatio="xMidYMin meet"
          role="group"
          :aria-label="`How the profit of the last ${values.length} maps is spread`"
        >
          <rect :x="spread.bandX" :y="spread.T" :width="spread.bandW" :height="spread.B - spread.T" class="band" />
          <template v-for="g in spread.grid" :key="g.y">
            <line :x1="spread.L" :x2="spread.R" :y1="g.y" :y2="g.y" :class="g.zero ? 'axis' : 'grid'" />
            <text :x="spread.L - 6" :y="g.y + 3" text-anchor="end" class="tick">{{ g.label }}</text>
          </template>
          <path v-for="b in spread.bars" :key="b.id" :d="b.d" :class="b.loss ? 'loss' : 'profit'" />
          <text v-for="k in spread.ticks" :key="k.x" :x="k.x" :y="spread.B + 16" text-anchor="middle" class="tick">{{ k.text }}</text>
          <line :x1="spread.avgX" :x2="spread.avgX" y1="22" :y2="spread.B" class="avg" />
          <line :x1="spread.medX" :x2="spread.medX" y1="22" :y2="spread.B" class="med" />
          <text :x="spread.avgX + (spread.medianLeft ? 3 : -3)" y="14" :text-anchor="spread.medianLeft ? 'start' : 'end'" class="strong">average {{ fmtFE(stats.avg) }}</text>
          <text :x="spread.medX + (spread.medianLeft ? -3 : 3)" y="14" :text-anchor="spread.medianLeft ? 'end' : 'start'" class="strong">median {{ fmtFE(stats.median) }}</text>
          <g
            v-for="(h, i) in spread.hits"
            :key="h.x"
            class="hit plain"
            :aria-label="h.title"
            @mouseenter="hover = i"
            @mouseleave="hover = null"
          >
            <rect :x="h.x" :y="spread.T" :width="h.w" :height="spread.B - spread.T" :class="hover === i ? 'hit-on' : 'hit-off'" />
          </g>
          <g v-if="spreadTip" class="tip">
            <rect :x="spreadTip.x" :y="spread.T + 4" width="150" height="38" rx="6" />
            <text :x="spreadTip.x + 10" :y="spread.T + 20" class="strong">{{ spreadTip.title }}</text>
            <text :x="spreadTip.x + 10" :y="spread.T + 34" class="link">{{ spreadTip.sub }}</text>
          </g>
        </svg>

        <div v-else class="ms-scroll dash-scroll">
          <svg
            :viewBox="`0 0 ${W} ${areas.height}`"
            width="100%"
            role="group"
            :aria-label="`Average profit and dispersion per area over the last ${values.length} maps`"
          >
            <template v-for="g in areas.grid" :key="g.x">
              <line :x1="g.x" :x2="g.x" :y1="areas.T" :y2="areas.B" :class="g.zero ? 'axis' : 'grid'" />
              <text :x="g.x" :y="areas.B + 16" text-anchor="middle" class="tick">{{ g.label }}</text>
            </template>
            <line :x1="areas.avgX" :x2="areas.avgX" :y1="areas.T" :y2="areas.B" class="avg" />
            <text :x="areas.avgX" y="12" text-anchor="middle" class="strong">all maps {{ fmtFE(stats.avg) }}</text>
            <g v-for="r in areas.rows" :key="r.id">
              <title>{{ r.help }}</title>
              <rect x="0" :y="r.top" :width="W" :height="r.h" fill="transparent" />
              <text x="0" :y="r.y - 2" class="name">{{ r.name }}</text>
              <text x="0" :y="r.y + 11" class="tick">{{ r.count }}</text>
              <line :x1="r.x1" :x2="r.x2" :y1="r.y" :y2="r.y" :class="['whisker', r.loss ? 'loss' : 'profit']" />
              <circle :cx="r.cx" :cy="r.y" r="5" :class="['dot', r.loss ? 'loss' : 'profit']" />
              <text :x="W" :y="r.y - 2" text-anchor="end" class="name mono">{{ r.avg }}</text>
              <text :x="W" :y="r.y + 11" text-anchor="end" class="tick">{{ r.spread }}</text>
            </g>
          </svg>
        </div>
      </div>

      <div class="ms-foot">
        <span v-for="k in legend" :key="k.text" class="key"><i :class="k.mark"></i>{{ k.text }}</span>
        <span class="note">{{ note }}</span>
      </div>
    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useTrackerStore } from '../../stores/trackerStore';
import { fmtFE, fmtWhen } from './format';
import { histogram, mean, niceStep, spreadStats, stdev } from './mapStats';

defineEmits<{ (e: 'open-map', id: string): void }>();

const store = useTrackerStore();

const W = 600;
const H = 306;
const COUNTS = [10, 25, 50, 100] as const;
const VIEWS = [
  { id: 'map', label: 'Per map' },
  { id: 'spread', label: 'Spread' },
  { id: 'areas', label: 'By area' },
] as const;
type Count = typeof COUNTS[number];
type View = typeof VIEWS[number]['id'];

const STORE_KEY = 'tli_overview_chart';

function loadChoice(): { count: Count; view: View } {
  const fallback = { count: 25 as Count, view: 'map' as View };
  try {
    const raw = JSON.parse(localStorage.getItem(STORE_KEY) ?? '{}');
    return {
      count: COUNTS.find(c => c === raw?.count) ?? fallback.count,
      view: VIEWS.find(v => v.id === raw?.view)?.id ?? fallback.view,
    };
  } catch {
    return fallback;
  }
}

const saved = loadChoice();
const count = ref<Count>(saved.count);
const view = ref<View>(saved.view);
const hover = ref<number | null>(null);

function remember() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({ count: count.value, view: view.value }));
  } catch {
    // Remembering the choice is a convenience; ignore storage errors.
  }
}

function pickCount(c: Count) {
  count.value = c;
  remember();
}

function pickView(v: View) {
  view.value = v;
  remember();
}

// Finished maps only: the running map's profit still changes with every drop.
const maps = computed(() => [...store.mapHistory].sort((a, b) => a.startedAt - b.startedAt).slice(-count.value));
const values = computed(() => maps.value.map(m => m.profit));
const stats = computed(() => spreadStats(values.value));

// The list under the pointer can change with a new map or another view.
watch([maps, view], () => { hover.value = null; });

const tiles = computed(() => {
  const s = stats.value;
  const tone = (v: number) => (v < 0 ? 'neg' : 'pos');
  return [
    { label: 'Average per map', value: fmtFE(s.avg), tone: tone(s.avg), help: 'Total profit of these maps divided by their number' },
    { label: 'Median map', value: fmtFE(s.median), tone: tone(s.median), help: 'Half of these maps earned more, half earned less. Lucky drops barely move it' },
    { label: 'Dispersion', value: '±' + fmtFE(s.sd).replace('+', ''), tone: '', help: 'Standard deviation: how far a map usually lands from the average' },
    { label: 'Dispersion ÷ average', value: s.avg > 0 ? `${Math.round((s.sd / s.avg) * 100)}%` : '—', tone: '', help: 'Lower is steadier. Above 100% a map can swing by more than it earns on average' },
  ];
});

const sentence = computed(() => {
  const s = stats.value;
  const n = values.value.length;
  return `${s.inside} of ${n} maps landed between ${fmtFE(s.low)} and ${fmtFE(s.high)} · ${s.losing} lost money · best ${fmtFE(s.best)}, worst ${fmtFE(s.worst)}`;
});

const fmtTick = (v: number) => fmtFE(v).replace(/\.0(?=k?$)/, '');
const round = (v: number) => Math.round(v * 100) / 100;

// A column from the baseline to `tip`, with a rounded end.
function column(x: number, w: number, tip: number, base: number): string {
  const r = Math.min(4, w / 2, Math.abs(base - tip));
  const inner = tip <= base ? tip + r : tip - r;
  return `M${x} ${base} V${inner} Q${x} ${tip} ${x + r} ${tip} H${x + w - r} Q${x + w} ${tip} ${x + w} ${inner} V${base} Z`;
}

const perMap = computed(() => {
  const L = 34, R = 546, T = 14, B = 284;
  const s = stats.value;
  const list = maps.value;
  const hi = Math.max(s.best, s.high, 1);
  const lo = Math.min(s.worst, s.low, 0);
  const step = niceStep(hi - lo, 4);
  const top = Math.ceil(hi / step) * step;
  // Room under the lowest column for its label.
  const bottom = lo < 0 ? lo - (top - lo) * 0.07 : 0;
  const y = (v: number) => round(T + (1 - (v - bottom) / (top - bottom)) * (B - T));
  const zero = y(0);
  const grid = [];
  for (let v = Math.ceil(bottom / step) * step; v <= top + step / 2; v += step) {
    grid.push({ y: y(v), label: fmtTick(v), zero: Math.abs(v) < step / 2 });
  }
  const slot = (R - L) / Math.max(list.length, 1);
  const w = Math.max(1.5, Math.min(24, slot - 2));
  const barX = (i: number) => round(L + slot * i + (slot - w) / 2);
  const bars = list.map((m, i) => {
    // A map near zero stays visible.
    const tip = Math.abs(y(m.profit) - zero) < 1.5 ? zero + (m.profit < 0 ? 1.5 : -1.5) : y(m.profit);
    return { id: m.id, d: column(barX(i), round(w), round(tip), zero), loss: m.profit < 0 };
  });
  const hits = list.map((m, i) => ({
    id: m.id,
    x: round(L + slot * i),
    w: round(slot),
    title: `Map ${m.levelId} · ${fmtFE(m.profit)}`,
    sub: `${fmtWhen(m.startedAt)} · click to open in Session`,
  }));
  const avgY = y(s.avg);
  const edges = [s.high, s.low]
    .filter(v => Math.abs(y(v) - avgY) >= 24)
    .map(v => ({ y: y(v), text: fmtFE(v) }));
  const clampX = (x: number) => Math.min(Math.max(x, L + 16), R - 16);
  const vals = values.value;
  const notes = [{ x: clampX(barX(vals.indexOf(s.best)) + w / 2), y: y(s.best) - 4, text: fmtFE(s.best) }];
  if (s.worst < 0) notes.push({ x: clampX(barX(vals.indexOf(s.worst)) + w / 2), y: y(s.worst) + 12, text: fmtFE(s.worst) });
  const firstNow = list.findIndex(m => m.sessionId === store.sessionId);
  return {
    L, R, T, B, grid, bars, hits, avgY, edges, notes,
    bandTop: y(s.high),
    bandH: round(y(s.low) - y(s.high)),
    seam: firstNow > 0 ? round(L + slot * firstNow) : null,
  };
});

const perMapTip = computed(() => {
  const h = hover.value === null ? undefined : perMap.value.hits[hover.value];
  if (!h) return null;
  const { L, R } = perMap.value;
  return { x: round(Math.min(Math.max(h.x + h.w / 2 - 104, L), R - 208)), title: h.title, sub: h.sub };
});

const spread = computed(() => {
  const L = 34, R = 586, T = 30, B = 284;
  const s = stats.value;
  const { bins, step } = histogram(values.value, 9);
  const start = bins[0].from;
  const peak = Math.max(...bins.map(b => b.count));
  const cStep = Math.max(1, niceStep(peak, 4));
  const cTop = Math.ceil(peak / cStep) * cStep;
  const y = (c: number) => round(B - (c / cTop) * (B - T));
  const grid = [];
  for (let c = 0; c <= cTop; c += cStep) grid.push({ y: y(c), label: String(c), zero: c === 0 });
  const slot = (R - L) / bins.length;
  const w = Math.max(3, Math.min(24, slot - 2));
  const x = (v: number) => round(L + ((v - start) / (bins.length * step)) * (R - L));
  const bars = bins.flatMap((b, i) => (b.count > 0
    ? [{ id: i, d: column(round(x(b.from) + (slot - w) / 2), round(w), y(b.count), B), loss: b.to <= 0 }]
    : []));
  const every = Math.ceil(36 / slot);
  const ticks = [];
  for (let i = 0; i <= bins.length; i += every) ticks.push({ x: x(start + i * step), text: fmtTick(start + i * step) });
  const clamp = (v: number) => Math.min(Math.max(v, L), R);
  const bandX = clamp(x(s.low));
  const total = values.value.length;
  return {
    L, R, T, B, grid, bars, ticks, bandX,
    bandW: round(clamp(x(s.high)) - bandX),
    avgX: x(s.avg),
    medX: x(s.median),
    medianLeft: s.median <= s.avg,
    hits: bins.map((b, i) => {
      const maps = `${b.count} ${b.count === 1 ? 'map' : 'maps'}`;
      return {
        x: round(L + slot * i),
        w: round(slot),
        title: `${fmtTick(b.from)} to ${fmtTick(b.to)}: ${maps}`,
        sub: `${Math.round((b.count / total) * 100)}% of these maps`,
      };
    }),
  };
});

const spreadTip = computed(() => {
  const h = hover.value === null ? undefined : spread.value.hits[hover.value];
  if (!h) return null;
  // Beside the column, so it never covers the column it describes.
  const right = h.x + h.w + 4;
  return { x: right + 150 <= spread.value.R ? right : h.x - 154, title: h.title, sub: h.sub };
});

const areas = computed(() => {
  const L = 124, R = 500, T = 22;
  const groups = new Map<number, number[]>();
  maps.value.forEach(m => groups.set(m.levelId, [...(groups.get(m.levelId) ?? []), m.profit]));
  const stat = [...groups].map(([id, list]) => ({ id, c: list.length, avg: mean(list), sd: stdev(list) }))
    .sort((a, b) => b.avg - a.avg);
  // Rows stay readable when there are many areas; the list scrolls then.
  const h = Math.max(32, Math.min(44, (H - 44) / stat.length));
  const B = T + h * stat.length;
  const s = stats.value;
  const hi = Math.max(...stat.map(g => g.avg + g.sd), s.avg, 1);
  const lo = Math.min(...stat.map(g => g.avg - g.sd), 0);
  const step = niceStep(hi - lo, 5);
  const from = Math.floor(lo / step) * step;
  const to = Math.ceil(hi / step) * step;
  const x = (v: number) => round(L + ((v - from) / (to - from)) * (R - L));
  const grid = [];
  for (let v = from; v <= to + step / 2; v += step) grid.push({ x: x(v), label: fmtTick(v), zero: Math.abs(v) < step / 2 });
  const rows = stat.map((g, i) => {
    const y = round(T + h * i + h / 2);
    const dispersion = fmtFE(g.sd).replace('+', '');
    return {
      id: g.id,
      name: `Map ${g.id}`,
      count: `${g.c} ${g.c === 1 ? 'map' : 'maps'}`,
      top: round(T + h * i),
      h: round(h),
      y,
      x1: x(g.avg - g.sd),
      x2: x(g.avg + g.sd),
      cx: x(g.avg),
      loss: g.avg < 0,
      avg: fmtFE(g.avg),
      spread: g.c > 1 ? `±${dispersion}` : 'one map',
      help: `Map ${g.id}: ${fmtFE(g.avg)} per map, dispersion ±${dispersion}, ${g.c} ${g.c === 1 ? 'map' : 'maps'}`,
    };
  });
  return { T, B, grid, rows, avgX: x(s.avg), height: B + 24 };
});

const legend = computed(() => {
  if (view.value === 'areas') {
    return [
      { mark: 'dot', text: 'Area average' },
      { mark: 'line', text: '± dispersion' },
      { mark: 'tall', text: 'All maps' },
    ];
  }
  const first = { mark: 'bar', text: view.value === 'map' ? 'Profit' : 'Maps' };
  const keys = [first, { mark: 'bar loss', text: 'Loss' }, { mark: 'wide', text: 'Average' }];
  if (view.value === 'spread') keys.push({ mark: 'tall med', text: 'Median' });
  keys.push({ mark: 'wash', text: '± dispersion' });
  return keys;
});

const note = computed(() => {
  const earlier = maps.value.filter(m => m.sessionId !== store.sessionId).length;
  const parts = [];
  if (earlier > 0) parts.push(`${earlier} from earlier sessions`);
  if (store.currentMapMeta) parts.push('running map not counted');
  return parts.join(' · ');
});
</script>

<style scoped>
.ms { --bar-loss: #f87171; min-height: 0; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; overflow: hidden; }
:global(.dash[data-theme='light']) .ms { --bar-loss: #dc6a6a; }
.ms-head { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; }
.ms-controls { display: flex; align-items: center; gap: 8px; }
.ms-stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; }
.ms-stat { padding: 6px 10px; border-radius: 8px; background: var(--line); }
.ms-stat .label { font-size: 10px; color: var(--label); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ms-stat .value { font-size: 16px; font-weight: 700; color: var(--strong); }
.ms-stat .value.pos { color: var(--pos); }
.ms-stat .value.neg { color: var(--neg); }
.ms-sentence { font-size: 11px; color: var(--muted); }
.ms-plot { flex: 1; min-height: 0; }
.ms-plot svg { display: block; }
.ms-scroll { height: 100%; }

.band { fill: var(--accent); fill-opacity: 0.1; }
.grid { stroke: var(--line); }
.axis { stroke: var(--faint); }
.avg, .med { stroke-width: 2; stroke-linecap: round; }
.avg { stroke: var(--strong); }
.med { stroke: var(--faint); }
path.profit { fill: var(--pos); }
path.loss { fill: var(--bar-loss); }
.whisker { stroke-width: 2; stroke-linecap: round; }
.whisker.profit { stroke: var(--pos); }
.whisker.loss { stroke: var(--bar-loss); }
.dot.profit { fill: var(--pos); }
.dot.loss { fill: var(--bar-loss); }
text { font-size: 10px; }
.tick { fill: var(--label); font-variant-numeric: tabular-nums; }
.strong { fill: var(--strong); font-size: 11px; font-weight: 700; }
.strong.small { font-size: 10px; }
.link { fill: var(--accent-text); }
.name { fill: var(--strong); font-size: 12px; font-weight: 600; }
.hit { cursor: pointer; outline: none; }
.hit.plain { cursor: default; }
.hit-off { fill: transparent; }
.hit-on { fill: var(--accent); fill-opacity: 0.14; }
.hit:focus-visible .hit-on { stroke: var(--accent-border); }
.tip { pointer-events: none; }
.tip rect { fill: var(--tooltip); stroke: var(--accent-border); }

.ms-foot { display: flex; align-items: center; gap: 12px; font-size: 10px; color: var(--label); white-space: nowrap; }
.ms-foot .key { display: flex; align-items: center; gap: 5px; }
.ms-foot .note { margin-left: auto; overflow: hidden; text-overflow: ellipsis; }
.ms-foot i { display: block; background: var(--pos); }
.ms-foot i.bar { width: 8px; height: 10px; border-radius: 2px; }
.ms-foot i.loss { background: var(--bar-loss); }
.ms-foot i.wide { width: 14px; height: 2px; border-radius: 1px; background: var(--strong); }
.ms-foot i.tall { width: 2px; height: 12px; border-radius: 1px; background: var(--strong); }
.ms-foot i.med { background: var(--faint); }
.ms-foot i.wash { width: 14px; height: 10px; border-radius: 2px; background: var(--accent); opacity: 0.25; }
.ms-foot i.dot { width: 10px; height: 10px; border-radius: 50%; }
.ms-foot i.line { width: 14px; height: 2px; border-radius: 1px; }
</style>
