export function mean(values: number[]): number {
  return values.length ? values.reduce((a, v) => a + v, 0) / values.length : 0;
}

// Sample standard deviation: how far a value usually lands from the average.
export function stdev(values: number[]): number {
  if (values.length < 2) return 0;
  const m = mean(values);
  return Math.sqrt(values.reduce((a, v) => a + (v - m) * (v - m), 0) / (values.length - 1));
}

export function median(values: number[]): number {
  if (values.length === 0) return 0;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

export interface SpreadStats {
  avg: number;
  sd: number;
  median: number;
  low: number;
  high: number;
  // How many values lie within one dispersion of the average.
  inside: number;
  losing: number;
  best: number;
  worst: number;
}

export function spreadStats(values: number[]): SpreadStats {
  const avg = mean(values);
  const sd = stdev(values);
  const low = avg - sd;
  const high = avg + sd;
  return {
    avg,
    sd,
    median: median(values),
    low,
    high,
    inside: values.filter(v => v >= low && v <= high).length,
    losing: values.filter(v => v < 0).length,
    best: values.length ? Math.max(...values) : 0,
    worst: values.length ? Math.min(...values) : 0,
  };
}

// A round step (1, 2 or 5 times a power of ten) that splits the span into about this many parts.
export function niceStep(span: number, parts: number): number {
  const raw = Math.max(span, 0.001) / parts;
  const pow = Math.pow(10, Math.floor(Math.log10(raw)));
  const f = raw / pow;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * pow;
}

export interface Bin {
  from: number;
  to: number;
  count: number;
}

// Counts the values per range of equal width, with no gaps from the lowest to the highest.
export function histogram(values: number[], parts: number): { bins: Bin[]; step: number } {
  const lo = values.length ? Math.min(...values) : 0;
  const hi = values.length ? Math.max(...values) : 0;
  const step = niceStep(Math.max(hi - lo, 1), parts);
  const first = Math.floor(lo / step);
  const size = Math.floor(hi / step) - first + 1;
  const bins: Bin[] = Array.from({ length: size }, (_, i) => ({
    from: (first + i) * step,
    to: (first + i + 1) * step,
    count: 0,
  }));
  values.forEach(v => { bins[Math.min(size - 1, Math.floor(v / step) - first)].count += 1; });
  return { bins, step };
}
