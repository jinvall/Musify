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

import 'package:musify/main.dart' show logger;

import 'shared_types.dart';
import 'evidence_discovery.dart';
import 'content_extraction.dart';
import 'entity_resolution.dart';
import 'confidence_scoring.dart';
import 'fingerprint_generation.dart';

bool _isInfluenceRelationshipType(RelationshipType type) {
  switch (type) {
    case RelationshipType.explicitInfluence:
    case RelationshipType.inspiration:
    case RelationshipType.favoriteArtist:
    case RelationshipType.favoriteAlbum:
    case RelationshipType.favoriteSong:
    case RelationshipType.currentListening:
    case RelationshipType.recommendation:
    case RelationshipType.admiration:
      return true;
    case RelationshipType.collaboration:
      return false;
  }
}

/// Stage 1 Orchestrator - Main Coordination Engine
/// 
/// Coordinates the entire fingerprint generation pipeline.
/// Implements zero-garbage architecture: temporary data discarded after processing.

class Stage1Orchestrator {
  /// Generate artist fingerprint from evidence discovery to final fingerprint
  static Future<FingerprintGenerationResult> generateArtistFingerprint(
    String artistName,
  ) async {
    final startTime = DateTime.now();
    final processingLog = <ProcessingStage>[];
    
    try {
      // Stage 1: Evidence Discovery
      processingLog.add(ProcessingStage(
        stage: 'Evidence Discovery',
        startTime: DateTime.now(),
      ));
      
      final evidenceSources = await EvidenceDiscoveryEngine.discoverEvidence(artistName);
      processingLog.last.endTime = DateTime.now();
      processingLog.last.resultCount = evidenceSources.length;
      
      if (evidenceSources.isEmpty) {
        return FingerprintGenerationResult(
          artistName: artistName,
          fingerprint: null,
          success: false,
          error: 'No evidence sources found',
          processingLog: processingLog,
          totalTime: DateTime.now().difference(startTime),
        );
      }
      
      // Stage 2: Content Extraction
      processingLog.add(ProcessingStage(
        stage: 'Content Extraction',
        startTime: DateTime.now(),
      ));
      
      final extractedRelationships = await _extractRelationshipsFromSources(
        artistName, 
        evidenceSources
      );
      processingLog.last.endTime = DateTime.now();
      processingLog.last.resultCount = extractedRelationships.length;
      
      if (extractedRelationships.isEmpty) {
        return FingerprintGenerationResult(
          artistName: artistName,
          fingerprint: null,
          success: false,
          error: 'No relationships extracted from evidence',
          processingLog: processingLog,
          totalTime: DateTime.now().difference(startTime),
        );
      }
      
      // Stage 3: Entity Resolution
      processingLog.add(ProcessingStage(
        stage: 'Entity Resolution',
        startTime: DateTime.now(),
      ));
      
      final normalizedRelationships = await RelationshipNormalizer.normalizeRelationships(
        extractedRelationships,
      );
      processingLog.last.endTime = DateTime.now();
      processingLog.last.resultCount = normalizedRelationships.length;
      
      // Stage 4: Confidence Scoring
      processingLog.add(ProcessingStage(
        stage: 'Confidence Scoring',
        startTime: DateTime.now(),
      ));
      
      final scoredRelationships = _scoreRelationships(normalizedRelationships);
      processingLog.last.endTime = DateTime.now();
      processingLog.last.resultCount = scoredRelationships.length;
      
      // Stage 5: Fingerprint Generation
      processingLog.add(ProcessingStage(
        stage: 'Fingerprint Generation',
        startTime: DateTime.now(),
      ));
      
      var fingerprint = FingerprintGenerationEngine.generateFingerprint(
        artistName: artistName,
        scoredRelationships: scoredRelationships,
        evidenceSources: evidenceSources,
      );
      processingLog.last.endTime = DateTime.now();
      
      // Stage 5b: Associated Acts Filtering
      // Filter out bands, projects, and associated acts from Wikipedia infobox
      processingLog.add(ProcessingStage(
        stage: 'Associated Acts Filtering',
        startTime: DateTime.now(),
      ));
      
      final associatedActs = await EvidenceDiscoveryEngine.fetchAssociatedActs(artistName);
      final beforeCount = fingerprint.relationships.length;
      
      fingerprint = _filterAssociatedActs(fingerprint, associatedActs);
      
      processingLog.last.endTime = DateTime.now();
      processingLog.last.resultCount = beforeCount - fingerprint.relationships.length;
      processingLog.last.success = true;
      
      if (associatedActs.isNotEmpty) {
        logger.log('Filtered ${beforeCount - fingerprint.relationships.length} associated acts for $artistName: ${associatedActs.join(", ")}');
      }
      
      // Stage 6: Fingerprint Validation
      processingLog.add(ProcessingStage(
        stage: 'Fingerprint Validation',
        startTime: DateTime.now(),
      ));
      
      final validation = FingerprintGenerationEngine.validateFingerprint(fingerprint);
      processingLog.last.endTime = DateTime.now();
      processingLog.last.success = validation.isValid;
      
      if (!validation.isValid) {
        logger.log('Fingerprint validation failed for $artistName: ${validation.issues}');
      }
      
      // Clean up temporary processing artifacts (zero-garbage)
      await _cleanupTemporaryData();
      
      return FingerprintGenerationResult(
        artistName: artistName,
        fingerprint: fingerprint,
        success: true,
        processingLog: processingLog,
        totalTime: DateTime.now().difference(startTime),
        validationResult: validation,
      );
      
    } catch (e, stackTrace) {
      logger.log('Error generating fingerprint for $artistName', 
                error: e, stackTrace: stackTrace);
      
      // Ensure cleanup even on failure
      await _cleanupTemporaryData();
      
      return FingerprintGenerationResult(
        artistName: artistName,
        fingerprint: null,
        success: false,
        error: e.toString(),
        processingLog: processingLog,
        totalTime: DateTime.now().difference(startTime),
      );
    }
  }
  
  /// Extract relationships from all evidence sources
  static Future<List<ExtractedRelationship>> _extractRelationshipsFromSources(
    String artistName,
    List<EvidenceSource> evidenceSources,
  ) async {
    final allRelationships = <ExtractedRelationship>[];
    final extractionTasks = <Future<List<ExtractedRelationship>>>[];
    
    for (final source in evidenceSources) {
      extractionTasks.add(_extractRelationshipsFromSource(artistName, source));
    }
    
    try {
      final results = await Future.wait(extractionTasks);
      for (final relationships in results) {
        allRelationships.addAll(relationships);
      }
    } catch (e, stackTrace) {
      logger.log('Error in parallel relationship extraction for $artistName', 
                error: e, stackTrace: stackTrace);
    }
    
    // Keep only influence/listening relationships.
    // Exclude bands, groups, projects, and collaboration-only entries.
    return allRelationships
        .where((r) => _isInfluenceRelationshipType(r.type))
        .toList();
  }
  
  /// Extract relationships from a single evidence source
  static Future<List<ExtractedRelationship>> _extractRelationshipsFromSource(
    String artistName,
    EvidenceSource source,
  ) async {
    try {
      // Extract content from source
      final content = await _extractSourceContent(source);
      
      if (content.isEmpty) {
        return [];
      }
      
      // Extract relationships from content
      return await ContentExtractionEngine.extractRelationships(
        artistName: artistName,
        content: content,
        source: source,
      );
      
    } catch (e, stackTrace) {
      logger.log('Error extracting relationships from ${source.url}', 
                error: e, stackTrace: stackTrace);
      return [];
    }
  }
  
  /// Extract content from evidence source
  static Future<String> _extractSourceContent(EvidenceSource source) async {
    try {
      final providerName = source.metadata['provider'] as String?;
      
      switch (providerName) {
        case 'wikipedia':
          return await WikipediaEvidenceProvider().extractContent(source);
        case 'musicbrainz':
          return await MusicBrainzEvidenceProvider().extractContent(source);
        case 'youtube_music':
          return await YoutubeMusicEvidenceProvider().extractContent(source);
        default:
          return '';
      }
    } catch (e, stackTrace) {
      logger.log('Error extracting content from ${source.url}', 
                  error: e, stackTrace: stackTrace);
      return '';
    }
  }
  
  /// Score all normalized relationships
  static List<RelationshipScore> _scoreRelationships(
    List<NormalizedRelationship> relationships,
  ) {
    return relationships
        .map((relationship) => ConfidenceScoringEngine.scoreRelationship(relationship))
        .toList();
  }
  
  /// Filter out associated acts from the fingerprint
  static ArtistFingerprint _filterAssociatedActs(
    ArtistFingerprint fingerprint,
    Set<String> associatedActs,
  ) {
    if (associatedActs.isEmpty) {
      return fingerprint;
    }
    
    final filteredRelationships = <String, FingerprintRelationship>{};
    final filteredArtistNameMap = <String, String>{};
    
    for (final entry in fingerprint.relationships.entries) {
      final artistId = entry.key;
      final relationship = entry.value;
      final artistName = fingerprint.artistNameMap?[artistId] ?? '';
      
      // Check if this artist is in the associated acts list
      final isAssociatedAct = associatedActs.any((act) {
        final normalizedAct = act.toLowerCase().trim();
        final normalizedArtistName = artistName.toLowerCase().trim();
        return normalizedArtistName == normalizedAct ||
            normalizedArtistName.contains(normalizedAct) ||
            normalizedAct.contains(normalizedArtistName);
      });
      
      if (!isAssociatedAct) {
        filteredRelationships[artistId] = relationship;
        filteredArtistNameMap[artistId] = artistName;
      }
    }
    
    return ArtistFingerprint(
      artistId: fingerprint.artistId,
      normalizedName: fingerprint.normalizedName,
      relationships: filteredRelationships,
      createdAt: fingerprint.createdAt,
      lastUpdated: DateTime.now(),
      evidenceCount: fingerprint.evidenceCount,
      artistNameMap: filteredArtistNameMap,
    );
  }
  
  /// Clean up temporary processing data (zero-garbage implementation)
  static Future<void> _cleanupTemporaryData() async {
    // Clear entity resolution cache
    EntityResolutionEngine.clearCache();
    
    // TODO: Implement cleanup of other temporary artifacts
    // - Downloaded files
    // - Intermediate processing results
    // - Temporary caches
    
    logger.log('Temporary data cleanup completed');
  }
  
  /// Batch generate fingerprints for multiple artists
  static Future<List<FingerprintGenerationResult>> generateFingerprints(
    List<String> artistNames,
  ) async {
    final results = <FingerprintGenerationResult>[];
    final generationTasks = <Future<FingerprintGenerationResult>>[];
    
    for (final artistName in artistNames) {
      generationTasks.add(generateArtistFingerprint(artistName));
    }
    
    final batchResults = await Future.wait(generationTasks);
    results.addAll(batchResults);
    
    return results;
  }
  
  /// Get fingerprint generation statistics
  static FingerprintStatistics calculateStatistics(
    List<FingerprintGenerationResult> results,
  ) {
    final successful = results.where((r) => r.success).toList();
    final failed = results.where((r) => !r.success).toList();
    
    int totalRelationships = 0;
    int totalEvidenceSources = 0;
    
    for (final result in successful) {
      if (result.fingerprint != null) {
        totalRelationships += result.fingerprint!.relationships.length;
        totalEvidenceSources += result.fingerprint!.evidenceCount;
      }
    }
    
    return FingerprintStatistics(
      totalArtists: results.length,
      successfulGenerations: successful.length,
      failedGenerations: failed.length,
      averageRelationships: successful.isNotEmpty ? 
          totalRelationships / successful.length : 0,
      averageEvidenceSources: successful.isNotEmpty ? 
          totalEvidenceSources / successful.length : 0,
      successRate: results.isNotEmpty ? successful.length / results.length : 0,
    );
  }
}
