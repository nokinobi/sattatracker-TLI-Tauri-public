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
      '--cq': CQ_SCALE[cols],
    }"
  >
    <span
      v-if="fx && fx.pop"
      :key="`float-${fx.n}`"
      class="absolute pointer-events-none rounded-full font-extrabold whitespace-nowrap"
      :style="{
        left: `${fx.left}px`,
        top: '-12px',
        zIndex: 2,
        padding: '1px 7px',
        fontSize: 'calc(11px * var(--fs))',
        color: '#1c1405',
        background: '#fbbf24',
        boxShadow: '0 0 12px rgba(251,191,36,0.7)',
        opacity: 0,
        animation: 'cw-float 2.4s ease-out 1 forwards',
      }"
    >{{ fmtSigned(fx.value) }} FE</span>
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
        animation: fx && fx.glow ? `cw-glow-${fx.ab} 2.4s ease-out 1` : 'none',
      }"
    >
      <div ref="topRef" class="shrink-0 grid" :style="{ gridTemplateColumns: TOP_COLS[cols], containerType: 'inline-size' }">
        <div v-if="cols >= 2" class="px-2 py-[5px] min-w-0" style="border-right: 1px solid rgba(255,255,255,0.08);">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em] whitespace-nowrap truncate" style="color: #a1a1aa;">Profit / hr</div>
          <div class="font-bold leading-[1.2] whitespace-nowrap truncate" style="font-size: calc(clamp(12px, calc(6cqw * var(--cq)), 18px) * var(--fs));">
            {{ perHour }}<span class="text-[length:calc(10px*var(--fs))] font-semibold" style="color: #a1a1aa;"> FE/h</span>
          </div>
          <div class="text-[length:calc(10px*var(--fs))] leading-[1.2] whitespace-nowrap truncate" style="color: #a1a1aa;">Session {{ store.formattedSessionTimer }}</div>
        </div>
        <div ref="profitRef" class="px-2 py-[5px] min-w-0" :style="cols === 3 ? { borderRight: '1px solid rgba(255,255,255,0.08)' } : {}">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em] whitespace-nowrap truncate" style="color: #a1a1aa;">Map profit</div>
          <div
            class="font-extrabold leading-[1.2] whitespace-nowrap truncate"
            :style="{
              fontSize: 'calc(clamp(13px, calc(6.7cqw * var(--cq)), 20px) * var(--fs))',
              color: oneDecimal(mapProfit) >= 0 ? '#4ade80' : '#f87171',
              transformOrigin: 'left center',
              animation: fx && fx.pop ? `cw-pop-${fx.ab} 1.6s ease-out 1` : 'none',
            }"
          >
            {{ fmtSigned(mapProfit) }}<span class="text-[length:calc(10px*var(--fs))] font-semibold" style="color: #a1a1aa;"> FE</span>
          </div>
        </div>
        <div v-if="cols === 3" class="px-2 py-[5px] min-w-0">
          <div class="text-[length:calc(10px*var(--fs))] font-bold uppercase tracking-[0.08em] whitespace-nowrap truncate" style="color: #a1a1aa;">Map</div>
          <div class="font-semibold leading-[1.5]" style="font-size: calc(clamp(12px, 5cqw, 15px) * var(--fs)); font-family: Consolas, 'Cascadia Mono', monospace; color: #fbbf24;">{{ store.formattedMapTimer }}</div>
        </div>
      </div>

      <template v-if="showLoot">
        <div ref="barRef" class="shrink-0 flex items-baseline justify-between gap-2 px-2 py-[2px]" style="background: rgba(255,255,255,0.04); border-top: 1px solid rgba(255,255,255,0.08); border-bottom: 1px solid rgba(255,255,255,0.08);">
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
              :style="rowStyle(item.item_id)"
            >
              <div class="w-[calc(18px*var(--fs))] h-[calc(18px*var(--fs))] shrink-0 rounded-[3px] flex items-center justify-center" style="background: rgba(0,0,0,0.35);">
                <img
                  :src="getIcon(item.item_id)"
                  @error="($event.target as HTMLImageElement).style.display='none'"
                  class="w-full h-full object-contain"
                />
              </div>
              <svg v-if="highIds.has(item.item_id)" class="shrink-0" width="10" height="10" viewBox="0 0 12 12" role="img" aria-label="High-value drop"><path d="M6 1l5 5-5 5-5-5z" fill="#fbbf24" /></svg>
              <div v-if="cols > 1" class="flex-1 min-w-0 text-[length:calc(11px*var(--fs))] font-semibold truncate">{{ item.item_name }}</div>
              <div v-else class="flex-1" />
              <div v-if="cols > 1" class="text-[length:calc(11px*var(--fs))]" style="color: #a1a1aa;">×{{ item.qty }}</div>
              <div class="shrink-0 min-w-[calc(40px*var(--fs))] text-right text-[length:calc(12px*var(--fs))] font-bold whitespace-nowrap" style="color: #4ade80;">{{ fmtSigned(item.total) }}</div>
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
      ref="cfgRef"
      class="absolute px-[10px] py-2 rounded-md flex flex-col gap-[6px]"
      :style="{
        ...(cfgAbove ? { bottom: `calc(100% + ${CFG_GAP}px)` } : { top: `calc(100% + ${CFG_GAP}px)` }),
        ...(x + cfgW > viewW ? { right: 0 } : { left: 0 }),
        width: `${cfgW}px`,
        background: 'rgba(16,16,20,0.96)',
        border: '1px solid rgba(96,165,250,0.5)',
      }"
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
      <div class="h-px" style="background: rgba(255,255,255,0.08);" />
      <div class="flex items-center gap-[10px]">
        <label for="compact-window-high-value" class="text-[12px] font-semibold whitespace-nowrap" style="color: #fbbf24;">High-value drop</label>
        <input
          id="compact-window-high-value"
          type="range" min="0" :max="THRESHOLD_STEPS.length - 1" step="1"
          :value="thresholdIndex"
          :aria-valuetext="thresholdLabel"
          @input="onThreshold"
          class="flex-1 min-w-0"
          style="accent-color: #fbbf24;"
        />
        <span class="w-[64px] text-right text-[12px] whitespace-nowrap" style="color: #e4e4e7;">{{ thresholdLabel }}</span>
      </div>
      <div role="group" aria-label="High-value drop effect" class="flex gap-[2px] p-[2px] rounded-[7px]" style="background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.12);">
        <button
          v-for="e in EFFECTS"
          :key="e.id"
          type="button"
          :aria-pressed="store.compactHighValueEffect === e.id"
          class="flex-1 px-[6px] py-[3px] rounded-[5px] text-[11px] font-semibold whitespace-nowrap"
          :style="{
            border: 0,
            cursor: 'pointer',
            background: store.compactHighValueEffect === e.id ? '#2563eb' : 'transparent',
            color: store.compactHighValueEffect === e.id ? '#ffffff' : '#d4d4d8',
          }"
          @click="onEffect(e.id)"
        >{{ e.label }}</button>
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
          <div class="shrink-0 min-w-[calc(40px*var(--fs))] text-right text-[length:calc(12px*var(--fs))] font-bold whitespace-nowrap" style="color: #4ade80;">{{ fmtSigned(item.total) }}</div>
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
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { useTrackerStore } from '../stores/trackerStore';
import { getIcon } from '../utils/assets';
import { cursorX, cursorY, updateCursor } from '../utils/cursor';

const WIDGET_ID = 'compactWindow';
const RESIZE_SNAP = 12;
const MAX_W     = 640;

// Narrowing the window drops the top-row blocks one at a time: first the map timer,
// then profit/hr. Map profit always stays; its width is the window's minimum.
const FULL_W    = 240;
const TWO_COL_W = 185;
const ONE_COL_W = 100;
const TOP_COLS: Record<number, string> = {
  3: 'minmax(0, 1.15fr) minmax(0, 1.15fr) minmax(0, 0.7fr)',
  2: 'minmax(0, 1fr) minmax(0, 1fr)',
  1: 'minmax(0, 1fr)',
};
const CQ_SCALE: Record<number, number> = { 3: 1, 2: 1.3, 1: 2.2 };

type HighValueEffect = 'glow' | 'pop' | 'both' | 'off';
const EFFECTS: { id: HighValueEffect; label: string }[] = [
  { id: 'glow', label: 'Window glow' },
  { id: 'pop',  label: 'Profit pop' },
  { id: 'both', label: 'Both' },
  { id: 'off',  label: 'Off' },
];
const FX_MS = 2600;
// The overlay never takes keyboard focus from the game, so the threshold is a slider over
// fixed steps instead of a text field. 0 turns marking and effects off.
const THRESHOLD_STEPS = [0, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000];

const PANEL_GAP    = 6;
const CFG_GAP      = 8;
const SCREEN_PAD   = 8;
const HOVER_POLL   = 60;

const store = useTrackerStore();

const fs          = computed(() => store.compactWindowFontScale);
const rowStep     = computed(() => 22 * fs.value + 2);
const lootBar     = computed(() => 6 + 14 * fs.value);
const fullW       = computed(() => Math.round(FULL_W * fs.value));
const twoColW     = computed(() => Math.round(TWO_COL_W * fs.value));
const oneColW     = computed(() => Math.round(ONE_COL_W * fs.value));
const emptyLine   = computed(() => 17 * fs.value);
const panelChrome = computed(() => 15 + 16 * fs.value);
const moreRow     = computed(() => 2 + 16 * fs.value);

const topRef   = ref<HTMLElement | null>(null);
const listRef  = ref<HTMLElement | null>(null);
const barRef   = ref<HTMLElement | null>(null);
const boxRef   = ref<HTMLElement | null>(null);
const hintRef  = ref<HTMLElement | null>(null);
const panelRef = ref<HTMLElement | null>(null);
const cfgRef   = ref<HTMLElement | null>(null);
const profitRef = ref<HTMLElement | null>(null);

const x = ref(60);
const y = ref(120);
const w = ref(300);
const h = ref(280);

const cfg      = ref(false);
const dragMode = ref<'move' | 'resize' | null>(null);
const topH     = ref(60);
const listH    = ref(0);
const barH     = ref(20);

const isVisible   = computed(() => store.widgetPositions.compactWindow?.show !== false);
const configuring = computed(() => cfg.value || store.isEditMode);

const cols = computed(() => w.value >= fullW.value ? 3 : w.value >= twoColW.value ? 2 : 1);

// The settings panel opens below the window, or above it when the screen has no room
// below and more room above (e.g. a window parked near the bottom edge).
const cfgH = ref(110);
const viewH = ref(window.innerHeight);
const viewW = ref(window.innerWidth);
const cfgW  = computed(() => Math.max(w.value, 300));
const cfgAbove = computed(() => {
  const below = viewH.value - (y.value + h.value) - CFG_GAP;
  const above = y.value - CFG_GAP;
  return below < cfgH.value && above > below;
});
watch([cfg, fs], async ([open]) => {
  if (!open) return;
  viewH.value = window.innerHeight;
  viewW.value = window.innerWidth;
  await nextTick();
  if (cfgRef.value) cfgH.value = cfgRef.value.offsetHeight;
});

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
const hintText     = computed(() => {
  if (cols.value === 1) return visibleCount.value === 0 ? `${groupedDrops.value.length}` : `+${moreCount.value}`;
  const text = visibleCount.value === 0 ? `${groupedDrops.value.length} items` : `+${moreCount.value} more`;
  return cols.value === 3 ? `${text} · hover to see all` : text;
});

const hintStyle = computed(() => ({
  color: panel.value ? '#fbbf24' : '#a1a1aa',
  cursor: 'help',
}));

const lootTotal = computed(() => groupedDrops.value.reduce((s, d) => s + d.total, 0));

// High-value drops: rows stay marked for the rest of the map; the window glow and the
// map profit pop play once per drop, alternating keyframe names so back-to-back drops restart.
const highIds = ref(new Set<string>());
const fx = ref<{ n: number; ab: 'a' | 'b'; glow: boolean; pop: boolean; value: number; id: string; left: number } | null>(null);
let fxCount = 0;
let fxTimer: ReturnType<typeof setTimeout> | null = null;

watch(() => store.currentMapDrops, () => {
  highIds.value = new Set();
  fx.value = null;
});

watch(() => store.latestDrop, (drop) => {
  const threshold = store.compactHighValueThreshold;
  if (!drop || threshold <= 0) return;
  const value = drop.price * drop.qty;
  if (value < threshold) return;
  highIds.value = new Set(highIds.value).add(drop.item_id);
  const effect = store.compactHighValueEffect;
  if (effect === 'off') return;
  fxCount++;
  fx.value = {
    n: fxCount,
    ab: fxCount % 2 ? 'a' : 'b',
    glow: effect === 'glow' || effect === 'both',
    pop: effect === 'pop' || effect === 'both',
    value,
    id: drop.item_id,
    left: (profitRef.value?.offsetLeft ?? 0) + 8,
  };
  if (fxTimer) clearTimeout(fxTimer);
  fxTimer = setTimeout(() => { fx.value = null; }, FX_MS);
});

function rowStyle(id: string) {
  const high = highIds.value.has(id);
  return {
    height: 'calc(22px*var(--fs))',
    background: high ? 'rgba(251,191,36,0.12)' : 'rgba(255,255,255,0.05)',
    boxShadow: high ? 'inset 0 0 0 1px rgba(251,191,36,0.55)' : 'none',
    animation: fx.value && fx.value.id === id ? `cw-row-${fx.value.ab} 2.4s ease-out 1 forwards` : 'none',
  };
}

// Keeps big numbers short enough for the top row and the loot rows: one decimal below
// 1000, whole numbers up to 100k, then k and M (a profit/hr in the first seconds of a
// session can reach millions).
function fmtAmount(n: number): string {
  const a = Math.abs(n);
  if (a >= 999_950) return (a / 1e6).toFixed(a >= 9_999_500 ? 0 : 1) + 'M';
  if (a >= 99_999.5) return Math.round(a / 1e3) + 'k';
  if (a >= 999.95) return String(Math.round(a));
  return a.toFixed(1);
}

// The sign and colour follow the shown value, so -0.04 reads "+0.0" rather than a red "−0.0".
function oneDecimal(n: number): number {
  return Math.round(n * 10) / 10 || 0;
}

function fmtSigned(n: number): string {
  const r = oneDecimal(n);
  return (r >= 0 ? '+' : '−') + fmtAmount(r);
}

const perHour = computed(() => {
  const r = oneDecimal(Number(store.profitPerHour));
  return (r < 0 ? '−' : '') + fmtAmount(r);
});

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
  const width = Math.max(box.width, fullW.value);

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

// App.vue's click-through poll feeds the cursor while the overlay ignores the mouse, but it
// skips that in configure/edit mode, when the overlay catches the mouse itself: this keeps the
// hover list working then.
const onWindowMouseMove = (e: MouseEvent) => updateCursor(e.clientX, e.clientY);

// The hover poll only runs while there is a hidden part of the loot list to show.
let hoverInterval: ReturnType<typeof setInterval> | null = null;
watch(() => isVisible.value && moreCount.value > 0, (needed) => {
  if (needed && !hoverInterval) {
    hoverInterval = setInterval(pollHover, HOVER_POLL);
  } else if (!needed && hoverInterval) {
    clearInterval(hoverInterval);
    hoverInterval = null;
    panel.value = null;
  }
}, { immediate: true });

let barObserver: ResizeObserver | null = null;
watch(barRef, (el) => {
  barObserver?.disconnect();
  barObserver = null;
  if (el) {
    barObserver = new ResizeObserver(() => {
      const hBar = barRef.value?.offsetHeight ?? 0;
      if (hBar > 0) barH.value = hBar;
    });
    barObserver.observe(el);
  }
});

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
    let nextW = Math.min(MAX_W, Math.max(oneColW.value, initialA + dx));
    for (const snap of [fullW.value, twoColW.value]) {
      if (Math.abs(nextW - snap) <= RESIZE_SNAP) { nextW = snap; break; }
    }
    if (nextW - oneColW.value <= RESIZE_SNAP) nextW = oneColW.value;
    w.value = nextW;
    const minH = topH.value + 2;
    const headerH = minH + Math.max(barH.value, lootBar.value);
    let next = Math.max(minH, initialB + dy);
    if (Math.abs(next - headerH) <= RESIZE_SNAP) next = headerH;
    else if (next - minH <= RESIZE_SNAP) next = minH;
    h.value = next;
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

const thresholdIndex = computed(() => {
  const value = store.compactHighValueThreshold;
  let best = 0;
  THRESHOLD_STEPS.forEach((step, i) => {
    if (Math.abs(step - value) < Math.abs(THRESHOLD_STEPS[best] - value)) best = i;
  });
  return best;
});
const thresholdLabel = computed(() => {
  const value = THRESHOLD_STEPS[thresholdIndex.value];
  return value === 0 ? 'Off' : `≥ ${value} FE`;
});

function onThreshold(e: Event) {
  store.compactHighValueThreshold = THRESHOLD_STEPS[Number((e.target as HTMLInputElement).value)] ?? 100;
  store.saveConfigToStorage();
}

function onEffect(effect: HighValueEffect) {
  store.compactHighValueEffect = effect;
  store.saveConfigToStorage();
}

function onOpacity(e: Event) {
  store.compactWindowOpacity = Number((e.target as HTMLInputElement).value) / 100;
  store.saveConfigToStorage();
}

function applySaved() {
  const saved = store.widgetPositions.compactWindow;
  if (!saved) return;
  // A position saved on a bigger screen could put the click-through window out of reach.
  if (saved.w) w.value = Math.min(MAX_W, Math.max(oneColW.value, saved.w));
  if (saved.h) h.value = saved.h;
  x.value = Math.min(Math.max(0, saved.x), Math.max(0, window.innerWidth - w.value));
  y.value = Math.min(Math.max(0, saved.y), Math.max(0, window.innerHeight - 24));
}

watch(() => store.widgetPositions.compactWindow, () => { if (!dragMode.value) applySaved(); }, { deep: true });

let topObserver: ResizeObserver | null = null;

onMounted(() => {
  applySaved();
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
  if (fxTimer) clearTimeout(fxTimer);
  window.removeEventListener('mousemove', onWindowMouseMove);
  topObserver?.disconnect();
  barObserver?.disconnect();
  listObserver?.disconnect();
  window.removeEventListener('mousemove', onMove);
  window.removeEventListener('mouseup', onUp);
});
</script>

<style>
@keyframes cw-glow-a {
  0%   { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 0 rgba(251,191,36,0); border-color: rgba(255,255,255,.12); }
  12%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 3px rgba(251,191,36,.95), 0 0 34px 10px rgba(251,191,36,.55); border-color: #fbbf24; }
  40%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 2px rgba(251,191,36,.6), 0 0 18px 4px rgba(251,191,36,.3); border-color: #fbbf24; }
  55%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 3px rgba(251,191,36,.9), 0 0 30px 8px rgba(251,191,36,.5); border-color: #fbbf24; }
  100% { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 0 rgba(251,191,36,0); border-color: rgba(255,255,255,.12); }
}
@keyframes cw-glow-b {
  0%   { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 0 rgba(251,191,36,0); border-color: rgba(255,255,255,.12); }
  12%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 3px rgba(251,191,36,.95), 0 0 34px 10px rgba(251,191,36,.55); border-color: #fbbf24; }
  40%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 2px rgba(251,191,36,.6), 0 0 18px 4px rgba(251,191,36,.3); border-color: #fbbf24; }
  55%  { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 3px rgba(251,191,36,.9), 0 0 30px 8px rgba(251,191,36,.5); border-color: #fbbf24; }
  100% { box-shadow: 0 6px 18px rgba(0,0,0,.45), 0 0 0 0 rgba(251,191,36,0); border-color: rgba(255,255,255,.12); }
}
@keyframes cw-pop-a {
  0%   { transform: scale(1); color: #4ade80; text-shadow: none; }
  18%  { transform: scale(1.25); color: #fde047; text-shadow: 0 0 14px rgba(250,204,21,.85); }
  45%  { transform: scale(1.08); color: #fde047; text-shadow: 0 0 8px rgba(250,204,21,.6); }
  100% { transform: scale(1); color: #4ade80; text-shadow: none; }
}
@keyframes cw-pop-b {
  0%   { transform: scale(1); color: #4ade80; text-shadow: none; }
  18%  { transform: scale(1.25); color: #fde047; text-shadow: 0 0 14px rgba(250,204,21,.85); }
  45%  { transform: scale(1.08); color: #fde047; text-shadow: 0 0 8px rgba(250,204,21,.6); }
  100% { transform: scale(1); color: #4ade80; text-shadow: none; }
}
@keyframes cw-float {
  0%   { opacity: 0; transform: translateY(8px); }
  12%  { opacity: 1; transform: translateY(0); }
  75%  { opacity: 1; transform: translateY(-14px); }
  100% { opacity: 0; transform: translateY(-22px); }
}
@keyframes cw-row-a {
  0%   { background: rgba(251,191,36,.55); }
  100% { background: rgba(251,191,36,.12); }
}
@keyframes cw-row-b {
  0%   { background: rgba(251,191,36,.55); }
  100% { background: rgba(251,191,36,.12); }
}
</style>
