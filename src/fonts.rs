pub(crate) fn register_cjk_fonts() {
    #[cfg(target_os = "android")]
    {
        let cjk_paths = [
            "/system/fonts/DroidSansFallback.ttf",
            "/system/fonts/NotoSansSC-Regular.otf",
            "/system/fonts/NotoSansHans-Regular.otf",
            "/system/fonts/MiLanProVF.ttf",
            "/system/fonts/NotoSansCJK-Regular.ttc",
        ];

        for path in &cjk_paths {
            match std::fs::read(path) {
                Ok(data) => {
                    let data: &'static [u8] = Box::leak(data.into_boxed_slice());
                    i_slint_core::text::FontCache::get().register_font_from_memory(data);
                    log::info!("fonts: registered CJK font from {path}");
                    return;
                }
                Err(_) => continue,
            }
        }
        log::warn!("fonts: no CJK font found in system font directories, Chinese characters may not render correctly");
    }

    #[cfg(not(target_os = "android"))]
    {
        let cjk_paths = [
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/noto/NotoSansSC-Regular.otf",
            "C:\\Windows\\Fonts\\msyh.ttc",
            "C:\\Windows\\Fonts\\simsun.ttc",
        ];

        for path in &cjk_paths {
            match std::fs::read(path) {
                Ok(data) => {
                    let data: &'static [u8] = Box::leak(data.into_boxed_slice());
                    i_slint_core::text::FontCache::get().register_font_from_memory(data);
                    log::info!("fonts: registered CJK font from {path}");
                    return;
                }
                Err(_) => continue,
            }
        }
        log::warn!("fonts: no CJK font found, Chinese characters may not render correctly");
    }
}