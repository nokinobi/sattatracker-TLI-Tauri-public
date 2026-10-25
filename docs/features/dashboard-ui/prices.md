# Prices

Every price the tracker knows, grouped by item type. Part of the [Dashboard](../dashboard-ui.md).

![Prices tab](img/prices.png)

- **Main type** (left): Equipment, Skills, Maps & compasses, Currency & materials, Vorax organs and Memories, with item counts.
- **Sub type** chips: the item types inside the chosen main type, for example Legendary, Destiny and Prism under Equipment, or Noble and Magnificent support skills under Skills.
- **Search** within the selection, **Price** min and max, **All / Counted / Blocked**, and **Sort** by price or name.
- **In bag** shows how many of the item you have. Items you own have a highlighted border.
- Bottom left: when the prices were last updated and when the next refresh is due (every 10 minutes while the tracker runs). Before the first download it says the tracker is using saved prices.

Main and sub types come from the item table bundled with the tracker (`src-tauri/data/en_id_table.json`). Types that are not listed under another main type fall under Currency & materials.

## Code

- `src/components/dashboard/PricesTab.vue`
- `src/components/dashboard/categories.ts`: the main types and which item types belong to them.
- `src-tauri/src/pricing.rs`: the time of the last successful price refresh.
