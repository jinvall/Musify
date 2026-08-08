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
import 'package:crypto/crypto.dart';
import 'package:musify/main.dart' show logger;

import 'shared_types.dart';

/// Entity Resolution Engine - Stage 1 Core Component
/// 
/// Resolves artist names to deterministic identifiers.
/// Eliminates aliases, duplicates, and variations.

class EntityResolutionEngine {
  static final Map<String, ResolvedArtist> _resolutionCache = {};
  
  /// Resolve artist name to deterministic identifier
  static Future<ResolvedArtist> resolveArtist(String artistName) async {
    // Check cache first
    final cacheKey = ArtistNormalizer.normalizeName(artistName);
    if (_resolutionCache.containsKey(cacheKey)) {
      return _resolutionCache[cacheKey]!;
    }
    
    try {
      // Phase 1: Name normalization
      final normalized = ArtistNormalizer.normalizeName(artistName);
      
      // Phase 2: Alias resolution
      final aliases = await _resolveAliases(normalized);
      
      // Phase 3: Music database lookup
      final canonicalName = await _findCanonicalName(normalized, aliases);
      
      // Phase 4: Confidence calculation
      final confidence = await _calculateResolutionConfidence(normalized, canonicalName);
      
      // Phase 5: Generate deterministic ID
      final finalName = canonicalName ?? normalized;
      final artistId = ArtistHasher.hashArtistName(finalName);
      
      final resolvedArtist = ResolvedArtist(
        normalizedName: finalName,
        artistId: artistId,
        aliases: aliases,
        resolutionConfidence: confidence,
        metadata: {
          'originalName': artistName,
          'normalizedNames': [normalized, ...aliases],
        },
      );
      
      // Cache resolution
      _resolutionCache[cacheKey] = resolvedArtist;
      
      return resolvedArtist;
      
    } catch (e, stackTrace) {
      logger.log('Error resolving artist: $artistName', error: e, stackTrace: stackTrace);
      
      // Fallback: basic normalization and hashing
      return ResolvedArtistExtension.fromName(artistName);
    }
  }
  
  /// Resolve aliases for artist name
  static Future<List<String>> _resolveAliases(String normalizedName) async {
    final aliases = <String>[];
    
    // TODO: Implement alias resolution
    // - Music database APIs
    // - Discogs artist aliases
    // - MusicBrainz artist relations
    // - Wikipedia disambiguation
    
    logger.log('Alias resolution not yet implemented for: $normalizedName');
    return aliases;
  }
  
  /// Find canonical artist name
  static Future<String?> _findCanonicalName(
    String normalizedName, 
    List<String> aliases
  ) async {
    // TODO: Implement canonical name lookup
    // - Music database canonical name resolution
    // - Most common usage pattern
    // - Verified artist profiles
    
    return normalizedName; // Fallback to normalized name
  }
  
  /// Calculate resolution confidence
  static Future<double> _calculateResolutionConfidence(
    String normalizedName, 
    String? canonicalName
  ) async {
    double confidence = 1.0;
    
    // Adjust based on canonical name match
    if (canonicalName != null && canonicalName != normalizedName) {
      confidence *= 0.9; // Slight penalty for non-exact match
    }
    
    // Adjust based on alias count
    // More aliases = higher confidence in resolution
    
    return confidence.clamp(0.0, 1.0);
  }
  
  /// Clear resolution cache
  static void clearCache() {
    _resolutionCache.clear();
  }
  
  /// Batch resolve multiple artists
  static Future<Map<String, ResolvedArtist>> resolveArtists(List<String> artistNames) async {
    final resolutions = <String, ResolvedArtist>{};
    final resolutionTasks = <Future<ResolvedArtist>>[];
    
    for (final name in artistNames) {
      resolutionTasks.add(resolveArtist(name));
    }
    
    final results = await Future.wait(resolutionTasks);
    for (var i = 0; i < artistNames.length; i++) {
      resolutions[artistNames[i]] = results[i];
    }
    
    return resolutions;
  }
}

/// Artist name normalizer
class ArtistNormalizer {
  /// Normalize artist name for consistent resolution
  static String normalizeName(String artistName) {
    return artistName
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s&]" ), '') // Remove special chars
        .replaceAll(RegExp(r'\b(the|a|an)\b', caseSensitive: false), '') // Remove articles
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .replaceAll(RegExp(r'^\s+|\s+$'), '') // Trim
        .replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring|with)\b', caseSensitive: false), '&') // Normalize features
        .replaceAll(RegExp(r'\s*&\s*'), ' & ') // Normalize ampersand
        .replaceAll(RegExp(r'\s*,\s*'), ' ') // Remove commas
        .trim();
  }
  
  /// Check if two artist names are likely the same
  static bool areLikelySame(String name1, String name2) {
    final normalized1 = normalizeName(name1);
    final normalized2 = normalizeName(name2);
    
    // Exact match
    if (normalized1 == normalized2) return true;
    
    // Contains match (one name contains the other)
    if (normalized1.contains(normalized2) || normalized2.contains(normalized1)) {
      return normalized1.length >= 3 && normalized2.length >= 3;
    }
    
    // TODO: Implement more sophisticated similarity matching
    // - Levenshtein distance
    // - Soundex matching
    // - Common abbreviation resolution
    
    return false;
  }
  
  /// Extract primary artist from featured string
  static String extractPrimaryArtist(String artistString) {
    final normalized = normalizeName(artistString);
    
    // Split by common feature separators
    final parts = normalized.split(RegExp(r'\s+(&|feat\.?|ft\.?|featuring|with)\s+'));
    
    if (parts.isNotEmpty) {
      return parts.first.trim();
    }
    
    return normalized;
  }
}

/// Artist hashing for deterministic identifiers
class ArtistHasher {
  /// Generate deterministic hash for artist name
  static String hashArtistName(String artistName) {
    final normalized = ArtistNormalizer.normalizeName(artistName);
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    
    // Use first 3 bytes for compact representation (0x7A9C21 format)
    final hashBytes = digest.bytes.take(3).toList();
    final hexString = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    
    return '0x${hexString.toUpperCase()}';
  }
  
  /// Verify hash consistency
  static bool verifyHash(String artistName, String expectedHash) {
    return hashArtistName(artistName) == expectedHash;
  }
  
  /// Generate hash from multiple names (for alias groups)
  static String hashArtistGroup(List<String> artistNames) {
    final normalizedNames = artistNames.map(ArtistNormalizer.normalizeName).toList()..sort();
    final combined = normalizedNames.join('|');
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    
    final hashBytes = digest.bytes.take(3).toList();
    final hexString = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    
    return '0x${hexString.toUpperCase()}';
  }
}

/// Artist relationship normalizer
class RelationshipNormalizer {
  /// Normalize extracted relationships
  static Future<List<NormalizedRelationship>> normalizeRelationships(
    List<ExtractedRelationship> extractedRelationships,
  ) async {
    final normalized = <NormalizedRelationship>[];
    
    // Resolve all artists first
    final allArtists = _extractAllArtists(extractedRelationships).toList();
    final artistResolutions = await EntityResolutionEngine.resolveArtists(allArtists);
    
    // Group relationships by resolved artist pairs
    final relationshipGroups = <String, List<ExtractedRelationship>>{};
    
    for (final relationship in extractedRelationships) {
      final sourceResolution = artistResolutions[relationship.sourceArtist];
      final targetResolution = artistResolutions[relationship.targetArtist];
      
      if (sourceResolution != null && targetResolution != null) {
        final groupKey = '${sourceResolution.artistId}:${targetResolution.artistId}';
        
        if (!relationshipGroups.containsKey(groupKey)) {
          relationshipGroups[groupKey] = [];
        }
        relationshipGroups[groupKey]!.add(relationship);
      }
    }
    
    // Merge relationships in each group
    for (final group in relationshipGroups.values) {
      final merged = _mergeRelationshipGroup(group, artistResolutions);
      normalized.add(merged);
    }
    
    return normalized;
  }
  
  /// Extract all unique artists from relationships
  static Set<String> _extractAllArtists(List<ExtractedRelationship> relationships) {
    final artists = <String>{};
    
    for (final relationship in relationships) {
      artists.add(relationship.sourceArtist);
      artists.add(relationship.targetArtist);
    }
    
    return artists;
  }
  
  /// Merge multiple relationships for the same artist pair
  static NormalizedRelationship _mergeRelationshipGroup(
    List<ExtractedRelationship> relationships,
    Map<String, ResolvedArtist> artistResolutions,
  ) {
    if (relationships.isEmpty) {
      throw ArgumentError('Cannot merge empty relationship group');
    }
    
    final first = relationships.first;
    final sourceResolution = artistResolutions[first.sourceArtist];
    final targetResolution = artistResolutions[first.targetArtist];
    
    final evidenceHashes = relationships.map((r) => r.evidenceText.hashCode.toString()).toList();
    
    // Calculate merged confidence
    final mergedConfidence = relationships
        .map((r) => r.confidence)
        .reduce((a, b) => a + b) / relationships.length;
    
    // Use strongest relationship type
    final strongestType = relationships
        .map((r) => r.type)
        .reduce((a, b) => _getTypeStrength(a) > _getTypeStrength(b) ? a : b);
    
    return NormalizedRelationship(
      sourceArtist: sourceResolution?.artistId ?? first.sourceArtist,
      targetArtist: targetResolution?.artistId ?? first.targetArtist,
      relationshipType: strongestType,
      baseConfidence: mergedConfidence,
      evidenceHashes: evidenceHashes,
      extractionDate: DateTime.now(),
      metadata: {
        'sourceCount': relationships.length,
        'mergedFrom': relationships.map((r) => r.type.toString()).toList(),
        if (sourceResolution != null) 'sourceNormalizedName': sourceResolution.normalizedName,
        if (targetResolution != null) 'targetNormalizedName': targetResolution.normalizedName,
      },
      sourceArtistName: first.sourceArtist,
      targetArtistName: first.targetArtist,
    );
  }

  static double _getTypeStrength(RelationshipType type) {
    switch (type) {
      case RelationshipType.explicitInfluence:
        return 1.2;
      case RelationshipType.favoriteArtist:
        return 1.1;
      case RelationshipType.collaboration:
        return 1.05;
      case RelationshipType.favoriteAlbum:
        return 1.0;
      case RelationshipType.favoriteSong:
        return 1.0;
      case RelationshipType.currentListening:
        return 0.9;
      case RelationshipType.recommendation:
        return 0.8;
      case RelationshipType.inspiration:
        return 1.1;
      case RelationshipType.admiration:
        return 1.0;
    }
  }
}

// Extension for ResolvedArtist factory method
extension ResolvedArtistExtension on ResolvedArtist {
  static ResolvedArtist fromName(String artistName) {
    final normalized = ArtistNormalizer.normalizeName(artistName);
    final artistId = ArtistHasher.hashArtistName(normalized);
    
    return ResolvedArtist(
      normalizedName: normalized,
      artistId: artistId,
      aliases: [artistName],
      resolutionConfidence: 1.0,
    );
  }
}
