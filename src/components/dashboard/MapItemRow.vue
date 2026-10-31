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
    <form v-if="editing" class="mi-edit" @submit.prevent="apply" @keydown.esc="$emit('cancel')">
      <label class="fld">Price
        <input ref="input" v-model="text" class="mono" type="text" inputmode="decimal" maxlength="12" aria-label="Price per item for this map" @focus="($event.target as HTMLInputElement).select()" /> FE each
      </label>
      <span class="hint">Only this map. The item's price everywhere else doesn't change.</span>
      <button class="dash-btn small primary push" type="submit">Apply</button>
      <button class="dash-btn small" type="button" @click="$emit('cancel')">Cancel</button>
      <span v-if="error" class="err" role="alert">{{ error }}</span>
    </form>
  </div>
</template>

<script setup lang="ts">
import { nextTick, ref, watch } from 'vue';
import { getIcon } from '../../utils/assets';
import { fmtPrice } from './format';

const props = defineProps<{
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
}>();
const emit = defineEmits<{ edit: []; revert: []; cancel: []; apply: [price: number] }>();

const MAX_PRICE = 1e7;
const text = ref('');
const error = ref('');
const input = ref<HTMLInputElement | null>(null);

watch(() => props.editing, (open) => {
  if (!open) return;
  text.value = String(Math.round(props.unit * 1000) / 1000);
  error.value = '';
  void nextTick(() => input.value?.focus());
}, { immediate: true });

function apply() {
  const price = Number(text.value.trim().replace(',', '.'));
  if (!Number.isFinite(price) || price <= 0 || price > MAX_PRICE) {
    error.value = 'Enter a price above 0.';
    return;
  }
  emit('apply', price);
}
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
.mi-edit { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; padding: 8px 12px 8px 54px; border-top: 1px solid var(--line); font-size: 11px; color: var(--muted); }
.mi-edit .fld { display: flex; align-items: center; gap: 6px; }
.mi-edit input { box-sizing: border-box; width: 72px; padding: 3px 7px; border-radius: 6px; font-size: 12px; font-weight: 600; text-align: right; outline: none; color: var(--strong); background: var(--input); border: 1px solid var(--accent-border); }
.mi-edit .hint { font-size: 10px; color: var(--label); }
.mi-edit .push { margin-left: auto; }
.mi-edit .dash-btn { align-self: center; }
.mi-edit .err { flex-basis: 100%; font-weight: 600; color: var(--neg); }
</style>
