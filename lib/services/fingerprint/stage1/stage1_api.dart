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

import 'package:hive_flutter/hive_flutter.dart';
import 'package:musify/main.dart' show logger;

import 'shared_types.dart';
import 'stage1_orchestrator.dart';
import 'entity_resolution.dart';

/// Stage 1 API - Public Interface for Evidence Discovery & Fingerprint Generation
/// 
/// Provides clean API for Stage 1 functionality while maintaining zero-garbage architecture.

class Stage1Api {
  /// Generate fingerprint for artist
  static Future<FingerprintApiResult> generateFingerprint(
    String artistName, {
    bool permanent = false,
  }) async {
    try {
      final result = await Stage1Orchestrator.generateArtistFingerprint(artistName);
      
      if (result.success && result.fingerprint != null) {
        // Store fingerprint
        if (permanent) {
          await _storeFingerprint(result.fingerprint!);
        } else {
          await _storeFingerprintCache(result.fingerprint!);
        }
        
        return FingerprintApiResult.success(
          fingerprint: result.fingerprint!,
          processingTime: result.totalTime,
          evidenceSources: result.fingerprint!.evidenceCount,
          relationships: result.fingerprint!.relationships.length,
        );
      } else {
        return FingerprintApiResult.failure(
          error: result.error ?? 'Fingerprint generation failed',
          processingTime: result.totalTime,
        );
      }
      
    } catch (e, stackTrace) {
      logger.log('API error generating fingerprint for $artistName', 
                error: e, stackTrace: stackTrace);
      
      return FingerprintApiResult.failure(
        error: e.toString(),
        processingTime: Duration.zero,
      );
    }
  }
  
  /// Load existing fingerprint
  static Future<FingerprintApiResult> loadFingerprint(String artistName) async {
    try {
      final fingerprint = await _loadFingerprint(artistName);
      
      if (fingerprint != null) {
        return FingerprintApiResult.success(
          fingerprint: fingerprint,
          processingTime: Duration.zero,
          evidenceSources: fingerprint.evidenceCount,
          relationships: fingerprint.relationships.length,
        );
      } else {
        return FingerprintApiResult.failure(
          error: 'No fingerprint found for $artistName',
          processingTime: Duration.zero,
        );
      }
      
    } catch (e, stackTrace) {
      logger.log('API error loading fingerprint for $artistName', 
                error: e, stackTrace: stackTrace);
      
      return FingerprintApiResult.failure(
        error: e.toString(),
        processingTime: Duration.zero,
      );
    }
  }
  
  /// Check if fingerprint exists
  static Future<bool> fingerprintExists(String artistName) async {
    try {
      final fingerprint = await _loadFingerprint(artistName);
      return fingerprint != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Get fingerprint statistics
  static Future<FingerprintStats> getFingerprintStats() async {
    try {
      final box = await Hive.openBox('fingerprints');
      final allFingerprints = box.values
          .where((value) => value is Map)
          .map((value) => ArtistFingerprint.fromJson(Map<String, dynamic>.from(value)))
          .toList();
      
      return FingerprintStats(
        totalFingerprints: allFingerprints.length,
        totalRelationships: allFingerprints
            .map((f) => f.relationships.length)
            .fold(0, (a, b) => a + b),
        totalEvidenceSources: allFingerprints
            .map((f) => f.evidenceCount)
            .fold(0, (a, b) => a + b),
        averageRelationships: allFingerprints.isNotEmpty ?
            allFingerprints.map((f) => f.relationships.length).reduce((a, b) => a + b) / 
            allFingerprints.length : 0,
        lastUpdated: allFingerprints.isNotEmpty ?
            allFingerprints.map((f) => f.lastUpdated).reduce((a, b) => 
                a.isAfter(b) ? a : b) : DateTime.now(),
      );
      
    } catch (e, stackTrace) {
      logger.log('Error getting fingerprint statistics', error: e, stackTrace: stackTrace);
      return FingerprintStats.empty();
    }
  }
  
  /// Search fingerprints by relationship
  static Future<List<FingerprintSearchResult>> searchFingerprints({
    String? query,
    double? minConfidence,
    int? limit,
  }) async {
    try {
      final box = await Hive.openBox('fingerprints');
      final allFingerprints = box.values
          .where((value) => value is Map)
          .map((value) => ArtistFingerprint.fromJson(Map<String, dynamic>.from(value)))
          .toList();
      
      final results = <FingerprintSearchResult>[];
      
      for (final fingerprint in allFingerprints) {
        // Filter by confidence if specified
        final relationships = minConfidence != null ?
            fingerprint.relationships.values
                .where((r) => r.confidence >= minConfidence)
                .toList() :
            fingerprint.relationships.values.toList();
        
        if (relationships.isNotEmpty) {
          results.add(FingerprintSearchResult(
            artistName: fingerprint.normalizedName,
            fingerprint: fingerprint,
            matchingRelationships: relationships.length,
            highestConfidence: relationships
                .map((r) => r.confidence)
                .reduce((a, b) => a > b ? a : b),
          ));
        }
      }
      
      // Sort by relevance
      results.sort((a, b) => b.highestConfidence.compareTo(a.highestConfidence));
      
      return limit != null ? results.take(limit).toList() : results;
      
    } catch (e, stackTrace) {
      logger.log('Error searching fingerprints', error: e, stackTrace: stackTrace);
      return [];
    }
  }
  
  /// Store fingerprint permanently
  static Future<void> _storeFingerprint(ArtistFingerprint fingerprint) async {
    try {
      final box = await Hive.openBox('fingerprints');
      await box.put(fingerprint.artistId, fingerprint.toJson());
    } catch (e, stackTrace) {
      logger.log('Error storing fingerprint ${fingerprint.artistId}', 
                error: e, stackTrace: stackTrace);
    }
  }
  
  /// Store fingerprint in cache with TTL (7 days)
  static Future<void> _storeFingerprintCache(ArtistFingerprint fingerprint) async {
    try {
      final box = await Hive.openBox('cache');
      final cacheEntry = {
        'fingerprint': fingerprint.toJson(),
        'cachedAt': DateTime.now().toIso8601String(),
        'ttlDays': 7,
      };
      await box.put('fp_v1_${fingerprint.artistId}', cacheEntry);
    } catch (e, stackTrace) {
      logger.log('Error caching fingerprint ${fingerprint.artistId}', 
                error: e, stackTrace: stackTrace);
    }
  }
  
  /// Load fingerprint from storage or cache
  static Future<ArtistFingerprint?> _loadFingerprint(String artistName) async {
    try {
      final artistId = ArtistHasher.hashArtistName(artistName);
      
      // Try permanent storage first
      final permanentBox = await Hive.openBox('fingerprints');
      final permanentData = permanentBox.get(artistId);
      if (permanentData is Map) {
        return ArtistFingerprint.fromJson(Map<String, dynamic>.from(permanentData));
      }
      
      // Try cache with TTL check
      final cacheBox = await Hive.openBox('cache');
      final cacheData = cacheBox.get('fp_v1_$artistId');
      if (cacheData is Map) {
        final cachedAt = DateTime.tryParse(cacheData['cachedAt'] as String? ?? '') ?? DateTime.now();
        final ttlDays = cacheData['ttlDays'] as int? ?? 7;
        final age = DateTime.now().difference(cachedAt).inDays;
        
        if (age < ttlDays) {
          final fingerprintData = cacheData['fingerprint'] as Map<String, dynamic>?;
          if (fingerprintData != null) {
            return ArtistFingerprint.fromJson(fingerprintData);
          }
        } else {
          // Expired cache entry
          unawaited(cacheBox.delete('fp_v1_$artistId'));
        }
      }
      
      return null;
    } catch (e, stackTrace) {
      logger.log('Error loading fingerprint for $artistName', 
                error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
