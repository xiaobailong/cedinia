//! Process-wide logging switch behind the "Enable logging" setting.
//!
//! Disabling it flips `log`'s max level to `Off`, which is a *global* switch: every crate
//! logging through the `log` facade (czkawka_core included) goes quiet, not just cedinia.
//!
//! Also owns the log file policy: on Android the file lives in the user-visible
//! `Download/cedinia` folder (falling back to the app-private cache folder until storage
//! access is granted), one file per day, and files untouched for a week are deleted at
//! startup.

use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime};

use log::LevelFilter;

/// Log files last written to more than this long ago are deleted at startup.
const LOG_RETENTION: Duration = Duration::from_secs(7 * 24 * 60 * 60);

static LOGGING_ENABLED: AtomicBool = AtomicBool::new(true);

// Max level that was in effect before logging got turned off - restored when it comes back on.
static SAVED_MAX_LEVEL: Mutex<Option<LevelFilter>> = Mutex::new(None);

pub(crate) fn is_logging_enabled() -> bool {
    LOGGING_ENABLED.load(Ordering::Relaxed)
}

pub(crate) fn set_logging_enabled(enabled: bool) {
    if enabled == is_logging_enabled() {
        return;
    }

    if enabled {
        LOGGING_ENABLED.store(true, Ordering::Relaxed);
        let previous = SAVED_MAX_LEVEL.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(level) = previous {
            log::set_max_level(level);
        }
    } else {
        LOGGING_ENABLED.store(false, Ordering::Relaxed);
        let current = log::max_level();
        if current != LevelFilter::Off {
            *SAVED_MAX_LEVEL.lock().unwrap_or_else(|e| e.into_inner()) = Some(current);
        }
        log::set_max_level(LevelFilter::Off);
    }
}

/// Deletes the log files in `dir` that were last written to outside the retention window.
///
/// Age is taken from the timestamp rather than the file name, so the file of a long running
/// session survives even once its name is older than the window.
pub(crate) fn prune_old_logs(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let now = SystemTime::now();
    for entry in entries.flatten() {
        let path = entry.path();
        if !is_log_file(&path) {
            continue;
        }
        let age = entry.metadata().and_then(|m| m.modified()).ok().and_then(|m| now.duration_since(m).ok());
        if age.is_some_and(|age| age > LOG_RETENTION) && std::fs::remove_file(&path).is_ok() {
            log::info!("prune_old_logs: removed stale log file \"{}\"", path.display());
        }
    }
}

/// Log files are `cedinia<date>.log` plus czkawka_core's rotated `cedinia.log.<n>` siblings.
pub(crate) fn is_log_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("cedinia") && name.contains(".log"))
}

/// Paths of Android's user-visible log folder.
#[cfg(target_os = "android")]
pub(crate) mod android {
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;

    /// Folder the app owns inside the shared Downloads directory.
    const DOWNLOADS_FOLDER_NAME: &str = "cedinia";

    /// Re-opens the process log file, invoked when the folder it belongs to may just have
    /// become writable - the logger is set up before storage access is granted.
    static RETARGET_HOOK: Mutex<Option<Box<dyn Fn() + Send + Sync>>> = Mutex::new(None);

    /// `/storage/emulated/0/Download/cedinia`, created on demand.
    ///
    /// `None` while the shared storage is unreachable - i.e. until the user grants
    /// `MANAGE_EXTERNAL_STORAGE` - and on desktop builds, where logs stay in the czkawka_core
    /// cache folder.
    pub(crate) fn download_log_dir() -> Option<PathBuf> {
        // `/sdcard/Download` is the legacy alias of the canonical path, used on old devices only.
        const CANDIDATES: [&str; 2] = ["/storage/emulated/0/Download", "/sdcard/Download"];
        CANDIDATES.iter().find_map(|base| {
            let dir = Path::new(base).join(DOWNLOADS_FOLDER_NAME);
            std::fs::create_dir_all(&dir).ok().map(|()| dir)
        })
    }

    /// Today's log file name - one file per day, which is what the retention window prunes.
    pub(crate) fn daily_log_file_name() -> String {
        format!("cedinia_{}.log", chrono::Local::now().format("%Y-%m-%d"))
    }

    pub(crate) fn set_log_retarget_hook(hook: impl Fn() + Send + Sync + 'static) {
        *RETARGET_HOOK.lock().unwrap_or_else(|e| e.into_inner()) = Some(Box::new(hook));
    }

    pub(crate) fn retarget_log_file() {
        if let Some(hook) = RETARGET_HOOK.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
            hook();
        }
    }
}

#[cfg(not(target_os = "android"))]
pub(crate) mod android {
    use std::path::PathBuf;

    pub(crate) fn download_log_dir() -> Option<PathBuf> {
        None
    }
}
