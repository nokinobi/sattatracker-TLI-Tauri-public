import data from './trees.json';

// Node: [x, y, kind, md5]; kind 0 start, 1 small, 2 medium, 3 large/special.
export type TreeNode = [number, number, number, string];
export interface Tree { n: TreeNode[]; l: [number, number][] }

export const TREES = data as unknown as Record<string, Tree>;
export const PROFOUND = '幽邃';

// `guessed`: taken nodes whose position the data can't confirm (an effect shared by several
// nodes, only some of which were taken, off any required path).
export interface Placement { root: number; taken: Set<number>; guessed: Set<number>; points: number; unplaced: number }

// Strategy data only says "talent md5 × count", not which nodes. Medium and large
// nodes are unique, so they are exact; small nodes sharing an effect are placed on
// the shortest path from the start node, which is how they are usually taken.
export function placePoints(tree: Tree, picked: Map<string, number>): Placement {
  const adj = new Map<number, number[]>();
  tree.l.forEach(([a, b]) => {
    adj.set(a, [...(adj.get(a) ?? []), b]);
    adj.set(b, [...(adj.get(b) ?? []), a]);
  });
  const root = Math.max(0, tree.n.findIndex(n => n[2] === 0));

  const dist = new Map<number, number>([[root, 0]]);
  const parent = new Map<number, number>();
  const queue = [root];
  while (queue.length) {
    const u = queue.shift()!;
    (adj.get(u) ?? []).forEach(v => {
      if (dist.has(v)) return;
      dist.set(v, dist.get(u)! + 1);
      parent.set(v, u);
      queue.push(v);
    });
  }

  const groups = new Map<string, number[]>();
  tree.n.forEach((n, i) => { if (n[3]) groups.set(n[3], [...(groups.get(n[3]) ?? []), i]); });
  const left = new Map<string, number>();
  picked.forEach((c, md5) => { if (groups.has(md5)) left.set(md5, c); });
  const points = [...left.values()].reduce((s, c) => s + c, 0);

  // Every node of a fully taken effect is required, and so is its path to the start.
  const need = new Set<number>();
  left.forEach((c, md5) => {
    const g = groups.get(md5)!;
    if (c < g.length) return;
    g.forEach(i => {
      let cur: number | undefined = i;
      while (cur !== undefined && !need.has(cur)) {
        need.add(cur);
        cur = parent.get(cur);
      }
    });
  });

  const taken = new Set<number>([root]);
  for (;;) {
    const frontier = new Set<number>();
    taken.forEach(u => (adj.get(u) ?? []).forEach(v => { if (!taken.has(v)) frontier.add(v); }));
    const next = [...frontier]
      .sort((a, b) => Number(need.has(b)) - Number(need.has(a)) || (dist.get(a) ?? 99) - (dist.get(b) ?? 99))
      .find(v => need.has(v) || (left.get(tree.n[v][3]) ?? 0) > 0);
    if (next === undefined) break;
    taken.add(next);
    const md5 = tree.n[next][3];
    if (left.has(md5)) left.set(md5, left.get(md5)! - 1);
  }
  const unplaced = [...left.values()].reduce((s, c) => s + Math.max(0, c), 0);
  const guessed = new Set<number>();
  taken.forEach(i => {
    const g = groups.get(tree.n[i][3]);
    if (i !== root && !need.has(i) && g && g.some(j => !taken.has(j))) guessed.add(i);
  });
  return { root, taken, guessed, points, unplaced };
}
