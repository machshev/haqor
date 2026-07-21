// Copyright 2026 Haqor contributors. All rights reserved.
//
// The Bible Companion is a fixed annual schedule. This module intentionally
// contains no saved progress: it only returns the three readings for a date.

class ChristadelphianReading {
  const ChristadelphianReading({
    required this.reference,
    required this.bookIndex,
    required this.chapter,
    this.verse,
  });

  final String reference;
  final int bookIndex;
  final int chapter;
  final int? verse;
}

List<ChristadelphianReading> christadelphianReadingsFor(DateTime date) {
  final index = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(date.year, 1, 1)).inDays;
  // The Companion has no February 29 entry; leap day uses February 28.
  final day = date.month == 2 && date.day == 29
      ? 58
      : (DateTime(date.year, date.month, date.day).isLeapYear && date.month > 2
            ? index - 1
            : index.clamp(0, 364));
  return _readings[day];
}

extension on DateTime {
  bool get isLeapYear => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

// Book indexes in `kBooks`, followed by the first chapter of each portion.
// This compact table is the Bible Companion's fixed three-passage calendar.
// Ranges open at their first chapter; the reader's normal adjacent-chapter
// navigation makes the rest of the listed passage immediately available.
final _readings = _parseReadings();

List<List<ChristadelphianReading>> _parseReadings() {
  const bookIndexes = {
    'Genesis': 0,
    'Exodus': 1,
    'Lev.': 2,
    'Leviticus': 2,
    'Numbers': 3,
    'Deut.': 4,
    'Joshua': 5,
    'Judges': 6,
    '1 Samuel': 7,
    '2 Samuel': 8,
    '1 Kings': 9,
    '2 Kings': 10,
    'Isaiah': 11,
    'Jeremiah': 12,
    'Ezekiel': 13,
    'Hosea': 14,
    'Joel': 15,
    'Amos': 16,
    'Obadiah': 17,
    'Jonah': 18,
    'Micah': 19,
    'Nahum': 20,
    'Habak.': 21,
    'Zephan.': 22,
    'Haggai': 23,
    'Zechariah': 24,
    'Malachi': 25,
    'Psalms': 26,
    'Psalm': 26,
    'Proverbs': 27,
    'Job': 28,
    'Song': 29,
    'Ruth': 30,
    'Lament.': 31,
    'Eccl.': 32,
    'Esther': 33,
    'Daniel': 34,
    'Ezra': 35,
    'Nehem.': 36,
    '1 Chron.': 37,
    '2 Chron.': 38,
    'Matthew': 39,
    'Mark': 40,
    'Luke': 41,
    'John': 42,
    'Acts': 43,
    'Romans': 44,
    '1 Cor.': 45,
    '2 Cor.': 46,
    'Galatians': 47,
    'Ephes.': 48,
    'Philip.': 49,
    'Colossians': 50,
    '1 Thess.': 51,
    '2 Thess.': 52,
    '1 Tim.': 53,
    '2 Tim.': 54,
    'Titus': 55,
    'Philemon': 56,
    'Hebrews': 57,
    'James': 58,
    '1 Peter': 59,
    '2 Peter': 60,
    '1 John': 61,
    '2&3 John': 62,
    'Jude': 64,
    'Rev.': 65,
  };
  final names = bookIndexes.keys.toList()..sort((a, b) => b.length - a.length);
  final currentBook = List<String?>.filled(3, null);
  return [
    for (final row in _companionData.trim().split('\n'))
      [
        for (var column = 0; column < 3; column++)
          () {
            var value = row.split('\t')[column + 1].trim();
            final name = names
                .where((name) => value.startsWith(name))
                .firstOrNull;
            if (name != null) {
              currentBook[column] = name;
              value = value.substring(name.length).trim();
            }
            final book = currentBook[column]!;
            final start = RegExp(r'(\d+)(?:v(\d+))?').firstMatch(value);
            final chapter = int.parse(start?.group(1) ?? '1');
            return ChristadelphianReading(
              reference: '$book ${value.replaceAll('v', ':')}',
              bookIndex: bookIndexes[book]!,
              chapter: chapter,
              verse: start?.group(2) == null
                  ? null
                  : int.parse(start!.group(2)!),
            );
          }(),
      ],
  ];
}

const _companionData = r'''
January	Genesis 1, 2	Psalms 1, 2	Matthew 1, 2
January	 3, 4	 3 - 5	 3, 4
January	 5, 6	6 - 8	 5
January	 7, 8	 9,10	 6
January	 9,10	 11-13	 7
January	 11,12	 14-16	 8
January	 13,14	 17	 9
January	 15,16	 18	 10
January	 17,18	 19-21	 11
January	 19	 22	 12
January	 20,21	 23-25	 13
January	 22,23	 26-28	 14
January	 24	 29,30	 15
January	 25,26	 31	 16
January	 27	 32	 17
January	 28,29	 33	 18
January	 30	 34	 19
January	 31	 35	 20
January	 32,33	 36	 21
January	 34,35	 37	 22
January	 36	 38	 23
January	 37	 39,40	 24
January	 38	 41-43	 25
January	 39,40	 44	 26
January	 41	 45	 27
January	 42,43	 46-48	 28
January	 44,45	 49	 Romans 1, 2
January	 46,47	 50	 3, 4
January	 48,50	 51,52	 5, 6
January	 Exodus 1, 2	 53-55	 7, 8
January	 3, 4	 56,57	 9
February	Exodus 5,6	Psalm 58,59	Romans 10,11
February	 7,8	 60,61	 12
February	 9	 62,63	 13,14
February	 10	 64,65	 15,16
February	 11,12	 66,67	 Mark 1
February	 13,14	 68	 2
February	 15	 69	 3
February	 16	 70,71	 4
February	 17,18	 72	 5
February	 19,20	 73	 6
February	 21	 74	 7
February	 22	 75,76	 8
February	 23	 77	 9
February	 24,25	 78	 10
February	 26	 79,80	 11
February	 27	 81,82	 12
February	 28	 83,84	 13
February	 29	 85,86	 14
February	 30	 87,88	 15,16
February	 31,32	 89	 1 Cor. 1,2
February	 33,34	 90,91	 3
February	 35	 92,93	 4,5
February	 36	 94,95	 6
February	 37	 96-99	 7
February	 38	 100,101	 8,9
February	 39,40	 102	 10
February	Lev. 1,2	 103	 11
February	 3,4	 104	 12,13 
March	Lev. 5,6	Psalms 105	1 Cor. 14
March	 7	 106	 15
March	 8	 107	 16
March	 9,10	 108,109	 2 Cor. 1,2
March	 11	 110-112	 3,4
March	 12,13	 113,114	 5,6,7
March	 14	 115,116	 8,9
March	 15	 117,118	 10,11
March	 16	 119v1-40	 12,13
March	 17,18	 119v41-80	 Luke 1
March	 19	119v81-128	 2
March	 20	119v129-176	 3
March	 21	 120-124	 4
March	 22	 125-127	 5
March	 23	 128-130	 6
March	 24	 131-134	 7
March	 25	 135,136	 8
March	 26	 137-139	 9
March	 27	 140-142	 10
March	 Numbers 1	 143-144	 11
March	 2	 145-147	 12
March	 3	 148-150	 13,14
March	 4	 Proverbs 1	 15
March	 5	 2	 16
March	 6	 3	 17
March	 7	 4	 18
March	 8,9	 5	 19
March	 10	 6	 20
March	 11	 7	 21
March	 12,13	 8,9	 22
March	 14	 10	 23
April	Numbers 15	Proverbs 11	Luke 24
April	 16	 12	Galatians 1,2
April	 17,18	 13	3,4
April	 19	 14	 5,6
April	 20,21	 15	Ephes. 1,2
April	 22,23	 16	 3,4
April	 24,25	 17	 5,6
April	 26	 18	Philip. 1,2
April	 27	 19	 3,4
April	 28	 20	 John 1
April	 29,30	 21	 2,3
April	 31	 22	 4
April	 32	 23	 5
April	 33	 24	 6
April	 34	 25	 7
April	 35	 26	 8
April	 36	 27	 9,10
April	 Deut. 1	 28	 11
April	 2	 29	 12
April	 3	 30	 13,14
April	 4	 31	 15,16
April	 5	 Eccl. 1	 17,18
April	 6,7	 2	 19
April	 8,9	 3	 20,21
April	 10,11	 4	 Acts 1
April	 12	 5	 2
April	 13,14	 6	 3,4
April	 15	 7	 5,6
April	 16	 8	 7
April	 17	 9	 8
May	Deut. 18	Eccl. 10	Acts 9
May	 19	 11	 10
May	 20	 12	 11,12
May	 21	 Song 1	 13
May	 22	 2	 14,15
May	 23	 3	 16,17
May	 24	 4	 18,19
May	 25	 5	 20
May	 26	 6	 21,22
May	 27	 7	 23,24
May	 28	 8	 25,26
May	 29	Isaiah 1	 27
May	 30	 2	 28
May	 31	 3,4	Colossians 1
May	 32	 5	 2
May	 33,34	 6	 3,4
May	 Joshua 1	 7	1 Thess. 1,2
May	 2	 8	 3,4
May	 3,4	 9	 5
May	 5,6	 10	2 Thess. 1,2
May	 7	 11	 3
May	 8	 12	 1 Tim. 1,2,3
May	 9	 13	 4,5
May	 10	 14	 6
May	 11	 15	 2 Tim. 1
May	 12	 16	 2
May	 13	 17,18	 3,4
May	 14	 19	Titus 1,2,3
May	 15	 20,21	Philemon
May	 16	 22	Hebrews 1,2
May	 17	 23	 3,4,5
June	Joshua 18	Isaiah 24	Hebrews 6,7
June	 19	 25	 8, 9
June	 20,21	 26,27	 10
June	 22	 28	 11
June	 23,24	 29	 12
June	 Judges 1	 30	 13
June	 2,3	 31	 James 1
June	 4,5	 32	 2
June	 6	 33	 3,4
June	 7,8	 34	 5
June	 9	 35	 1 Peter 1
June	 10,11	 36	 2
June	 12,13	 37	 3,4,5
June	 14,15	 38	2 Peter 1,2
June	 16	 39	 3
June	 17,18	 40	1 John 1,2
June	 19	 41	 3,4
June	 20	 42	 5
June	 21	 43	2&amp;3 John
June	 Ruth 1,2	 44	 Jude
June	 3,4	 45	Rev. 1,2
June	1 Samuel 1	 46,47	 3,4
June	 2	 48	 5,6
June	 3	 49	 7,8,9
June	 4	 50	 10,11
June	 5,6	 51	 12,13
June	 7,8	 52	 14
June	 9	 53	 15,16
June	 10	 54	 17,18
June	 11,12	 55	 19,20
July	1 Samuel 13	Isaiah 56,57	Rev. 21,22
July	 14	 58	Matthew 1,2
July	 15	 59	 3,4
July	 16	 60	 5
July	 17	 61	 6
July	 18	 62	 7
July	 19	 63	 8
July	 20	 64	 9
July	 21,22	 65	 10
July	 23	 66	 11
July	 24	Jeremiah 1	 12
July	 25	 2	 13
July	 26,27	 3	 14
July	 28	 4	 15
July	 29,30	 5	 16
July	 31	 6	 17
July	2 Samuel 1	 7	 18
July	 2	 8	 19
July	 3	 9	 20
July	 4,5	 10	 21
July	 6	 11	 22
July	 7	 12	 23
July	 8,9	 13	 24
July	 10	 14	 25
July	 11	 15	 26
July	 12	 16	 27
July	 13	 17	 28
July	 14	 18	Romans 1, 2
July	 15	 19	 3,4
July	 16	 20	 5,6
July	 17	 21	 7,8
August	2 Samuel 18	Jeremiah 22	Romans 9
August	 19	 23	 10,11
August	 20,21	 24	 12
August	 22	 25	 13,14
August	 23	 26	 15,16
August	 24	 27	Mark 1
August	1 Kings 1	 28	 2
August	 2	 29	 3
August	 3	 30	 4
August	 4, 5	 31	 5
August	 6	 32	 6
August	 7	 33	 7
August	 8	 34	 8
August	 9	 35	 9
August	 10	 36	 10
August	 11	 37	 11
August	 12	 38	 12
August	 13	 39	 13
August	 14	 40	 14
August	 15	 41	 15
August	 16	 42	 16
August	 17	 43	 1 Cor. 1,2
August	 18	 44	 3
August	 19	 45,46	 4,5
August	 20	 47	 6
August	 21	 48	 7
August	 22	 49	 8,9
August	2 Kings 1,2	 50	 10
August	 3	 51	 11
August	 4	 52	 12,13
August	 5	Lament. 1	 14
September	2 Kings 6	Lament. 2	1 Cor. 15
September	 7	 3	 16
September	 8	 4	2 Cor. 1,2
September	 9	 5	 3,4
September	 10	Ezekiel 1	 5,6,7
September	 11,12	 2	 8,9
September	 13	 3	 10,11
September	 14	 4	 12,13
September	 15	 5	 Luke 1
September	 16	 6	 2
September	 17	 7	 3
September	 18	 8	 4
September	 19	 9	 5
September	 20	 10	 6
September	 21	 11	 7
September	 22,23	 12	 8
September	 24,25	 13	 9
September	1 Chron. 1	 14	 10
September	 2	 15	 11
September	 3	 16	 12
September	 4	 17	 13,14
September	 5	 18	 15
September	 6	 19	 16
September	 7	 20	 17
September	 8	 21	 18
September	 9	 22	 19
September	 10	 23	 20
September	 11	 24	 21
September	 12	 25	 22
September	 13,14	 26	 23
October	1 Chron. 15	Ezekiel 27	Luke 24
October	 16	 28	Galatians 1,2
October	 17	 29	 3,4
October	 18,19	 30	 5,6
October	 20,21	 31	Ephes. 1,2
October	 22	 32	 3,4
October	 23	 33	 5,6
October	 24,25	 34	Philip. 1,2
October	 26	 35	 3,4
October	 27	 36	John 1
October	 28	 37	 2,3
October	 29	 38	 4
October	2 Chron. 1,2	 39	 5
October	 3,4	 40	 6
October	 5,6	 41	 7
October	 7	 42	 8
October	 8	 43	 9,10
October	 9	 44	 11
October	 10,11	 45	 12
October	 12,13	 46	 13,14
October	 14,15	 47	 15,16
October	 16,17	 48	 17,18
October	 18,19	Daniel 1	 19
October	 20	 2	 20,21
October	 21,22	 3	Acts 1
October	 23	 4	 2
October	 24	 5	 3,4
October	 25	 6	 5,6
October	 26,27	 7	 7
October	 28	 8	 8
October	 29	 9	 9
November	2 Chron. 30	Daniel 10	Acts 10
November	 31	 11	 11,12
November	 32	 12	 13 
November	 33	Hosea 1	 14,15
November	 34	 2	 16,17
November	 35	 3	 18,19
November	 36	 4	 20
November	Ezra 1,2	 5	 21,22
November	 3,4	 6	 23,24
November	 5,6	 7	 25,26
November	 7	 8	 27
November	 8	 9	 28
November	 9	 10	Colossians 1
November	 10	 11	 2
November	Nehem. 1,2	 12	 3,4
November	 3	 13	1 Thess. 1,2
November	 4	 14	 3,4
November	 5,6	 Joel 1	 5
November	 7	 2	2 Thess. 1,2
November	 8	 3	 3
November	 9	 Amos 1	1 Tim. 1,2,3
November	 10	 2	 4,5
November	 11	 3	 6
November	 12	 4	2 Tim. 1
November	 13	 5	 2
November	 Esther 1	 6	 3,4
November	 2	 7	Titus 1,2,3
November	 3,4	 8	Philemon
November	 5,6	 9	Hebrews 1,2
November	 7,8	 Obadiah	 3,4,5
December	Esther 9,10	Jonah 1	Hebrews 6,7
December	Job 1,2	 2,3	 8,9
December	 3,4	 4	 10
December	 5	Micah 1	 11
December	 6,7	 2	 12
December	 8	 3,4	 13
December	 9	 5	James 1
December	 10	 6	 2
December	 11	 7	 3,4
December	 12	Nahum 1,2	 5
December	 13	 3	1 Peter 1
December	 14	Habak. 1	 2
December	 15	 2	 3,4,5
December	 16,17	 3	2 Peter 1,2
December	 18,19	Zephan. 1	 3
December	 20	 2	1 John 1,2
December	 21	 3	 3,4
December	 22	Haggai 1,2	 5
December	 23,24	Zechariah 1	2&3 John
December	 25,26,27	 2,3	 Jude
December	 28	 4,5	Rev. 1,2
December	 29,30	 6,7	 3,4
December	 31,32	 8	 5,6
December	 33	 9	 7,8,9
December	 34	 10	 10,11
December	 35,36	 11	 12,13
December	 37	 12	 14
December	 38	 13,14	 15,16
December	 39	Malachi 1	 17,18
December	 40	 2	 19,20
December	 41,42	 3,4	 21,22
''';
