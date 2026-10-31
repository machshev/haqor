import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/timeline_wheel.dart';

void main() {
  test('dense chronology spans stay separate and individually selectable', () {
    const timeline = StudyTimeline(
      id: 'chronology',
      title: 'Chronology',
      scale: TimelineScale.calendar,
    );
    const cycle = TimelineWheelCycle(
      start: 0,
      length: 7000,
      title: '7,000 years',
      segments: ['1', '2', '3', '4', '5', '6', '7'],
    );
    final entries = [
      for (var i = 0; i < 24; i++)
        StudyTimelineEntry(
          id: 'span-$i',
          title: 'Span $i',
          timelineId: timeline.id,
          start: const TimelineTime(100),
          end: const TimelineTime(2000),
        ),
    ];
    final marks = timelineWheelMarks(timeline, entries, 0, cycle: cycle);
    expect(marks, hasLength(entries.length));
    expect(marks.map((m) => m.radius).toSet(), hasLength(entries.length));
    for (final side in [320.0, 800.0]) {
      final size = Size.square(side);
      final layout = TimelineWheelLayout(
        timeline: timeline,
        year: 0,
        cycle: cycle,
        marks: marks,
        size: size,
        selectedId: marks.last.entry.id,
        faded: const {},
        theme: ThemeData(),
      );
      for (var i = 1; i < marks.length; i++) {
        final gap = (marks[i - 1].radius - marks[i].radius).abs() * side / 2;
        expect(
          (layout.spanStrokeWidth(marks[i - 1]) +
                  layout.spanStrokeWidth(marks[i])) /
              2,
          lessThan(gap),
        );
      }
      for (final mark in marks) {
        for (final turn in [0.0, 0.37]) {
          final point = timelineWheelPoint(
            size.center(Offset.zero),
            mark.radius * side / 2,
            (mark.from + mark.to) / 2,
            turn: turn,
          );
          expect(
            TimelineWheel.markAt(marks, size, point, turn: turn)?.entry.id,
            mark.entry.id,
          );
        }
      }
    }
  });
}
