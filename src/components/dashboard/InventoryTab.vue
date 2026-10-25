<template>
  <div class="inv">
    <div class="inv-top">
      <div class="inv-search-row">
        <label class="dash-input inv-search">
          <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.5" fill="none" stroke="var(--muted)" stroke-width="1.5"/><path d="M10.5 10.5L14 14" stroke="var(--muted)" stroke-width="1.5" stroke-linecap="round"/></svg>
          <input v-model="query" placeholder="Search your inventory" aria-label="Search inventory" />
          <span class="count">{{ filtered.length }} of {{ items.length }} items</span>
        </label>
        <div class="inv-total">
          <div class="dash-label">Inventory value</div>
          <div class="mono gold">{{ fmtValue(totalValue) }} <small>FE</small></div>
        </div>
      </div>
      <div class="inv-filters">
        <div class="chips" role="group" aria-label="Bag tab">
          <button v-for="c in pageChips" :key="c.id" :class="['dash-chip', { on: page === c.id }]" @click="page = c.id">
            {{ c.label }}<span class="n">{{ c.count }}</span>
          </button>
        </div>
        <div class="dash-seg" role="group" aria-label="Show">
          <button :class="{ on: !onlyBlocked }" @click="onlyBlocked = false">All</button>
          <button :class="{ on: onlyBlocked }" @click="onlyBlocked = true">Blocked</button>
        </div>
        <label class="sort">
          <span>Sort</span>
          <select v-model="sortBy">
            <option value="value">Total value</option>
            <option value="price">Unit price</option>
            <option value="qty">Quantity</option>
            <option value="name">Name</option>
          </select>
        </label>
      </div>
    </div>

    <div v-if="items.length === 0" class="dash-empty">
      No inventory data yet. Sort your bag in game once and it appears here.
    </div>
    <template v-else>
      <div class="inv-head">
        <span></span><span>Item</span><span>Bag tab</span><span class="r">Quantity</span><span class="r">Unit price</span><span class="r">Total</span><span></span>
      </div>
      <div class="inv-list dash-scroll">
        <div v-if="filtered.length === 0" class="dash-empty">Nothing matches</div>
        <div v-for="it in filtered" :key="it.item_id" :class="['inv-row', { blocked: it.blocked }]">
          <span class="dash-icon"><img :src="getIcon(it.item_id)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
          <span class="name">
            <span>{{ it.item_name }}</span>
            <small>{{ it.item_type || 'Unknown type' }}{{ it.price > 0 ? '' : ' · no market price' }}</small>
          </span>
          <span class="tab">{{ bagPageLabel(it.page_id) }}</span>
          <span class="mono r">{{ it.qty.toLocaleString() }}</span>
          <span class="mono r muted">{{ it.price > 0 ? fmtPrice(it.price) : '—' }}</span>
          <span class="mono r gold strong">{{ it.blocked || it.price <= 0 ? '—' : fmtValue(it.value) + ' FE' }}</span>
          <button
            class="block-btn"
            :title="it.blocked ? 'Count this item again' : 'Stop counting this item'"
            @click="toggleBlock(it.item_id, it.blocked)"
          >{{ it.blocked ? 'Unblock' : 'Block' }}</button>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useTrackerStore } from '../../stores/trackerStore';
import { getIcon } from '../../utils/assets';
import { BAG_PAGES, bagPageLabel } from './categories';
import { fmtPrice, fmtValue } from './format';

const store = useTrackerStore();

const query = ref('');
const page = ref<number | 'all'>('all');
const onlyBlocked = ref(false);
const sortBy = ref<'value' | 'price' | 'qty' | 'name'>('value');

const items = computed(() =>
  store.inventoryItems.map(i => ({
    ...i,
    value: i.price * i.qty,
    blocked: store.isBlocked(i.item_id),
  })),
);

const totalValue = computed(() => items.value.filter(i => !i.blocked).reduce((a, i) => a + i.value, 0));

const pageChips = computed(() => {
  const chips: Array<{ id: number | 'all'; label: string; count: number }> = [
    { id: 'all', label: 'All', count: items.value.length },
  ];
  for (const p of BAG_PAGES) {
    const count = items.value.filter(i => i.page_id === p.id).length;
    if (count > 0) chips.push({ id: p.id, label: p.label, count });
  }
  return chips;
});

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  const list = items.value.filter(i =>
    (page.value === 'all' || i.page_id === page.value)
    && (!onlyBlocked.value || i.blocked)
    && (!q || i.item_name.toLowerCase().includes(q) || (i.item_type ?? '').toLowerCase().includes(q)),
  );
  const by = sortBy.value;
  return list.sort((a, b) =>
    by === 'name' ? a.item_name.localeCompare(b.item_name)
      : by === 'qty' ? b.qty - a.qty
        : by === 'price' ? b.price - a.price
          : b.value - a.value,
  );
});

function toggleBlock(id: string, blocked: boolean) {
  if (blocked) store.unblockItem(id);
  else store.blockItem(id);
}
</script>

<style scoped>
.inv { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.inv-top { padding: 14px 18px 12px; border-bottom: 1px solid var(--line); display: flex; flex-direction: column; gap: 10px; }
.inv-search-row { display: flex; align-items: center; gap: 16px; }
.inv-search { flex: 1; padding: 9px 12px; }
.inv-search input { font-size: 13px; }
.inv-search .count { font-size: 11px; color: var(--label); white-space: nowrap; }
.inv-total { text-align: right; }
.inv-total .mono { font-size: 16px; font-weight: 700; }
.inv-total small { font-size: 11px; color: var(--label); }
.inv-filters { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.chips { display: flex; gap: 4px; flex-wrap: wrap; }
.inv-filters .dash-seg { margin-left: auto; }
.sort { display: flex; align-items: center; gap: 6px; font-size: 11px; color: var(--muted); }

.inv-head, .inv-row { display: grid; grid-template-columns: 30px minmax(0, 1fr) 140px 74px 74px 90px 64px; gap: 12px; align-items: center; }
.inv-head { padding: 8px 30px 4px; font-size: 9px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--label); }
.inv-list { flex: 1; min-height: 0; padding: 0 18px 14px; display: flex; flex-direction: column; gap: 4px; }
.inv-row { flex-shrink: 0; padding: 6px 12px; border-radius: 10px; background: var(--panel); border: 1px solid var(--panel-border); font-size: 12px; }
.inv-row.blocked { opacity: 0.55; }
.inv-row .name { min-width: 0; display: flex; flex-direction: column; font-weight: 600; color: var(--strong); }
.inv-row .name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.inv-row .name small { font-size: 10px; font-weight: 400; color: var(--label); }
.inv-row .tab { font-size: 11px; color: var(--muted); }
.r { text-align: right; }
.muted { color: var(--muted); }
.strong { font-weight: 700; font-size: 13px; }
.block-btn { justify-self: end; font-size: 10px; font-weight: 600; padding: 3px 8px; border-radius: 6px; cursor: pointer; background: transparent; border: 1px solid var(--chip-border); color: var(--muted); opacity: 0; }
.inv-row:hover .block-btn, .inv-row.blocked .block-btn { opacity: 1; }
</style>
