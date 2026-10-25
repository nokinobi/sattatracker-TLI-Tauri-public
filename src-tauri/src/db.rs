use lazy_static::lazy_static;
use serde_json::Value;
use std::collections::HashMap;

struct ItemInfo {
    name: String,
    item_type: String,
}

lazy_static! {
    static ref ITEM_DB: HashMap<String, ItemInfo> = {
        let json_str = include_str!("../data/en_id_table.json");
        let parsed: Value = serde_json::from_str(json_str).unwrap_or(Value::Null);

        let mut map = HashMap::new();
        if let Some(obj) = parsed.as_object() {
            for (id, data) in obj {
                if let Some(name) = data.get("name").and_then(|n| n.as_str()) {
                    let raw_type = data.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    map.insert(
                        id.clone(),
                        ItemInfo {
                            name: name.to_string(),
                            item_type: clean_type(raw_type),
                        },
                    );
                }
            }
        }
        map
    };
}

fn clean_type(raw: &str) -> String {
    let t = raw.trim_start_matches("\\n").trim();
    let mapped = match t {
        "崇高辅助技能" => "Noble Support Skill",
        "华贵辅助技能" => "Magnificent Support Skill",
        "精密技能" => "Precise Skill",
        "触媒" => "Activation Medium",
        "主动技能" => "Active Skill",
        "暗金" => "Legendary Gear",
        "Used in the TOWER Sequence system. Consumed after use." => "TOWER Sequence Mod",
        "A necessary item for adjusting Talent" => "Talent Item",
        "An item required to refine the gear energy value" => "Gear Refining Item",
        "Item obtained by recycling Compasses" => "Compass Recycling Item",
        "Item obtained by recycling Exclusive Support Skills" => "Skill Recycling Item",
        _ if t.starts_with("Proof of Reaching Level") => "Proof of the Brave",
        _ => t,
    };
    mapped.to_string()
}

pub struct DbManager;

impl DbManager {
    pub fn get_item_name(id: &str) -> String {
        ITEM_DB
            .get(id)
            .map(|i| i.name.clone())
            .unwrap_or_else(|| format!("Unknown Item ({})", id))
    }

    pub fn get_item_type(id: &str) -> String {
        ITEM_DB
            .get(id)
            .map(|i| i.item_type.clone())
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn types_are_cleaned() {
        assert_eq!(clean_type("\\nCompass"), "Compass");
        assert_eq!(clean_type("崇高辅助技能"), "Noble Support Skill");
        assert_eq!(clean_type("Proof of Reaching Level 11 of High Tower"), "Proof of the Brave");
        assert_eq!(clean_type("Beacon"), "Beacon");
    }

    #[test]
    fn known_item_has_type() {
        assert_eq!(DbManager::get_item_type("100300"), "Fuel");
        assert_eq!(DbManager::get_item_type("no-such-id"), "");
    }
}
