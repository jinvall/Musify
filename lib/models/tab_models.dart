/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

/// Internal representation of a guitar/bass/drum tab.
///
/// This is Musify's normalized format. Songsterr data is converted
/// into this representation so the rest of the app never depends
/// on Songsterr's raw format.
class Tab {
  const Tab({
    required this.song,
    required this.artist,
    required this.instrument,
    required this.tuning,
    this.capo,
    this.tempo,
    this.sections = const <String>[],
    this.measures = const <TabMeasure>[],
    this.chords = const <String>[],
    this.sourceUrl,
    this.songId,
    this.revisionId,
    this.trackId,
    this.rawNotation,
  });

  /// Song title.
  final String song;

  /// Artist name.
  final String artist;

  /// Instrument name (e.g. "Distortion Guitar", "Electric Bass", "Drums").
  final String instrument;

  /// Tuning as MIDI note numbers (lowest string first).
  /// Standard guitar = [64, 59, 55, 50, 45, 40]
  final List<int> tuning;

  /// Capo fret (null if no capo).
  final int? capo;

  /// Tempo in BPM (null if unknown).
  final int? tempo;

  /// Section labels encountered in this tab (intro, verse, chorus, solo...).
  final List<String> sections;

  /// Ordered measures in this tab.
  final List<TabMeasure> measures;

  /// Chord symbols for this tab (if available from the provider).
  final List<String> chords;

  /// Original Songsterr URL for attribution/deep-link.
  final String? sourceUrl;

  /// Songsterr song ID.
  final int? songId;

  /// Songsterr revision ID.
  final int? revisionId;

  /// Track/part ID within the revision.
  final int? trackId;

  /// Raw structured notation from the provider, if available.
  final Map<String, dynamic>? rawNotation;

  /// Compute measure timings from tempo if not explicitly provided.
  List<TabMeasure> get measuredMeasures {
    if (tempo == null || tempo! <= 0) return measures;
    final msPerBeat = 60000.0 / tempo!;
    return measures.map((m) {
      final startTime = m.startTime ??
          Duration(milliseconds: (msPerBeat * m.startBeat).round());
      final duration = m.duration ??
          Duration(milliseconds: (msPerBeat * m.beats).round());
      return m.copyWith(startTime: startTime, duration: duration);
    }).toList();
  }

  Tab copyWith({
    String? song,
    String? artist,
    String? instrument,
    List<int>? tuning,
    int? capo,
    int? tempo,
    List<String>? sections,
    List<TabMeasure>? measures,
    List<String>? chords,
    String? sourceUrl,
    int? songId,
    int? revisionId,
    int? trackId,
    Map<String, dynamic>? rawNotation,
  }) {
    return Tab(
      song: song ?? this.song,
      artist: artist ?? this.artist,
      instrument: instrument ?? this.instrument,
      tuning: tuning ?? this.tuning,
      capo: capo ?? this.capo,
      tempo: tempo ?? this.tempo,
      sections: sections ?? this.sections,
      measures: measures ?? this.measures,
      chords: chords ?? this.chords,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      songId: songId ?? this.songId,
      revisionId: revisionId ?? this.revisionId,
      trackId: trackId ?? this.trackId,
      rawNotation: rawNotation ?? this.rawNotation,
    );
  }

  /// Convert to JSON for disk cache.
  Map<String, dynamic> toJson() => {
        'song': song,
        'artist': artist,
        'instrument': instrument,
        'tuning': tuning,
        'capo': capo,
        'tempo': tempo,
        'sections': sections,
        'measures': measures.map((m) => m.toJson()).toList(),
        'chords': chords,
        'sourceUrl': sourceUrl,
        'songId': songId,
        'revisionId': revisionId,
        'trackId': trackId,
        'rawNotation': rawNotation,
      };

  /// Create from cached JSON.
  factory Tab.fromJson(Map<String, dynamic> json) {
    return Tab(
      song: json['song'] as String,
      artist: json['artist'] as String,
      instrument: json['instrument'] as String,
      tuning: List<int>.from(json['tuning'] as List),
      capo: json['capo'] as int?,
      tempo: json['tempo'] as int?,
      sections: (json['sections'] as List?)?.cast<String>() ?? const <String>[],
      measures: (json['measures'] as List?)
              ?.map((m) => TabMeasure.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const <TabMeasure>[],
      chords: (json['chords'] as List?)?.cast<String>() ?? const <String>[],
      sourceUrl: json['sourceUrl'] as String?,
      songId: json['songId'] as int?,
      revisionId: json['revisionId'] as int?,
      trackId: json['trackId'] as int?,
      rawNotation: json['rawNotation'] as Map<String, dynamic>?,
    );
  }
}

/// A single measure (bar) in a tab.
class TabMeasure {
  const TabMeasure({
    required this.lines,
    this.startBeat = 0,
    this.beats = 4,
    this.beatType = 4,
    this.isRepeatOpen = false,
    this.isRepeatClose = false,
    this.repeatCount = 0,
    this.sectionLabel,
    this.startTime,
    this.duration,
  });

  /// Rendered text lines for this measure (one per string).
  final List<String> lines;

  /// Start beat within the song (0-based global beat position).
  final int startBeat;

  /// Time signature numerator.
  final int beats;

  /// Time signature denominator.
  final int beatType;

  /// Whether this measure opens a repeat section.
  final bool isRepeatOpen;

  /// Whether this measure closes a repeat section.
  final bool isRepeatClose;

  /// Number of repeats (0 = default).
  final int repeatCount;

  /// Optional section label (intro, verse, chorus, solo...).
  final String? sectionLabel;

  /// Optional start time within the song (for playback sync).
  final Duration? startTime;

  /// Optional measure duration (for playback sync).
  final Duration? duration;

  TabMeasure copyWith({
    List<String>? lines,
    int? startBeat,
    int? beats,
    int? beatType,
    bool? isRepeatOpen,
    bool? isRepeatClose,
    int? repeatCount,
    String? sectionLabel,
    Duration? startTime,
    Duration? duration,
  }) {
    return TabMeasure(
      lines: lines ?? this.lines,
      startBeat: startBeat ?? this.startBeat,
      beats: beats ?? this.beats,
      beatType: beatType ?? this.beatType,
      isRepeatOpen: isRepeatOpen ?? this.isRepeatOpen,
      isRepeatClose: isRepeatClose ?? this.isRepeatClose,
      repeatCount: repeatCount ?? this.repeatCount,
      sectionLabel: sectionLabel ?? this.sectionLabel,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
    );
  }

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'startBeat': startBeat,
        'beats': beats,
        'beatType': beatType,
        'isRepeatOpen': isRepeatOpen,
        'isRepeatClose': isRepeatClose,
        'repeatCount': repeatCount,
        'sectionLabel': sectionLabel,
        'startTime': startTime?.inMilliseconds,
        'duration': duration?.inMilliseconds,
      };

  factory TabMeasure.fromJson(Map<String, dynamic> json) {
    return TabMeasure(
      lines: (json['lines'] as List?)?.cast<String>() ?? const <String>[],
      startBeat: json['startBeat'] as int? ?? 0,
      beats: json['beats'] as int? ?? 4,
      beatType: json['beatType'] as int? ?? 4,
      isRepeatOpen: json['isRepeatOpen'] as bool? ?? false,
      isRepeatClose: json['isRepeatClose'] as bool? ?? false,
      repeatCount: json['repeatCount'] as int? ?? 0,
      sectionLabel: json['sectionLabel'] as String?,
      startTime: json['startTime'] != null
          ? Duration(milliseconds: json['startTime'] as int)
          : null,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
    );
  }
}

/// Supported tab techniques.
enum TabTechnique {
  hammerOn('h'),
  pullOff('p'),
  slideUp('/'),
  slideDown('\\'),
  bend('b'),
  release('r'),
  vibrato('~'),
  mutedNote('x'),
  palmMute('PM'),
  tap('T'),
  harmonic('<>'),
  naturalHarmonic('N.H.'),
  artificialHarmonic('A.H.'),
  tremoloPicking('TP'),
  tremoloBar('TB'),
  arpeggioUp('^'),
  arpeggioDown('v'),
  upStroke('↑'),
  downStroke('↓');

  const TabTechnique(this.symbol);
  final String symbol;
}
