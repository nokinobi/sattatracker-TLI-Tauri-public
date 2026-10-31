export interface TimelinePoint {
  t: number;
  v: number;
}

export interface RecordDrop {
  item_id: string;
  item_name: string;
  qty: number;
  price: number;
  // The recorded price, kept while the user has set their own for this map.
  originalPrice?: number;
}

export interface RecordExpense {
  id: string;
  name: string;
  qty: number;
  total: number;
  // The recorded cost, kept while the user has set their own price for this map.
  originalTotal?: number;
}

export interface MapRecord {
  id: string;
  sessionId: string;
  levelType: number;
  levelId: number;
  startedAt: number;
  endedAt: number;
  durationSec: number;
  profit: number;
  lootValue: number;
  expenseValue: number;
  lootCount: number;
  drops: RecordDrop[];
  expenses: RecordExpense[];
  timeline: TimelinePoint[];
}

export interface SessionRecord {
  id: string;
  startedAt: number;
  endedAt: number;
  timeSec: number;
  profit: number;
  maps: number;
  lootCount: number;
  name?: string;
}

export const MAX_SESSION_NAME = 60;
export const MAX_MAP_HISTORY = 500;
export const MAX_ARCHIVED_SESSIONS = 200;
export const MAX_RECORD_DROPS = 80;
export const MAX_TIMELINE_POINTS = 150;
