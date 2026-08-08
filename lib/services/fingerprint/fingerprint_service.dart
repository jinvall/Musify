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

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/fingerprint/stage1/shared_types.dart';

// Import Stage 1 API only (avoid circular imports)
import 'stage1/stage1_api.dart';

/// Artist Fingerprint Service - Integrated Stage 1 Implementation
/// 
/// Core philosophy: Store relationships, not content.
/// Raw evidence is processed and discarded, only distilled knowledge remains.

const fingerprintCacheVersion = 1;

/// Core fingerprint service
class FingerprintService {
  static final FingerprintService _instance = FingerprintService._internal();
  factory FingerprintService() => _instance;
  FingerprintService._internal();

  /// Generate deterministic hash for artist name
  static String hashArtistName(String artistName) {
    final normalized = _normalizeArtistName(artistName);
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    return '0x${digest.bytes.take(3).map((b) => b.toRadixString(16).padLeft(2, "0")).join("").toUpperCase()}';
  }

  /// Normalize artist name for consistent hashing
  static String _normalizeArtistName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Load fingerprint for artist
  Future<ArtistFingerprint?> loadFingerprint(String artistId) async {
    try {
      final box = await Hive.openBox('fingerprints');
      final fingerprintData = box.get(artistId);
      
      if (fingerprintData is Map) {
        return ArtistFingerprint.fromJson(Map<String, dynamic>.from(fingerprintData));
      }
      return null;
    } catch (e, stackTrace) {
      logger.log('Error loading fingerprint for $artistId', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Save fingerprint
  Future<void> saveFingerprint(ArtistFingerprint fingerprint) async {
    try {
      final box = await Hive.openBox('fingerprints');
      await box.put(fingerprint.artistId, fingerprint.toJson());
    } catch (e, stackTrace) {
      logger.log('Error saving fingerprint for ${fingerprint.artistId}', error: e, stackTrace: stackTrace);
    }
  }

  /// Generate fingerprint for artist using Stage 1 engine
  Future<ArtistFingerprint?> generateFingerprint(
    String artistName, {
    bool permanent = false,
  }) async {
    final result = await Stage1Api.generateFingerprint(
      artistName,
      permanent: permanent,
    );
    
    if (result.success) {
      return result.fingerprint;
    } else {
      logger.log('Fingerprint generation failed for $artistName: ${result.error}');
      return null;
    }
  }

  /// Generate playlist from fingerprint
  Future<List<Map<String, dynamic>>> generatePlaylist(ArtistFingerprint fingerprint) async {
    final topRelationships = fingerprint.getTopRelationships(10);
    final playlist = <Map<String, dynamic>>[];
    
    for (final relationship in topRelationships) {
      try {
        // Resolve artist name from fingerprint metadata
        final targetName = fingerprint.artistNameMap?[relationship.artistId] ?? relationship.artistId;
        
        logger.log('Fingerprint playlist: searching for influential artist: $targetName');
        
        // Search for the influential artist in Musify's catalog
        final searchResults = await searchVerifiedArtists(targetName, limit: 5);
        logger.log('Fingerprint playlist: search results for $targetName: ${searchResults.length}');
        
        if (searchResults.isEmpty) {
          logger.log('Fingerprint playlist: no search results for $targetName, skipping');
          continue;
        }
        
        final artistResult = searchResults.first;
        final artistId = artistResult['ytid']?.toString() ?? '';
        if (artistId.isEmpty) {
          logger.log('Fingerprint playlist: empty artistId for $targetName, skipping');
          continue;
        }
        
        // Get artist catalog
        final catalog = await getArtistCatalog(artistId);
        if (catalog == null || catalog['list'] is! List) {
          logger.log('Fingerprint playlist: empty catalog for $targetName ($artistId), skipping');
          continue;
        }
        
        final tracks = (catalog['list'] as List).cast<Map<String, dynamic>>();
        final topTracks = tracks.take(3).toList();
        logger.log('Fingerprint playlist: adding ${topTracks.length} tracks from $targetName');
        
        // Weight tracks by relationship confidence
        for (final track in topTracks) {
          final weightedTrack = {
            ...track,
            'fingerprintWeight': relationship.confidence,
            'influentialArtist': targetName,
            'influentialArtistId': artistId,
          };
          playlist.add(weightedTrack);
        }
      } catch (e, stackTrace) {
        logger.log('Error searching tracks for artist ${relationship.artistId}', 
                  error: e, stackTrace: stackTrace);
      }
    }
    
    // Sort by fingerprint weight
    playlist.sort((a, b) => (b['fingerprintWeight'] as double)
        .compareTo(a['fingerprintWeight'] as double));
    
    logger.log('Fingerprint playlist: generated ${playlist.length} tracks total');
    return playlist;
  }

  /// Get fingerprint statistics
  Future<FingerprintStats> getStats() async {
    return Stage1Api.getFingerprintStats();
  }

  /// Check if fingerprint exists
  Future<bool> fingerprintExists(String artistName) async {
    return Stage1Api.fingerprintExists(artistName);
  }

  /// Search fingerprints
  Future<List<FingerprintSearchResult>> searchFingerprints({
    String? query,
    double? minConfidence,
    int? limit,
  }) async {
    return Stage1Api.searchFingerprints(
      query: query,
      minConfidence: minConfidence,
      limit: limit,
    );
  }
}

/// Initialize fingerprint service
Future<void> initializeFingerprintService() async {
  await Hive.openBox('fingerprints');
  await Hive.openBox('cache');
}
