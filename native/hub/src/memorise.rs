//! Handlers for learning passages by heart (see `haqor_core::memorise`).

use haqor_core::bible::Bible;
use haqor_core::memorise::{self as core, MemorySettings};
use haqor_core::tutor::Grade;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock, now_epoch, persist_browser_progress};
use crate::signals::{
    DeleteMemoryPassage, GetMemoryCard, GetMemoryPassages, GetMemoryStats, GetNextMemoryCard,
    MemoryAchievement, MemoryCard, MemoryDay, MemoryItem, MemoryPassageEntry, MemoryPassages,
    MemoryReviewResult, MemoryStats, MemoryVerseState, MemoryWord, SaveMemoryPassage,
    SetMemorySettings, SubmitMemoryReview,
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

fn to_signal_card(card: core::MemoryCard) -> MemoryCard {
    MemoryCard {
        passage_id: card.passage_id,
        book: card.book,
        chapter: card.chapter,
        verse: card.verse,
        stage: card.stage,
        words: card
            .words
            .into_iter()
            .map(|w| MemoryWord {
                text: w.text,
                hidden: w.hidden,
                hint: w.hint,
                gloss: w.gloss,
                translit: w.translit,
            })
            .collect(),
        cue: card.cue,
        translation: card.translation,
        is_new: card.is_new,
        is_review: card.is_review,
        position: card.position,
        total: card.total,
        due_remaining: card.due_remaining,
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

pub async fn get_memory_card(bible: SharedBible) {
    let receiver = GetMemoryCard::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let bible = lock(&bible);
        let stage = r.recall.then_some(core::STAGE_RECALL);
        match bible.memory_card(
            &r.passage_id,
            r.book,
            r.chapter,
            r.verse,
            stage,
            now_epoch(),
        ) {
            Ok(card) => to_signal_item(core::MemoryItem::Card(card)).send_signal_to_dart(),
            Err(e) => debug_print!("get_memory_card error: {e:?}"),
        }
    }
}

pub async fn submit_memory_review(bible: SharedBible) {
    let receiver = SubmitMemoryReview::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let Some(grade) = Grade::from_i64(i64::from(r.grade)) else {
            debug_print!("submit_memory_review: bad grade {}", r.grade);
            continue;
        };
        let bible = lock(&bible);
        match bible.submit_memory_review(
            &r.passage_id,
            r.book,
            r.chapter,
            r.verse,
            grade,
            r.run_through,
            now_epoch(),
            r.utc_offset,
        ) {
            Ok(o) => {
                persist_browser_progress(&bible);
                MemoryReviewResult {
                    book: r.book,
                    chapter: r.chapter,
                    verse: r.verse,
                    xp: o.xp,
                    stage_before: o.stage_before,
                    stage_after: o.stage_after,
                    interval_days: o.interval_days,
                    first_graduation: o.first_graduation,
                    completed_passages: o.completed_passages,
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
            Err(e) => debug_print!("submit_memory_review error: {e:?}"),
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
