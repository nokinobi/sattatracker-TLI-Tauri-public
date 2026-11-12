use std::collections::HashMap;

#[derive(Clone, Debug)]
pub struct SlotState {
    pub item_id: String,
    pub qty: u32,
}

#[derive(Debug)]
pub enum SlotDelta {
    Gained(String, u32),
    Lost(String, u32),
    Swapped { new_item_id: String, new_qty: u32 },
    None,
}

pub struct BagManager {
    slots: HashMap<String, SlotState>,
}

impl BagManager {
    pub fn new() -> Self {
        Self {
            slots: HashMap::new(),
        }
    }

    pub fn init_slot(&mut self, page_id: u32, slot_id: u32, item_id: &str, qty: u32) {
        let key = Self::key(page_id, slot_id);
        self.slots.insert(
            key,
            SlotState {
                item_id: item_id.to_string(),
                qty,
            },
        );
    }

    pub fn update_slot(
        &mut self,
        page_id: u32,
        slot_id: u32,
        item_id: &str,
        qty: u32,
    ) -> SlotDelta {
        let key = Self::key(page_id, slot_id);

        let delta = match self.slots.get(&key) {
            // A slot the tracker hasn't seen yet. The game logs the bag's contents (`InitBagData`)
            // at login and after a bag sort, and the tracker reads the whole current log when it
            // starts, so this only happens to a stack with no `InitBagData` line in that log. Its
            // new size is only the starting point; counting it would add the whole stack as loot.
            // New stacks come as `ItemChange@ Add` and are counted there.
            None => SlotDelta::None,
            Some(old) if old.item_id == item_id => {
                if qty > old.qty {
                    SlotDelta::Gained(item_id.to_string(), qty - old.qty)
                } else if qty < old.qty {
                    SlotDelta::Lost(item_id.to_string(), old.qty - qty)
                } else {
                    SlotDelta::None
                }
            }
            Some(_) => {
                if qty > 0 {
                    SlotDelta::Swapped {
                        new_item_id: item_id.to_string(),
                        new_qty: qty,
                    }
                } else {
                    SlotDelta::None
                }
            }
        };

        self.slots.insert(
            key,
            SlotState {
                item_id: item_id.to_string(),
                qty,
            },
        );
        delta
    }

    pub fn remove_slot(&mut self, page_id: u32, slot_id: u32) -> Option<SlotState> {
        let key = Self::key(page_id, slot_id);
        self.slots.remove(&key)
    }

    pub fn clear_page(&mut self, page_id: u32) {
        self.slots
            .retain(|k, _| !k.starts_with(&format!("{}:", page_id)));
    }

    pub fn reset(&mut self) {
        self.slots.clear();
    }

    fn key(page_id: u32, slot_id: u32) -> String {
        format!("{}:{}", page_id, slot_id)
    }

    pub fn get_all_main_inventory_items(&self) -> HashMap<String, u32> {
        let mut result: HashMap<String, u32> = HashMap::new();
        for (key, slot) in &self.slots {
            if slot.qty == 0 {
                continue;
            }
            let page_id: u32 = key
                .split(':')
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            if Self::is_main_inventory(page_id) {
                *result.entry(slot.item_id.clone()).or_insert(0) += slot.qty;
            }
        }
        result
    }

    pub fn get_main_inventory_pages(&self) -> HashMap<String, u32> {
        let mut result: HashMap<String, u32> = HashMap::new();
        for (key, slot) in &self.slots {
            if slot.qty == 0 {
                continue;
            }
            let page_id: u32 = key
                .split(':')
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            if Self::is_main_inventory(page_id) {
                let page = result.entry(slot.item_id.clone()).or_insert(page_id);
                *page = (*page).min(page_id);
            }
        }
        result
    }

    pub fn is_main_inventory(page_id: u32) -> bool {
        (100..=104).contains(&page_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unknown_stack_is_a_starting_point_not_loot() {
        let mut bag = BagManager::new();
        assert!(matches!(bag.update_slot(102, 0, "100300", 3707), SlotDelta::None));
        assert!(matches!(
            bag.update_slot(102, 0, "100300", 3709),
            SlotDelta::Gained(ref id, 2) if id == "100300"
        ));
        assert!(matches!(
            bag.update_slot(102, 0, "100300", 3700),
            SlotDelta::Lost(ref id, 9) if id == "100300"
        ));
    }

    #[test]
    fn a_known_slot_still_counts_its_first_change() {
        let mut bag = BagManager::new();
        bag.init_slot(103, 5, "6002", 10);
        assert!(matches!(bag.update_slot(103, 5, "6002", 12), SlotDelta::Gained(_, 2)));
        assert!(matches!(
            bag.update_slot(103, 5, "6004", 3),
            SlotDelta::Swapped { new_qty: 3, .. }
        ));
    }
}
