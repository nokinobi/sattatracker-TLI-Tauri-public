<template>
  <div class="sd">
    <div class="sd-top">
      <div class="crumbs">
        <button class="sd-back" @click="$emit('back')">← Strategies</button>
        <span class="faint">#{{ row.rank }} · {{ stageName(stage) }}</span>
      </div>
      <div class="title-row">
        <h2>{{ title }}</h2>
        <span class="muted">{{ areaName(row.mapLabel) }} · {{ timeName(row.timeLabel) }}</span>
        <div class="dash-seg sd-views" role="group" aria-label="Detail view">
          <button :class="{ on: view === 'loot' }" @click="view = 'loot'">Loot & cost</button>
          <button :class="{ on: view === 'talents' }" @click="view = 'talents'">Talent trees</button>
        </div>
      </div>
      <div class="tags">
        <span v-for="t in tagChips" :key="t.kind + t.label" :class="['tag', t.kind]">{{ t.label }}</span>
      </div>
    </div>

    <div v-if="!detail" class="dash-empty">{{ failed ? "Couldn't load this strategy. Try again in a minute." : 'Loading strategy…' }}</div>
    <div v-else class="sd-body">
      <div class="sd-side dash-scroll">
        <div class="stats">
          <div v-for="s in stats" :key="s.label" class="stat">
            <div class="dash-label">{{ s.label }}</div>
            <div :class="['mono', 'val', s.tone]">{{ s.value }}</div>
          </div>
        </div>

        <div class="today">
          <div class="dash-label accent">At today's prices, per map</div>
          <div class="line"><span>Loot</span><span class="mono gold">{{ fmtFE(perMap.loot) }}</span></div>
          <div class="line"><span>Cost</span><span class="mono neg">{{ fmtFE(-perMap.cost) }}</span></div>
          <div class="rule"></div>
          <div class="line total"><span>Profit</span><span :class="['mono', perMap.profit >= 0 ? 'pos' : 'neg']">{{ fmtFE(perMap.profit) }}</span></div>
          <div class="note">Reported average was {{ fmtFE(row.avgEarnings) }} per map. Prices moved since these maps were run.</div>
        </div>
      </div>

      <div v-if="view === 'talents'" class="sd-trees dash-scroll">
        <TalentTrees :talents="detail.talents" />
      </div>
      <div v-if="view === 'loot'" class="sd-col dash-scroll">
        <div class="col-head"><span class="dash-label">Cost per map ({{ cost.length }})</span><span class="dash-label">FE</span></div>
        <div v-for="c in cost" :key="c.id" class="item">
          <span class="dash-icon"><img :src="getIcon(c.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
          <span class="name"><span>{{ c.name }}</span><small>{{ c.qty }} per map · @ {{ c.price }}</small></span>
          <span class="mono neg strong">{{ c.value }}</span>
        </div>
      </div>
      <div v-if="view === 'loot'" class="sd-col dash-scroll">
        <div class="col-head"><span class="dash-label">Top loot per map ({{ shownLoot.length }} of {{ loot.length }})</span><span class="dash-label">FE</span></div>
        <div v-for="l in shownLoot" :key="l.id" class="item">
          <span class="dash-icon"><img :src="getIcon(l.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
          <span class="name"><span>{{ l.name }}</span><small>{{ l.qty }} per map · @ {{ l.price }}</small></span>
          <span class="mono gold strong">{{ l.value }}</span>
        </div>
        <button v-if="!allLoot && loot.length > LOOT_ROWS" class="sd-more" @click="allLoot = true">Show all {{ loot.length }} items</button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { getIcon } from '../../utils/assets';
import { fmtDur, fmtFE, fmtPrice, fmtValue } from './format';
import TalentTrees from './TalentTrees.vue';
import {
  areaName, fetchDetail, itemInfo, stageName, timeName, treeList, treeName,
  type DetailData, type ItemInfo, type ItemQty, type StrategyRow,
} from './strategies/api';

const props = defineProps<{ row: StrategyRow; stage: string }>();
defineEmits(['back']);

const LOOT_ROWS = 12;

const detail = ref<DetailData | null>(null);
const failed = ref(false);
const info = ref(new Map<string, ItemInfo>());
const allLoot = ref(false);
const view = ref<'loot' | 'talents'>('loot');

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
const maps = computed(() => Math.max(1, detail.value?.strategy.count ?? props.row.count));

function perMapRows(list: ItemQty[]) {
  return list
    .map(i => {
      const it = info.value.get(i.id);
      const price = it?.price ?? 0;
      return {
        id: i.id,
        name: it?.name || `Item ${i.id}`,
        perMap: i.quantity / maps.value,
        price,
        total: (i.quantity * price) / maps.value,
      };
    })
    .sort((a, b) => b.total - a.total || b.perMap - a.perMap)
    .map(r => ({
      ...r,
      qty: r.perMap >= 10 ? r.perMap.toFixed(0) : r.perMap.toFixed(2),
      price: r.price ? fmtPrice(r.price) : 'no price',
      value: r.total.toFixed(1),
    }));
}

const cost = computed(() => perMapRows(detail.value?.items.cost ?? []));
const loot = computed(() => perMapRows(detail.value?.items.loot ?? []));
const shownLoot = computed(() => (allLoot.value ? loot.value : loot.value.slice(0, LOOT_ROWS)));

const perMap = computed(() => {
  const l = loot.value.reduce((s, r) => s + r.total, 0);
  const c = cost.value.reduce((s, r) => s + r.total, 0);
  return { loot: l, cost: c, profit: l - c };
});

const stats = computed(() => [
  { label: 'Maps', value: String(props.row.count), tone: '' },
  { label: 'Reported FE / map', value: fmtFE(props.row.avgEarnings), tone: 'gold' },
  { label: 'FE / hour', value: fmtValue(props.row.avgEfficiency * 60), tone: 'pos' },
  { label: 'Avg map time', value: fmtDur(props.row.avgDuration / 1000), tone: '' },
  { label: 'Loot items', value: String(detail.value?.items.loot.length ?? 0), tone: '' },
  { label: 'Cost items', value: String(detail.value?.items.cost.length ?? 0), tone: '' },
]);


const tagChips = computed(() => {
  const chips: { kind: string; label: string }[] = [
    { kind: 'area', label: areaName(props.row.mapLabel) },
    { kind: 'time', label: timeName(props.row.timeLabel) },
  ];
  (detail.value?.tags ?? []).forEach(t => {
    if (t.type === 'mainTalentCluster') {
      const [tree, points] = t.key.split('|');
      chips.push({ kind: 'talent', label: `${treeName(tree)}${points ? ' ' + points : ''}` });
    } else if (t.type === 'costItem') {
      chips.push({ kind: 'cost', label: info.value.get(t.key)?.name || `Item ${t.key}` });
    }
  });
  return chips;
});
</script>

<style scoped>
.sd { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.sd-top { padding: 12px 18px; border-bottom: 1px solid var(--line); display: flex; flex-direction: column; gap: 8px; }
.crumbs { display: flex; align-items: center; gap: 10px; font-size: 11px; }
.sd-back { padding: 0; font-size: 12px; font-weight: 600; background: none; border: none; color: var(--accent); cursor: pointer; }
.title-row { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.title-row h2 { margin: 0; font-size: 17px; font-weight: 700; color: var(--strong); }
.muted { font-size: 12px; color: var(--muted); }
.faint { color: var(--faint); }
.tags { display: flex; gap: 5px; flex-wrap: wrap; }
.tag { font-size: 10.5px; padding: 1px 8px; border-radius: 999px; background: var(--chip); color: var(--muted); }
.tag.area { background: rgba(217,119,6,0.12); color: var(--gold); }
.tag.talent { background: var(--accent-bg); color: var(--accent-text); }
.tag.cost { background: rgba(248,113,113,0.1); color: var(--neg); }

.sd-body { flex: 1; min-height: 0; display: grid; grid-template-columns: 300px minmax(0, 1fr) minmax(0, 1fr); }
.sd-side { padding: 14px 18px; border-right: 1px solid var(--line); display: flex; flex-direction: column; gap: 14px; }
.stats { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.stat { padding: 8px 10px; border-radius: 10px; background: var(--panel); border: 1px solid var(--panel-border); }
.stat .val { font-size: 16px; font-weight: 700; color: var(--strong); }
.stat .val.gold { color: var(--gold); }
.stat .val.pos { color: var(--pos); }
.today { padding: 12px; border-radius: 12px; background: var(--accent-bg); border: 1px solid var(--accent-border); display: flex; flex-direction: column; gap: 8px; font-size: 12px; color: var(--text); }
.today .accent { color: var(--accent-text); }
.today .line { display: flex; justify-content: space-between; }
.today .line .mono { font-size: 13px; font-weight: 700; }
.today .total { font-size: 13px; font-weight: 700; }
.today .total .mono { font-size: 15px; }
.today .rule { height: 1px; background: var(--accent-border); }
.today .note { font-size: 10.5px; color: var(--muted); }

.sd-views { margin-left: auto; }
.sd-trees { grid-column: span 2; padding: 14px 16px; min-height: 0; }
.sd-col { padding: 14px 16px; display: flex; flex-direction: column; gap: 6px; min-height: 0; }
.sd-col + .sd-col { border-left: 1px solid var(--line); }
.col-head { display: flex; justify-content: space-between; }
.item { flex-shrink: 0; display: grid; grid-template-columns: 30px minmax(0, 1fr) auto; gap: 8px; align-items: center; font-size: 11.5px; }
.item .name { display: flex; flex-direction: column; min-width: 0; color: var(--strong); }
.item .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.item .name small { font-size: 10px; color: var(--label); }
.strong { font-weight: 700; }
.sd-more { align-self: flex-start; margin-top: 4px; padding: 0; font-size: 11px; background: none; border: none; color: var(--accent); cursor: pointer; }
</style>
