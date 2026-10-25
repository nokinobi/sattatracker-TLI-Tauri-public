//! Small rotating log file in the app data folder: `logs/tracker.log`, rolled over to
//! `tracker.1.log` and `tracker.2.log` at 1 MB, so it never grows past about 3 MB.
//! Lines are `2026-10-25T15:04:16.123Z WARN [strategy] message`, times in UTC.

use lazy_static::lazy_static;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_BYTES: u64 = 1_000_000;
const KEEP: usize = 2;
const MAX_MESSAGE: usize = 2000;

lazy_static! {
    static ref LOG_FILE: Mutex<Option<PathBuf>> = Mutex::new(None);
}

pub fn init(dir: PathBuf, version: &str) {
    if fs::create_dir_all(&dir).is_err() {
        return;
    }
    *LOG_FILE.lock().unwrap() = Some(dir.join("tracker.log"));
    info("app", &format!("started version {}", version));
}

pub fn info(source: &str, message: &str) {
    write("INFO", source, message);
}

pub fn warn(source: &str, message: &str) {
    write("WARN", source, message);
}

pub fn error(source: &str, message: &str) {
    write("ERROR", source, message);
}

fn write(level: &str, source: &str, message: &str) {
    let line = format!(
        "{} {} [{}] {}\n",
        timestamp(),
        level,
        source,
        clean(message)
    );
    print!("{}", line);
    let guard = LOG_FILE.lock().unwrap();
    let Some(path) = guard.as_ref() else { return };
    rotate(path);
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = f.write_all(line.as_bytes());
    }
}

fn rotate(path: &Path) {
    let big = fs::metadata(path)
        .map(|m| m.len() >= MAX_BYTES)
        .unwrap_or(false);
    if !big {
        return;
    }
    let numbered = |n: usize| path.with_file_name(format!("tracker.{}.log", n));
    let _ = fs::remove_file(numbered(KEEP));
    for n in (1..KEEP).rev() {
        let _ = fs::rename(numbered(n), numbered(n + 1));
    }
    let _ = fs::rename(path, numbered(1));
}

// One line per entry, capped, so a huge error body can't flood the file.
fn clean(message: &str) -> String {
    let flat: String = message
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    if flat.chars().count() > MAX_MESSAGE {
        format!("{}…", flat.chars().take(MAX_MESSAGE).collect::<String>())
    } else {
        flat
    }
}

fn timestamp() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs() as i64;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}Z",
        year,
        month,
        day,
        rem / 3600,
        rem % 3600 / 60,
        rem % 60,
        now.subsec_millis()
    )
}

/// Lets the dashboard write its own errors into the same file.
#[tauri::command]
pub fn log_event(level: String, source: String, message: String) {
    let source: String = source
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
        .take(32)
        .collect();
    let source = if source.is_empty() {
        "ui".to_string()
    } else {
        format!("ui-{}", source)
    };
    match level.as_str() {
        "error" => error(&source, &message),
        "warn" => warn(&source, &message),
        _ => info(&source, &message),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn messages_stay_on_one_capped_line() {
        assert_eq!(clean("a\nb\tc"), "a b c");
        assert_eq!(
            clean(&"x".repeat(MAX_MESSAGE + 5)).chars().count(),
            MAX_MESSAGE + 1
        );
    }

    #[test]
    fn timestamp_is_iso_utc() {
        let t = timestamp();
        assert_eq!(t.len(), 24);
        assert!(t.ends_with('Z') && t.as_bytes()[10] == b'T');
    }

    #[test]
    fn files_roll_over_at_the_limit() {
        let dir = std::env::temp_dir().join(format!("tli-applog-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("tracker.log");
        fs::write(&path, vec![b'x'; MAX_BYTES as usize]).unwrap();
        rotate(&path);
        assert!(!path.exists());
        assert!(dir.join("tracker.1.log").exists());
        let _ = fs::remove_dir_all(&dir);
    }
}
