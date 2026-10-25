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
    static ref PREFERRED: Mutex<Option<String>> = Mutex::new(None);
}

// Servers to try, the one that answered last first. A server can sit behind a bot check
// for a while (it answers with a script page), and asking it first costs every call a second.
fn bases() -> Vec<String> {
    let mut list = crate::pricing::api_bases();
    if let Some(p) = PREFERRED.lock().unwrap().clone() {
        if let Some(i) = list.iter().position(|b| *b == p) {
            let b = list.remove(i);
            list.insert(0, b);
        }
    }
    list
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

// Short description of a request for the log: long tag lists (a mechanic is ~35 talent
// ids) become counts per type.
fn describe(endpoint: &str, params: &[(String, String)]) -> String {
    let parts: Vec<String> = params
        .iter()
        .map(|(k, v)| {
            if k != "tags" && k != "excludeTags" {
                return format!("{}={}", k, v);
            }
            let mut counts: Vec<(String, usize)> = Vec::new();
            for t in v.split(',') {
                let kind = t.split(':').next().unwrap_or("").to_string();
                match counts.iter_mut().find(|(c, _)| *c == kind) {
                    Some((_, n)) => *n += 1,
                    None => counts.push((kind, 1)),
                }
            }
            let list: Vec<String> = counts
                .iter()
                .map(|(c, n)| format!("{}({})", c, n))
                .collect();
            format!("{}=[{}]", k, list.join(" "))
        })
        .collect();
    format!("{} {}", endpoint, parts.join(" "))
}

fn snippet(bytes: &[u8]) -> String {
    String::from_utf8_lossy(&bytes[..bytes.len().min(200)]).to_string()
}

const BUSY: &str = "The strategy server is busy, try again in a minute";

async fn fetch(endpoint: &str, params: &[(String, String)], what: &str) -> Result<Value, String> {
    let client = crate::net::client(Duration::from_secs(15))?;
    let mut last_err = String::from("no strategy server reachable");
    for base in bases() {
        let host = reqwest::Url::parse(&base)
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
            .unwrap_or_else(|| base.clone());
        let mut url = match reqwest::Url::parse(&format!("{}/api/strategy/{}", base, endpoint)) {
            Ok(u) => u,
            Err(e) => {
                last_err = e.to_string();
                continue;
            }
        };
        url.query_pairs_mut().extend_pairs(params);
        let started = Instant::now();
        let ms = || started.elapsed().as_millis();
        let log_fail = |reason: String| {
            crate::applog::warn(
                "strategy",
                &format!("{} via {}: {} after {} ms", what, host, reason, ms()),
            );
        };
        let resp = match client.get(url).send().await {
            Ok(r) => r,
            Err(e) => {
                log_fail(format!("request failed ({})", e));
                last_err = e.to_string();
                continue;
            }
        };
        let status = resp.status();
        if !status.is_success() {
            let body = crate::net::read_limited(resp, MAX_BODY_BYTES)
                .await
                .unwrap_or_default();
            log_fail(format!("HTTP {} {}", status.as_u16(), snippet(&body)));
            last_err = match status.as_u16() {
                429 => "The strategy server is rate limiting requests, try again in a minute"
                    .to_string(),
                // The server answers 503 with a "strategy query busy" message when it sheds load.
                502..=504 | 520..=524 => BUSY.to_string(),
                _ => format!("Strategy server answered {}", status),
            };
            continue;
        }
        let bytes = match crate::net::read_limited(resp, MAX_BODY_BYTES).await {
            Ok(b) => b,
            Err(e) => {
                log_fail(format!("reading the answer failed ({})", e));
                last_err = e;
                continue;
            }
        };
        let mut body: Value = match serde_json::from_slice(&bytes) {
            Ok(v) => v,
            Err(e) => {
                log_fail(format!("answer is not JSON ({}): {}", e, snippet(&bytes)));
                last_err =
                    "The strategy server answered with a web page instead of data".to_string();
                continue;
            }
        };
        if body.get("success").and_then(Value::as_bool) == Some(false) {
            let message = body
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            log_fail(format!("server error: {}", message));
            last_err = if message.contains('\u{7e41}') {
                BUSY.to_string()
            } else {
                format!("Strategy server returned an error: {}", message)
            };
            continue;
        }
        *PREFERRED.lock().unwrap() = Some(base.clone());
        crate::applog::info(
            "strategy",
            &format!(
                "{} via {}: OK in {} ms, {} bytes",
                what,
                host,
                ms(),
                bytes.len()
            ),
        );
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
    let params = validate(&endpoint, &query).map_err(|e| {
        crate::applog::warn("strategy", &format!("rejected {} request: {}", endpoint, e));
        e
    })?;
    let key = cache_key(&endpoint, &params);
    let now_ms = chrono_ms();
    let what = describe(&endpoint, &params);

    {
        let cache = CACHE.lock().unwrap();
        if let Some(e) = cache.get(&key) {
            if e.at.elapsed() < ttl(&endpoint) {
                crate::applog::info(
                    "strategy",
                    &format!("{}: from cache ({} s old)", what, e.at.elapsed().as_secs()),
                );
                return Ok(
                    json!({ "data": e.body, "fetchedAt": now_ms - e.at.elapsed().as_millis() as i64, "stale": false }),
                );
            }
        }
    }

    match fetch(&endpoint, &params, &what).await {
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
                Some(e) => {
                    crate::applog::warn(
                        "strategy",
                        &format!(
                            "{}: all servers failed ({}), showing the saved answer from {} s ago",
                            what,
                            err,
                            e.at.elapsed().as_secs()
                        ),
                    );
                    Ok(
                        json!({ "data": e.body, "fetchedAt": now_ms - e.at.elapsed().as_millis() as i64, "stale": true }),
                    )
                }
                None => {
                    crate::applog::error(
                        "strategy",
                        &format!("{}: all servers failed: {}", what, err),
                    );
                    Err(err)
                }
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
