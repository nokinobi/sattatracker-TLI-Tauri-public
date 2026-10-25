<template>
  <div
    v-if="isOpen"
    class="fixed inset-0 z-[160] flex items-center justify-center pointer-events-auto"
    style="background: rgba(0,0,0,0.6);"
    @click.self="$emit('close')"
  >
    <div
      class="dash select-none"
      :data-theme="store.dashboardTheme"
      :style="{ zoom: store.dashboardFontScale, '--zoom': store.dashboardFontScale }"
    >
      <header class="dash-header">
        <div class="dash-brand">
          <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true"><path d="M10 2c2.5 3 4.5 5 4.5 8.5A4.5 4.5 0 0110 15a4.5 4.5 0 01-4.5-4.5C5.5 8 7 6.5 8 4.5c.8 1.6 1.4 2.4 2.5 3C10.8 5.6 10.6 3.8 10 2z" fill="none" stroke="var(--brand)" stroke-width="1.5" stroke-linejoin="round"/><path d="M4 18h12" stroke="var(--brand)" stroke-width="1.5" stroke-linecap="round"/></svg>
          <span>TLI Tracker</span>
        </div>

        <nav class="dash-tabs" aria-label="Tracker sections">
          <button
            v-for="t in tabs"
            :key="t.id"
            :class="['dash-tab', { on: tab === t.id }]"
            :aria-current="tab === t.id ? 'page' : undefined"
            @click="selectTab(t.id)"
          >
            {{ t.label }}
            <span v-if="t.badge" class="dash-badge">{{ t.badge }}</span>
          </button>
        </nav>

        <div class="dash-header-right">
          <span :class="['dash-status', tracking ? 'live' : 'idle']">
            <span class="dot"></span>{{ statusText }}
          </span>

          <button
            :class="['dash-btn', 'icon', { primary: showSettings }]"
            aria-label="Settings"
            title="Settings"
            @click="showSettings = !showSettings"
          >
            <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 4h6M11 4h3M2 8h2M7 8h7M2 12h8M13 12h1" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/><circle cx="9.5" cy="4" r="1.5" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="5.5" cy="8" r="1.5" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="11.5" cy="12" r="1.5" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>
          </button>

          <button class="dash-btn" title="Save this session and start a new one" @click="confirmReset = true">
            <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M13 8a5 5 0 11-1.5-3.6M13 2.5V5h-2.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
            New session
          </button>
          <button class="dash-btn icon" aria-label="Close" @click="$emit('close')">
            <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
          </button>
        </div>
      </header>

      <div class="dash-body">
        <OverviewTab v-if="tab === 'overview'" @open-map="openMap" />
        <SessionTab v-else-if="tab === 'session'" :focus-map-id="focusMapId" />
        <InventoryTab v-else-if="tab === 'inventory'" />
        <PricesTab v-else-if="tab === 'prices'" />
        <StrategiesTab v-else-if="tab === 'strategies'" />
      </div>

      <section v-if="showSettings" class="dash-settings" aria-label="Settings">
        <div class="head">
          <span class="title">Settings</span>
          <button class="close" aria-label="Close settings" @click="showSettings = false">
            <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
          </button>
        </div>

        <div class="field">
          <span class="dash-label">Theme</span>
          <div class="dash-seg wide" role="group" aria-label="Theme">
            <button :class="{ on: store.dashboardTheme === 'dark' }" @click="setTheme('dark')">
              <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true"><path d="M13.5 9.8A5.6 5.6 0 016.2 2.5a5.6 5.6 0 107.3 7.3z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>
              Dark
            </button>
            <button :class="{ on: store.dashboardTheme === 'light' }" @click="setTheme('light')">
              <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="3" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 1.5v1.6M8 12.9v1.6M1.5 8h1.6M12.9 8h1.6M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
              Light
            </button>
          </div>
        </div>

        <div class="field">
          <div class="row">
            <label class="dash-label" for="dash-text-size">Text size</label>
            <span class="mono pct">{{ Math.round(store.dashboardFontScale * 100) }}%</span>
          </div>
          <div class="row slider">
            <span class="a-small">A</span>
            <input
              id="dash-text-size"
              type="range" min="0.8" max="1.3" step="0.05"
              :value="store.dashboardFontScale"
              @input="setFontScale(Number(($event.target as HTMLInputElement).value))"
            />
            <span class="a-large">A</span>
          </div>
          <button class="dash-btn small" @click="setFontScale(1)">Reset to 100%</button>
        </div>

        <span class="note">Changes apply right away and are remembered.</span>
      </section>

      <div v-if="confirmReset" class="dash-confirm" @click.self="confirmReset = false">
        <div class="dash-confirm-box">
          <div class="title">Start a new session?</div>
          <p>
            Current session: {{ mapsLabel }} · {{ fmtFE(store.totalProfit) }} FE · {{ store.formattedSessionTimer }},
            started {{ fmtWhen(store.sessionStartedAt) }}.
          </p>
          <label class="name-field">
            <span class="dash-label">Session name (optional)</span>
            <input
              ref="nameInput"
              v-model="sessionName"
              :maxlength="MAX_SESSION_NAME"
              :placeholder="`e.g. Glacial Abyss T8, ${fmtWhen(store.sessionStartedAt)}`"
              @keydown.enter="startNewSession(true)"
            />
          </label>
          <p class="hint">
            Saved sessions stay in the Session tab under their name.
            Discarding deletes this session's {{ mapsLabel }} for good.
          </p>
          <div class="actions">
            <button class="dash-btn" @click="confirmReset = false">Cancel</button>
            <button :class="['dash-btn', 'danger', { armed: discardArmed }]" @click="discard">
              {{ discardArmed ? `Delete ${mapsLabel}?` : 'Discard and start new' }}
            </button>
            <button class="dash-btn primary" @click="startNewSession(true)">Save and start new</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import { invoke } from '@tauri-apps/api/core';
import { useTrackerStore } from '../../stores/trackerStore';
import { MAX_SESSION_NAME } from '../../types/history';
import { fmtFE, fmtWhen } from './format';
import OverviewTab from './OverviewTab.vue';
import SessionTab from './SessionTab.vue';
import InventoryTab from './InventoryTab.vue';
import PricesTab from './PricesTab.vue';
import StrategiesTab from './StrategiesTab.vue';

const props = defineProps<{ isOpen: boolean }>();
defineEmits(['close']);

const store = useTrackerStore();

type TabId = 'overview' | 'session' | 'inventory' | 'prices' | 'strategies';
const tab = ref<TabId>('overview');
const focusMapId = ref('');
const confirmReset = ref(false);
const showSettings = ref(false);
const sessionName = ref('');
const discardArmed = ref(false);
const nameInput = ref<HTMLInputElement | null>(null);

const sessionMaps = computed(() =>
  store.mapHistory.filter(m => m.sessionId === store.sessionId).length + (store.currentMapMeta ? 1 : 0),
);
const mapsLabel = computed(() => `${sessionMaps.value} ${sessionMaps.value === 1 ? 'map' : 'maps'}`);

const tabs = computed(() => [
  { id: 'overview' as TabId, label: 'Overview', badge: '' },
  { id: 'session' as TabId, label: 'Session', badge: sessionMaps.value ? String(sessionMaps.value) : '' },
  { id: 'inventory' as TabId, label: 'Inventory', badge: '' },
  { id: 'prices' as TabId, label: 'Prices', badge: '' },
  { id: 'strategies' as TabId, label: 'Strategies', badge: '' },
]);

const logFound = ref(true);
const tracking = computed(() => logFound.value);

const statusText = computed(() => {
  if (!logFound.value) return 'Not tracking · game log not found';
  if (store.currentMapMeta) return `Tracking · in map ${store.formattedMapTimer}`;
  return 'Tracking · in hideout';
});

async function checkLog() {
  try {
    const path = await invoke<string>('get_log_path');
    logFound.value = path !== 'Log file not found';
  } catch {
    logFound.value = false;
  }
}

function setTheme(theme: 'dark' | 'light') {
  store.dashboardTheme = theme;
  store.saveConfigToStorage();
}

function setFontScale(scale: number) {
  store.dashboardFontScale = Math.min(1.3, Math.max(0.8, Math.round(scale * 100) / 100));
  store.saveConfigToStorage();
}

function selectTab(id: TabId) {
  focusMapId.value = '';
  tab.value = id;
}

function openMap(id: string) {
  focusMapId.value = id;
  tab.value = 'session';
}

function startNewSession(save: boolean) {
  store.resetSession({ save, name: sessionName.value });
  confirmReset.value = false;
}

function discard() {
  if (!discardArmed.value) {
    discardArmed.value = true;
    return;
  }
  startNewSession(false);
}

watch(confirmReset, (open) => {
  sessionName.value = '';
  discardArmed.value = false;
  if (open) void nextTick(() => nameInput.value?.focus());
});

watch(() => props.isOpen, (open) => {
  if (open) void checkLog();
  else {
    confirmReset.value = false;
    showSettings.value = false;
  }
}, { immediate: true });
</script>

<style>
.dash {
  --brand: #fbbf24;
  --bg: linear-gradient(160deg, #0e0c16 0%, #0a0912 100%);
  --border: rgba(255,255,255,0.09);
  --line: rgba(255,255,255,0.06);
  --text: #e7e5ee;
  --strong: #f4f3f8;
  --muted: #a19fae;
  --label: #8b8898;
  --faint: #6b6878;
  --panel: rgba(255,255,255,0.03);
  --panel-border: rgba(255,255,255,0.06);
  --chip: rgba(255,255,255,0.04);
  --chip-border: rgba(255,255,255,0.1);
  --input: rgba(255,255,255,0.05);
  --accent: #60a5fa;
  --accent-bg: rgba(96,165,250,0.16);
  --accent-border: rgba(96,165,250,0.45);
  --accent-text: #bfdbfe;
  --pos: #4ade80;
  --neg: #f87171;
  --neg-soft: #fca5a5;
  --gold: #fbbf24;
  --live: #34d399;
  --live-bg: rgba(52,211,153,0.1);
  --live-border: rgba(52,211,153,0.3);
  --live-text: #a7f3d0;
  --tooltip: rgba(20,18,30,0.96);
  --shadow: 0 24px 80px rgba(0,0,0,0.85);

  width: 1080px;
  height: 660px;
  max-width: calc((100vw - 32px) / var(--zoom, 1));
  max-height: calc((100vh - 32px) / var(--zoom, 1));
  display: flex;
  flex-direction: column;
  overflow: hidden;
  position: relative;
  font-family: Inter, 'Segoe UI', system-ui, sans-serif;
  color: var(--text);
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 18px;
  box-shadow: var(--shadow);
}

.dash[data-theme='light'] {
  --brand: #d97706;
  --bg: linear-gradient(160deg, #fbfaf8 0%, #f2f1f6 100%);
  --border: rgba(20,18,30,0.12);
  --line: rgba(20,18,30,0.08);
  --text: #1c1a24;
  --strong: #15131c;
  --muted: #4a4757;
  --label: #5f5c6b;
  --faint: #8b8898;
  --panel: #ffffff;
  --panel-border: rgba(20,18,30,0.08);
  --chip: #ffffff;
  --chip-border: rgba(20,18,30,0.12);
  --input: #ffffff;
  --accent: #2563eb;
  --accent-bg: rgba(37,99,235,0.1);
  --accent-border: rgba(37,99,235,0.4);
  --accent-text: #1d4ed8;
  --pos: #15803d;
  --neg: #b91c1c;
  --neg-soft: #b91c1c;
  --gold: #a16207;
  --live: #16a34a;
  --live-bg: rgba(22,163,74,0.08);
  --live-border: rgba(22,163,74,0.3);
  --live-text: #166534;
  --tooltip: #ffffff;
  --shadow: 0 24px 80px rgba(0,0,0,0.35);
}

.dash button { font-family: inherit; }
.dash .mono { font-family: 'JetBrains Mono', Consolas, monospace; }

.dash-header { display: flex; align-items: center; gap: 22px; padding: 0 16px; height: 52px; flex-shrink: 0; border-bottom: 1px solid var(--line); }
.dash-brand { display: flex; align-items: center; gap: 8px; white-space: nowrap; font-size: 12px; font-weight: 800; letter-spacing: 2.5px; text-transform: uppercase; color: var(--strong); }
.dash-tabs { display: flex; align-self: stretch; gap: 2px; }
.dash-tab { display: flex; align-items: center; gap: 7px; padding: 0 12px; white-space: nowrap; font-size: 13px; font-weight: 600; color: var(--muted); background: none; border: none; cursor: pointer; }
.dash-tab:hover { color: var(--strong); }
.dash-tab.on { color: var(--strong); box-shadow: inset 0 -2px 0 var(--accent); }
.dash-badge { font: 600 10px 'JetBrains Mono', Consolas, monospace; padding: 1px 6px; border-radius: 999px; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.dash-tab.on .dash-badge { background: var(--accent-bg); border-color: var(--accent-border); color: var(--accent-text); }
.dash-header-right { margin-left: auto; display: flex; align-items: center; gap: 10px; }

.dash-status { display: flex; align-items: center; gap: 7px; white-space: nowrap; font-size: 11px; font-weight: 600; padding: 5px 10px; border-radius: 999px; }
.dash-status .dot { width: 7px; height: 7px; border-radius: 50%; }
.dash-status.live { background: var(--live-bg); border: 1px solid var(--live-border); color: var(--live-text); }
.dash-status.live .dot { background: var(--live); box-shadow: 0 0 0 3px var(--live-bg); }
.dash-status.idle { background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.dash-status.idle .dot { background: var(--faint); }

.dash-btn { display: flex; align-items: center; gap: 6px; white-space: nowrap; height: 32px; padding: 0 12px; font-size: 12px; font-weight: 600; border-radius: 8px; background: var(--chip); border: 1px solid var(--chip-border); color: var(--text); cursor: pointer; }
.dash-btn:hover { border-color: var(--accent-border); }
.dash-btn.icon { width: 32px; padding: 0; justify-content: center; }
.dash-btn.primary { background: var(--accent-bg); border-color: var(--accent-border); color: var(--accent-text); }
.dash-btn.danger { color: var(--neg); }
.dash-btn.danger:hover, .dash-btn.danger.armed { border-color: var(--neg); }
.dash-btn.danger.armed { background: var(--neg); color: #fff; }

.dash-seg { display: flex; padding: 2px; border-radius: 8px; background: var(--input); border: 1px solid var(--chip-border); }
.dash-seg button { min-width: 28px; height: 26px; padding: 0 9px; display: flex; align-items: center; justify-content: center; border-radius: 6px; border: none; background: transparent; color: var(--muted); font-size: 11px; font-weight: 600; cursor: pointer; }
.dash-seg button.on { background: var(--accent-bg); color: var(--accent-text); }

.dash-body { flex: 1; min-height: 0; display: flex; flex-direction: column; }

.dash-label { font-size: 9px; letter-spacing: 1.8px; text-transform: uppercase; color: var(--label); }
.dash-panel { border-radius: 12px; background: var(--panel); border: 1px solid var(--panel-border); }
.dash-chip { font-size: 11px; font-weight: 600; padding: 5px 10px; border-radius: 999px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.dash-chip .n { opacity: 0.7; margin-left: 3px; }
.dash-chip.on { background: var(--accent-bg); border-color: var(--accent-border); color: var(--accent-text); }
.dash-input { display: flex; align-items: center; gap: 8px; padding: 7px 10px; border-radius: 8px; background: var(--input); border: 1px solid var(--chip-border); }
.dash-input input { flex: 1; min-width: 0; background: none; border: none; outline: none; font-size: 12px; color: var(--strong); font-family: inherit; }
.dash-input input::placeholder { color: var(--label); }
.dash select { font-size: 12px; padding: 5px 8px; border-radius: 8px; background: var(--input); border: 1px solid var(--chip-border); color: var(--text); outline: none; font-family: inherit; }
.dash select option { background: #14121c; color: #e7e5ee; }
.dash[data-theme='light'] select option { background: #ffffff; color: #1c1a24; }
.dash-scroll { overflow-y: auto; }
.dash-scroll::-webkit-scrollbar { width: 6px; }
.dash-scroll::-webkit-scrollbar-thumb { background: var(--chip-border); border-radius: 3px; }
.dash-icon { width: 30px; height: 30px; flex-shrink: 0; border-radius: 8px; display: flex; align-items: center; justify-content: center; overflow: hidden; background: var(--chip); border: 1px solid var(--chip-border); }
.dash-icon img { width: 22px; height: 22px; object-fit: contain; }
.dash-empty { flex: 1; display: flex; align-items: center; justify-content: center; text-align: center; padding: 24px; font-size: 12px; color: var(--label); }
.pos { color: var(--pos); }
.neg { color: var(--neg); }
.gold { color: var(--gold); }

.dash-btn.small { height: 26px; padding: 0 10px; font-size: 11px; align-self: flex-start; }
.dash-seg.wide { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); }
.dash-seg.wide button { height: 30px; gap: 6px; font-size: 12px; }

.dash-settings { position: absolute; top: 58px; right: 96px; width: 300px; padding: 16px; border-radius: 14px; background: var(--bg); border: 1px solid var(--border); box-shadow: var(--shadow); display: flex; flex-direction: column; gap: 16px; z-index: 5; }
.dash-settings .head { display: flex; align-items: center; justify-content: space-between; }
.dash-settings .title { font-size: 14px; font-weight: 700; color: var(--strong); }
.dash-settings .close { display: flex; padding: 4px; border: none; background: none; color: var(--muted); cursor: pointer; }
.dash-settings .field { display: flex; flex-direction: column; gap: 8px; }
.dash-settings .row { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
.dash-settings .pct { font-size: 12px; font-weight: 700; color: var(--strong); }
.dash-settings .slider input { flex: 1; accent-color: var(--accent); }
.dash-settings .a-small { font-size: 11px; font-weight: 600; color: var(--muted); }
.dash-settings .a-large { font-size: 17px; font-weight: 600; color: var(--muted); }
.dash-settings .note { font-size: 10px; color: var(--label); }

.dash-confirm { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(0,0,0,0.45); }
.dash-confirm-box { width: 460px; padding: 18px; border-radius: 14px; background: var(--bg); border: 1px solid var(--border); box-shadow: var(--shadow); }
.dash-confirm-box .title { font-size: 15px; font-weight: 700; color: var(--strong); }
.dash-confirm-box p { font-size: 12px; line-height: 1.5; color: var(--muted); margin: 8px 0 16px; }
.dash-confirm-box .actions { display: flex; justify-content: flex-end; gap: 8px; }
.dash-confirm-box .name-field { display: flex; flex-direction: column; gap: 6px; }
.dash-confirm-box .name-field input { padding: 8px 10px; border-radius: 8px; font-size: 13px; font-family: inherit; background: var(--input); border: 1px solid var(--chip-border); color: var(--strong); outline: none; }
.dash-confirm-box .name-field input:focus { border-color: var(--accent-border); }
.dash-confirm-box .name-field input::placeholder { color: var(--label); }
.dash-confirm-box p.hint { font-size: 11px; margin: 10px 0 16px; color: var(--label); }
</style>
