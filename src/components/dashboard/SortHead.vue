<template>
  <button
    type="button"
    :class="['dash-sort', { on: active }]"
    :title="`Sort by ${label.toLowerCase()}`"
    @click="$emit('sort')"
  >{{ label }}<span v-if="active" aria-hidden="true"> {{ dir === 'asc' ? '↑' : '↓' }}</span><span v-if="active" class="dash-sr">, sorted {{ dir === 'asc' ? 'low to high' : 'high to low' }}</span></button>
</template>

<script setup lang="ts">
import type { SortDir } from './useSort';

defineProps<{ label: string; active: boolean; dir: SortDir }>();
defineEmits(['sort']);
</script>
