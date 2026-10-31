export function fmtDur(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  const ss = String(s % 60).padStart(2, '0');
  if (h > 0) return `${h}:${String(m % 60).padStart(2, '0')}:${ss}`;
  return `${String(m).padStart(2, '0')}:${ss}`;
}

export function fmtFE(v: number): string {
  const sign = v > 0 ? '+' : v < 0 ? '−' : '';
  const a = Math.abs(v);
  const body = a >= 10000 ? (a / 1000).toFixed(1) + 'k' : a >= 100 ? a.toFixed(0) : a.toFixed(1);
  return `${sign}${body}`;
}

export function fmtValue(v: number): string {
  if (v >= 10000) return (v / 1000).toFixed(1) + 'k';
  if (v >= 100) return v.toFixed(0);
  return v.toFixed(1);
}

export function fmtPrice(p: number): string {
  if (p >= 100) return p.toFixed(0);
  if (p >= 1) return p.toFixed(2);
  return p.toFixed(3);
}

export function fmtTime(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function fmtWhen(ms: number): string {
  const d = new Date(ms);
  const sameDay = d.toDateString() === new Date().toDateString();
  return sameDay ? fmtTime(ms) : `${d.toLocaleDateString([], { day: '2-digit', month: '2-digit' })} ${fmtTime(ms)}`;
}

export function fmtDate(ms: number): string {
  return new Date(ms).toLocaleDateString([], { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export function fmtFull(ms: number): string {
  return new Date(ms).toLocaleString([], {
    day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

// A number typed by hand, with a dot or comma for decimals. Null when it isn't one, or when it
// could mean two things: "1,500" is 1.5 with a decimal comma but 1500 with a thousands comma.
export function parseDecimal(text: string): number | null {
  const t = text.trim();
  if (!/^\d*[.,]?\d*$/.test(t) || !/\d/.test(t)) return null;
  if (/^[1-9]\d*,\d{3}$/.test(t)) return null;
  return Number(t.replace(',', '.'));
}

// Time left on something, e.g. "42 min left", "1 h 12 min left".
export function fmtLeft(ms: number): string {
  const min = Math.ceil(ms / 60000);
  if (min <= 1) return 'under 1 min left';
  if (min < 60) return `${min} min left`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} h ${m} min left` : `${h} h left`;
}

export function fmtAgo(ms: number, now: number): string {
  const min = Math.max(0, Math.round((now - ms) / 60000));
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min ago`;
  const h = Math.floor(min / 60);
  return `${h} h ago`;
}
