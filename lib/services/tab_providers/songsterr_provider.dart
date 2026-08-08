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
import 'dart:io';

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

  /// Verified current Songsterr structured tab CDN endpoints.
  static const _cdnBases = <String>[
    'https://dqsljvtekg760.cloudfront.net',
    'https://d3d3l6a6rcgkaf.cloudfront.net',
  ];

  final http.Client _client;

  SongsterrProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_searchEndpoint?pattern=test&size=1'))
          .timeout(const Duration(seconds: 10));
      logger.log('Songsterr availability check: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      logger.log('Songsterr availability check failed', error: e);
      return false;
    }
  }

  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    if (query.artist == null && query.title == null) return <TabSearchResult>[];
    final pattern = _buildSearchPattern(query.artist, query.title);
    if (pattern.isEmpty) return <TabSearchResult>[];

    try {
      final uri = Uri.https(
        'www.songsterr.com',
        '/api/songs',
        <String, String>{'pattern': pattern, 'size': '20'},
      );
      logger.log('Songsterr search: $uri');
      final response = await _client
          .get(uri, headers: const <String, String>{'User-Agent': 'Musify/1.0'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        logger.log('Songsterr search failed: ${response.statusCode}');
        return <TabSearchResult>[];
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      logger.log('Songsterr search results: ${data.length}');
      return data.map((item) => _fromSongsterrSong(item as Map<String, dynamic>, query.instrument)).toList();
    } catch (e, stackTrace) {
      logger.log('Songsterr search error', error: e, stackTrace: stackTrace);
      return <TabSearchResult>[];
    }
  }

  @override
  Future<TabSearchResult?> resolve(TabSearchQuery query) async {
    final results = await search(query);
    logger.log('Songsterr resolve: ${results.length} results');
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
    logger.log('Songsterr resolve: ${pool.length} candidates after filter');

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
    logger.log('Songsterr resolve: ${candidates.length} candidates after instrument filter');

    // Sort by views descending.
    candidates.sort((a, b) => (b.views ?? 0).compareTo(a.views ?? 0));
    final selected = candidates.first;
    logger.log('Songsterr resolve selected: ${selected.artist} - ${selected.title} (trackId: ${selected.trackId})');
    return selected;
  }

  @override
  Future<Tab?> getTab(TabSearchResult result) async {
    try {
      logger.log('Songsterr getTab: songId=${result.songId}, instrument=${result.instrument}');
      
      // Fetch meta to get revision, image, and track list.
      final meta = await _fetchMeta(result.songId);
      if (meta == null) {
        logger.log('Songsterr getTab: meta fetch failed');
        return null;
      }

      final revisionId = meta['revisionId'] as int?;
      if (revisionId == null) {
        logger.log('Songsterr getTab: no revisionId in meta');
        return null;
      }

      final image = meta['image'] as String?;
      if (image == null) {
        logger.log('Songsterr getTab: no image in meta');
        return null;
      }

      logger.log('Songsterr getTab: revisionId=$revisionId, image=$image');

      // Select the best matching track from meta.
      final tracks = meta['tracks'] as List<dynamic>? ?? <dynamic>[];
      if (tracks.isEmpty) {
        logger.log('Songsterr getTab: no tracks in meta');
        return null;
      }

      final selectedTrack = _selectTrackFromMeta(tracks, result.instrument);
      if (selectedTrack == null) {
        logger.log('Songsterr getTab: no matching track found');
        return null;
      }

      // The CDN path uses the track index within the tracks array.
      final trackIndex = tracks.indexOf(selectedTrack);
      if (trackIndex < 0) {
        logger.log('Songsterr getTab: selected track not in tracks array');
        return null;
      }

      logger.log('Songsterr getTab: selected track index=$trackIndex, instrument=${selectedTrack['instrument']}');

      // Build updated result with resolved identifiers.
      final updatedResult = result.copyWith(
        trackId: trackIndex,
        instrument: selectedTrack['instrument'] as String? ?? result.instrument,
        tuning: selectedTrack['tuning'] != null ? List<int>.from(selectedTrack['tuning'] as List) : result.tuning,
        capo: selectedTrack['capo'] as int? ?? result.capo,
        tempo: selectedTrack['tempo'] as int? ?? result.tempo,
        image: image,
      );

      // Fetch structured tab data from CDN.
      final tab = await _fetchTabFromCdn(result.songId, revisionId, image, updatedResult);
      if (tab != null) {
        logger.log('Songsterr getTab: CDN fetch succeeded, measures=${tab.measures.length}');
        return tab;
      }

      logger.log('Songsterr getTab: CDN fetch failed, returning metadata-only tab');
      // Fallback: return a metadata-only tab.
      return Tab(
        song: result.title,
        artist: result.artist,
        instrument: updatedResult.instrument ?? 'Unknown',
        tuning: updatedResult.tuning ?? _defaultTuningFor(updatedResult.instrument),
        capo: updatedResult.capo,
        tempo: updatedResult.tempo,
        sourceUrl: result.sourceUrl,
        songId: result.songId,
        revisionId: revisionId,
        trackId: updatedResult.trackId,
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

  Future<Map<String, dynamic>?> _fetchMeta(int songId) async {
    try {
      final uri = Uri.parse('$_apiBase/meta/$songId?allowOwnUnpublished=true');
      logger.log('Songsterr meta: fetching $uri');
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      logger.log('Songsterr meta: status ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      logger.log('Songsterr meta: revisionId=${data['revisionId']}, image=${data['image']}, tracks=${(data['tracks'] as List?)?.length}');
      return data;
    } catch (e) {
      logger.log('Songsterr meta error', error: e);
      return null;
    }
  }

  Future<Tab?> _fetchTabFromCdn(
    int songId,
    int revisionId,
    String image,
    TabSearchResult result,
  ) async {
    try {
      final trackId = result.trackId;
      if (trackId == null) {
        logger.log('Songsterr CDN: no trackId');
        return null;
      }

      // Try known CDN bases; stop on first successful structured JSON response.
      for (final cdnBase in _cdnBases) {
        final uri = Uri.parse('$cdnBase/$songId/$revisionId/$image/$trackId.json');
        logger.log('Songsterr CDN trying: $uri');
        final response = await _client
            .get(uri, headers: const <String, String>{'Accept-Encoding': 'gzip'})
            .timeout(const Duration(seconds: 15), onTimeout: () => http.Response('', 408));

        logger.log('Songsterr CDN response: ${response.statusCode}, length=${response.body.length}');
        if (response.statusCode != 200) continue;
        if (response.body.isEmpty) continue;

        // Defensive parse: accept gzip-compressed JSON or plain JSON.
        dynamic raw;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            raw = decoded;
          }
        } on FormatException {
          // Response may be compressed despite headers; try gzip decode.
          try {
            final gzipped = gzip.decode(response.bodyBytes);
            final decoded = jsonDecode(utf8.decode(gzipped));
            if (decoded is Map<String, dynamic>) raw = decoded;
          } on Exception {
            continue;
          }
        }

        if (raw == null) continue;
        final map = raw as Map<String, dynamic>;

        // Validate minimal structure.
        if (map['songId'] == null || map['revisionId'] == null || map['measures'] == null) {
          logger.log('Songsterr CDN: invalid structure, missing required fields');
          continue;
        }

        return _parseStructuredTab(map, result);
      }

      logger.log('Songsterr CDN: all CDN bases failed');
      return null;
    } catch (e, stackTrace) {
      logger.log('Songsterr CDN tab fetch error', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Tab?> _parseStructuredTab(
    Map<String, dynamic> map,
    TabSearchResult result,
  ) async {
    try {
      logger.log('Songsterr parser: starting parse, measures=${(map['measures'] as List?)?.length}');
      final measures = <TabMeasure>[];
      final rawMeasures = map['measures'] as List<dynamic>? ?? <dynamic>[];
      for (final rawMeasure in rawMeasures) {
        final measureMap = rawMeasure as Map<String, dynamic>;
        final voices = measureMap['voices'] as List<dynamic>? ?? <dynamic>[];
        final lines = <String>[];
        
        for (final voice in voices) {
          final voiceMap = voice as Map<String, dynamic>;
          final beats = voiceMap['beats'] as List<dynamic>? ?? <dynamic>[];
          
          for (final beat in beats) {
            final beatMap = beat as Map<String, dynamic>;
            final notes = beatMap['notes'] as List<dynamic>? ?? <dynamic>[];
            final chord = beatMap['chord'] as Map<String, dynamic>?;
            final isRest = beatMap['rest'] as bool? ?? false;
            
            if (isRest) {
              lines.add('-' * 30);
              continue;
            }
            
            if (chord != null && chord['text'] != null) {
              lines.add(' ' * 10 + (chord['text'] as String));
            }
            
            for (final note in notes) {
              final noteMap = note as Map<String, dynamic>;
              final fret = noteMap['fret'] as int? ?? -1;
              final string = noteMap['string'] as int? ?? 0;
              final lineIndex = (map['strings'] as int? ?? 6) - 1 - string;
              while (lines.length <= lineIndex) {
                lines.add('');
              }
              final line = lines[lineIndex];
              final fretStr = fret >= 0 ? fret.toString() : '-';
              lines[lineIndex] = line + fretStr;
            }
          }
        }
        
        measures.add(TabMeasure(
          lines: lines,
          startBeat: 0,
          beats: (measureMap['signature'] as List<dynamic>?)?.first as int? ?? 4,
          beatType: (measureMap['signature'] as List<dynamic>?)?.last as int? ?? 4,
          sectionLabel: measureMap['marker']?['text'] as String?,
        ));
      }
      logger.log('Songsterr parser: parsed ${measures.length} measures');

      return Tab(
        song: result.title,
        artist: result.artist,
        instrument: map['instrument'] as String? ?? result.instrument ?? 'Unknown',
        tuning: map['tuning'] != null
            ? List<int>.from(map['tuning'] as List)
            : result.tuning ?? _defaultTuningFor(map['instrument'] as String?),
        capo: map['capo'] as int? ?? result.capo,
        tempo: map['automations']?['tempo']?.first?['bpm'] as int? ?? result.tempo,
        measures: measures,
        chords: _extractChords(map),
        sourceUrl: result.sourceUrl,
        songId: map['songId'] as int? ?? result.songId,
        revisionId: map['revisionId'] as int? ?? result.revisionId,
        trackId: map['partId'] as int? ?? result.trackId,
        rawNotation: map,
      );
    } catch (e, stackTrace) {
      logger.log('Songsterr tab parse error', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  List<String> _extractChords(Map<String, dynamic> map) {
    final chords = <String>{};
    final measures = map['measures'] as List<dynamic>? ?? <dynamic>[];
    for (final rawMeasure in measures) {
      final measureMap = rawMeasure as Map<String, dynamic>;
      final voices = measureMap['voices'] as List<dynamic>? ?? <dynamic>[];
      for (final voice in voices) {
        final voiceMap = voice as Map<String, dynamic>;
        final beats = voiceMap['beats'] as List<dynamic>? ?? <dynamic>[];
        for (final beat in beats) {
          final beatMap = beat as Map<String, dynamic>;
          final chord = beatMap['chord'] as Map<String, dynamic>?;
          if (chord != null && chord['text'] != null) {
            chords.add(chord['text'] as String);
          }
        }
      }
    }
    return chords.toList();
  }

  Map<String, dynamic>? _selectTrackFromMeta(List<dynamic> tracks, String? preferredInstrument) {
    if (tracks.isEmpty) return null;
    
    final preferred = preferredInstrument?.toLowerCase() ?? 'guitar';
    
    // Try to find a track matching the preferred instrument.
    for (final track in tracks) {
      final trackMap = track as Map<String, dynamic>;
      final instrument = (trackMap['instrument'] as String? ?? '').toLowerCase();
      if (instrument.contains(preferred) ||
          (preferred == 'guitar' && (instrument.contains('guitar') || instrument.contains('ukulele'))) ||
          (preferred == 'bass' && instrument.contains('bass')) ||
          (preferred == 'drums' && instrument.contains('drums'))) {
        return trackMap;
      }
    }
    
    // Fallback to first track.
    return tracks[0] as Map<String, dynamic>;
  }

  TabSearchResult _fromSongsterrSong(dynamic item, String preferredInstrument) {
    final map = item as Map<String, dynamic>;
    final tracks = map['tracks'] as List<dynamic>? ?? <dynamic>[];
    final defaultTrackIndex = map['defaultTrack'] as int? ?? 0;
    final defaultTrack = defaultTrackIndex < tracks.length
        ? tracks[defaultTrackIndex] as Map<String, dynamic>?
        : null;

    // Try to find a track matching the preferred instrument.
    Map<String, dynamic>? selectedTrack = defaultTrack;
    if (preferredInstrument.isNotEmpty) {
      final preferred = preferredInstrument.toLowerCase();
      for (final track in tracks) {
        final trackMap = track as Map<String, dynamic>;
        final instrument = (trackMap['instrument'] as String? ?? '').toLowerCase();
        if (instrument.contains(preferred) ||
            (preferred == 'guitar' && (instrument.contains('guitar') || instrument.contains('ukulele'))) ||
            (preferred == 'bass' && instrument.contains('bass')) ||
            (preferred == 'drums' && instrument.contains('drums'))) {
          selectedTrack = trackMap;
          break;
        }
      }
    }

    return TabSearchResult(
      songId: map['songId'] as int,
      artist: map['artist'] as String? ?? 'Unknown',
      title: map['title'] as String? ?? 'Unknown',
      revisionId: null,
      trackId: null,
      instrument: selectedTrack?['instrument'] as String?,
      tuning: selectedTrack?['tuning'] != null
          ? List<int>.from(selectedTrack!['tuning'] as List)
          : null,
      capo: null,
      tempo: null,
      difficulty: selectedTrack?['difficulty'] as int?,
      views: selectedTrack?['views'] as int?,
      sourceUrl: '$_baseUrl/a/wsa/${_slug(map['artist'] as String? ?? '')}-${_slug(map['title'] as String? ?? '')}-tab-s${map['songId']}',
      image: map['image'] as String?,
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
