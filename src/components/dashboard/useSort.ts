import { ref, type Ref } from 'vue';

export type SortDir = 'asc' | 'desc';

// Sort state for one dashboard table, remembered between runs. `columns` gives each sortable
// column the direction it starts with: numbers high to low, names A to Z.
export function useSort<C extends Record<string, SortDir>>(table: string, columns: C, initial: keyof C & string) {
  type K = keyof C & string;
  const storageKey = `tli_sort_${table}`;
  const key = ref(initial) as Ref<K>;
  const dir = ref<SortDir>(columns[initial]);

  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) ?? 'null');
    if (saved && Object.prototype.hasOwnProperty.call(columns, saved.key) && (saved.dir === 'asc' || saved.dir === 'desc')) {
      key.value = saved.key;
      dir.value = saved.dir;
    }
  } catch {
    // A missing or broken saved sort just means the default order.
  }

  function toggle(column: K) {
    if (key.value === column) dir.value = dir.value === 'asc' ? 'desc' : 'asc';
    else {
      key.value = column;
      dir.value = columns[column];
    }
    try {
      localStorage.setItem(storageKey, JSON.stringify({ key: key.value, dir: dir.value }));
    } catch {
      // Remembering the sort is a convenience; ignore storage errors.
    }
  }

  return { key, dir, toggle };
}

// Sorted copy of a list. Rows without a value (no price, blocked) stay last in both directions.
export function sortedBy<T>(list: T[], value: (row: T) => number | string | null, dir: SortDir): T[] {
  return [...list].sort((a, b) => {
    const x = value(a);
    const y = value(b);
    if (x === null || y === null) return x === y ? 0 : x === null ? 1 : -1;
    const c = typeof x === 'string' ? x.localeCompare(String(y)) : x - (y as number);
    return dir === 'asc' ? c : -c;
  });
}
