/// Versions and source credits shown in the About view.
///
/// [appVersion] mirrors `pubspec.yaml`; `test/app_info_test.dart` fails if the
/// two drift apart, so there is no runtime plugin dependency just to read the
/// bundle version.
///
/// The database version is not here: it is the databases' own build timestamp,
/// read from the asset bundle by `db_version.dart`, so nothing about it has to
/// be maintained by hand.
library;

const appVersion = '0.7.11+12';

/// One credited data source. [licence] is the terms under which Haqor
/// redistributes it; [note] adds anything a reader should know beyond that.
class DataSourceCredit {
  const DataSourceCredit({
    required this.title,
    required this.description,
    required this.licence,
    this.url,
    this.note,
  });

  final String title;
  final String description;
  final String licence;
  final String? url;
  final String? note;
}

/// Attribution for the bundled data. Mirrors the Attribution section of both
/// projects' README files; several of these sources require the credit, so
/// entries are removed only when the underlying data stops shipping.
const dataSourceCredits = <DataSourceCredit>[
  DataSourceCredit(
    title: 'Unicode/XML Leningrad Codex',
    description:
        'The Hebrew Bible text, transcribed from the Westminster Leningrad '
        'Codex.',
    licence: 'Public domain',
    url: 'https://tanach.us',
  ),
  DataSourceCredit(
    title: 'Open Scriptures Hebrew Bible',
    description: 'Lemmas and morphology for the Hebrew Bible.',
    licence: 'CC BY 4.0',
    url: 'https://github.com/openscriptures/morphhb',
  ),
  DataSourceCredit(
    title: 'OSHB Hebrew Lexicon',
    description:
        "Brown-Driver-Briggs, Strong's Hebrew Dictionary, and the lexical "
        'index bridging them. Haqor\'s lexicon is an edited and expanded '
        'derivative of these entries.',
    licence:
        'CC BY 4.0 — credit the Open Scriptures Hebrew Bible Project. '
        "The underlying BDB and Strong's text is public domain.",
    url: 'https://github.com/openscriptures/HebrewLexicon',
  ),
  DataSourceCredit(
    title: 'STEP Bible TAHOT',
    description: 'Context-sensitive interlinear translations.',
    licence: 'CC BY 4.0',
    url: 'https://github.com/STEPBible/STEPBible-Data',
  ),
  DataSourceCredit(
    title: 'SEDRA',
    description:
        'Syriac lexical and morphological data, with the New Testament text '
        "of the British and Foreign Bible Society's edition.",
    licence:
        'Used with the acknowledgement below, in the form SEDRA III asks for, '
        "citing G. Kiraz, 'Automatic Concordance Generation of Syriac Texts', "
        'in VI Symposium Syriacum 1992, ed. R. Lavenant, Orientalia Christiana '
        'Analecta 247, Rome, 1994.',
    note:
        'This work makes use of the Syriac Electronic Data Retrieval Archive '
        '(SEDRA) by George A. Kiraz, distributed by the Syriac Computing '
        'Institute.',
  ),
];
