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

/// Shared types for Stage 1 fingerprint engine
/// Avoids circular dependencies between modules

/// Represents a verified musical relationship with confidence scoring
class FingerprintRelationship {
  final String artistId; // Hashed identifier
  final double confidence; // 0.0 to 1.0
  final List<String> sources; // Evidence sources
  final DateTime lastUpdated;

  FingerprintRelationship({
    required this.artistId,
    required this.confidence,
    required this.sources,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'artistId': artistId,
    'confidence': confidence,
    'sources': sources,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory FingerprintRelationship.fromJson(Map<String, dynamic> json) {
    return FingerprintRelationship(
      artistId: json['artistId'],
      confidence: json['confidence']?.toDouble() ?? 0.0,
      sources: List<String>.from(json['sources'] ?? []),
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }
}

/// Artist fingerprint - sparse weighted graph of musical influences
class ArtistFingerprint {
  final String artistId; // Hashed identifier
  final String normalizedName;
  final Map<String, FingerprintRelationship> relationships;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final int evidenceCount;
  final Map<String, String>? artistNameMap; // artistId -> normalizedName

  ArtistFingerprint({
    required this.artistId,
    required this.normalizedName,
    required this.relationships,
    required this.createdAt,
    required this.lastUpdated,
    required this.evidenceCount,
    this.artistNameMap,
  });

  Map<String, dynamic> toJson() => {
    'artistId': artistId,
    'normalizedName': normalizedName,
    'relationships': relationships.map((key, value) => MapEntry(key, value.toJson())),
    'createdAt': createdAt.toIso8601String(),
    'lastUpdated': lastUpdated.toIso8601String(),
    'evidenceCount': evidenceCount,
    if (artistNameMap != null) 'artistNameMap': artistNameMap,
  };

  factory ArtistFingerprint.fromJson(Map<String, dynamic> json) {
    final relationships = <String, FingerprintRelationship>{};
    (json['relationships'] as Map<String, dynamic>?)?.forEach((key, value) {
      relationships[key] = FingerprintRelationship.fromJson(value);
    });

    Map<String, String>? artistNameMap;
    if (json['artistNameMap'] is Map) {
      artistNameMap = Map<String, String>.from(json['artistNameMap']);
    }

    return ArtistFingerprint(
      artistId: json['artistId'],
      normalizedName: json['normalizedName'],
      relationships: relationships,
      createdAt: DateTime.parse(json['createdAt']),
      lastUpdated: DateTime.parse(json['lastUpdated']),
      evidenceCount: json['evidenceCount'] ?? 0,
      artistNameMap: artistNameMap,
    );
  }

  /// Get top relationships sorted by confidence
  List<FingerprintRelationship> getTopRelationships([int limit = 20]) {
    final sorted = relationships.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return sorted.take(limit).toList();
  }

  /// Get confidence score for a specific artist relationship
  double getConfidenceForArtist(String targetArtistId) {
    return relationships[targetArtistId]?.confidence ?? 0.0;
  }
}

class EvidenceSource {
  final String id;
  final EvidenceSourceType type;
  final String url;
  final String title;
  final DateTime publishedDate;
  final double credibilityWeight;
  final Map<String, dynamic> metadata;
  final EvidenceSourceCategory category;
  final EvidenceSourceSubCategory subCategory;
  final String? parentSourceId;

  EvidenceSource({
    required this.id,
    required this.type,
    required this.url,
    required this.title,
    required this.publishedDate,
    required this.credibilityWeight,
    this.metadata = const {},
    this.category = EvidenceSourceCategory.other,
    this.subCategory = EvidenceSourceSubCategory.other,
    this.parentSourceId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'url': url,
    'title': title,
    'publishedDate': publishedDate.toIso8601String(),
    'credibilityWeight': credibilityWeight,
    'metadata': metadata,
    'category': category.toString(),
    'subCategory': subCategory.toString(),
    if (parentSourceId != null) 'parentSourceId': parentSourceId,
  };

  factory EvidenceSource.fromJson(Map<String, dynamic> json) {
    return EvidenceSource(
      id: json['id'],
      type: EvidenceSourceType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => EvidenceSourceType.article,
      ),
      url: json['url'],
      title: json['title'],
      publishedDate: DateTime.parse(json['publishedDate']),
      credibilityWeight: json['credibilityWeight']?.toDouble() ?? 0.7,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      category: EvidenceSourceCategory.values.firstWhere(
        (e) => e.toString() == json['category'],
        orElse: () => EvidenceSourceCategory.other,
      ),
      subCategory: EvidenceSourceSubCategory.values.firstWhere(
        (e) => e.toString() == json['subCategory'],
        orElse: () => EvidenceSourceSubCategory.other,
      ),
      parentSourceId: json['parentSourceId'],
    );
  }
}

enum EvidenceSourceType {
  interview,
  autobiography,
  podcast,
  article,
  socialMedia,
  verifiedPlaylist,
  documentary,
  radioAppearance,
  biography,
}

enum EvidenceSourceCategory {
  soundcloud,
  spotify,
  interviews,
  youtube,
  web,
  other;

  String get displayName {
    switch (this) {
      case EvidenceSourceCategory.soundcloud:
        return 'SoundCloud';
      case EvidenceSourceCategory.spotify:
        return 'Spotify';
      case EvidenceSourceCategory.interviews:
        return 'Interviews';
      case EvidenceSourceCategory.youtube:
        return 'YouTube';
      case EvidenceSourceCategory.web:
        return 'Web';
      case EvidenceSourceCategory.other:
        return 'Other';
    }
  }
}

enum EvidenceSourceSubCategory {
  likes,
  playlists,
  publicArtistPlaylists,
  whatAreYouListeningTo,
  publicPlaylists,
  musicRecommendations,
  favoriteArtists,
  other;

  String get displayName {
    switch (this) {
      case EvidenceSourceSubCategory.likes:
        return 'Likes';
      case EvidenceSourceSubCategory.playlists:
        return 'Playlists';
      case EvidenceSourceSubCategory.publicArtistPlaylists:
        return 'Public artist playlists / picks';
      case EvidenceSourceSubCategory.whatAreYouListeningTo:
        return '"What are you listening to?"';
      case EvidenceSourceSubCategory.publicPlaylists:
        return 'Public playlists / interviews';
      case EvidenceSourceSubCategory.musicRecommendations:
        return 'Music recommendations / favorite artists';
      case EvidenceSourceSubCategory.favoriteArtists:
        return 'Favorite artists';
      case EvidenceSourceSubCategory.other:
        return 'Other';
    }
  }
}

class ExtractedRelationship {
  final String sourceArtist;
  final String targetArtist;
  final RelationshipType type;
  final double confidence;
  final String evidenceText;
  final DateTime extractionDate;
  final Map<String, dynamic> metadata;

  ExtractedRelationship({
    required this.sourceArtist,
    required this.targetArtist,
    required this.type,
    required this.confidence,
    required this.evidenceText,
    required this.extractionDate,
    this.metadata = const {},
  });
}

enum RelationshipType {
  explicitInfluence,
  favoriteArtist,
  favoriteAlbum,
  favoriteSong,
  currentListening,
  collaboration,
  recommendation,
  inspiration,
  admiration,
}

class NormalizedRelationship {
  final String sourceArtist;
  final String targetArtist;
  final RelationshipType relationshipType;
  final double baseConfidence;
  final List<String> evidenceHashes;
  final DateTime extractionDate;
  final Map<String, dynamic> metadata;
  final String sourceArtistName;
  final String targetArtistName;

  NormalizedRelationship({
    required this.sourceArtist,
    required this.targetArtist,
    required this.relationshipType,
    required this.baseConfidence,
    required this.evidenceHashes,
    required this.extractionDate,
    this.metadata = const {},
    required this.sourceArtistName,
    required this.targetArtistName,
  });
}

class RelationshipPattern {
  final RelationshipType relationshipType;
  final String targetArtist;
  final String evidenceText;
  final double matchScore;
  final Map<String, dynamic> metadata;

  RelationshipPattern({
    required this.relationshipType,
    required this.targetArtist,
    required this.evidenceText,
    required this.matchScore,
    this.metadata = const {},
  });
}

class ResolvedArtist {
  final String normalizedName;
  final String artistId;
  final List<String> aliases;
  final double resolutionConfidence;
  final Map<String, dynamic> metadata;

  ResolvedArtist({
    required this.normalizedName,
    required this.artistId,
    required this.aliases,
    required this.resolutionConfidence,
    this.metadata = const {},
  });
}

class RelationshipScore {
  final NormalizedRelationship relationship;
  final double finalConfidence;
  final Map<String, double> scoreBreakdown;
  final RelationshipQuality qualityAssessment;

  RelationshipScore({
    required this.relationship,
    required this.finalConfidence,
    required this.scoreBreakdown,
    required this.qualityAssessment,
  });
}

enum RelationshipQuality {
  high,
  medium,
  low,
  weak,
  none,
  minimal,
  partial,
}

enum ConfidenceCategory {
  veryHigh,
  high,
  medium,
  low,
  veryLow,
}

class ProcessingStage {
  final String stage;
  final DateTime startTime;
  DateTime? endTime;
  int? resultCount;
  bool? success;
  String? error;

  ProcessingStage({
    required this.stage,
    required this.startTime,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}

class FingerprintGenerationResult {
  final String artistName;
  final ArtistFingerprint? fingerprint;
  final bool success;
  final String? error;
  final List<ProcessingStage> processingLog;
  final Duration totalTime;
  final FingerprintValidationResult? validationResult;

  FingerprintGenerationResult({
    required this.artistName,
    required this.fingerprint,
    required this.success,
    this.error,
    required this.processingLog,
    required this.totalTime,
    this.validationResult,
  });
}

class FingerprintValidationResult {
  final ArtistFingerprint fingerprint;
  final bool isValid;
  final List<String> issues;
  final DateTime validationDate;

  FingerprintValidationResult({
    required this.fingerprint,
    required this.isValid,
    required this.issues,
    required this.validationDate,
  });
}

class FingerprintStatistics {
  final int totalArtists;
  final int successfulGenerations;
  final int failedGenerations;
  final double averageRelationships;
  final double averageEvidenceSources;
  final double successRate;

  FingerprintStatistics({
    required this.totalArtists,
    required this.successfulGenerations,
    required this.failedGenerations,
    required this.averageRelationships,
    required this.averageEvidenceSources,
    required this.successRate,
  });
}

class FingerprintApiResult {
  final bool success;
  final ArtistFingerprint? fingerprint;
  final String? error;
  final Duration processingTime;
  final int? evidenceSources;
  final int? relationships;

  FingerprintApiResult._({
    required this.success,
    this.fingerprint,
    this.error,
    required this.processingTime,
    this.evidenceSources,
    this.relationships,
  });

  factory FingerprintApiResult.success({
    required ArtistFingerprint fingerprint,
    required Duration processingTime,
    required int evidenceSources,
    required int relationships,
  }) {
    return FingerprintApiResult._(
      success: true,
      fingerprint: fingerprint,
      processingTime: processingTime,
      evidenceSources: evidenceSources,
      relationships: relationships,
    );
  }

  factory FingerprintApiResult.failure({
    required String error,
    required Duration processingTime,
  }) {
    return FingerprintApiResult._(
      success: false,
      error: error,
      processingTime: processingTime,
    );
  }
}

class FingerprintStats {
  final int totalFingerprints;
  final int totalRelationships;
  final int totalEvidenceSources;
  final double averageRelationships;
  final DateTime lastUpdated;

  FingerprintStats({
    required this.totalFingerprints,
    required this.totalRelationships,
    required this.totalEvidenceSources,
    required this.averageRelationships,
    required this.lastUpdated,
  });

  factory FingerprintStats.empty() {
    return FingerprintStats(
      totalFingerprints: 0,
      totalRelationships: 0,
      totalEvidenceSources: 0,
      averageRelationships: 0,
      lastUpdated: DateTime.now(),
    );
  }
}

class FingerprintSearchResult {
  final String artistName;
  final ArtistFingerprint fingerprint;
  final int matchingRelationships;
  final double highestConfidence;

  FingerprintSearchResult({
    required this.artistName,
    required this.fingerprint,
    required this.matchingRelationships,
    required this.highestConfidence,
  });
}
