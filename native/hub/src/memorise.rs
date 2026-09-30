//! Handlers for learning passages by heart (see `haqor_core::memorise`).

use haqor_core::bible::Bible;
use haqor_core::memorise::{self as core, MemoryPurpose, MemorySettings, MemoryVerseGrade};
use haqor_core::tutor::Grade;
use rinf::{DartSignal, RustSignal};

use crate::functions::{SharedBible, lock, now_epoch, persist_browser_progress, send_failure};
use crate::signals::{
    DeleteMemoryPassage, GetMemoryLayout, GetMemoryPassages, GetMemoryRun, GetMemoryStats,
    GetNextMemoryCard, MemoryAchievement, MemoryCard, MemoryDay, MemoryItem, MemoryLayout,
    MemoryLayoutVerse, MemoryPassageEntry, MemoryPassages, MemoryReviewResult, MemorySegment,
    MemoryStats, MemoryVerseState, MemoryWord, SaveMemoryPassage, SetMemoryLayout,
    SetMemorySettings, SubmitMemoryRecital,
};

/// Days of history and forecast the dashboard graphs.
const HISTORY_DAYS: i64 = 30;
const FORECAST_DAYS: i64 = 14;

fn send_passages(bible: &Bible, saved_id: String, saved_nothing: bool) {
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
                    needs_shaping: s.needs_shaping,
                })
                .collect(),
            saved_id,
            saved_nothing,
        }
        .send_signal_to_dart(),
        Err(e) => send_failure("memory_passages", "", e),
    }
}

fn send_layout(bible: &Bible, passage_id: &str) {
    let book = match bible.memory_passage(passage_id) {
        Ok(p) => p.map_or(0, |p| p.book),
        Err(e) => {
            send_failure("memory_layout", passage_id, e);
            return;
        }
    };
    match bible.memory_layout(passage_id) {
        Ok(verses) => MemoryLayout {
            passage_id: passage_id.to_string(),
            book,
            verses: verses
                .into_iter()
                .map(|v| MemoryLayoutVerse {
                    chapter: v.chapter,
                    verse: v.verse,
                    words: v.words,
                    glosses: v.glosses,
                    line_starts: v
                        .line_starts
                        .into_iter()
                        .map(|i| i.min(255) as u8)
                        .collect(),
                    section_start: v.section_start,
                    shaped: v.shaped,
                    ready: v.ready,
                    needs_shaping: v.needs_shaping,
                })
                .collect(),
        }
        .send_signal_to_dart(),
        Err(e) => send_failure("memory_layout", passage_id, e),
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
            shape_passage_id: String::new(),
        },
        core::MemoryItem::Done {
            next_due_epoch,
            can_learn_more,
            shape_passage_id,
        } => MemoryItem {
            kind: "done".to_string(),
            card: None,
            next_due_epoch,
            can_learn_more,
            shape_passage_id,
        },
        core::MemoryItem::Empty => MemoryItem {
            kind: "empty".to_string(),
            card: None,
            next_due_epoch: 0,
            can_learn_more: false,
            shape_passage_id: String::new(),
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
        Err(e) => send_failure("memory_stats", "", e),
    }
}

pub async fn get_memory_passages(bible: SharedBible) {
    let receiver = GetMemoryPassages::get_dart_signal_receiver();
    while receiver.recv().await.is_some() {
        send_passages(&lock(&bible), String::new(), false);
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
                let saved_nothing = saved.is_none();
                send_passages(
                    &bible,
                    saved.map(|p| p.id).unwrap_or_default(),
                    saved_nothing,
                );
            }
            Err(e) => send_failure("memory_passages", "", e),
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
                send_passages(&bible, String::new(), false);
            }
            Err(e) => send_failure("memory_passages", "", e),
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
        let result = bible
            .set_memory_line_starts(
                r.book,
                r.chapter,
                r.verse,
                r.shaped.then_some(&starts[..]),
                now,
            )
            .and_then(|()| {
                bible.set_memory_section_start(r.book, r.chapter, r.verse, r.section_start, now)
            });
        match result {
            Ok(()) => {
                persist_browser_progress(&bible);
                send_layout(&bible, &r.passage_id);
            }
            Err(e) => send_failure("memory_layout", r.passage_id, e),
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
            Err(e) => send_failure("memory_item", r.passage_id, e),
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
                    shape_passage_id: String::new(),
                },
                core::MemoryItem::Card,
            ))
            .send_signal_to_dart(),
            Err(e) => send_failure("memory_item", pack.message.passage_id, e),
        }
    }
}

/// Check a recital before it touches any progress: a purpose or grade the core
/// does not know, per-verse lists of different lengths, or a per-verse grade
/// out of range rejects the whole recital rather than recording a part of it.
fn parse_recital(
    r: &SubmitMemoryRecital,
) -> Result<(MemoryPurpose, Grade, Vec<MemoryVerseGrade>), String> {
    let purpose = MemoryPurpose::parse(&r.purpose)
        .ok_or_else(|| format!("Unknown recital purpose {:?}.", r.purpose))?;
    let grade = Grade::from_i64(i64::from(r.grade))
        .ok_or_else(|| format!("Recital grade {} is out of range.", r.grade))?;
    if r.chapters.len() != r.verses.len() || r.verses.len() != r.grades.len() {
        return Err(format!(
            "Recital lists differ in length ({} chapters, {} verses, {} grades).",
            r.chapters.len(),
            r.verses.len(),
            r.grades.len()
        ));
    }
    let verses = r
        .chapters
        .iter()
        .zip(&r.verses)
        .zip(&r.grades)
        .map(|((&chapter, &verse), &g)| {
            Ok(MemoryVerseGrade {
                chapter,
                verse,
                grade: Grade::from_i64(i64::from(g)).ok_or_else(|| {
                    format!("Grade {g} for verse {chapter}:{verse} is out of range.")
                })?,
            })
        })
        .collect::<Result<_, String>>()?;
    Ok((purpose, grade, verses))
}

pub async fn submit_memory_recital(bible: SharedBible) {
    let receiver = SubmitMemoryRecital::get_dart_signal_receiver();
    while let Some(pack) = receiver.recv().await {
        let r = pack.message;
        let (purpose, grade, verses) = match parse_recital(&r) {
            Ok(parsed) => parsed,
            Err(e) => {
                send_failure("memory_recital", r.passage_id, e);
                continue;
            }
        };
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
            Err(e) => send_failure("memory_recital", r.passage_id, e),
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
            Err(e) => send_failure("memory_stats", "", e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn recital() -> SubmitMemoryRecital {
        SubmitMemoryRecital {
            passage_id: "p".to_string(),
            book: 27,
            purpose: "review".to_string(),
            target_chapter: 23,
            target_verse: 2,
            step: 0,
            grade: 2,
            chapters: vec![23, 23],
            verses: vec![1, 2],
            grades: vec![2, 3],
            utc_offset: 0,
        }
    }

    #[test]
    fn a_well_formed_recital_is_accepted_whole() {
        let (purpose, grade, verses) = parse_recital(&recital()).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(purpose, MemoryPurpose::Review);
        assert_eq!(grade, Grade::Good);
        assert_eq!(verses.len(), 2);
        assert_eq!(verses[1].verse, 2);
        assert_eq!(verses[1].grade, Grade::Easy);
    }

    #[test]
    fn a_bad_purpose_or_grade_rejects_the_recital() {
        let mut r = recital();
        r.purpose = "cram".to_string();
        assert!(parse_recital(&r).is_err());
        let mut r = recital();
        r.grade = 4;
        assert!(parse_recital(&r).is_err());
    }

    #[test]
    fn mismatched_lists_reject_the_recital_instead_of_truncating() {
        let mut r = recital();
        r.grades.pop();
        assert!(parse_recital(&r).is_err());
        let mut r = recital();
        r.chapters.push(23);
        assert!(parse_recital(&r).is_err());
    }

    #[test]
    fn an_out_of_range_verse_grade_rejects_the_recital_instead_of_dropping_it() {
        let mut r = recital();
        r.grades[0] = 9;
        assert!(parse_recital(&r).is_err());
    }
}
