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

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:musify/main.dart' show logger;
import 'package:musify/models/tab_models.dart';
import 'package:musify/services/tab_providers/tab_provider.dart';

/// Songsterr implementation of [TabProvider].
///
/// Uses Songsterr's public JSON API for search and metadata.
/// Tab notation data is fetched from the Songsterr page and parsed
/// from the embedded JSON state.
class SongsterrProvider implements TabProvider {
  static const _baseUrl = 'https://www.songsterr.com';
  static const _apiBase = '$_baseUrl/api';
  static const _searchEndpoint = '$_apiBase/songs';

  final http.Client _client;

  SongsterrProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_searchEndpoint?pattern=test&size=1'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    if (query.artist == null && query.title == null) return <TabSearchResult>[];
    final pattern = _buildSearchPattern(query.artist, query.title);
    if (pattern.isEmpty) return <TabSearchResult>[];

    try {
      final uri = Uri.parse('$_searchEndpoint?pattern=$pattern&size=20');
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        logger.log('Songsterr search failed: ${response.statusCode}');
        return <TabSearchResult>[];
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map(_fromSongsterrSong).toList();
    } catch (e, stackTrace) {
      logger.log('Songsterr search error', error: e, stackTrace: stackTrace);
      return <TabSearchResult>[];
    }
  }

  @override
  Future<TabSearchResult?> resolve(TabSearchQuery query) async {
    final results = await search(query);
    if (results.isEmpty) return null;

    // Filter by exact artist + title when possible.
    final exact = results.where((r) {
      final artistMatch = query.artist == null ||
          _normalize(r.artist) == _normalize(query.artist!);
      final titleMatch = query.title == null ||
          _normalize(r.title) == _normalize(query.title!);
      return artistMatch && titleMatch;
    }).toList();

    final pool = exact.isNotEmpty ? exact : results;

    // Prefer results that have a guitar track when querying for guitar.
    final instrument = query.instrument.toLowerCase();
    final withInstrument = pool.where((r) {
      if (r.instrument == null) return false;
      final inst = r.instrument!.toLowerCase();
      return inst.contains(instrument) ||
          (instrument == 'guitar' && (inst.contains('guitar') || inst.contains('ukulele'))) ||
          (instrument == 'bass' && inst.contains('bass')) ||
          (instrument == 'drums' && inst.contains('drums'));
    }).toList();

    final candidates = withInstrument.isNotEmpty ? withInstrument : pool;

    // Sort by views descending.
    candidates.sort((a, b) => (b.views ?? 0).compareTo(a.views ?? 0));
    return candidates.first;
  }

  @override
  Future<Tab?> getTab(TabSearchResult result) async {
    try {
      // Try to get revision ID from meta API if not present.
      final revisionId = result.revisionId ?? await _fetchLatestRevision(result.songId);
      if (revisionId == null) return null;

      // Fetch the Songsterr page and extract notation data.
      final tab = await _fetchTabFromPage(result.songId, revisionId, result);
      if (tab != null) return tab;

      // Fallback: return a metadata-only tab.
      return Tab(
        song: result.title,
        artist: result.artist,
        instrument: result.instrument ?? 'Unknown',
        tuning: result.tuning ?? _defaultTuningFor(result.instrument),
        capo: result.capo,
        tempo: result.tempo,
        sourceUrl: result.sourceUrl,
        songId: result.songId,
        revisionId: revisionId,
        trackId: result.trackId,
      );
    } catch (e, stackTrace) {
      logger.log('Songsterr getTab error', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<List<String>> getInstruments(TabSearchResult result) async {
    try {
      final uri = Uri.parse('$_apiBase/song/${result.songId}');
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return <String>[];

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> tracks = data['tracks'] as List<dynamic>? ?? <dynamic>[];
      final instruments = <String>{};
      for (final track in tracks) {
        final instrument = track['instrument'] as String?;
        if (instrument != null && instrument.isNotEmpty) {
          instruments.add(instrument);
        }
      }
      return instruments.toList()..sort();
    } catch (e) {
      return <String>[];
    }
  }

  Future<int?> _fetchLatestRevision(int songId) async {
    try {
      final uri = Uri.parse('$_apiBase/meta/$songId');
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      return data['revisionId'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<Tab?> _fetchTabFromPage(
    int songId,
    int revisionId,
    TabSearchResult result,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/a/wsa/${_slug(result.title)}-${_slug(result.artist)}-tab-s$songId');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15), onTimeout: () => http.Response('', 408));

      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final stateScript = document.querySelector('script#state');
      if (stateScript == null) return null;

      final stateText = stateScript.text;
      final stateStart = stateText.indexOf('{');
      final stateEnd = stateText.lastIndexOf('}');
      if (stateStart < 0 || stateEnd < 0) return null;

      final Map<String, dynamic> state =
          jsonDecode(stateText.substring(stateStart, stateEnd + 1)) as Map<String, dynamic>;

      // Extract part/notation data if present.
      final part = state['part'] as Map<String, dynamic>?;
      final lines = part?['lines'] as Map<String, dynamic>?;
      final lineList = lines?['lines'] as List<dynamic>?;

      if (lineList == null || lineList.isEmpty) return null;

      // Parse lines into ASCII measures.
      final measures = <TabMeasure>[];
      for (final line in lineList) {
        final lineMap = line as Map<String, dynamic>;
        final measure = TabMeasure(
          lines: (lineMap['lines'] as List<dynamic>?)
                  ?.map((l) => l.toString())
                  .toList() ??
              const <String>[],
          startBeat: lineMap['startBeat'] as int? ?? 0,
          beats: lineMap['beats'] as int? ?? 4,
          beatType: lineMap['beatType'] as int? ?? 4,
          isRepeatOpen: lineMap['isRepeatOpen'] as bool? ?? false,
          isRepeatClose: lineMap['isRepeatClose'] as bool? ?? false,
          repeatCount: lineMap['repeatCount'] as int? ?? 0,
        );
        measures.add(measure);
      }

      return Tab(
        song: result.title,
        artist: result.artist,
        instrument: result.instrument ?? 'Unknown',
        tuning: result.tuning ?? _defaultTuningFor(result.instrument),
        capo: result.capo,
        tempo: result.tempo,
        measures: measures,
        sourceUrl: result.sourceUrl ?? uri.toString(),
        songId: result.songId,
        revisionId: revisionId,
        trackId: result.trackId,
      );
    } catch (e, stackTrace) {
      logger.log('Songsterr page parse error', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  TabSearchResult _fromSongsterrSong(dynamic item) {
    final map = item as Map<String, dynamic>;
    final tracks = map['tracks'] as List<dynamic>? ?? <dynamic>[];
    final defaultTrackIndex = map['defaultTrack'] as int? ?? 0;
    final track = defaultTrackIndex < tracks.length
        ? tracks[defaultTrackIndex] as Map<String, dynamic>?
        : null;

    return TabSearchResult(
      songId: map['songId'] as int,
      artist: map['artist'] as String? ?? 'Unknown',
      title: map['title'] as String? ?? 'Unknown',
      revisionId: null,
      trackId: track?['partId'] as int?,
      instrument: track?['instrument'] as String?,
      tuning: track?['tuning'] != null
          ? List<int>.from(track!['tuning'] as List)
          : null,
      capo: null,
      tempo: null,
      difficulty: track?['difficulty'] as int?,
      views: track?['views'] as int?,
      sourceUrl: '$_baseUrl/a/wsa/${_slug(map['title'] as String? ?? '')}-${_slug(map['artist'] as String? ?? '')}-tab-s${map['songId']}',
      raw: map,
    );
  }

  static String _buildSearchPattern(String? artist, String? title) {
    final parts = <String>[];
    if (artist != null && artist.isNotEmpty) parts.add(artist);
    if (title != null && title.isNotEmpty) parts.add(title);
    return parts.join(' ').replaceAll(RegExp(r'\s+'), '+');
  }

  static String _normalize(String input) {
    return input.toLowerCase().trim().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _slug(String input) {
    var result = input.toLowerCase().trim();
    result = result.replaceAll(RegExp(r'[^\w\s-]'), '');
    result = result.replaceAll(RegExp(r'\s+'), '-');
    result = result.replaceAll(RegExp(r'-+'), '-');
    if (result.isNotEmpty && result.endsWith('-')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.isNotEmpty && result.startsWith('-')) {
      result = result.substring(1);
    }
    return result;
  }

  static List<int> _defaultTuningFor(String? instrument) {
    final inst = (instrument ?? '').toLowerCase();
    if (inst.contains('bass')) {
      return <int>[43, 38, 33, 28]; // Standard 4-string bass
    } else if (inst.contains('ukulele')) {
      return <int>[69, 64, 60, 67];
    }
    return <int>[64, 59, 55, 50, 45, 40]; // Standard guitar
  }
}
