//! Read-only proxy for the strategy leaderboard API, used by the dashboard's
//! Strategies tab. The webview can't call the server itself (no CORS), and it
//! rate-limits, so every response is cached and player identities are dropped.

use lazy_static::lazy_static;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const MAX_BODY_BYTES: usize = 4 * 1024 * 1024;
const MAX_CACHE_ENTRIES: usize = 300;
// Mechanics are sent as all their talent node ids (~35 × 43 chars each), so allow several.
const MAX_PARAM_LEN: usize = 8000;
const LIST_TTL: Duration = Duration::from_secs(5 * 60);
const DETAIL_TTL: Duration = Duration::from_secs(30 * 60);
const DEFAULT_SEASON: u32 = 1601;

const ENDPOINTS: [&str; 4] = ["stage-options", "leaderboard", "tags", "detail"];
const PARAMS: [&str; 8] = [
    "stage",
    "sort",
    "limit",
    "offset",
    "minCount",
    "tags",
    "excludeTags",
    "strategyKey",
];
const PRIVATE_KEYS: [&str; 5] = [
    "userId",
    "playerId",
    "playerName",
    "heroId",
    "heroPurchaseId",
];

struct Entry {
    at: Instant,
    body: Value,
}

lazy_static! {
    static ref CACHE: Mutex<HashMap<String, Entry>> = Mutex::new(HashMap::new());
}

static SEASON: AtomicU32 = AtomicU32::new(0);

/// Season detected from the game log by the tailer.
pub fn set_season(id: u32) {
    SEASON.store(id, Ordering::Relaxed);
}

fn season() -> u32 {
    match SEASON.load(Ordering::Relaxed) {
        0 => DEFAULT_SEASON,
        id => id,
    }
}

fn ttl(endpoint: &str) -> Duration {
    match endpoint {
        "detail" | "stage-options" => DETAIL_TTL,
        _ => LIST_TTL,
    }
}

fn validate(
    endpoint: &str,
    query: &HashMap<String, String>,
) -> Result<Vec<(String, String)>, String> {
    if !ENDPOINTS.contains(&endpoint) {
        return Err(format!("unknown strategy endpoint: {}", endpoint));
    }
    let mut params: Vec<(String, String)> = Vec::new();
    for (k, v) in query {
        if !PARAMS.contains(&k.as_str()) {
            return Err(format!("parameter not allowed: {}", k));
        }
        let v = v.trim();
        if v.is_empty() {
            continue;
        }
        if v.len() > MAX_PARAM_LEN || v.chars().any(char::is_control) {
            return Err(format!("bad value for {}", k));
        }
        params.push((k.clone(), v.to_string()));
    }
    params.push(("seasonId".to_string(), season().to_string()));
    params.sort();
    Ok(params)
}

fn cache_key(endpoint: &str, params: &[(String, String)]) -> String {
    let q: Vec<String> = params.iter().map(|(k, v)| format!("{}={}", k, v)).collect();
    format!("{}?{}", endpoint, q.join("&"))
}

fn strip_private(v: &mut Value) {
    match v {
        Value::Object(map) => {
            for k in PRIVATE_KEYS {
                map.remove(k);
            }
            map.values_mut().for_each(strip_private);
        }
        Value::Array(list) => list.iter_mut().for_each(strip_private),
        _ => {}
    }
}

async fn fetch(endpoint: &str, params: &[(String, String)]) -> Result<Value, String> {
    let client = crate::net::client(Duration::from_secs(15))?;
    let mut last_err = String::from("no strategy server reachable");
    for base in crate::pricing::api_bases() {
        let mut url = match reqwest::Url::parse(&format!("{}/api/strategy/{}", base, endpoint)) {
            Ok(u) => u,
            Err(e) => {
                last_err = e.to_string();
                continue;
            }
        };
        url.query_pairs_mut().extend_pairs(params);
        let resp = match client.get(url).send().await {
            Ok(r) => r,
            Err(e) => {
                last_err = e.to_string();
                continue;
            }
        };
        let status = resp.status();
        match status.as_u16() {
            429 => {
                last_err = "The strategy server is rate limiting requests, try again in a minute"
                    .to_string();
                continue;
            }
            // The server answers 503 with "策略查询繁忙" (strategy query busy) when it sheds load.
            502..=504 | 520..=524 => {
                last_err = "The strategy server is busy, try again in a minute".to_string();
                continue;
            }
            _ if !status.is_success() => {
                last_err = format!("Strategy server answered {}", status);
                continue;
            }
            _ => {}
        }
        let bytes = crate::net::read_limited(resp, MAX_BODY_BYTES).await?;
        let mut body: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        if body.get("success").and_then(Value::as_bool) == Some(false) {
            let message = body.get("message").and_then(Value::as_str).unwrap_or("");
            last_err = if message.contains("繁忙") {
                "The strategy server is busy, try again in a minute".to_string()
            } else {
                format!("Strategy server returned an error: {}", message)
            };
            continue;
        }
        let mut data = body.get_mut("data").map(Value::take).unwrap_or(Value::Null);
        strip_private(&mut data);
        return Ok(data);
    }
    Err(last_err)
}

/// GET one of the strategy endpoints. Returns `{ data, fetchedAt, stale }`;
/// a stale copy is served when the server fails but an older answer is cached.
#[tauri::command]
pub async fn strategy_api(
    endpoint: String,
    query: HashMap<String, String>,
) -> Result<Value, String> {
    let params = validate(&endpoint, &query)?;
    let key = cache_key(&endpoint, &params);
    let now_ms = chrono_ms();

    {
        let cache = CACHE.lock().unwrap();
        if let Some(e) = cache.get(&key) {
            if e.at.elapsed() < ttl(&endpoint) {
                return Ok(
                    json!({ "data": e.body, "fetchedAt": now_ms - e.at.elapsed().as_millis() as i64, "stale": false }),
                );
            }
        }
    }

    match fetch(&endpoint, &params).await {
        Ok(data) => {
            let mut cache = CACHE.lock().unwrap();
            if cache.len() >= MAX_CACHE_ENTRIES {
                if let Some(oldest) = cache
                    .iter()
                    .min_by_key(|(_, e)| e.at)
                    .map(|(k, _)| k.clone())
                {
                    cache.remove(&oldest);
                }
            }
            cache.insert(
                key,
                Entry {
                    at: Instant::now(),
                    body: data.clone(),
                },
            );
            Ok(json!({ "data": data, "fetchedAt": now_ms, "stale": false }))
        }
        Err(err) => {
            let cache = CACHE.lock().unwrap();
            match cache.get(&key) {
                Some(e) => Ok(
                    json!({ "data": e.body, "fetchedAt": now_ms - e.at.elapsed().as_millis() as i64, "stale": true }),
                ),
                None => Err(err),
            }
        }
    }
}

#[derive(serde::Serialize)]
pub struct ItemInfo {
    name: String,
    item_type: String,
    price: f64,
}

/// Names, types and today's prices for item IDs found in strategy data.
#[tauri::command]
pub fn get_item_info(ids: Vec<String>) -> HashMap<String, ItemInfo> {
    ids.into_iter()
        .take(2000)
        .map(|id| {
            let info = ItemInfo {
                name: crate::db::DbManager::get_item_name(&id),
                item_type: crate::db::DbManager::get_item_type(&id),
                price: crate::pricing::cached_price(&id).unwrap_or(0.0),
            };
            (id, info)
        })
        .collect()
}

fn chrono_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn only_known_endpoints_and_params_pass() {
        assert!(validate(
            "leaderboard",
            &q(&[("stage", "week1"), ("tags", "timeIndex:10")])
        )
        .is_ok());
        assert!(validate("windboard", &q(&[])).is_err());
        assert!(validate("leaderboard", &q(&[("playerName", "someone")])).is_err());
        assert!(validate("detail", &q(&[("strategyKey", "1\n2")])).is_err());
    }

    #[test]
    fn season_is_always_added_and_keys_are_stable() {
        let a = validate("tags", &q(&[("stage", "week1"), ("minCount", "30")])).unwrap();
        let b = validate(
            "tags",
            &q(&[("minCount", "30"), ("stage", "week1"), ("tags", "")]),
        )
        .unwrap();
        assert!(a.iter().any(|(k, _)| k == "seasonId"));
        assert_eq!(cache_key("tags", &a), cache_key("tags", &b));
    }

    #[test]
    fn player_fields_are_removed_everywhere() {
        let mut v = json!({"items": [{"rank": 1, "playerName": "x", "userId": "1", "nested": {"heroId": "2", "score": 3}}]});
        strip_private(&mut v);
        assert_eq!(v, json!({"items": [{"rank": 1, "nested": {"score": 3}}]}));
    }
}

#[cfg(test)]
mod live {
    use super::*;

    // Hits the live server; run by hand with `cargo test --lib strategy::live -- --ignored`.
    #[tokio::test]
    #[ignore]
    async fn leaderboard_round_trip() {
        let stages = strategy_api("stage-options".into(), HashMap::new())
            .await
            .unwrap();
        let q: HashMap<String, String> =
            [("stage", "week1"), ("limit", "2"), ("tags", "timeIndex:10")]
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect();
        let board = strategy_api("leaderboard".into(), q).await.unwrap();
        println!("{}\n{}", stages, board);
        assert!(board["data"]["items"][0].get("playerName").is_none());
        assert_eq!(board["data"]["items"][0]["timeLabel"], "10");
    }
}
