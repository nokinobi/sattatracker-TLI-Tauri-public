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
      <MapSpreadPanel @open-map="$emit('open-map', $event)" />

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
import { computed } from 'vue';
import { useTrackerStore } from '../../stores/trackerStore';
import { getIcon } from '../../utils/assets';
import { fmtDur, fmtFE, fmtTime, fmtValue } from './format';
import MapSpreadPanel from './MapSpreadPanel.vue';

defineEmits<{ (e: 'open-map', id: string): void }>();

const store = useTrackerStore();

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
.ov-loot { min-height: 0; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px; overflow: hidden; }
.ov-head { display: flex; justify-content: space-between; align-items: baseline; }
.ov-hint { font-size: 10px; color: var(--label); }
.ov-totals { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; font-size: 10px; color: var(--label); }
.ov-totals b { display: block; font-size: 16px; }
.ov-sep { height: 1px; background: var(--line); }
.ov-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 6px; padding-right: 4px; }
.ov-item { flex-shrink: 0; display: flex; align-items: center; gap: 8px; font-size: 12px; }
.ov-item img { width: 18px; height: 18px; object-fit: contain; flex-shrink: 0; }
.ov-item .name { flex: 1; min-width: 0; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ov-item .qty { font-size: 10px; color: var(--label); }
.ov-item .value { width: 48px; text-align: right; font-weight: 700; }
</style>
