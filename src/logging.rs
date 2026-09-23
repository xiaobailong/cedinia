//! Process-wide logging switch behind the "Enable logging" setting.
//!
//! Disabling it flips `log`'s max level to `Off`, which is a *global* switch: every crate
//! logging through the `log` facade (czkawka_core included) goes quiet, not just cedinia.
//!
//! The switch owns the log *file* as well: opening one is what creates the log folder (Android's
//! `Download/cedinia`) and the platform logger itself creates the file while it is built, so a
//! session with logging off never opens a file - and the platform logger is not installed at all
//! until the switch is turned on. On Android the file lives in the user-visible `Download/cedinia`
//! folder (falling back to the app-private cache folder until storage access is granted), one file
//! per day, and files untouched for a week are deleted at startup.

use std::path::Path;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime};

use log::LevelFilter;

/// Log files last written to more than this long ago are deleted at startup.
const LOG_RETENTION: Duration = Duration::from_secs(7 * 24 * 60 * 60);

/// Level the loggers themselves are built with (czkawka_core's file logger and cedinia's Android
/// `DualLogger`), and therefore the level to restore once the switch is turned back on.
///
/// A constant rather than a capture of `log::max_level()`: before a logger is installed that value
/// is the facade's own default (`Trace`), and the persisted switch is applied at start-up exactly
/// that early - capturing it there would make re-enabling far noisier than a normal session.
pub(crate) const LOG_LEVEL: LevelFilter = LevelFilter::Debug;

static LOGGING_ENABLED: AtomicBool = AtomicBool::new(true);

/// Open/close hooks of the platform log file, registered by whichever logger the session installs.
///
/// The switch drives them: turning logging off releases the file (so nothing keeps writing to a
/// file the user asked to stop), turning it on opens it again - creating it only then.
static LOG_FILE_HOOKS: OnceLock<(Box<dyn Fn() + Send + Sync>, Box<dyn Fn() + Send + Sync>)> = OnceLock::new();

pub(crate) fn is_logging_enabled() -> bool {
    LOGGING_ENABLED.load(Ordering::Relaxed)
}

/// Applies the facade level implied by the current switch state.
///
/// Called on every switch flip and again right after a logger is installed - installing one resets
/// the facade's max level, which would otherwise re-enable logging behind the switch's back.
pub(crate) fn apply_log_level() {
    log::set_max_level(if is_logging_enabled() { LOG_LEVEL } else { LevelFilter::Off });
}

/// Registered once per session by the logger set-up (`open` installs/opens, `close` releases).
pub(crate) fn set_log_file_hooks(open: impl Fn() + Send + Sync + 'static, close: impl Fn() + Send + Sync + 'static) {
    let _ = LOG_FILE_HOOKS.set((Box::new(open), Box::new(close)));
}

/// Opens (or re-opens) the platform log file.
///
/// On Android this is also the "storage access was just granted" path - the file can only move
/// into `Download/cedinia` once that folder is writable - so it stays a no-op while logging is off.
pub(crate) fn open_log_file() {
    if is_logging_enabled()
        && let Some((open, _)) = LOG_FILE_HOOKS.get()
    {
        open();
    }
}

pub(crate) fn close_log_file() {
    if let Some((_, close)) = LOG_FILE_HOOKS.get() {
        close();
    }
}

pub(crate) fn set_logging_enabled(enabled: bool) {
    if enabled == is_logging_enabled() {
        return;
    }

    LOGGING_ENABLED.store(enabled, Ordering::Relaxed);
    apply_log_level();

    if enabled {
        open_log_file();
    } else {
        close_log_file();
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

    /// Folder the app owns inside the shared Downloads directory.
    const DOWNLOADS_FOLDER_NAME: &str = "cedinia";

    /// `/storage/emulated/0/Download/cedinia`, without touching the file system.
    ///
    /// Resolving the path must not create the folder: with logging off it has no reason to exist,
    /// and the pruning/log export walks only ever read it.
    ///
    /// `None` while the shared Downloads folder is unreachable (storage not mounted yet) and on
    /// desktop builds, where logs stay in the czkawka_core cache folder.
    pub(crate) fn download_log_dir() -> Option<PathBuf> {
        // `/sdcard/Download` is the legacy alias of the canonical path, used on old devices only.
        const CANDIDATES: [&str; 2] = ["/storage/emulated/0/Download", "/sdcard/Download"];
        CANDIDATES.iter().map(|base| Path::new(base).join(DOWNLOADS_FOLDER_NAME)).find(|dir| dir.parent().is_some_and(Path::is_dir))
    }

    /// The same folder, created on demand - only reached while a log file is actually about to be
    /// written, so that a session with logging off leaves no folder behind.
    pub(crate) fn create_download_log_dir() -> Option<PathBuf> {
        let dir = download_log_dir()?;
        std::fs::create_dir_all(&dir).ok().map(|()| dir)
    }

    /// Today's log file name - one file per day, which is what the retention window prunes.
    pub(crate) fn daily_log_file_name() -> String {
        format!("cedinia_{}.log", chrono::Local::now().format("%Y-%m-%d"))
    }
}

#[cfg(not(target_os = "android"))]
pub(crate) mod android {
    use std::path::PathBuf;

    pub(crate) fn download_log_dir() -> Option<PathBuf> {
        None
    }
}
