<template>
  <div
    v-show="isVisible"
    class="absolute"
    :class="configuring ? 'pointer-events-auto' : 'pointer-events-none'"
    v-bind="configuring ? { 'data-interactive': '' } : {}"
    :style="{
      left: `${x}px`,
      top: `${y}px`,
      width: `${w}px`,
      zIndex: configuring ? 999 : 10,
      fontFamily: `'Segoe UI', Inter, system-ui, sans-serif`,
      color: '#f4f4f5',
      fontVariantNumeric: 'tabular-nums',
      '--fs': fs,
    }"
  >
    <div
      ref="boxRef"
      class="relative flex flex-col overflow-hidden select-none"
      :style="{
        height: `${h}px`,
        background: `rgba(16,16,20,${store.compactWindowOpacity})`,
        border: '1px solid rgba(255,255,255,0.12)',
        borderRadius: '6px',
        boxShadow: '0 6px 18px rgba(0,0,0,0.45)',
        outline: configuring ? '2px dashed #60a5fa' : 'none',
        outlineOffset: '3px',
      }"
    >
      <div ref="topRef" class="shrink-0 grid" style="grid-template-columns: minmax(0, 1.15fr) minmax(0, 1.15fr) minmax(0, 0.7fr); container-type: inline-size;">
        <div class="px-2 py-[5px] min-w-0" style="border-right: 1px solid rgba(255,255,255,0.08);">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em]" style="color: #a1a1aa;">Profit / hr</div>
          <div class="font-bold leading-[1.2] whitespace-nowrap truncate" style="font-size: calc(clamp(12px, 6cqw, 18px) * var(--fs));">
            {{ store.profitPerHour }}<span class="text-[length:calc(10px*var(--fs))] font-semibold" style="color: #a1a1aa;"> FE/h</span>
          </div>
          <div class="text-[length:calc(10px*var(--fs))] leading-[1.2]" style="color: #a1a1aa;">Session {{ store.formattedSessionTimer }}</div>
        </div>
        <div class="px-2 py-[5px] min-w-0" style="border-right: 1px solid rgba(255,255,255,0.08);">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em]" style="color: #a1a1aa;">Map profit</div>
          <div class="font-extrabold leading-[1.2] whitespace-nowrap truncate" :style="{ fontSize: 'calc(clamp(13px, 6.7cqw, 20px) * var(--fs))', color: mapProfit >= 0 ? '#4ade80' : '#f87171' }">
            {{ fmtSigned(mapProfit) }}<span class="text-[length:calc(10px*var(--fs))] font-semibold" style="color: #a1a1aa;"> FE</span>
          </div>
        </div>
        <div class="px-2 py-[5px] min-w-0">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em]" style="color: #a1a1aa;">Map</div>
          <div class="font-semibold leading-[1.5]" style="font-size: calc(clamp(12px, 5cqw, 15px) * var(--fs)); font-family: Consolas, 'Cascadia Mono', monospace; color: #fbbf24;">{{ store.formattedMapTimer }}</div>
        </div>
      </div>

      <template v-if="showLoot">
        <div class="shrink-0 flex items-baseline justify-between gap-2 px-2 py-[2px]" style="background: rgba(255,255,255,0.04); border-top: 1px solid rgba(255,255,255,0.08); border-bottom: 1px solid rgba(255,255,255,0.08);">
          <span class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.1em]" style="color: #fbbf24;">Loot</span>
          <span
            v-if="moreCount > 0"
            ref="hintRef"
            class="inline-flex items-center gap-1 text-[length:calc(10px*var(--fs))] italic whitespace-nowrap min-w-0"
            :style="hintStyle"
          >
            <svg width="1.1em" height="1.1em" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z" /><circle cx="12" cy="12" r="3" /></svg>
            <span class="truncate">{{ hintText }}</span>
          </span>
        </div>

        <div ref="listRef" class="relative flex-1 min-h-0 overflow-hidden px-1 py-[3px]">
          <div v-if="groupedDrops.length === 0 && listH >= emptyLine" class="h-full flex flex-col items-center justify-center gap-[2px] text-center">
            <div class="text-[length:calc(12px*var(--fs))]" style="color: #d4d4d8;">Waiting for drops…</div>
            <div v-if="costSum > 0 && listH >= emptyLine * 2" class="text-[length:calc(11px*var(--fs))]" style="color: #a1a1aa;">
              Need <span class="font-bold" style="color: #fca5a5;">{{ costSum.toFixed(1) }} FE</span> to break even
            </div>
          </div>

          <div class="flex flex-col gap-[2px]">
            <div
              v-for="item in visibleDrops"
              :key="item.item_id"
              class="flex items-center gap-[6px] px-1 rounded-[3px]"
              style="height: calc(22px*var(--fs)); background: rgba(255,255,255,0.05);"
            >
              <div class="w-[calc(18px*var(--fs))] h-[calc(18px*var(--fs))] shrink-0 rounded-[3px] flex items-center justify-center" style="background: rgba(0,0,0,0.35);">
                <img
                  :src="getIcon(item.item_id)"
                  @error="($event.target as HTMLImageElement).style.display='none'"
                  class="w-full h-full object-contain"
                />
              </div>
              <div class="flex-1 min-w-0 text-[length:calc(11px*var(--fs))] font-semibold truncate">{{ item.item_name }}</div>
              <div class="text-[length:calc(11px*var(--fs))]" style="color: #a1a1aa;">×{{ item.qty }}</div>
              <div class="w-[calc(40px*var(--fs))] text-right text-[length:calc(12px*var(--fs))] font-bold" style="color: #4ade80;">{{ fmtSigned(item.total) }}</div>
            </div>
          </div>
        </div>
      </template>

      <div
        v-if="configuring"
        class="absolute bottom-0 right-0 w-[16px] h-[16px] flex items-end justify-end p-[2px] cursor-nwse-resize"
        @mousedown.stop.prevent="startResize"
      >
        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="#60a5fa" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M15 6L6 15" /><path d="M15 11L11 15" /></svg>
      </div>
    </div>

    <button
      type="button"
      data-interactive
      class="absolute pointer-events-auto flex items-center justify-center rounded-full cursor-move"
      :style="{
        top: '-10px',
        right: '-10px',
        width: '22px',
        height: '22px',
        padding: 0,
        background: cfg ? '#2563eb' : 'rgba(16,16,20,0.85)',
        border: cfg ? '1px solid #93c5fd' : '1px solid rgba(255,255,255,0.25)',
        opacity: cfg ? 1 : 0.7,
      }"
      aria-label="Move, resize, opacity and text size"
      title="Drag to move · click to configure"
      @mousedown.stop.prevent="onHandleDown"
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 2v20" /><path d="M2 12h20" /><path d="M9 5l3-3 3 3" /><path d="M9 19l3 3 3-3" /><path d="M5 9l-3 3 3 3" /><path d="M19 9l3 3-3 3" /></svg>
    </button>

    <div
      v-if="cfg"
      class="mt-2 px-[10px] py-2 rounded-md flex flex-col gap-[6px]"
      style="background: rgba(16,16,20,0.96); border: 1px solid rgba(96,165,250,0.5);"
    >
      <div class="flex items-center gap-[10px]">
        <label for="compact-window-opacity" class="text-[12px] font-semibold" style="color: #e4e4e7;">Opacity</label>
        <input
          id="compact-window-opacity"
          type="range" min="30" max="100" step="5"
          :value="Math.round(store.compactWindowOpacity * 100)"
          @input="onOpacity"
          class="flex-1"
          style="accent-color: #60a5fa;"
        />
        <span class="w-[36px] text-right text-[12px]" style="color: #e4e4e7;">{{ Math.round(store.compactWindowOpacity * 100) }}%</span>
      </div>
      <div class="flex items-center gap-[10px]">
        <label for="compact-window-font" class="text-[12px] font-semibold" style="color: #e4e4e7;">Text size</label>
        <input
          id="compact-window-font"
          type="range" min="80" max="150" step="5"
          :value="Math.round(fs * 100)"
          @input="onFontScale"
          class="flex-1"
          style="accent-color: #60a5fa;"
        />
        <span class="w-[36px] text-right text-[12px]" style="color: #e4e4e7;">{{ Math.round(fs * 100) }}%</span>
      </div>
      <div class="flex items-center justify-between gap-2">
        <span class="text-[10px]" style="color: #a1a1aa;">Drag handle to move · corner to resize</span>
        <button
          type="button"
          class="px-3 py-1 rounded text-[12px] font-semibold"
          style="background: #2563eb; color: #ffffff; border: 0; cursor: pointer;"
          @click="cfg = false"
        >Done</button>
      </div>
    </div>

    <div
      v-if="panel"
      ref="panelRef"
      class="fixed pointer-events-none overflow-hidden"
      :style="{
        left: `${panel.left}px`,
        top: `${panel.top}px`,
        width: `${panel.width}px`,
        zIndex: 1000,
        background: '#101014',
        border: '1px solid rgba(251,191,36,0.45)',
        borderRadius: '6px',
        boxShadow: '0 10px 28px rgba(0,0,0,0.6)',
      }"
    >
      <div class="flex justify-between items-baseline px-2 py-[3px]" style="background: rgba(251,191,36,0.08); border-bottom: 1px solid rgba(255,255,255,0.08);">
        <span class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.1em]" style="color: #fbbf24;">All map loot</span>
        <span class="text-[length:calc(12px*var(--fs))] font-bold" style="color: #4ade80;">{{ fmtSigned(lootTotal) }}<span class="text-[length:calc(10px*var(--fs))] font-semibold" style="color: #a1a1aa;"> FE</span></span>
      </div>
      <div class="flex flex-col gap-[2px] px-1 py-[3px]">
        <div
          v-for="(item, idx) in panel.rows"
          :key="item.item_id"
          class="flex items-center gap-[6px] px-1 rounded-[3px]"
          :style="{ height: 'calc(22px*var(--fs))', background: idx >= visibleCount ? 'rgba(251,191,36,0.10)' : 'rgba(255,255,255,0.05)' }"
        >
          <div class="w-[calc(18px*var(--fs))] h-[calc(18px*var(--fs))] shrink-0 rounded-[3px] flex items-center justify-center" style="background: rgba(0,0,0,0.35);">
            <img
              :src="getIcon(item.item_id)"
              @error="($event.target as HTMLImageElement).style.display='none'"
              class="w-full h-full object-contain"
            />
          </div>
          <div class="flex-1 min-w-0 text-[length:calc(11px*var(--fs))] font-semibold truncate">{{ item.item_name }}</div>
          <div class="text-[length:calc(11px*var(--fs))]" style="color: #a1a1aa;">×{{ item.qty }}</div>
          <div class="w-[calc(40px*var(--fs))] text-right text-[length:calc(12px*var(--fs))] font-bold" style="color: #4ade80;">{{ fmtSigned(item.total) }}</div>
        </div>
        <div v-if="panel.hidden > 0" class="text-center text-[length:calc(10px*var(--fs))] leading-[16px]" style="color: #d4d4d8;">+{{ panel.hidden }} more</div>
      </div>
    </div>

    <div
      v-if="dragMode"
      data-interactive
      class="fixed inset-0 pointer-events-auto"
      :style="{ cursor: dragMode === 'move' ? 'move' : 'nwse-resize', zIndex: 100000 }"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useTrackerStore } from '../stores/trackerStore';
import { getIcon } from '../utils/assets';
import { cursorX, cursorY, updateCursor } from '../utils/cursor';

const WIDGET_ID = 'compactWindow';
const MIN_W     = 240;
const MAX_W     = 640;

const PANEL_GAP    = 6;
const SCREEN_PAD   = 8;
const HOVER_POLL   = 60;

const store = useTrackerStore();

const fs          = computed(() => store.compactWindowFontScale);
const rowStep     = computed(() => 22 * fs.value + 2);
const lootBar     = computed(() => 6 + 14 * fs.value);
const emptyLine   = computed(() => 17 * fs.value);
const panelChrome = computed(() => 15 + 16 * fs.value);
const moreRow     = computed(() => 2 + 16 * fs.value);

const topRef   = ref<HTMLElement | null>(null);
const listRef  = ref<HTMLElement | null>(null);
const boxRef   = ref<HTMLElement | null>(null);
const hintRef  = ref<HTMLElement | null>(null);
const panelRef = ref<HTMLElement | null>(null);

const x = ref(60);
const y = ref(120);
const w = ref(300);
const h = ref(280);

const cfg      = ref(false);
const dragMode = ref<'move' | 'resize' | null>(null);
const topH     = ref(60);
const listH    = ref(0);

const isVisible   = computed(() => store.widgetPositions.compactWindow?.show !== false);
const configuring = computed(() => cfg.value || store.isEditMode);

const showLoot = computed(() => h.value - topH.value >= lootBar.value);

const costSum   = computed(() => store.mapExpenses.reduce((s, e) => s + e.total, 0));
const mapProfit = computed(() => store.currentMapProfit);

const groupedDrops = computed(() => {
  const map = new Map<string, { item_id: string; item_name: string; qty: number; total: number }>();
  for (const d of store.currentMapDrops) {
    const value = d.price * d.qty;
    const existing = map.get(d.item_id);
    if (existing) {
      existing.qty   += d.qty;
      existing.total += value;
    } else {
      map.set(d.item_id, { item_id: d.item_id, item_name: d.item_name, qty: d.qty, total: value });
    }
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
});

const visibleCount = computed(() =>
  Math.min(groupedDrops.value.length, Math.max(0, Math.floor((listH.value + 2) / rowStep.value))));
const visibleDrops = computed(() => groupedDrops.value.slice(0, visibleCount.value));
const moreCount    = computed(() => groupedDrops.value.length - visibleCount.value);
const hintText     = computed(() => visibleCount.value === 0
  ? `${groupedDrops.value.length} items · hover to see all`
  : `+${moreCount.value} more · hover to see all`);

const hintStyle = computed(() => ({
  color: panel.value ? '#fbbf24' : '#a1a1aa',
  cursor: 'help',
}));

const lootTotal = computed(() => groupedDrops.value.reduce((s, d) => s + d.total, 0));

function fmtSigned(n: number): string {
  return (n >= 0 ? '+' : '−') + Math.abs(n).toFixed(1);
}

type LootRow = (typeof groupedDrops.value)[number];

interface PanelLayout {
  left:   number;
  top:    number;
  width:  number;
  rows:   LootRow[];
  hidden: number;
}

const panel = ref<PanelLayout | null>(null);

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), Math.max(lo, hi));
}

function layoutPanel(): PanelLayout | null {
  const box = boxRef.value?.getBoundingClientRect();
  if (!box) return null;
  const sw = window.innerWidth;
  const sh = window.innerHeight;
  const width = box.width;

  const all = groupedDrops.value;
  const maxH = sh - SCREEN_PAD * 2;
  let rows = all;
  let hidden = 0;
  if (panelChrome.value + all.length * rowStep.value - 2 > maxH) {
    const fit = Math.max(1, Math.floor((maxH - panelChrome.value - moreRow.value + 2) / rowStep.value));
    rows = all.slice(0, fit);
    hidden = all.length - fit;
  }
  const height = panelChrome.value + rows.length * rowStep.value - 2 + (hidden > 0 ? moreRow.value : 0);

  let left = box.left;
  let top: number;
  if (box.bottom + PANEL_GAP + height <= sh - SCREEN_PAD) {
    top = box.bottom + PANEL_GAP;
  } else if (box.top - PANEL_GAP - height >= SCREEN_PAD) {
    top = box.top - PANEL_GAP - height;
  } else {
    top = box.top;
    left = box.left + box.width / 2 < sw / 2 ? box.right + PANEL_GAP : box.left - PANEL_GAP - width;
  }

  return {
    left: clamp(left, SCREEN_PAD, sw - width - SCREEN_PAD),
    top:  clamp(top, SCREEN_PAD, sh - height - SCREEN_PAD),
    width,
    rows,
    hidden,
  };
}

function isOver(el: HTMLElement | null, pad: number): boolean {
  if (!el) return false;
  const r = el.getBoundingClientRect();
  return cursorX >= r.left - pad && cursorX <= r.right + pad && cursorY >= r.top - pad && cursorY <= r.bottom + pad;
}

function pollHover() {
  if (!isVisible.value || moreCount.value === 0 || dragMode.value) {
    panel.value = null;
    return;
  }
  const open = !!panel.value;
  const hovering = isOver(hintRef.value, 4)
    || (open && (isOver(boxRef.value, 0) || isOver(panelRef.value, PANEL_GAP + 2)));
  if (hovering && !open) panel.value = layoutPanel();
  else if (!hovering && open) panel.value = null;
}

watch(groupedDrops, () => { if (panel.value) panel.value = layoutPanel(); });

const onWindowMouseMove = (e: MouseEvent) => updateCursor(e.clientX, e.clientY);

let hoverInterval: ReturnType<typeof setInterval> | null = null;

let listObserver: ResizeObserver | null = null;
watch(listRef, (el) => {
  listObserver?.disconnect();
  listObserver = null;
  if (el) {
    listObserver = new ResizeObserver(([entry]) => { listH.value = entry.contentRect.height; });
    listObserver.observe(el);
  }
});

let startMouseX = 0, startMouseY = 0, initialA = 0, initialB = 0;
let handleMoved = false;

function onHandleDown(e: MouseEvent) {
  startMouseX = e.clientX;
  startMouseY = e.clientY;
  initialA = x.value;
  initialB = y.value;
  handleMoved = false;
  dragMode.value = 'move';
  window.addEventListener('mousemove', onMove);
  window.addEventListener('mouseup', onUp);
}

function startResize(e: MouseEvent) {
  startMouseX = e.clientX;
  startMouseY = e.clientY;
  initialA = w.value;
  initialB = h.value;
  dragMode.value = 'resize';
  window.addEventListener('mousemove', onMove);
  window.addEventListener('mouseup', onUp);
}

function onMove(e: MouseEvent) {
  const dx = e.clientX - startMouseX;
  const dy = e.clientY - startMouseY;
  if (dragMode.value === 'move') {
    if (!handleMoved && Math.abs(dx) + Math.abs(dy) < 3) return;
    handleMoved = true;
    x.value = Math.min(Math.max(0, initialA + dx), window.innerWidth - w.value);
    y.value = Math.min(Math.max(0, initialB + dy), window.innerHeight - 24);
  } else if (dragMode.value === 'resize') {
    w.value = Math.min(MAX_W, Math.max(MIN_W, initialA + dx));
    h.value = Math.max(topH.value + 2, initialB + dy);
  }
}

function onUp() {
  const wasMove = dragMode.value === 'move';
  dragMode.value = null;
  window.removeEventListener('mousemove', onMove);
  window.removeEventListener('mouseup', onUp);
  if (wasMove && !handleMoved) {
    cfg.value = !cfg.value;
    return;
  }
  store.updatePosition(WIDGET_ID, x.value, y.value, w.value, h.value);
  store.saveConfigToStorage();
}

function onFontScale(e: Event) {
  store.compactWindowFontScale = Number((e.target as HTMLInputElement).value) / 100;
  store.saveConfigToStorage();
}

function onOpacity(e: Event) {
  store.compactWindowOpacity = Number((e.target as HTMLInputElement).value) / 100;
  store.saveConfigToStorage();
}

function applySaved() {
  const saved = store.widgetPositions.compactWindow;
  if (!saved) return;
  x.value = saved.x;
  y.value = saved.y;
  if (saved.w) w.value = saved.w;
  if (saved.h) h.value = saved.h;
}

watch(() => store.widgetPositions.compactWindow, () => { if (!dragMode.value) applySaved(); }, { deep: true });

let topObserver: ResizeObserver | null = null;

onMounted(() => {
  applySaved();
  hoverInterval = setInterval(pollHover, HOVER_POLL);
  window.addEventListener('mousemove', onWindowMouseMove);
  if (topRef.value) {
    topObserver = new ResizeObserver(() => {
      const hTop = topRef.value?.offsetHeight ?? 0;
      if (hTop > 0) topH.value = hTop;
    });
    topObserver.observe(topRef.value);
  }
});

onUnmounted(() => {
  if (hoverInterval) clearInterval(hoverInterval);
  window.removeEventListener('mousemove', onWindowMouseMove);
  topObserver?.disconnect();
  listObserver?.disconnect();
  window.removeEventListener('mousemove', onMove);
  window.removeEventListener('mouseup', onUp);
});
</script>
