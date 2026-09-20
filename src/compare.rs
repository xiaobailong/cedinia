use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread;

use czkawka_core::common::image::{ImgResizeOptions, get_dynamic_image_from_path};
use czkawka_core::re_exported::FirFilterType;
use image::imageops;
use log::error;
use slint::{ComponentHandle, Model, ModelRc, SharedString, VecModel};

use crate::file_actions::{delete_path, show_delete_errors};
use crate::model::rebuild_similar_images_after_delete;
use crate::{AppState, CompareImageData, MainWindow};

thread_local! {
    static CANCEL_TOKEN: RefCell<Arc<AtomicBool>> =
        RefCell::new(Arc::new(AtomicBool::new(false)));
}

fn new_cancel_token() -> Arc<AtomicBool> {
    let token = Arc::new(AtomicBool::new(false));
    CANCEL_TOKEN.with(|t| *t.borrow_mut() = token.clone());
    token
}

fn request_cancel() {
    CANCEL_TOKEN.with(|t| t.borrow().store(true, Ordering::Relaxed));
}

thread_local! {
    static DIFF_GEN: RefCell<Arc<AtomicU64>> =
        RefCell::new(Arc::new(AtomicU64::new(0)));
    // Separate counters for set-left / set-right thumbnail loads so they
    // don't cancel each other when both sides are updated in quick succession.
    static SET_LEFT_GEN: RefCell<Arc<AtomicU64>> =
        RefCell::new(Arc::new(AtomicU64::new(0)));
    static SET_RIGHT_GEN: RefCell<Arc<AtomicU64>> =
        RefCell::new(Arc::new(AtomicU64::new(0)));
    // Counter for open_group background loads - used to discard stale results
    // when the user navigates to another group before the previous load finishes.
    static OPEN_GEN: RefCell<Arc<AtomicU64>> =
        RefCell::new(Arc::new(AtomicU64::new(0)));
    // Counter for fullscreen viewer image loads - closing the viewer or switching
    // to another image must discard the results of the previous load.
    static FULLSCREEN_GEN: RefCell<Arc<AtomicU64>> =
        RefCell::new(Arc::new(AtomicU64::new(0)));
}

fn next_diff_gen() -> (Arc<AtomicU64>, u64) {
    DIFF_GEN.with(|g| {
        let arc = g.borrow().clone();
        let val = arc.fetch_add(1, Ordering::Relaxed) + 1;
        (arc, val)
    })
}

fn next_set_left_gen() -> (Arc<AtomicU64>, u64) {
    SET_LEFT_GEN.with(|g| {
        let arc = g.borrow().clone();
        let val = arc.fetch_add(1, Ordering::Relaxed) + 1;
        (arc, val)
    })
}

fn next_set_right_gen() -> (Arc<AtomicU64>, u64) {
    SET_RIGHT_GEN.with(|g| {
        let arc = g.borrow().clone();
        let val = arc.fetch_add(1, Ordering::Relaxed) + 1;
        (arc, val)
    })
}

fn next_open_gen() -> (Arc<AtomicU64>, u64) {
    OPEN_GEN.with(|g| {
        let arc = g.borrow().clone();
        let val = arc.fetch_add(1, Ordering::Relaxed) + 1;
        (arc, val)
    })
}

fn next_fullscreen_gen() -> (Arc<AtomicU64>, u64) {
    FULLSCREEN_GEN.with(|g| {
        let arc = g.borrow().clone();
        let val = arc.fetch_add(1, Ordering::Relaxed) + 1;
        (arc, val)
    })
}

/// Score an image starts with in the fullscreen viewer.  The viewer stepper and the
/// group-level "delete below score" limit share the range below.
const DEFAULT_SCORE: i32 = 5;
const MIN_SCORE: i32 = 1;
const MAX_SCORE: i32 = 10;
/// A limit of 0 sits below every score, i.e. it deletes nothing.
const MIN_LIMIT: i32 = 0;

thread_local! {
    /// Scores entered in the fullscreen viewer, keyed by path: open_group() rebuilds the
    /// model, so a score kept in a row would be lost when a group is re-opened.
    static SCORES: RefCell<HashMap<String, i32>> = RefCell::new(HashMap::new());
}

struct RawPixels {
    data: Vec<u8>,
    width: u32,
    height: u32,
}

impl RawPixels {
    fn into_slint_image(self) -> slint::Image {
        if self.width == 0 {
            return slint::Image::default();
        }
        let buf = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(&self.data, self.width, self.height);
        slint::Image::from_rgba8(buf)
    }
}

fn load_raw_image(path: &str, max_w: u32, max_h: u32) -> Option<RawPixels> {
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() {
        return None;
    }
    match get_dynamic_image_from_path(
        path,
        Some(ImgResizeOptions {
            max_width: max_w,
            max_height: max_h,
            filter: FirFilterType::Bilinear,
        }),
    ) {
        Ok(result) => {
            let buf = result.image.into_rgba8();
            let w = buf.width();
            let h = buf.height();
            Some(RawPixels {
                data: buf.into_raw(),
                width: w,
                height: h,
            })
        }
        Err(e) => {
            error!("compare: failed to load \"{path}\": {e}");
            None
        }
    }
}

fn compute_diff_image(left_path: &str, right_path: &str) -> Option<RawPixels> {
    let left = load_raw_image(left_path, 1200, 900)?;
    let right = load_raw_image(right_path, 1200, 900)?;

    let (w, h) = (left.width, left.height);

    let right_data: Vec<u8> = if (right.width, right.height) != (w, h) {
        let right_buf = image::ImageBuffer::<image::Rgba<u8>, _>::from_raw(right.width, right.height, right.data)?;
        let resized = imageops::resize(&right_buf, w, h, imageops::FilterType::Lanczos3);
        resized.into_raw()
    } else {
        right.data
    };

    let mut out: Vec<u8> = Vec::with_capacity((w * h * 4) as usize);
    for (lp, rp) in left.data.as_chunks::<4>().0.iter().zip(right_data.as_chunks::<4>().0.iter()) {
        let dr = (lp[0] as f32 - rp[0] as f32).powi(2);
        let dg = (lp[1] as f32 - rp[1] as f32).powi(2);
        let db = (lp[2] as f32 - rp[2] as f32).powi(2);
        let val = ((dr + dg + db) / (3.0 * 255.0_f32 * 255.0_f32)).sqrt() * 255.0;
        let val = val.clamp(0.0, 255.0) as u8;
        out.extend_from_slice(&[val, val, val, 255]);
    }

    Some(RawPixels { data: out, width: w, height: h })
}

fn score_state_for(path: &str) -> (i32, bool) {
    SCORES.with(|scores| scores.borrow().get(path).map_or((DEFAULT_SCORE, false), |score| (*score, true)))
}

/// Score of every image of the opened group, in model order.
fn score_rows(images: &ModelRc<CompareImageData>) -> Vec<(String, i32)> {
    (0..images.row_count())
        .map(|idx| {
            let row = images
                .row_data(idx)
                .unwrap_or_else(|| panic!("score_rows: index {idx} out of bounds (row_count={})", images.row_count()));
            (row.path.to_string(), row.score)
        })
        .collect()
}

/// Paths scored below `limit`.  The same list drives the dialog preview and the delete.
fn paths_below_limit(scores: &[(String, i32)], limit: i32) -> Vec<String> {
    scores.iter().filter(|(_, score)| *score < limit).map(|(path, _)| path.clone()).collect()
}

fn stepped_score(current: i32, delta: i32) -> i32 {
    (current + delta).clamp(MIN_SCORE, MAX_SCORE)
}

fn clamped_limit(limit: i32) -> i32 {
    limit.clamp(MIN_LIMIT, MAX_SCORE)
}

/// `None` while the limit field holds something that is not a number.
fn parse_limit(text: &str) -> Option<i32> {
    text.trim().parse::<i32>().ok().map(clamped_limit)
}

/// Keeps the score of one image in its model row and in SCORES, so it survives the model
/// rebuild that follows a delete or a group change.
fn store_score(images: &ModelRc<CompareImageData>, compare_idx: usize, delta: i32) {
    let mut row = images
        .row_data(compare_idx)
        .unwrap_or_else(|| panic!("store_score: index {compare_idx} out of bounds (row_count={})", images.row_count()));
    let previous = row.score;
    let was_rated = row.rated;
    row.score = stepped_score(row.score, delta);
    row.rated = true;
    let path = row.path.to_string();
    let score = row.score;
    images.set_row_data(compare_idx, row);
    SCORES.with(|scores| {
        if was_rated {
            if score != previous {
                log::debug!("compare: score of \"{path}\" changed {previous} -> {score}");
            } else {
                log::debug!("compare: score of \"{path}\" kept at {score}");
            }
        } else {
            log::info!("compare: rated \"{path}\" {score}");
        }
        scores.borrow_mut().insert(path, score);
    });
}

/// How much of the opened group is scored - the "delete below score" entry only unlocks
/// once every image has one.
fn refresh_score_summary(state: &AppState) {
    let images = state.get_compare_images();
    let rated = (0..images.row_count()).filter(|idx| images.row_data(*idx).is_some_and(|row| row.rated)).count();
    state.set_compare_rated_count(rated as i32);
    let all_rated = rated > 0 && rated == images.row_count();
    state.set_compare_all_rated(all_rated);
    log::debug!("compare: {rated}/{} image(s) rated (delete-by-score unlocked={all_rated})", images.row_count());
}

fn refresh_score_delete_preview(state: &AppState) {
    let count = paths_below_limit(&score_rows(&state.get_compare_images()), state.get_compare_score_delete_limit()).len();
    state.set_compare_score_delete_count(count as i32);
    log::debug!(
        "compare: delete-by-score preview: {count} of {} image(s) below limit {}",
        state.get_compare_images().row_count(),
        state.get_compare_score_delete_limit()
    );
}

/// Group of a path in the current (post-delete) model: rebuild_similar_images_after_delete()
/// renumbers the groups, so they are located by path instead of by index.
fn locate_path(app: &MainWindow, path: &str) -> Option<(usize, usize)> {
    let groups = app.get_similar_images_groups();
    (0..groups.row_count()).find_map(|group_idx| {
        let group = groups.row_data(group_idx)?;
        (0..group.items.row_count()).find_map(|item_idx| {
            let item = group.items.row_data(item_idx)?;
            (item.full_path.as_str() == path).then_some((group_idx, item_idx))
        })
    })
}

pub fn wire_compare(app: &MainWindow) {
    wire_compare_open(app);
    wire_compare_set_left(app);
    wire_compare_set_right(app);
    wire_compare_toggle_checkbox(app);
    wire_compare_next_group(app);
    wire_compare_prev_group(app);
    wire_compare_swap(app);
    wire_compare_cancel_load(app);
    wire_compare_compute_diff(app);
    wire_compare_fullscreen_open(app);
    wire_compare_fullscreen_close(app);
    wire_compare_delete_current(app);
    wire_compare_score(app);
    wire_compare_score_delete(app);
}

fn wire_compare_open(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_open(move |group_idx| {
        let app = weak.upgrade().expect("wire_compare_open: upgrade failed");
        open_group(&app, group_idx as usize);
    });
}

fn wire_compare_set_left(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_set_left(move |compare_idx| {
        let app = weak.upgrade().expect("wire_compare_set_left: upgrade failed");
        let state = app.global::<AppState>();
        let idx = compare_idx as usize;
        if compare_idx == state.get_compare_right_idx() {
            return;
        }
        let images = state.get_compare_images();
        if idx >= images.row_count() {
            return;
        }
        let path = images
            .row_data(idx)
            .unwrap_or_else(|| panic!("wire_compare_set_left: invalid compare_idx {compare_idx}"))
            .path
            .to_string();
        state.set_compare_left_idx(compare_idx);
        state.set_compare_diff_image(slint::Image::default());

        let (gen_counter, gen_val) = next_set_left_gen();
        let weak2 = weak.clone();
        thread::spawn(move || {
            let raw = load_raw_image(&path, 1200, 900);
            if gen_counter.load(Ordering::Relaxed) != gen_val {
                return;
            }
            weak2
                .upgrade_in_event_loop(move |app| {
                    if gen_counter.load(Ordering::Relaxed) == gen_val
                        && let Some(raw) = raw
                    {
                        app.global::<AppState>().set_compare_left_image(raw.into_slint_image());
                    }
                })
                .expect("set_left: upgrade_in_event_loop failed");
        });
    });
}

fn wire_compare_set_right(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_set_right(move |compare_idx| {
        let app = weak.upgrade().expect("wire_compare_set_right: upgrade failed");
        let state = app.global::<AppState>();
        let idx = compare_idx as usize;
        if compare_idx == state.get_compare_left_idx() {
            return;
        }
        let images = state.get_compare_images();
        if idx >= images.row_count() {
            return;
        }
        let path = images
            .row_data(idx)
            .unwrap_or_else(|| panic!("wire_compare_set_right: invalid compare_idx {idx}"))
            .path
            .to_string();
        state.set_compare_right_idx(compare_idx);
        state.set_compare_diff_image(slint::Image::default());

        let (gen_counter, gen_val) = next_set_right_gen();
        let weak2 = weak.clone();
        thread::spawn(move || {
            let raw = load_raw_image(&path, 1200, 900);
            if gen_counter.load(Ordering::Relaxed) != gen_val {
                return;
            }
            weak2
                .upgrade_in_event_loop(move |app| {
                    if gen_counter.load(Ordering::Relaxed) == gen_val
                        && let Some(raw) = raw
                    {
                        app.global::<AppState>().set_compare_right_image(raw.into_slint_image());
                    }
                })
                .expect("set_right: upgrade_in_event_loop failed");
        });
    });
}

fn wire_compare_toggle_checkbox(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_toggle_checkbox(move |compare_idx| {
        let app = weak.upgrade().expect("wire_compare_toggle_checkbox: upgrade failed");
        let state = app.global::<AppState>();
        let cidx = compare_idx as usize;
        let images_model = state.get_compare_images();

        if cidx >= images_model.row_count() {
            return;
        }

        let item = images_model
            .row_data(cidx)
            .unwrap_or_else(|| panic!("wire_compare_toggle_checkbox: invalid compare_idx {cidx}"));
        let new_checked = !item.checked;
        let flat_idx = item.flat_idx as usize;
        let group_idx = item.group_idx as usize;
        let item_idx = item.item_idx as usize;

        // checked state lives in three separate models (flat, gallery groups, compare) - update all.
        let flat_model = app.get_similar_images_model();
        let mut row = flat_model
            .row_data(flat_idx)
            .unwrap_or_else(|| panic!("wire_compare_toggle_checkbox: flat_idx {flat_idx} out of bounds (row_count={})", flat_model.row_count()));
        row.checked = new_checked;
        flat_model.set_row_data(flat_idx, row);

        let groups = app.get_similar_images_groups();
        let group = groups
            .row_data(group_idx)
            .unwrap_or_else(|| panic!("wire_compare_toggle_checkbox: group_idx {group_idx} out of bounds (row_count={})", groups.row_count()));
        let mut gi = group
            .items
            .row_data(item_idx)
            .unwrap_or_else(|| panic!("wire_compare_toggle_checkbox: item_idx {item_idx} out of bounds in group {group_idx}"));
        gi.checked = new_checked;
        group.items.set_row_data(item_idx, gi);

        update_compare_checked(&images_model, cidx, new_checked);

        let delta: i64 = if new_checked { 1 } else { -1 };
        let cur = state.get_selected_count() as i64 + delta;
        state.set_selected_count(cur.max(0) as i32);
    });
}

fn wire_compare_next_group(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_next_group(move || {
        let app = weak.upgrade().expect("wire_compare_next_group: upgrade failed");
        let state = app.global::<AppState>();
        let groups = app.get_similar_images_groups();
        let current = state.get_compare_current_group_idx() as usize;
        let next = current + 1;
        if next < groups.row_count() {
            open_group(&app, next);
        }
    });
}

fn wire_compare_prev_group(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_prev_group(move || {
        let app = weak.upgrade().expect("wire_compare_prev_group: upgrade failed");
        let state = app.global::<AppState>();
        let current = state.get_compare_current_group_idx() as usize;
        if current > 0 {
            open_group(&app, current - 1);
        }
    });
}

fn wire_compare_swap(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_swap(move || {
        let app = weak.upgrade().expect("wire_compare_swap: upgrade failed");
        let state = app.global::<AppState>();
        let li = state.get_compare_left_idx();
        let ri = state.get_compare_right_idx();
        let li_img = state.get_compare_left_image();
        let ri_img = state.get_compare_right_image();
        state.set_compare_left_idx(ri);
        state.set_compare_right_idx(li);
        state.set_compare_left_image(ri_img);
        state.set_compare_right_image(li_img);
        state.set_compare_diff_image(slint::Image::default());
    });
}

fn wire_compare_cancel_load(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_cancel_load(move || {
        let app = weak.upgrade().expect("wire_compare_cancel_load: upgrade failed");
        app.global::<AppState>().set_compare_cancelling(true);
        request_cancel();
    });
}

fn wire_compare_compute_diff(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_compute_diff(move || {
        let app = weak.upgrade().expect("wire_compare_compute_diff: upgrade failed");
        let state = app.global::<AppState>();
        let li = state.get_compare_left_idx() as usize;
        let ri = state.get_compare_right_idx() as usize;
        let images = state.get_compare_images();

        let left_path = images.row_data(li).map(|d| d.path.to_string()).unwrap_or_default();
        let right_path = images.row_data(ri).map(|d| d.path.to_string()).unwrap_or_default();
        if left_path.is_empty() || right_path.is_empty() {
            return;
        }

        state.set_compare_diff_image(slint::Image::default());
        let (gen_counter, gen_val) = next_diff_gen();
        let weak2 = weak.clone();

        thread::spawn(move || {
            let diff = compute_diff_image(&left_path, &right_path);
            if gen_counter.load(Ordering::Relaxed) != gen_val {
                return;
            }
            weak2
                .upgrade_in_event_loop(move |app| {
                    if gen_counter.load(Ordering::Relaxed) == gen_val
                        && let Some(raw) = diff
                    {
                        app.global::<AppState>().set_compare_diff_image(raw.into_slint_image());
                    }
                })
                .expect("compare_compute_diff: upgrade_in_event_loop failed");
        });
    });
}

fn wire_compare_fullscreen_open(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_fullscreen_open(move |compare_idx| {
        let app = weak.upgrade().expect("wire_compare_fullscreen_open: upgrade failed");
        load_fullscreen_image(&app, compare_idx);
    });
}

fn wire_compare_fullscreen_close(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_fullscreen_close(move || {
        let app = weak.upgrade().expect("wire_compare_fullscreen_close: upgrade failed");
        log::info!("compare: fullscreen viewer closed");
        reset_fullscreen(&app.global::<AppState>());
    });
}

fn wire_compare_delete_current(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_delete_current(move || {
        let app = weak.upgrade().expect("wire_compare_delete_current: upgrade failed");
        let state = app.global::<AppState>();
        let idx = state.get_compare_fullscreen_idx();
        let images = state.get_compare_images();
        if idx < 0 || idx as usize >= images.row_count() {
            return;
        }
        let path = images
            .row_data(idx as usize)
            .unwrap_or_else(|| panic!("compare_delete_current: index {idx} out of bounds (row_count={})", images.row_count()))
            .path
            .to_string();

        // The delete bar belongs to the image that is being removed.
        state.set_compare_fullscreen_delete_visible(false);
        log::info!("compare: deleting \"{path}\" from the fullscreen viewer");

        let weak2 = weak.clone();
        thread::spawn(move || {
            let result = delete_path(&path);
            weak2
                .upgrade_in_event_loop(move |app| finish_fullscreen_delete(&app, &path, result))
                .expect("compare_delete_current: upgrade_in_event_loop failed");
        });
    });
}

/// Shows the viewer for `compare_idx` and loads that image in the background.
fn load_fullscreen_image(app: &MainWindow, compare_idx: i32) {
    let state = app.global::<AppState>();
    let images = state.get_compare_images();
    if compare_idx < 0 || compare_idx as usize >= images.row_count() {
        log::warn!("compare: fullscreen viewer ignored image {compare_idx}, the model has {} row(s)", images.row_count());
        return;
    }
    let path = images
        .row_data(compare_idx as usize)
        .unwrap_or_else(|| panic!("load_fullscreen_image: index {compare_idx} out of bounds (row_count={})", images.row_count()))
        .path
        .to_string();

    log::debug!("compare: fullscreen viewer showing {compare_idx} of {total}: \"{path}\"", total = images.row_count());
    state.set_compare_fullscreen_idx(compare_idx);
    state.set_compare_fullscreen_visible(true);
    state.set_compare_fullscreen_delete_visible(false);
    state.set_compare_fullscreen_image(slint::Image::default());
    state.set_compare_fullscreen_loading(true);

    // RawPixels (not slint::Image) crosses the thread boundary - slint::Image isn't Send.
    let (gen_counter, gen_val) = next_fullscreen_gen();
    let weak = app.as_weak();
    thread::spawn(move || {
        // Larger than the side-by-side views - this image fills the whole screen.
        let raw = load_raw_image(&path, 2048, 2048);
        weak.upgrade_in_event_loop(move |app| {
            if gen_counter.load(Ordering::Relaxed) != gen_val {
                return;
            }
            let state = app.global::<AppState>();
            state.set_compare_fullscreen_loading(false);
            if let Some(raw) = raw {
                state.set_compare_fullscreen_image(raw.into_slint_image());
            } else {
                log::warn!("compare: fullscreen viewer could not decode \"{path}\"");
            }
        })
        .expect("load_fullscreen_image: upgrade_in_event_loop failed");
    });
}

/// Drops the viewer state and discards the results of an in-flight fullscreen load.
fn reset_fullscreen(state: &AppState) {
    let _ = next_fullscreen_gen();
    state.set_compare_fullscreen_visible(false);
    state.set_compare_fullscreen_loading(false);
    state.set_compare_fullscreen_delete_visible(false);
    state.set_compare_fullscreen_idx(0);
    state.set_compare_fullscreen_image(slint::Image::default());
}

fn wire_compare_score(app: &MainWindow) {
    // The score range lives here, so the UI can disable the -/+ buttons at the bounds
    // and label the limit field with it.
    let state = app.global::<AppState>();
    state.set_compare_score_min(MIN_SCORE);
    state.set_compare_score_max(MAX_SCORE);

    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_step(move |compare_idx, delta| {
        let app = weak.upgrade().expect("wire_compare_score: upgrade failed");
        let state = app.global::<AppState>();
        let images = state.get_compare_images();
        if compare_idx < 0 || compare_idx as usize >= images.row_count() {
            log::warn!("compare: score step ignored, index {compare_idx} not in the {}-row model", images.row_count());
            return;
        }
        store_score(&images, compare_idx as usize, delta);
        refresh_score_summary(&state);
    });
}

fn wire_compare_score_delete(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_delete_open(move || {
        let app = weak.upgrade().expect("compare_score_delete_open: upgrade failed");
        let state = app.global::<AppState>();
        state.set_compare_score_delete_limit(DEFAULT_SCORE);
        state.set_compare_score_delete_limit_text(SharedString::from(DEFAULT_SCORE.to_string()));
        state.set_compare_score_delete_progress_text(SharedString::default());
        state.set_compare_score_delete_running(false);
        refresh_score_delete_preview(&state);
        state.set_compare_score_delete_visible(true);
        log::info!(
            "compare: delete-by-score dialog opened (limit={DEFAULT_SCORE}, {} image(s) below it)",
            state.get_compare_score_delete_count()
        );
    });

    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_delete_close(move || {
        let app = weak.upgrade().expect("compare_score_delete_close: upgrade failed");
        let state = app.global::<AppState>();
        // While the worker runs, this dialog is the only place its progress is visible.
        if state.get_compare_score_delete_running() {
            log::warn!("compare: delete-by-score dialog stays open, a delete is still running");
            return;
        }
        state.set_compare_score_delete_visible(false);
        log::debug!("compare: delete-by-score dialog closed");
    });

    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_delete_limit_edited(move |text| {
        let app = weak.upgrade().expect("compare_score_delete_limit_edited: upgrade failed");
        let state = app.global::<AppState>();
        // A field the user is still typing in (empty included) keeps its text.
        let Some(limit) = parse_limit(text.as_str()) else {
            log::debug!(
                "compare: delete-by-score limit \"{}\" is not a number, keeping {}",
                text.as_str(),
                state.get_compare_score_delete_limit()
            );
            return;
        };
        state.set_compare_score_delete_limit(limit);
        state.set_compare_score_delete_limit_text(SharedString::from(limit.to_string()));
        refresh_score_delete_preview(&state);
    });

    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_delete_limit_step(move |delta| {
        let app = weak.upgrade().expect("compare_score_delete_limit_step: upgrade failed");
        let state = app.global::<AppState>();
        let limit = clamped_limit(state.get_compare_score_delete_limit() + delta);
        state.set_compare_score_delete_limit(limit);
        state.set_compare_score_delete_limit_text(SharedString::from(limit.to_string()));
        refresh_score_delete_preview(&state);
    });

    let weak = app.as_weak();
    app.global::<AppState>().on_compare_score_delete_confirm(move || {
        let app = weak.upgrade().expect("compare_score_delete_confirm: upgrade failed");
        start_score_delete(&app);
    });
}

/// Deletes every image of the opened group scored below the dialog limit.
fn start_score_delete(app: &MainWindow) {
    let state = app.global::<AppState>();
    let limit = state.get_compare_score_delete_limit();
    if state.get_compare_score_delete_running() {
        // Two workers over the same paths would make the second pass fail on files the
        // first one already removed.
        log::warn!("compare: delete-by-score ignored, another delete is still running");
        return;
    }
    let images = state.get_compare_images();
    let targets = paths_below_limit(&score_rows(&images), limit);
    if targets.is_empty() {
        log::warn!("compare: delete-by-score ignored, no image of the group is below the limit {limit}");
        return;
    }
    let total = targets.len();
    // The group is re-opened afterwards, and by then the compare model is the rebuilt one.
    let group_paths: Vec<String> = score_rows(&images).into_iter().map(|(path, _)| path).collect();

    state.set_compare_score_delete_running(true);
    state.set_compare_score_delete_progress_text(SharedString::from(format!("0 / {total}")));
    log::info!(
        "compare: delete-by-score removing {total} image(s) below {limit} from group {}",
        state.get_compare_current_group_idx()
    );
    log::debug!("compare: delete-by-score targets: {targets:?}");

    let weak = app.as_weak();
    thread::spawn(move || {
        let mut deleted: HashSet<String> = HashSet::new();
        let mut errors: Vec<String> = Vec::new();

        for (done, path) in targets.iter().enumerate() {
            match delete_path(path) {
                Ok(()) => {
                    log::debug!("compare: delete-by-score removed \"{path}\"");
                    deleted.insert(path.clone());
                }
                Err(err) => {
                    log::error!("compare: failed to delete \"{path}\": {err}");
                    errors.push(format!("{path}\n  {err}"));
                }
            }

            let progress = SharedString::from(format!("{} / {total}", done + 1));
            weak.upgrade_in_event_loop(move |app| app.global::<AppState>().set_compare_score_delete_progress_text(progress))
                .expect("start_score_delete progress: upgrade_in_event_loop failed");
        }

        weak.upgrade_in_event_loop(move |app| finish_score_delete(&app, &group_paths, deleted, errors))
            .expect("start_score_delete finish: upgrade_in_event_loop failed");
    });
}

fn finish_score_delete(app: &MainWindow, group_paths: &[String], deleted: HashSet<String>, errors: Vec<String>) {
    let state = app.global::<AppState>();
    state.set_compare_score_delete_running(false);
    state.set_compare_score_delete_progress_text(SharedString::default());
    state.set_compare_score_delete_visible(false);
    log::info!("compare: delete-by-score finished ({} deleted, {} failed)", deleted.len(), errors.len());

    SCORES.with(|scores| {
        let mut scores = scores.borrow_mut();
        for path in &deleted {
            scores.remove(path);
        }
    });

    if !deleted.is_empty() {
        rebuild_similar_images_after_delete(app, &deleted);
    }

    let status = if errors.is_empty() {
        crate::flc!("status_deleted_selected")
    } else {
        crate::flc!("status_deleted_with_errors")
    };
    state.set_status_message(SharedString::from(status));
    if !errors.is_empty() {
        show_delete_errors(app, &errors);
    }

    // The overlay stays on the group that still holds images, keeping their scores.
    let surviving_group = group_paths
        .iter()
        .filter(|path| !deleted.contains(*path))
        .find_map(|path| locate_path(app, path))
        .map(|(group_idx, _)| group_idx);
    match surviving_group {
        Some(group_idx) => {
            log::info!(
                "compare: delete-by-score kept the overlay on group {group_idx} ({} survivor(s))",
                group_paths.len() - deleted.len()
            );
            open_group(app, group_idx);
        }
        None => {
            log::info!("compare: delete-by-score removed the whole group, closing the overlay");
            reset_fullscreen(&state);
            state.set_compare_loading(false);
            state.set_compare_visible(false);
        }
    }
}

fn open_group(app: &MainWindow, group_idx: usize) {
    let groups = app.get_similar_images_groups();
    let state = app.global::<AppState>();

    if group_idx >= groups.row_count() {
        log::warn!("compare: open group {group_idx} ignored, the model holds only {} group(s)", groups.row_count());
        return;
    }
    let group = groups.row_data(group_idx).unwrap_or_else(|| panic!("open_group: invalid group_idx {group_idx}"));
    if group.items.row_count() == 0 {
        log::warn!("compare: open group {group_idx} ignored, it holds no image");
        return;
    }

    let flat_model = app.get_similar_images_model();
    let mut compare_data: Vec<CompareImageData> = Vec::with_capacity(group.items.row_count());

    for i in 0..group.items.row_count() {
        let item = group.items.row_data(i).unwrap_or_else(|| panic!("open_group: invalid item_idx {i} in group {group_idx}"));

        // Use the live checked state from the flat model (may have changed since
        // the gallery group was last built).
        let live_checked = flat_model.row_data(item.flat_idx as usize).map_or(item.checked, |r| r.checked);

        let get_str = |idx: usize| -> SharedString {
            item.val_str
                .row_data(idx)
                .unwrap_or_else(|| panic!("open_group: val_str[{idx}] missing, full val_str={:?}", item.val_str.iter().collect::<Vec<_>>()))
        };

        // Score of a previous visit to this group, if there was one.
        let (score, rated) = score_state_for(item.full_path.as_str());

        compare_data.push(CompareImageData {
            path: item.full_path.clone(),
            dir: get_str(crate::common::STR_IDX_PATH),
            name: item.name.clone(),
            size: item.size.clone(),
            dims: get_str(crate::common::StrDataSimilarImages::DimsDisplay as usize),
            modified: get_str(crate::common::STR_IDX_MODIFIED),
            checked: live_checked,
            thumbnail: item.thumbnail.clone(),
            flat_idx: item.flat_idx,
            group_idx: group_idx as i32,
            item_idx: i as i32,
            score,
            rated,
        });
    }

    let carried_scores = compare_data.iter().filter(|row| row.rated).count();
    log::info!(
        "compare: opening group {group_idx} ({} image(s), {carried_scores} with a score from an earlier visit)",
        compare_data.len()
    );
    let total = compare_data.len() as i32;
    let left_idx = 0i32;
    let right_idx = (total - 1).min(1);
    let left_path = compare_data.first().map(|s| s.path.to_string()).unwrap_or_default();
    let right_path = compare_data.get(right_idx as usize).map(|s| s.path.to_string()).unwrap_or_default();

    state.set_compare_current_group_idx(group_idx as i32);
    state.set_compare_images(ModelRc::new(VecModel::from(compare_data)));
    refresh_score_summary(&state);
    state.set_compare_left_idx(left_idx);
    state.set_compare_right_idx(right_idx);
    state.set_compare_left_image(slint::Image::default());
    state.set_compare_right_image(slint::Image::default());
    state.set_compare_diff_image(slint::Image::default());
    state.set_compare_loading(true);
    state.set_compare_cancelling(false);
    state.set_compare_loading_current(0);
    state.set_compare_loading_total(total);
    state.set_compare_visible(true);
    // Opening another group must not leave the viewer of the previous one on screen.
    reset_fullscreen(&state);

    // RawPixels (not slint::Image) crosses the thread boundary - slint::Image isn't Send.
    let cancel = new_cancel_token();
    let (open_gen_counter, open_gen_val) = next_open_gen();
    let weak = app.as_weak();

    thread::spawn(move || {
        if cancel.load(Ordering::Relaxed) {
            // Explicit user cancel - still the current group, so close the overlay.
            if open_gen_counter.load(Ordering::Relaxed) == open_gen_val {
                weak.upgrade_in_event_loop(|app| finish_cancel(&app)).expect("open_group cancel1: upgrade failed");
            }
            return;
        }

        let left_full = load_raw_image(&left_path, 1200, 900);
        let right_full = if left_path != right_path { load_raw_image(&right_path, 1200, 900) } else { None };

        if cancel.load(Ordering::Relaxed) {
            if open_gen_counter.load(Ordering::Relaxed) == open_gen_val {
                weak.upgrade_in_event_loop(|app| finish_cancel(&app)).expect("open_group cancel2: upgrade failed");
            }
            return;
        }

        weak.upgrade_in_event_loop(move |app| {
            // Stale: a newer open_group call superseded this one; discard results.
            if open_gen_counter.load(Ordering::Relaxed) != open_gen_val {
                return;
            }
            let state = app.global::<AppState>();
            if let Some(raw) = left_full {
                state.set_compare_left_image(raw.into_slint_image());
            }
            if let Some(raw) = right_full {
                state.set_compare_right_image(raw.into_slint_image());
            }
            state.set_compare_loading(false);
            state.set_compare_cancelling(false);
        })
        .expect("open_group finish: upgrade_in_event_loop failed");
    });
}

fn finish_fullscreen_delete(app: &MainWindow, path: &str, result: Result<(), String>) {
    let state = app.global::<AppState>();
    match result {
        Ok(()) => {
            log::info!("compare: fullscreen viewer removed \"{path}\"");
            let deleted: std::collections::HashSet<String> = std::iter::once(path.to_string()).collect();
            rebuild_similar_images_after_delete(app, &deleted);
            state.set_status_message(SharedString::from(crate::flc!("status_deleted_selected")));
            reopen_after_fullscreen_delete(app, path);
        }
        Err(err) => {
            log::error!("compare: failed to delete \"{path}\": {err}");
            state.set_delete_errors_text(SharedString::from(format!("{path}\n  {err}")));
            state.set_delete_errors_visible(true);
        }
    }
}

/// Keeps the viewer open on the deleted image nearest surviving neighbour, so the user
/// can carry on reviewing the group instead of being sent back to the gallery.
fn reopen_after_fullscreen_delete(app: &MainWindow, deleted_path: &str) {
    let state = app.global::<AppState>();
    let images = state.get_compare_images();
    let cur = state.get_compare_fullscreen_idx() as usize;

    // The compare model is still the pre-delete one, so the removed image sits at `cur`.
    let neighbor_path = images
        .row_data(cur + 1)
        .map(|d| d.path.to_string())
        .or_else(|| cur.checked_sub(1).and_then(|prev| images.row_data(prev)).map(|d| d.path.to_string()));

    let Some(neighbor_path) = neighbor_path else {
        log::info!("compare: fullscreen viewer removed the last image of the group (\"{deleted_path}\")");
        reset_fullscreen(&state);
        state.set_compare_visible(false);
        return;
    };

    // rebuild_similar_images_after_delete() renumbered the groups, so the group is
    // located by the surviving path instead of by index.
    let target = locate_path(app, neighbor_path.as_str());

    match target {
        Some((group_idx, item_idx)) => {
            // open_group() resets the viewer, so it is re-opened afterwards.
            open_group(app, group_idx);
            load_fullscreen_image(app, item_idx as i32);
        }
        None => {
            log::info!("compare: no surviving neighbour of \"{deleted_path}\" left to compare");
            reset_fullscreen(&state);
            state.set_compare_visible(false);
        }
    }
}

fn finish_cancel(app: &MainWindow) {
    let state = app.global::<AppState>();
    state.set_compare_loading(false);
    state.set_compare_cancelling(false);
    reset_fullscreen(&state);
    state.set_compare_visible(false);
}

fn update_compare_checked(images_model: &ModelRc<CompareImageData>, compare_idx: usize, new_checked: bool) {
    let mut item = images_model
        .row_data(compare_idx)
        .unwrap_or_else(|| panic!("update_compare_checked: compare_idx={compare_idx} out of bounds (row_count={})", images_model.row_count()));
    item.checked = new_checked;
    images_model.set_row_data(compare_idx, item);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stepped_score_moves_within_the_supported_range() {
        assert_eq!(stepped_score(DEFAULT_SCORE, 1), DEFAULT_SCORE + 1);
        assert_eq!(stepped_score(MAX_SCORE, 1), MAX_SCORE);
        assert_eq!(stepped_score(MIN_SCORE, -1), MIN_SCORE);
    }

    #[test]
    fn stepped_score_without_a_delta_keeps_the_value() {
        // Tapping the number in the viewer accepts the score it already shows.
        assert_eq!(stepped_score(DEFAULT_SCORE, 0), DEFAULT_SCORE);
        assert_eq!(stepped_score(MIN_SCORE + 1, 0), MIN_SCORE + 1);
    }

    #[test]
    fn parse_limit_reads_plain_numbers_and_clamps_them() {
        assert_eq!(parse_limit("7"), Some(7));
        assert_eq!(parse_limit(" 0 "), Some(0));
        assert_eq!(parse_limit("99"), Some(MAX_SCORE));
        assert_eq!(parse_limit("-3"), Some(MIN_LIMIT));
    }

    #[test]
    fn parse_limit_rejects_what_is_not_a_number() {
        assert_eq!(parse_limit(""), None);
        assert_eq!(parse_limit("abc"), None);
        assert_eq!(parse_limit("5.5"), None);
    }

    #[test]
    fn paths_below_limit_keeps_only_lower_scores() {
        let scores: Vec<(String, i32)> = vec![
            ("low".to_string(), MIN_SCORE),
            ("same".to_string(), DEFAULT_SCORE),
            ("high".to_string(), MAX_SCORE),
        ];
        assert_eq!(paths_below_limit(&scores, DEFAULT_SCORE), vec!["low".to_string()]);
        assert_eq!(paths_below_limit(&scores, MIN_LIMIT), Vec::<String>::new());
        assert_eq!(
            paths_below_limit(&scores, MAX_SCORE + 1),
            vec!["low".to_string(), "same".to_string(), "high".to_string()]
        );
    }
}
