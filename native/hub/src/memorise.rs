//! Handlers for learning passages by heart (see `haqor_core::memorise`).

use haqor_core::bible::Bible;
use haqor_core::memorise::{self as core, MemoryPurpose, MemorySettings, MemoryVerseGrade};
use haqor_core::tutor::Grade;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock, now_epoch, persist_browser_progress};
use crate::signals::{
    DeleteMemoryPassage, GetMemoryLayout, GetMemoryPassages, GetMemoryRun, GetMemoryStats,
    GetNextMemoryCard, MemoryAchievement, MemoryCard, MemoryDay, MemoryItem, MemoryLayout,
    MemoryLayoutVerse, MemoryPassageEntry, MemoryPassages, MemoryReviewResult, MemorySegment,
    MemoryStats, MemoryVerseState, MemoryWord, ResetMemoryLayout, SaveMemoryPassage,
    SetMemoryLayout, SetMemorySettings, SubmitMemoryRecital,
};

/// Days of history and forecast the dashboard graphs.
const HISTORY_DAYS: i64 = 30;
const FORECAST_DAYS: i64 = 14;

fn send_passages(bible: &Bible, saved_id: String) {
    match bible.memory_passages(now_epoch()) {
        Ok(passages) => MemoryPassages {
            passages: passages
                .into_iter()
                .map(|s| MemoryPassageEntry {
                    id: s.passage.id,
                    book: s.passage.book,
                    start_chapter: s.passage.start_chapter,
                    start_verse: s.passage.start_verse,
                    end_chapter: s.passage.end_chapter,
                    end_verse: s.passage.end_verse,
                    title: s.passage.title,
                    created_epoch: s.passage.created_epoch,
                    verses: s
                        .verses
                        .into_iter()
                        .map(|v| MemoryVerseState {
                            chapter: v.chapter,
                            verse: v.verse,
                            strength: v.strength,
                            due: v.due,
                            section_start: v.section_start,
                        })
                        .collect(),
                    learnt: s.learnt,
                    mature: s.mature,
                    due: s.due,
                    mastery_pct: s.mastery_pct,
                    last_studied_epoch: s.last_studied_epoch,
                })
                .collect(),
            saved_id,
        }
        .send_signal_to_dart(),
        Err(e) => debug_print!("memory passages error: {e:?}"),
    }
}

fn send_layout(bible: &Bible, passage_id: &str) {
    match bible.memory_layout(passage_id) {
        Ok(verses) => MemoryLayout {
            passage_id: passage_id.to_string(),
            verses: verses
                .into_iter()
                .map(|v| MemoryLayoutVerse {
                    chapter: v.chapter,
                    verse: v.verse,
                    words: v.words,
                    line_starts: v
                        .line_starts
                        .into_iter()
                        .map(|i| i.min(255) as u8)
                        .collect(),
                    section_start: v.section_start,
                    custom_lines: v.custom_lines,
                    custom_section: v.custom_section,
                })
                .collect(),
        }
        .send_signal_to_dart(),
        Err(e) => debug_print!("memory layout error: {e:?}"),
    }
}

fn to_signal_card(card: core::MemoryCard) -> MemoryCard {
    MemoryCard {
        passage_id: card.passage_id,
        book: card.book,
        purpose: card.purpose.as_str().to_string(),
        title: card.title,
        prompt: card.prompt,
        segments: card
            .segments
            .into_iter()
            .map(|s| MemorySegment {
                chapter: s.chapter,
                verse: s.verse,
                line: s.line.min(255) as u8,
                line_count: s.line_count.min(255) as u8,
                words: s
                    .words
                    .into_iter()
                    .map(|w| MemoryWord {
                        text: w.text,
                        gloss: w.gloss,
                        translit: w.translit,
                    })
                    .collect(),
            })
            .collect(),
        cue: card.cue,
        target_chapter: card.target_chapter,
        target_verse: card.target_verse,
        step: card.step as u32,
        step_count: card.step_count as u32,
        is_new: card.is_new,
        position: card.position as u32,
        total: card.total as u32,
        section: card.section as u32,
        section_count: card.section_count as u32,
    }
}

fn to_signal_item(item: core::MemoryItem) -> MemoryItem {
    match item {
        core::MemoryItem::Card(card) => MemoryItem {
            kind: "card".to_string(),
            card: Some(to_signal_card(card)),
            next_due_epoch: 0,
            can_learn_more: true,
        },
        core::MemoryItem::Done {
            next_due_epoch,
            can_learn_more,
        } => MemoryItem {
            kind: "done".to_string(),
            card: None,
            next_due_epoch,
            can_learn_more,
        },
        core::MemoryItem::Empty => MemoryItem {
            kind: "empty".to_string(),
            card: None,
            next_due_epoch: 0,
            can_learn_more: false,
        },
    }
}

fn send_stats(bible: &Bible, utc_offset: i64) {
    match bible.memory_stats(now_epoch(), utc_offset, HISTORY_DAYS, FORECAST_DAYS) {
        Ok(s) => MemoryStats {
            total_xp: s.total_xp,
            level: s.level,
            level_xp: s.level_xp,
            level_span: s.level_span,
            today_xp: s.today_xp,
            daily_goal_xp: s.daily_goal_xp,
            new_per_day: s.new_per_day,
            streak_days: s.streak_days,
            best_streak_days: s.best_streak_days,
            goal_days: s.goal_days,
            verses_learnt: s.verses_learnt,
            verses_mature: s.verses_mature,
            verses_learning: s.verses_learning,
            verses_total: s.verses_total,
            due_now: s.due_now,
            passages_completed: s.passages_completed,
            passages_total: s.passages_total,
            reviews_total: s.reviews_total,
            accuracy_pct: s.accuracy_pct,
            history: s
                .history
                .into_iter()
                .map(|d| MemoryDay {
                    day: d.day,
                    xp: d.xp,
                    reviews: d.reviews,
                    learnt_total: d.learnt_total,
                })
                .collect(),
            forecast: s.forecast,
            achievements: s
                .achievements
                .into_iter()
                .map(|a| MemoryAchievement {
                    key: a.key,
                    title: a.title,
                    description: a.description,
                    progress: a.progress,
                    target: a.target,
                    earned: a.earned,
                })
                .collect(),
        }
        .send_signal_to_dart(),
        Err(e) => debug_print!("memory stats error: {e:?}"),
    }
}

pub async fn get_memory_passages(bible: SharedBible) {
    let receiver = GetMemoryPassages::get_dart_signal_receiver();
    while receiver.recv().await.is_some() {
        send_passages(&lock(&bible), String::new());
    }
}

pub async fn save_memory_passage(bible: SharedBible) {
    let receiver = SaveMemoryPassage::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let bible = lock(&bible);
        match bible.add_memory_passage(
            r.book,
            r.start_chapter,
            r.start_verse,
            r.end_chapter,
            r.end_verse,
            &r.title,
            now_epoch(),
        ) {
            Ok(saved) => {
                persist_browser_progress(&bible);
                send_passages(&bible, saved.map(|p| p.id).unwrap_or_default());
            }
            Err(e) => debug_print!("save_memory_passage error: {e:?}"),
        }
    }
}

pub async fn delete_memory_passage(bible: SharedBible) {
    let receiver = DeleteMemoryPassage::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.delete_memory_passage(&pack.message.id, now_epoch()) {
            Ok(_) => {
                persist_browser_progress(&bible);
                send_passages(&bible, String::new());
            }
            Err(e) => debug_print!("delete_memory_passage error: {e:?}"),
        }
    }
}

pub async fn get_memory_layout(bible: SharedBible) {
    let receiver = GetMemoryLayout::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        send_layout(&lock(&bible), &pack.message.passage_id);
    }
}

pub async fn set_memory_layout(bible: SharedBible) {
    let receiver = SetMemoryLayout::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let bible = lock(&bible);
        let now = now_epoch();
        let starts: Vec<usize> = r.line_starts.iter().map(|&i| usize::from(i)).collect();
        let section = match r.section_start {
            0 => Some(false),
            1 => Some(true),
            _ => None,
        };
        let result = bible
            .set_memory_line_starts(
                r.book,
                r.chapter,
                r.verse,
                (!r.default_lines).then_some(&starts[..]),
                now,
            )
            .and_then(|()| {
                bible.set_memory_section_start(r.book, r.chapter, r.verse, section, now)
            });
        match result {
            Ok(()) => {
                persist_browser_progress(&bible);
                send_layout(&bible, &r.passage_id);
            }
            Err(e) => debug_print!("set_memory_layout error: {e:?}"),
        }
    }
}

pub async fn reset_memory_layout(bible: SharedBible) {
    let receiver = ResetMemoryLayout::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let id = pack.message.passage_id;
        let bible = lock(&bible);
        match bible.reset_memory_layout(&id, now_epoch()) {
            Ok(()) => {
                persist_browser_progress(&bible);
                send_layout(&bible, &id);
            }
            Err(e) => debug_print!("reset_memory_layout error: {e:?}"),
        }
    }
}

pub async fn get_next_memory_card(bible: SharedBible) {
    let receiver = GetNextMemoryCard::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let bible = lock(&bible);
        match bible.next_memory_item(&r.passage_id, r.extra_new, now_epoch(), r.utc_offset) {
            Ok(item) => to_signal_item(item).send_signal_to_dart(),
            Err(e) => debug_print!("get_next_memory_card error: {e:?}"),
        }
    }
}

pub async fn get_memory_run(bible: SharedBible) {
    let receiver = GetMemoryRun::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.memory_run_card(&pack.message.passage_id) {
            Ok(card) => to_signal_item(card.map_or(
                core::MemoryItem::Done {
                    next_due_epoch: 0,
                    can_learn_more: false,
                },
                core::MemoryItem::Card,
            ))
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_memory_run error: {e:?}"),
        }
    }
}

pub async fn submit_memory_recital(bible: SharedBible) {
    let receiver = SubmitMemoryRecital::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let (Some(purpose), Some(grade)) = (
            MemoryPurpose::parse(&r.purpose),
            Grade::from_i64(i64::from(r.grade)),
        ) else {
            debug_print!("submit_memory_recital: bad purpose or grade {r:?}");
            continue;
        };
        let verses: Vec<MemoryVerseGrade> = r
            .chapters
            .iter()
            .zip(&r.verses)
            .zip(&r.grades)
            .filter_map(|((&chapter, &verse), &g)| {
                Some(MemoryVerseGrade {
                    chapter,
                    verse,
                    grade: Grade::from_i64(i64::from(g))?,
                })
            })
            .collect();
        let target = (r.target_verse > 0).then_some((r.target_chapter, r.target_verse));
        let bible = lock(&bible);
        match bible.submit_memory_recital(
            &r.passage_id,
            r.book,
            purpose,
            target,
            r.step as usize,
            grade,
            &verses,
            now_epoch(),
            r.utc_offset,
        ) {
            Ok(o) => {
                persist_browser_progress(&bible);
                MemoryReviewResult {
                    purpose: r.purpose,
                    target_chapter: r.target_chapter,
                    target_verse: r.target_verse,
                    xp: o.xp,
                    first_graduation: o.first_graduation,
                    section_completed: o.section_completed,
                    completed_passages: o.completed_passages,
                    relearn: o.relearn,
                    interval_days: o.interval_days,
                    total_xp: o.total_xp,
                    level_before: o.level_before,
                    level_after: o.level_after,
                    today_xp: o.today_xp,
                    daily_goal_xp: o.daily_goal_xp,
                    goal_reached_now: o.goal_reached_now,
                    streak_days: o.streak_days,
                }
                .send_signal_to_dart();
            }
            Err(e) => debug_print!("submit_memory_recital error: {e:?}"),
        }
    }
}

pub async fn get_memory_stats(bible: SharedBible) {
    let receiver = GetMemoryStats::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        send_stats(&lock(&bible), pack.message.utc_offset);
    }
}

pub async fn set_memory_settings(bible: SharedBible) {
    let receiver = SetMemorySettings::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let bible = lock(&bible);
        let settings = MemorySettings {
            new_per_day: r.new_per_day,
            daily_goal_xp: r.daily_goal_xp,
        };
        match bible.set_memory_settings(settings, now_epoch()) {
            Ok(_) => {
                persist_browser_progress(&bible);
                send_stats(&bible, r.utc_offset);
            }
            Err(e) => debug_print!("set_memory_settings error: {e:?}"),
        }
    }
}
