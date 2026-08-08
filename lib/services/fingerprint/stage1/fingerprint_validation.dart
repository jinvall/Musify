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

/// Fingerprint Validation Engine - Stage 1 Component
/// 
/// Validates fingerprint generation results for quality and completeness.
/// Ensures generated fingerprints meet validation criteria before storage.

class FingerprintValidationEngine {
  /// Validate a fingerprint generation result
  static FingerprintValidationResult validateFingerprint(ArtistFingerprint fingerprint) {
    final issues = <String>[];
    
    // Check minimum requirements
    if (fingerprint.relationships.isEmpty) {
      issues.add('Fingerprint has no relationships');
    }
    
    // Validate each relationship
    for (final entry in fingerprint.relationships.entries) {
      final relationship = entry.value;
      
      if (relationship.artistId.isEmpty) {
        issues.add('Relationship has empty artist ID');
      }
      
      if (relationship.confidence < 0.0 || relationship.confidence > 1.0) {
        issues.add('Relationship ${relationship.artistId} has invalid confidence: ${relationship.confidence}');
      }
      
      if (relationship.sources.isEmpty) {
        issues.add('Relationship ${relationship.artistId} has no evidence sources');
      }
    }
    
    // Check fingerprint metadata
    if (fingerprint.normalizedName.isEmpty) {
      issues.add('Fingerprint has empty normalized name');
    }
    
    if (fingerprint.evidenceCount < 0) {
      issues.add('Fingerprint has invalid evidence count');
    }
    
    final isValid = issues.isEmpty;
    
    return FingerprintValidationResult(
      fingerprint: fingerprint,
      isValid: isValid,
      issues: issues,
      validationDate: DateTime.now(),
    );
  }

  /// Validate relationship extraction quality
  static List<String> validateRelationshipExtraction(List<ExtractedRelationship> relationships) {
    final issues = <String>[];
    
    for (int i = 0; i < relationships.length; i++) {
      final relationship = relationships[i];
      
      if (relationship.sourceArtist.isEmpty) {
        issues.add('Relationship $i has empty source artist');
      }
      
      if (relationship.targetArtist.isEmpty) {
        issues.add('Relationship $i has empty target artist');
      }
      
      if (relationship.confidence < 0.0 || relationship.confidence > 1.0) {
        issues.add('Relationship $i has invalid confidence: ${relationship.confidence}');
      }
      
      if (relationship.evidenceText.isEmpty) {
        issues.add('Relationship $i has empty evidence text');
      }
    }
    
    return issues;
  }

  /// Validate evidence source quality
  static List<String> validateEvidenceSources(List<EvidenceSource> sources) {
    final issues = <String>[];
    
    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      
      if (source.url.isEmpty) {
        issues.add('Evidence source $i has empty URL');
      }
      
      if (source.title.isEmpty) {
        issues.add('Evidence source $i has empty title');
      }
      
      if (source.credibilityWeight < 0.0 || source.credibilityWeight > 1.0) {
        issues.add('Evidence source $i has invalid credibility weight: ${source.credibilityWeight}');
      }
    }
    
    return issues;
  }

  /// Generate quality score for fingerprint
  static double calculateQualityScore(ArtistFingerprint fingerprint) {
    double score = 0.0;
    
    // Check relationship count (weight: 30%)
    final relationshipCountScore = (fingerprint.relationships.length / 10).clamp(0.0, 1.0);
    score += relationshipCountScore * 0.3;
    
    // Check average confidence (weight: 30%)
    if (fingerprint.relationships.isNotEmpty) {
      final totalConfidence = fingerprint.relationships.values
          .fold(0.0, (sum, rel) => sum + rel.confidence);
      final averageConfidence = totalConfidence / fingerprint.relationships.length;
      score += averageConfidence * 0.3;
    }
    
    // Check evidence count (weight: 20%)
    final evidenceScore = (fingerprint.evidenceCount / 50).clamp(0.0, 1.0);
    score += evidenceScore * 0.2;
    
    // Check recency (weight: 15%)
    final daysSinceUpdate = DateTime.now().difference(fingerprint.lastUpdated).inDays;
    final recencyScore = (30 - daysSinceUpdate / 30.0).clamp(0.0, 1.0);
    score += recencyScore * 0.15;
    
    return score;
  }
}