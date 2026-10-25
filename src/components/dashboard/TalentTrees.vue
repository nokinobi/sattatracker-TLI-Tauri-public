<template>
  <div class="tt">
    <div class="tt-grid" role="tablist" aria-label="Talent constellations">
      <button
        v-for="t in tiles"
        :key="t.key"
        role="tab"
        :aria-selected="t.key === current"
        :class="['tt-hex', { used: t.points > 0, on: t.key === current }]"
        :title="`${t.name}: ${t.points} points`"
        @click="current = t.key"
      >
        <span class="nm">{{ t.name }}</span>
        <span class="mono pt">{{ t.points }}</span>
      </button>
    </div>

    <div v-if="view" class="tt-view">
      <svg :viewBox="view.box" class="tt-svg" role="img" :aria-label="`${view.name} constellation`">
        <line
          v-for="(l, i) in view.links"
          :key="'l' + i"
          :x1="l.x1" :y1="l.y1" :x2="l.x2" :y2="l.y2"
          :class="['ln', { on: l.on }]"
        />
        <circle
          v-for="(n, i) in view.nodes"
          :key="'n' + i"
          :cx="n.x" :cy="n.y" :r="n.r"
          :class="['nd', n.cls]"
        ><title>{{ n.text }}</title></circle>
      </svg>
      <div class="tt-side dash-scroll">
        <div class="head">
          <span class="name">{{ view.name }}</span>
          <span class="mono pts">{{ view.points }} points</span>
        </div>
        <div v-if="view.unplaced" class="warn">{{ view.unplaced }} point(s) placed approximately</div>
        <div v-if="!view.list.length" class="none">No points in this constellation</div>
        <div v-for="(e, i) in view.list" :key="i" :class="['effect', { big: e.big }]">
          <span v-if="!e.big" class="mono n">×{{ e.count }}</span>
          <span>{{ e.text }}</span>
        </div>
        <div class="hint">Medium and large nodes are exact. Small nodes follow the shortest path, since the data only counts them.</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { talentText, treeName } from './strategies/api';
import { PROFOUND, TREES, placePoints } from './strategies/trees';

const props = defineProps<{ talents: { key: string; count: number }[] }>();

const NODE_R = [44, 22, 34, 46];

const picked = computed(() => new Map(props.talents.map(t => [t.key, t.count])));

const placements = computed(() =>
  new Map(Object.entries(TREES).map(([key, tree]) => [key, placePoints(tree, picked.value)])),
);

const tiles = computed(() =>
  Object.keys(TREES)
    .map(key => ({ key, name: treeName(key), points: placements.value.get(key)!.points }))
    .sort((a, b) => Number(a.key === PROFOUND) - Number(b.key === PROFOUND) || a.name.localeCompare(b.name)),
);

const current = ref('');
watch(tiles, (list) => {
  if (!list.some(t => t.key === current.value && t.points > 0)) {
    current.value = [...list].sort((a, b) => b.points - a.points)[0]?.key ?? '';
  }
}, { immediate: true });

const view = computed(() => {
  const tree = TREES[current.value];
  const p = placements.value.get(current.value);
  if (!tree || !p) return null;
  const xs = tree.n.map(n => n[0]);
  const ys = tree.n.map(n => n[1]);
  const pad = 70;
  const minX = Math.min(...xs) - pad;
  const minY = Math.min(...ys) - pad;
  const box = `${minX} ${minY} ${Math.max(...xs) + pad - minX} ${Math.max(...ys) + pad - minY}`;

  const links = tree.l.map(([a, b]) => ({
    x1: tree.n[a][0], y1: tree.n[a][1], x2: tree.n[b][0], y2: tree.n[b][1],
    on: p.taken.has(a) && p.taken.has(b),
  }));
  const nodes = tree.n.map((n, i) => ({
    x: n[0], y: n[1], r: NODE_R[n[2]] ?? 22,
    cls: n[2] === 0 ? 'start' : [p.taken.has(i) ? 'on' : '', n[2] === 3 ? 'large' : ''].join(' '),
    text: n[2] === 0 ? 'Start' : talentText(n[3]),
  }));

  const effects = new Map<string, { text: string; count: number; big: boolean }>();
  p.taken.forEach(i => {
    const n = tree.n[i];
    if (n[2] === 0) return;
    const key = `${n[2] >= 2 ? i : ''}:${n[3]}`;
    const e = effects.get(key) ?? { text: talentText(n[3]), count: 0, big: n[2] >= 2 };
    e.count++;
    effects.set(key, e);
  });
  const list = [...effects.values()].sort((a, b) => Number(b.big) - Number(a.big) || b.count - a.count);

  return { name: treeName(current.value), points: p.points, unplaced: p.unplaced, box, links, nodes, list };
});
</script>

<style scoped>
.tt { display: flex; flex-direction: column; gap: 12px; min-height: 0; }
.tt-grid { display: grid; grid-template-columns: repeat(9, minmax(0, 1fr)); gap: 5px; }
.tt-hex { aspect-ratio: 1 / 0.9; clip-path: polygon(25% 3%, 75% 3%, 100% 50%, 75% 97%, 25% 97%, 0 50%); border: none; cursor: pointer; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; padding: 0 6px; text-align: center; font-size: 9.5px; font-weight: 600; line-height: 1.15; background: var(--chip-border); color: var(--label); }
.tt-hex .pt { font-size: 10.5px; font-weight: 700; padding: 0 6px; border-radius: 999px; background: var(--text); color: var(--panel); }
.tt-hex.used { background: rgba(20,184,166,0.28); color: var(--strong); }
.tt-hex.used .pt { background: #2dd4bf; color: #062925; }
.tt-hex.on { background: var(--accent); color: #fff; }
.tt-hex:hover:not(.on) { filter: brightness(1.15); }

.tt-view { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap: 14px; min-height: 0; padding: 12px; border-radius: 12px; background: var(--panel); border: 1px solid var(--panel-border); }
.tt-svg { width: 100%; height: 300px; }
.ln { stroke: var(--chip-border); stroke-width: 10; }
.ln.on { stroke: var(--gold); stroke-width: 14; }
.nd { fill: var(--input); stroke: var(--faint); stroke-width: 5; }
.nd.large { stroke-width: 9; }
.nd.on { fill: var(--gold); stroke: var(--gold); }
.nd.start { fill: var(--accent); stroke: var(--accent-border); }
.tt-side { max-height: 300px; display: flex; flex-direction: column; gap: 5px; font-size: 11.5px; line-height: 1.4; color: var(--text); }
.tt-side .head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 2px; }
.tt-side .name { font-size: 14px; font-weight: 700; color: var(--strong); }
.tt-side .pts { font-size: 12px; font-weight: 700; color: var(--gold); }
.tt-side .warn { font-size: 11px; color: var(--gold); }
.tt-side .none { color: var(--label); }
.effect { display: flex; gap: 6px; }
.effect .n { flex-shrink: 0; width: 26px; font-size: 10px; color: var(--label); }
.effect.big { color: var(--gold); font-weight: 600; }
.tt-side .hint { margin-top: auto; padding-top: 8px; font-size: 10px; color: var(--label); }
</style>
