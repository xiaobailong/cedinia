//! Registers the device's own CJK font with Slint so Chinese text stops rendering as tofu boxes.
//!
//! fontique's Android backend maps the `sans-serif` generic family to `Roboto Flex` / `Roboto` /
//! `Noto Sans` (`fontique::backend::android::DEFAULT_GENERIC_FAMILIES`) - none of which contains
//! Han glyphs - so every CJK character is drawn as the "missing glyph" box. Naming a CJK family in
//! `default-font-family` alone cannot fix that: modern Android ships
//! `/system/fonts/NotoSansCJK-Regular.ttc`, whose families are `Noto Sans CJK SC|TC|HK|JP|KR`,
//! while Android 4.x shipped `DroidSansFallback.ttf`.
//!
//! Slint's shared font collection (`i-slint-common::sharedfontique::create_collection`) reads
//! `SLINT_DEFAULT_FONT` (one file) and `SLINT_FONT_PATH` (OS path list) before building the
//! collection, registers every face of every file it finds and then *replaces* the
//! `SansSerif` / `SystemUi` / `UiSansSerif` generic-family chains with those families.
//!
//! Pointing those variables at the system font fixes every `Text` element without shipping a
//! multi-megabyte CJK font inside the APK.

#[cfg(target_os = "android")]
const CANDIDATE_FONT_FILES: &[&str] = &[
    // Android 5+ / AOSP - families "Noto Sans CJK SC|TC|HK|JP|KR"
    "NotoSansCJK-Regular.ttc",
    // Same family, real bold face instead of a synthesized one
    "NotoSansCJK-Bold.ttc",
    // Newer AOSP images ship the language specific faces as well
    "NotoSansSC-Regular.otf",
    "NotoSansTC-Regular.otf",
    // Android 4.x
    "DroidSansFallbackFull.ttf",
    "DroidSansFallback.ttf",
];

/// Must run before Slint builds its (once per process) font collection, i.e. before
/// `slint::android::init()` and before the first `MainWindow::new()`.
#[cfg(target_os = "android")]
pub fn install_system_cjk_font() {
    let android_root = std::env::var("ANDROID_ROOT").unwrap_or_else(|_| "/system".to_owned());
    let font_dir = std::path::Path::new(&android_root).join("fonts");

    let found: Vec<std::path::PathBuf> = CANDIDATE_FONT_FILES.iter().map(|name| font_dir.join(name)).filter(|path| path.is_file()).collect();
    let Some((primary, extra_faces)) = found.split_first() else {
        log::warn!(
            "install_system_cjk_font: no CJK font in '{}' - CJK text will be drawn as boxes",
            font_dir.display()
        );
        return;
    };

    // SAFETY: called from android_main() during single-threaded start-up, before Slint spawns
    // any thread that could read the environment.
    unsafe {
        std::env::set_var("SLINT_DEFAULT_FONT", primary);
        if !extra_faces.is_empty() {
            match std::env::join_paths(extra_faces) {
                Ok(path_list) => std::env::set_var("SLINT_FONT_PATH", path_list),
                Err(e) => log::warn!("install_system_cjk_font: cannot build SLINT_FONT_PATH: {e}"),
            }
        }
    }

    log::info!(
        "install_system_cjk_font: using '{}' (+{} extra face file(s))",
        primary.display(),
        extra_faces.len()
    );
}
