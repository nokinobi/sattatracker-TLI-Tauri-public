<template>
  <form class="pe" @submit.prevent="apply" @keydown.esc.stop="$emit('cancel')">
    <label class="fld">Price
      <input ref="input" v-model="text" class="mono" type="text" inputmode="decimal" maxlength="12" :aria-label="label" @focus="($event.target as HTMLInputElement).select()" /> FE each
    </label>
    <span class="hint">{{ hint }}</span>
    <button class="dash-btn small primary push" type="submit">Apply</button>
    <button class="dash-btn small" type="button" @click="$emit('cancel')">Cancel</button>
    <span v-if="ownError || error" class="err" role="alert">{{ ownError || error }}</span>
  </form>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { parseDecimal } from './format';

const props = defineProps<{
  unit: number;
  label: string;
  hint: string;
  error?: string;
}>();
const emit = defineEmits<{ cancel: []; apply: [price: number] }>();

const MAX_PRICE = 10_000_000;
const opened = String(Math.round(props.unit * 1000) / 1000);
const text = ref(opened);
const ownError = ref('');
const input = ref<HTMLInputElement | null>(null);

onMounted(() => input.value?.focus());

function apply() {
  // Left as it was opened: nothing to change, and the field holds a rounded value.
  if (text.value.trim() === opened) {
    emit('cancel');
    return;
  }
  const price = parseDecimal(text.value);
  if (price === null || price <= 0) {
    ownError.value = 'Enter a price above 0, like 1500 or 1.5.';
    return;
  }
  if (price > MAX_PRICE) {
    ownError.value = 'The price can be at most 10,000,000.';
    return;
  }
  ownError.value = '';
  emit('apply', price);
}
</script>

<style scoped>
.pe { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; padding: 8px 12px 8px 54px; border-top: 1px solid var(--line); font-size: 11px; color: var(--muted); }
.pe .fld { display: flex; align-items: center; gap: 6px; }
.pe input { box-sizing: border-box; width: 72px; padding: 3px 7px; border-radius: 6px; font-size: 12px; font-weight: 600; text-align: right; outline: none; color: var(--strong); background: var(--input); border: 1px solid var(--accent-border); }
.pe .hint { font-size: 10px; color: var(--label); }
.pe .push { margin-left: auto; }
.pe .dash-btn { align-self: center; }
.pe .err { flex-basis: 100%; font-weight: 600; color: var(--neg); }
</style>
