import { computed, reactive } from 'vue';
import { validRow } from './state';
import type { StrategyRow } from './api';

// Strategies the user starred, with their own note. Saved locally and kept across seasons;
// each one keeps the numbers it had when it was saved, so it can be shown even after the
// strategy drops off the ladder.

export interface Favorite {
  key: string;
  stage: string;
  seasonId: string;
  savedAt: number;
  note: string;
  row: StrategyRow;
}

const KEY = 'tli_strategy_favorites';
const MAX = 200;
export const NOTE_MAX = 500;

function load(): Favorite[] {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? '[]');
    if (!Array.isArray(v)) return [];
    return v.slice(0, MAX).flatMap((f): Favorite[] => {
      const row = validRow(f?.row);
      if (!row || typeof f.stage !== 'string') return [];
      return [{
        key: row.key,
        stage: f.stage.slice(0, 40),
        seasonId: typeof f.seasonId === 'string' ? f.seasonId.slice(0, 20) : '',
        savedAt: typeof f.savedAt === 'number' ? f.savedAt : 0,
        note: typeof f.note === 'string' ? f.note.slice(0, NOTE_MAX) : '',
        row,
      }];
    });
  } catch {
    return [];
  }
}

const list = reactive<Favorite[]>(load());

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(list));
  } catch {
    // Storage full or blocked: favorites stay for this run only.
  }
}

export const favorites = computed(() => [...list].sort((a, b) => b.savedAt - a.savedAt));

export function favoriteOf(key: string): Favorite | undefined {
  return list.find(f => f.key === key);
}

export const favoritesFull = computed(() => list.length >= MAX);

// Never drops an older favorite to make room: when the list is full, nothing is added.
export function addFavorite(row: StrategyRow, stage: string, seasonId: string): boolean {
  if (favoriteOf(row.key)) return true;
  if (list.length >= MAX) return false;
  list.unshift({ key: row.key, stage, seasonId, savedAt: Date.now(), note: '', row: { ...row } });
  save();
  return true;
}

export function removeFavorite(key: string) {
  const i = list.findIndex(f => f.key === key);
  if (i < 0) return;
  list.splice(i, 1);
  save();
}

export function toggleFavorite(row: StrategyRow, stage: string, seasonId: string) {
  if (favoriteOf(row.key)) removeFavorite(row.key);
  else addFavorite(row, stage, seasonId);
}

export function setNote(key: string, note: string) {
  const f = favoriteOf(key);
  if (!f) return;
  f.note = note.slice(0, NOTE_MAX);
  save();
}
