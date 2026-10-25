export const BAG_PAGES: Array<{ id: number; label: string }> = [
  { id: 100, label: 'Gear' },
  { id: 101, label: 'Skills' },
  { id: 102, label: 'Currency & materials' },
  { id: 103, label: 'Maps & compasses' },
  { id: 104, label: 'Other' },
];

export function bagPageLabel(pageId: number | undefined): string {
  return BAG_PAGES.find(p => p.id === pageId)?.label ?? 'Other';
}

export const PRICE_GROUPS = [
  'Equipment',
  'Skills',
  'Maps & compasses',
  'Currency & materials',
  'Vorax organs',
  'Memories',
] as const;

export type PriceGroup = typeof PRICE_GROUPS[number];

const GROUP_TYPES: Record<Exclude<PriceGroup, 'Currency & materials'>, string[]> = {
  'Equipment': ['Legendary', 'Legendary Gear', 'Gear Blueprint', 'Destiny', 'Prism'],
  'Skills': [
    'Noble Support Skill', 'Magnificent Support Skill', 'Tartarus Skill', 'Origin Tartarus Skill',
    'Precise Skill', 'Activation Medium', 'Active Skill', 'Modularization Skill', 'Skill Recycling Item',
  ],
  'Maps & compasses': [
    'Beacon', 'Compass', 'Probe', 'Season Compass', 'Fluorescent Memory', 'Primeval Core', 'Desire Core',
    'Void Sea Invitation', 'Dark Surge Edict', "Queen's Grace", "Queen's Wick", 'Divinity Slate',
    'Divinity Emblems', 'Compass Recycling Item', 'Proof of the Brave',
  ],
  'Vorax organs': [
    'Special Organ - Pre-fix', 'Special Organ - Suffix', 'Normal Organ', 'Core Organ', 'Suture',
    'Cutting Instrument', 'Imprint Material', 'Vorax Exchange Material', 'Vorax Amputated Limb',
    'Flawless Heart - Buff',
  ],
  'Memories': ['Memory Revival Material'],
};

const TYPE_TO_GROUP = new Map<string, PriceGroup>(
  Object.entries(GROUP_TYPES).flatMap(([group, types]) => types.map(t => [t, group as PriceGroup])),
);

export function priceGroup(itemType: string): PriceGroup {
  return TYPE_TO_GROUP.get(itemType) ?? 'Currency & materials';
}
