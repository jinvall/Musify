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

/// Confidence Scoring Engine - Stage 1 Core Component
/// 
/// Scores relationship confidence based on evidence quality and quantity.
/// Models confidence rather than certainty.

class ConfidenceScoringEngine {
  /// Calculate final confidence score for a relationship
  static double calculateFinalConfidence(NormalizedRelationship relationship) {
    double confidence = relationship.baseConfidence;
    
    // Factor 1: Relationship type strength
    confidence *= _calculateTypeStrength(relationship.relationshipType);
    
    // Factor 2: Evidence source count
    confidence *= _calculateSourceCountBonus(relationship.evidenceHashes.length);
    
    // Factor 3: Temporal consistency
    confidence *= _calculateTemporalConsistency(relationship.metadata);
    
    // Factor 4: Independent confirmation bonus
    confidence *= _calculateIndependentConfirmationBonus(relationship.metadata);
    
    // Factor 5: Source credibility aggregation
    confidence *= _calculateSourceCredibility(relationship.metadata);
    
    return confidence.clamp(0.0, 1.0);
  }
  
  /// Calculate strength based on relationship type
  static double _calculateTypeStrength(RelationshipType type) {
    switch (type) {
      case RelationshipType.explicitInfluence:
        return 1.2;
      case RelationshipType.favoriteArtist:
        return 1.15;
      case RelationshipType.collaboration:
        return 1.1;
      case RelationshipType.inspiration:
        return 1.1;
      case RelationshipType.favoriteAlbum:
        return 1.05;
      case RelationshipType.favoriteSong:
        return 1.05;
      case RelationshipType.admiration:
        return 1.0;
      case RelationshipType.currentListening:
        return 0.9;
      case RelationshipType.recommendation:
        return 0.85;
    }
  }
  
  /// Calculate bonus for multiple evidence sources
  static double _calculateSourceCountBonus(int sourceCount) {
    if (sourceCount == 1) return 1.0;
    if (sourceCount <= 3) return 1.1;
    if (sourceCount <= 5) return 1.2;
    if (sourceCount <= 10) return 1.3;
    return 1.4; // Cap at 10+ sources
  }
  
  /// Calculate temporal consistency bonus
  static double _calculateTemporalConsistency(Map<String, dynamic> metadata) {
    // TODO: Implement temporal analysis
    // - Relationship mentions over time
    // - Consistency across different periods
    // - Recent vs historical evidence
    
    return 1.0; // Default no temporal adjustment
  }
  
  /// Calculate independent confirmation bonus
  static double _calculateIndependentConfirmationBonus(Map<String, dynamic> metadata) {
    final sourceTypes = metadata['sourceTypes'] as List<String>? ?? [];
    final uniqueTypes = sourceTypes.toSet();
    
    // Bonus for multiple independent source types
    if (uniqueTypes.length >= 3) return 1.2;
    if (uniqueTypes.length == 2) return 1.1;
    return 1.0;
  }
  
  /// Calculate aggregate source credibility
  static double _calculateSourceCredibility(Map<String, dynamic> metadata) {
    final sourceCredibilities = metadata['sourceCredibilities'] as List<double>? ?? [];
    
    if (sourceCredibilities.isEmpty) return 0.7; // Default for unknown sources
    
    // Use weighted average of source credibilities
    final average = sourceCredibilities.reduce((a, b) => a + b) / sourceCredibilities.length;
    
    // Penalize low-credibility sources
    if (average < 0.5) return average;
    
    return average;
  }
  
  /// Score relationship based on evidence quality
  static RelationshipScore scoreRelationship(NormalizedRelationship relationship) {
    final finalConfidence = calculateFinalConfidence(relationship);
    
    return RelationshipScore(
      relationship: relationship,
      finalConfidence: finalConfidence,
      scoreBreakdown: _calculateScoreBreakdown(relationship),
      qualityAssessment: _assessRelationshipQuality(relationship, finalConfidence),
    );
  }
  
  /// Calculate detailed score breakdown
  static Map<String, double> _calculateScoreBreakdown(NormalizedRelationship relationship) {
    return {
      'baseConfidence': relationship.baseConfidence,
      'typeStrength': _calculateTypeStrength(relationship.relationshipType),
      'sourceCountBonus': _calculateSourceCountBonus(relationship.evidenceHashes.length),
      'temporalConsistency': _calculateTemporalConsistency(relationship.metadata),
      'independentConfirmation': _calculateIndependentConfirmationBonus(relationship.metadata),
      'sourceCredibility': _calculateSourceCredibility(relationship.metadata),
    };
  }
  
  /// Assess relationship quality
  static RelationshipQuality _assessRelationshipQuality(
    NormalizedRelationship relationship, 
    double finalConfidence
  ) {
    if (finalConfidence >= 0.9) return RelationshipQuality.high;
    if (finalConfidence >= 0.7) return RelationshipQuality.medium;
    if (finalConfidence >= 0.5) return RelationshipQuality.low;
    return RelationshipQuality.weak;
  }
}
