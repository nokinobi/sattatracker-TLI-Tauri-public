//! Read-only proxy for the strategy leaderboard API, used by the dashboard's
//! Strategies tab. The webview can't call the server itself (no CORS), and it
//! rate-limits, so every response is cached and player identities are dropped.

use lazy_static::lazy_static;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const MAX_BODY_BYTES: usize = 4 * 1024 * 1024;
const MAX_CACHE_ENTRIES: usize = 300;
// Total size of the cached answers (as JSON text); big leaderboard pages add up quickly.
const MAX_CACHE_BYTES: usize = 32 * 1024 * 1024;
// Past this age an answer is no use even as a fallback when the server fails.
const STALE_KEEP: Duration = Duration::from_secs(2 * 60 * 60);
// A question that just failed isn't asked again at once, so requests waiting for the same answer
// fail together. Shorter than the dashboard's automatic retry after 4 s, which still goes out.
const FAIL_COOLDOWN: Duration = Duration::from_secs(3);
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
    size: usize,
}

/// Frees space for an answer of `incoming` bytes under `key`: drops the old copy of that key,
/// answers older than STALE_KEEP, then the oldest ones until both limits fit.
fn make_room(cache: &mut HashMap<String, Entry>, key: &str, incoming: usize) {
    cache.remove(key);
    cache.retain(|_, e| e.at.elapsed() < STALE_KEEP);
    let mut total: usize = cache.values().map(|e| e.size).sum();
    while !cache.is_empty()
        && (cache.len() >= MAX_CACHE_ENTRIES || total + incoming > MAX_CACHE_BYTES)
    {
        let Some(oldest) = cache
            .iter()
            .min_by_key(|(_, e)| e.at)
            .map(|(k, _)| k.clone())
        else {
            break;
        };
        if let Some(e) = cache.remove(&oldest) {
            total -= e.size;
        }
    }
}

lazy_static! {
    static ref CACHE: Mutex<HashMap<String, Entry>> = Mutex::new(HashMap::new());
    static ref PREFERRED: Mutex<Option<String>> = Mutex::new(None);
    // One request per question at a time; the others wait and use its answer.
    static ref IN_FLIGHT: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>> = Mutex::new(HashMap::new());
    static ref FAILED: Mutex<HashMap<String, (Instant, String)>> = Mutex::new(HashMap::new());
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

/// The saved answer to show when the server fails, unless it is too old to be of use.
fn fallback<'a>(cache: &'a HashMap<String, Entry>, key: &str) -> Option<&'a Entry> {
    cache.get(key).filter(|e| e.at.elapsed() < STALE_KEEP)
}

fn recent_failure(failed: &HashMap<String, (Instant, String)>, key: &str) -> Option<String> {
    failed
        .get(key)
        .filter(|(at, _)| at.elapsed() < FAIL_COOLDOWN)
        .map(|(_, err)| err.clone())
}

fn note_failure(failed: &mut HashMap<String, (Instant, String)>, key: &str, err: &str) {
    failed.retain(|_, (at, _)| at.elapsed() < FAIL_COOLDOWN);
    failed.insert(key.to_string(), (Instant::now(), err.to_string()));
}

type Turn = Arc<tokio::sync::Mutex<()>>;

fn turn_for(slots: &mut HashMap<String, Turn>, key: &str) -> Turn {
    slots.entry(key.to_string()).or_default().clone()
}

/// Gives up a caller's turn, and forgets the question once only the map still holds it. The turn is
/// dropped under the map's lock, so the last of several callers always sees that it was the last.
fn release_turn(slots: &mut HashMap<String, Turn>, key: &str, turn: Turn) {
    drop(turn);
    if slots.get(key).is_some_and(|t| Arc::strong_count(t) == 1) {
        slots.remove(key);
    }
}

fn cached_answer(key: &str, endpoint: &str, what: &str) -> Option<Value> {
    let cache = CACHE.lock().unwrap();
    let e = cache.get(key)?;
    if e.at.elapsed() >= ttl(endpoint) {
        return None;
    }
    crate::applog::info(
        "strategy",
        &format!("{}: from cache ({} s old)", what, e.at.elapsed().as_secs()),
    );
    Some(json!({ "data": e.body, "fetchedAt": chrono_ms() - e.at.elapsed().as_millis() as i64, "stale": false }))
}

/// What a failed question gets: the saved answer if there is a recent one, otherwise the error.
fn failed_answer(key: &str, what: &str, err: String) -> Result<Value, String> {
    let cache = CACHE.lock().unwrap();
    match fallback(&cache, key) {
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
            Ok(json!({ "data": e.body, "fetchedAt": chrono_ms() - e.at.elapsed().as_millis() as i64, "stale": true }))
        }
        None => {
            crate::applog::error("strategy", &format!("{}: all servers failed: {}", what, err));
            Err(err)
        }
    }
}

async fn ask_server(
    endpoint: &str,
    params: &[(String, String)],
    key: String,
    what: &str,
) -> Result<Value, String> {
    // The request this one waited for may have brought the answer, or just failed.
    if let Some(answer) = cached_answer(&key, endpoint, what) {
        return Ok(answer);
    }
    let failed = recent_failure(&FAILED.lock().unwrap(), &key);
    if let Some(err) = failed {
        return failed_answer(&key, what, err);
    }
    match fetch(endpoint, params, what).await {
        Ok(data) => {
            FAILED.lock().unwrap().remove(&key);
            let size = data.to_string().len();
            let mut cache = CACHE.lock().unwrap();
            make_room(&mut cache, &key, size);
            cache.insert(
                key,
                Entry {
                    at: Instant::now(),
                    body: data.clone(),
                    size,
                },
            );
            Ok(json!({ "data": data, "fetchedAt": chrono_ms(), "stale": false }))
        }
        Err(err) => {
            note_failure(&mut FAILED.lock().unwrap(), &key, &err);
            failed_answer(&key, what, err)
        }
    }
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
    let what = describe(&endpoint, &params);

    if let Some(answer) = cached_answer(&key, &endpoint, &what) {
        return Ok(answer);
    }

    let turn = turn_for(&mut IN_FLIGHT.lock().unwrap(), &key);
    let answer = {
        let _waited = turn.lock().await;
        ask_server(&endpoint, &params, key.clone(), &what).await
    };
    release_turn(&mut IN_FLIGHT.lock().unwrap(), &key, turn);
    answer
}

/// The ids `get_item_info` looks up: real item ids only, up to its limit.
fn lookup_ids(ids: Vec<String>) -> Vec<String> {
    ids.into_iter()
        .filter(|id| crate::pricing::valid_item_id(id))
        .take(2000)
        .collect()
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
    lookup_ids(ids)
        .into_iter()
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

    fn entry(age_secs: u64, size: usize) -> Entry {
        Entry {
            at: Instant::now() - Duration::from_secs(age_secs),
            body: Value::Null,
            size,
        }
    }

    #[test]
    fn cache_drops_answers_too_old_to_fall_back_on() {
        let mut c = HashMap::new();
        c.insert("old".to_string(), entry(STALE_KEEP.as_secs() + 1, 10));
        c.insert("recent".to_string(), entry(60, 10));
        make_room(&mut c, "new", 10);
        assert!(!c.contains_key("old"));
        assert!(c.contains_key("recent"));
    }

    #[test]
    fn failed_requests_only_fall_back_on_recent_answers() {
        let mut c = HashMap::new();
        c.insert("old".to_string(), entry(STALE_KEEP.as_secs() + 1, 10));
        c.insert("recent".to_string(), entry(STALE_KEEP.as_secs() - 60, 10));
        assert!(fallback(&c, "old").is_none());
        assert!(fallback(&c, "recent").is_some());
        assert!(fallback(&c, "missing").is_none());
    }

    #[test]
    fn a_failed_question_rests_only_for_the_cooldown() {
        let mut f = HashMap::new();
        assert!(recent_failure(&f, "k").is_none());
        note_failure(&mut f, "k", "down");
        assert_eq!(recent_failure(&f, "k").as_deref(), Some("down"));
        f.insert(
            "k".to_string(),
            (Instant::now() - FAIL_COOLDOWN - Duration::from_secs(1), "down".to_string()),
        );
        assert!(recent_failure(&f, "k").is_none());
        note_failure(&mut f, "other", "down");
        assert!(!f.contains_key("k"));
    }

    #[test]
    fn a_question_shares_one_turn_until_nobody_waits() {
        let mut slots = HashMap::new();
        let first = turn_for(&mut slots, "k");
        let second = turn_for(&mut slots, "k");
        assert!(Arc::ptr_eq(&first, &second));
        release_turn(&mut slots, "k", first);
        assert!(slots.contains_key("k"));
        release_turn(&mut slots, "k", second);
        assert!(!slots.contains_key("k"));
    }

    #[test]
    fn item_lookups_take_only_item_ids() {
        let ids = vec![
            "100300".to_string(),
            String::new(),
            "../x".to_string(),
            "1".repeat(13),
        ];
        assert_eq!(lookup_ids(ids), vec!["100300".to_string()]);
        assert_eq!(lookup_ids(vec!["1".to_string(); 2001]).len(), 2000);
    }

    #[test]
    fn cache_stays_under_its_byte_budget() {
        let mut c = HashMap::new();
        let big = MAX_CACHE_BYTES / 3;
        c.insert("a".to_string(), entry(30, big));
        c.insert("b".to_string(), entry(20, big));
        c.insert("c".to_string(), entry(10, big));
        make_room(&mut c, "d", big);
        // The oldest goes first, and only as much as needed.
        assert!(!c.contains_key("a"));
        assert!(c.contains_key("b") && c.contains_key("c"));
        assert!(c.values().map(|e| e.size).sum::<usize>() + big <= MAX_CACHE_BYTES);
    }

    #[test]
    fn cache_replaces_its_own_key() {
        let mut c = HashMap::new();
        c.insert("k".to_string(), entry(10, MAX_CACHE_BYTES - 5));
        make_room(&mut c, "k", MAX_CACHE_BYTES - 5);
        assert!(c.is_empty());
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
