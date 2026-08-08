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

import 'shared_types.dart';
import 'entity_resolution.dart';

/// Stage 1 Fingerprint Engine - Simplified Integration
/// 
/// This module provides the Stage 1 fingerprint generation functionality
/// for Musify's influence-based playlist system.
/// 
/// Stage 1 focuses on evidence discovery and relationship extraction from public sources
/// to understand an artist's musical background and influences.

class FingerprintGenerationEngine {
  /// Generate a complete fingerprint from Stage 1 results
  static ArtistFingerprint generateFingerprint({
    required String artistName,
    required List<RelationshipScore> scoredRelationships,
    required List<EvidenceSource> evidenceSources,
  }) {
    final relationships = <String, FingerprintRelationship>{};
    final artistNameMap = <String, String>{};
    final normalizedName = ArtistNormalizer.normalizeName(artistName);
    
    // Convert scored relationships to fingerprint format
    for (final score in scoredRelationships) {
      final targetName = score.relationship.targetArtistName;
      final artistId = ArtistHasher.hashArtistName(targetName);
      
      if (!relationships.containsKey(artistId)) {
        relationships[artistId] = FingerprintRelationship(
          artistId: artistId,
          confidence: score.finalConfidence,
          sources: score.relationship.evidenceHashes,
          lastUpdated: DateTime.now(),
        );
        artistNameMap[artistId] = targetName;
      }
    }
    
    return ArtistFingerprint(
      artistId: ArtistHasher.hashArtistName(artistName),
      normalizedName: normalizedName,
      relationships: relationships,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
      evidenceCount: evidenceSources.length,
      artistNameMap: artistNameMap,
    );
  }

  /// Validate generated fingerprint
  static FingerprintValidationResult validateFingerprint(ArtistFingerprint fingerprint) {
    final issues = <String>[];
    final relationships = fingerprint.relationships.values;
    
    // Check for minimum relationship count
    if (fingerprint.relationships.length < 1) {
      issues.add('Fingerprint has insufficient relationships');
    }
    
    // Check for duplicate relationships
    final seenArtists = <String>{};
    for (final relationship in relationships) {
      if (seenArtists.contains(relationship.artistId)) {
        issues.add('Duplicate relationship for artist: ${relationship.artistId}');
      }
      seenArtists.add(relationship.artistId);
    }
    
    // Check confidence scores
    for (final relationship in relationships) {
      if (relationship.confidence < 0.0 || relationship.confidence > 1.0) {
        issues.add('Invalid confidence score: ${relationship.confidence}');
      }
    }
    
    final isValid = issues.isEmpty;
    
    return FingerprintValidationResult(
      fingerprint: fingerprint,
      isValid: isValid,
      issues: issues,
      validationDate: DateTime.now(),
    );
  }
}