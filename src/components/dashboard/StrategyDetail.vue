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
      <div class="tags">
        <span v-for="t in tagChips" :key="t.kind + t.label" :class="['tag', t.kind]">{{ t.label }}</span>
      </div>
    </div>

    <div v-if="!detail" class="dash-empty">{{ failed ? "Couldn't load this strategy. Try again in a minute." : 'Loading strategy…' }}</div>
    <div v-else-if="view === 'talents'" class="sd-trees dash-scroll">
      <TalentTrees :talents="detail.talents" />
    </div>
    <div v-else class="sd-body">
      <div class="sd-side dash-scroll">
        <div class="today">
          <div class="dash-label accent">Same run at today's prices</div>
          <div class="line"><span>Loot per map</span><span class="mono gold">{{ fmtFE(perMap.loot) }}</span></div>
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
            <button :class="{ on: !rareOnly }" @click="rareOnly = false">All {{ loot.length }}</button>
            <button :class="{ on: rareOnly }" @click="rareOnly = true">
              <svg width="9" height="9" viewBox="0 0 12 12" aria-hidden="true"><path d="M6 1l5 5-5 5-5-5z" fill="var(--gold)"/></svg>
              Rare drops {{ rareCount }}
            </button>
          </div>
          <span class="loot-note">{{ rareOnly ? 'Drop in fewer than 1 of 5 maps: the lucky drops' : 'All items dropped in these maps · FE shown per map' }}</span>
        </div>
        <div class="loot-list dash-scroll">
          <div v-if="!shownLoot.length" class="dash-empty">No rare drops in this strategy</div>
          <div v-for="l in shownLoot" :key="l.id" :class="['loot-row', { rare: l.rare }]">
            <span class="dash-icon"><img :src="getIcon(l.id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
            <span class="name">
              <svg v-if="l.rare" width="10" height="10" viewBox="0 0 12 12" role="img" aria-label="Rare drop"><path d="M6 1l5 5-5 5-5-5z" fill="var(--gold)"/></svg>
              <span>{{ l.name }}</span>
            </span>
            <span :class="['mono', 'rate', { rare: l.rare }]">{{ l.rate }}</span>
            <span class="mono gold strong r">{{ l.value }}</span>
          </div>
          <button v-if="!rareOnly && !allLoot && loot.length > LOOT_ROWS" class="sd-more" @click="allLoot = true">Show all {{ loot.length }} items</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { getIcon } from '../../utils/assets';
import { fmtDur, fmtFE, fmtPrice } from './format';
import TalentTrees from './TalentTrees.vue';
import {
  areaName, fetchDetail, itemInfo, stageName, timeName, treeList, treeName,
  type DetailData, type ItemInfo, type ItemQty, type StrategyRow,
} from './strategies/api';

const props = defineProps<{ row: StrategyRow; stage: string }>();
defineEmits(['back']);

const LOOT_ROWS = 14;
// A "rare" drop shows up in fewer than one of five maps but is still worth something per map.
const RARE_SHARE = 0.2;
const RARE_MIN_VALUE = 0.5;

const detail = ref<DetailData | null>(null);
const failed = ref(false);
const info = ref(new Map<string, ItemInfo>());
const allLoot = ref(false);
const rareOnly = ref(false);
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
      return { id: i.id, name: it?.name || `Item ${i.id}`, perMap, price, total, rare: perMap < RARE_SHARE && total > RARE_MIN_VALUE };
    })
    .sort((a, b) => b.total - a.total || b.perMap - a.perMap)
    .map(r => ({
      ...r,
      qty: r.perMap >= 10 ? r.perMap.toFixed(0) : r.perMap.toFixed(2),
      price: r.price ? fmtPrice(r.price) : 'no price',
      value: r.total.toFixed(1),
      rate: r.perMap < 1 ? `1 in ${Math.round(1 / r.perMap)} maps` : `${r.perMap >= 10 ? r.perMap.toFixed(0) : r.perMap.toFixed(2)} / map`,
    }));
}

// Items used in at least 5% of maps; the rest are one-offs that clutter the list.
const cost = computed(() => perMapRows(detail.value?.items.cost ?? []).filter(c => c.perMap >= 0.05));
const loot = computed(() => perMapRows(detail.value?.items.loot ?? []));
const rareCount = computed(() => loot.value.filter(l => l.rare).length);
const shownLoot = computed(() => {
  if (rareOnly.value) return loot.value.filter(l => l.rare);
  return allLoot.value ? loot.value : loot.value.slice(0, LOOT_ROWS);
});

const perMap = computed(() => {
  const l = loot.value.reduce((s, r) => s + r.total, 0);
  const c = perMapRows(detail.value?.items.cost ?? []).reduce((s, r) => s + r.total, 0);
  return { loot: l, cost: c, profit: l - c };
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

const tagChips = computed(() => {
  const chips: { kind: string; label: string }[] = [];
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
.sd-top { padding: 12px 18px; border-bottom: 1px solid var(--line); display: flex; flex-direction: column; gap: 10px; }
.crumbs { display: flex; align-items: center; gap: 10px; font-size: 11px; }
.sd-back { padding: 0; font-size: 12px; font-weight: 600; background: none; border: none; color: var(--accent); cursor: pointer; }
.title-row { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.title-row h2 { margin: 0; font-size: 17px; font-weight: 700; color: var(--strong); }
.muted { font-size: 12px; color: var(--muted); }
.faint { color: var(--faint); }
.sd-views { margin-left: auto; }
.strip { display: flex; align-items: flex-start; gap: 28px; }
.strip .val { font-size: 16px; font-weight: 700; color: var(--strong); }
.strip .val.pos { color: var(--pos); }
.strip .val.neg { color: var(--neg); }
.strip .sub { font-size: 10px; color: var(--label); }
.strip .sub .pos, .strip .sub .neg { font-weight: 600; }
.tags { display: flex; gap: 5px; flex-wrap: wrap; }
.tag { font-size: 10.5px; padding: 1px 8px; border-radius: 999px; background: var(--chip); color: var(--muted); }
.tag.talent { background: var(--accent-bg); color: var(--accent-text); }
.tag.cost { background: rgba(248,113,113,0.1); color: var(--neg); }

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
.loot-list { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 3px; }
.loot-row { flex-shrink: 0; display: grid; grid-template-columns: 30px minmax(0, 1fr) 104px 56px; gap: 8px; align-items: center; padding: 3px 8px; border-radius: 8px; font-size: 11.5px; background: var(--panel); border: 1px solid var(--panel-border); }
.loot-row.rare { border-color: rgba(217,119,6,0.45); }
.loot-row .name { display: flex; align-items: center; gap: 6px; min-width: 0; color: var(--strong); }
.loot-row .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.loot-row .rate { font-size: 10.5px; color: var(--muted); }
.loot-row .rate.rare { color: var(--gold); }
.r { text-align: right; }
.strong { font-weight: 700; }
.sd-more { align-self: flex-start; margin-top: 4px; padding: 0; font-size: 11px; background: none; border: none; color: var(--accent); cursor: pointer; }
</style>
