<template>
  <div :class="['mi', { edited, open: editing }]">
    <div class="mi-row">
      <span v-if="share !== undefined" class="share" :style="{ width: share + '%' }"></span>
      <span class="dash-icon"><img :src="getIcon(itemId)" alt="" @error="($event.target as HTMLImageElement).style.visibility = 'hidden'" /></span>
      <span class="name">
        <span>{{ name }}</span>
        <small>{{ detail }}<template v-if="edited"> · <b>edited, was {{ fmtPrice(was ?? 0) }}</b></template></small>
      </span>
      <span :class="['mono', 'value', edited ? 'accent' : tone]">{{ value }} FE</span>
      <button v-if="edited" class="dash-btn small act" title="Back to the recorded price" @click="$emit('revert')">Revert</button>
      <button
        v-else-if="editable"
        class="pencil"
        :aria-expanded="editing"
        :aria-label="`Edit the price of ${name} for this map`"
        title="Edit the price for this map only"
        @click="$emit('edit')"
      >
        <svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path d="M11 2.5l2.5 2.5L6 12.5l-3.2.7.7-3.2z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>
      </button>
    </div>
    <PriceEditor
      v-if="editing"
      :unit="unit"
      label="Price per item for this map"
      :hint="`Only this map. The item's price everywhere else doesn't change.${afterTax ? ' Enter the price after market tax, like the recorded one.' : ''}`"
      :error="error"
      @cancel="$emit('cancel')"
      @apply="$emit('apply', $event)"
    />
  </div>
</template>

<script setup lang="ts">
import { getIcon } from '../../utils/assets';
import { fmtPrice } from './format';
import PriceEditor from './PriceEditor.vue';

defineProps<{
  itemId: string;
  name: string;
  detail: string;
  value: string;
  tone: 'gold' | 'neg';
  unit: number;
  share?: number;
  edited: boolean;
  was?: number;
  editable: boolean;
  editing: boolean;
  afterTax?: boolean;
  error?: string;
}>();
defineEmits<{ edit: []; revert: []; cancel: []; apply: [price: number] }>();
</script>

<style scoped>
.mi { flex-shrink: 0; border-radius: 10px; overflow: hidden; background: var(--panel); border: 1px solid var(--panel-border); }
.mi.edited, .mi.open { border-color: var(--accent-border); }
.mi-row { position: relative; display: flex; align-items: center; gap: 12px; padding: 6px 12px; }
.mi-row .share { position: absolute; left: 0; top: 0; bottom: 0; background: var(--gold); opacity: 0.08; }
.mi-row .name { position: relative; flex: 1; min-width: 0; display: flex; flex-direction: column; font-size: 12px; font-weight: 600; color: var(--strong); }
.mi-row .name span, .mi-row .name small { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mi-row .name small { font-size: 10px; font-weight: 400; color: var(--label); }
.mi-row .name b { font-weight: 600; color: var(--accent-text); }
.mi-row .value { position: relative; flex-shrink: 0; font-size: 13px; font-weight: 700; }
.mi-row .value.accent { color: var(--accent-text); }
.mi-row .act { position: relative; align-self: center; flex-shrink: 0; }
.pencil { position: relative; flex-shrink: 0; width: 24px; height: 24px; padding: 0; display: flex; align-items: center; justify-content: center; border-radius: 6px; cursor: pointer; background: var(--chip); border: 1px solid var(--chip-border); color: var(--muted); }
.pencil:hover { border-color: var(--accent-border); color: var(--strong); }
</style>
