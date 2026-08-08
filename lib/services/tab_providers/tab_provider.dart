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

import 'package:musify/models/tab_models.dart';

/// Abstract tab provider.
///
/// Implementations hide the details of where tab data comes from
/// (Songsterr, Ultimate Guitar, local cache, etc.).
abstract class TabProvider {
  /// Search for tracks matching the given query.
  Future<List<TabSearchResult>> search(TabSearchQuery query);

  /// Resolve the best match for a given query.
  Future<TabSearchResult?> resolve(TabSearchQuery query);

  /// Fetch the full tab for a previously resolved/search result.
  Future<Tab?> getTab(TabSearchResult result);

  /// List available instruments for a given search result.
  Future<List<String>> getInstruments(TabSearchResult result);

  /// Whether this provider is currently reachable.
  Future<bool> isAvailable();
}

/// A lightweight search result returned by [TabProvider.search].
class TabSearchResult {
  const TabSearchResult({
    required this.songId,
    required this.artist,
    required this.title,
    this.revisionId,
    this.trackId,
    this.instrument,
    this.tuning,
    this.capo,
    this.tempo,
    this.difficulty,
    this.views,
    this.sourceUrl,
    this.image,
    this.raw,
  });

  final int songId;
  final String artist;
  final String title;
  final int? revisionId;
  final int? trackId;
  final String? instrument;
  final List<int>? tuning;
  final int? capo;
  final int? tempo;
  final int? difficulty;
  final int? views;
  final String? sourceUrl;
  final String? image;
  final Map<String, dynamic>? raw;

  String get displayTitle => title;
  String get displayArtist => artist;

  TabSearchResult copyWith({
    int? songId,
    String? artist,
    String? title,
    int? revisionId,
    int? trackId,
    String? instrument,
    List<int>? tuning,
    int? capo,
    int? tempo,
    int? difficulty,
    int? views,
    String? sourceUrl,
    String? image,
    Map<String, dynamic>? raw,
  }) {
    return TabSearchResult(
      songId: songId ?? this.songId,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      revisionId: revisionId ?? this.revisionId,
      trackId: trackId ?? this.trackId,
      instrument: instrument ?? this.instrument,
      tuning: tuning ?? this.tuning,
      capo: capo ?? this.capo,
      tempo: tempo ?? this.tempo,
      difficulty: difficulty ?? this.difficulty,
      views: views ?? this.views,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      image: image ?? this.image,
      raw: raw ?? this.raw,
    );
  }
}

/// Query used to search/resolve a tab.
class TabSearchQuery {
  const TabSearchQuery({
    this.artist,
    this.title,
    this.album,
    this.duration,
    this.musicBrainzRecordingId,
    this.isrc,
    this.ytid,
    this.instrument = 'guitar',
    this.revisionId,
  });

  final String? artist;
  final String? title;
  final String? album;
  final int? duration;
  final String? musicBrainzRecordingId;
  final String? isrc;
  final String? ytid;
  final String instrument;
  final int? revisionId;

  /// Generate a cache key from stable identifiers.
  String get cacheKey {
    final parts = <String>[];
    if (isrc != null && isrc!.isNotEmpty) parts.add('isrc:$isrc');
    if (musicBrainzRecordingId != null && musicBrainzRecordingId!.isNotEmpty) {
      parts.add('mbid:$musicBrainzRecordingId');
    }
    if (ytid != null && ytid!.isNotEmpty) parts.add('ytid:$ytid');
    if (parts.isEmpty && artist != null && title != null) {
      final a = _normalize(artist!);
      final t = _normalize(title!);
      parts.add('query:${a}_$t');
    }
    if (parts.isEmpty) {
      parts.add('fallback:${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    }
    if (revisionId != null) {
      parts.add('rev:$revisionId');
    }
    return parts.join('|');
  }

  static String _normalize(String input) {
    var result = input.toLowerCase().trim();
    result = result.replaceAll(RegExp(r'[^\w\s]'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result;
  }

  TabSearchQuery copyWith({
    String? artist,
    String? title,
    String? album,
    int? duration,
    String? musicBrainzRecordingId,
    String? isrc,
    String? ytid,
    String? instrument,
    int? revisionId,
  }) {
    return TabSearchQuery(
      artist: artist ?? this.artist,
      title: title ?? this.title,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      musicBrainzRecordingId: musicBrainzRecordingId ?? this.musicBrainzRecordingId,
      isrc: isrc ?? this.isrc,
      ytid: ytid ?? this.ytid,
      instrument: instrument ?? this.instrument,
      revisionId: revisionId ?? this.revisionId,
    );
  }
}
