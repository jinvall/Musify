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

import 'package:musify/main.dart' show logger;

import 'shared_types.dart';

/// Content Extraction Engine - Stage 1 Core Component
/// 
/// Extracts musical relationships from evidence sources.
/// Uses lightweight keyword and pattern matching instead of NLP.

class ContentExtractionEngine {
  /// Extract relationships from evidence content
  static Future<List<ExtractedRelationship>> extractRelationships({
    required String artistName,
    required String content,
    required EvidenceSource source,
  }) async {
    final relationships = <ExtractedRelationship>[];
    
    try {
      // Phase 1: Text preprocessing
      final processedContent = _preprocessContent(content);
      
      // Phase 2: Provider-specific extraction
      final provider = source.metadata['provider'] as String? ?? 'unknown';
      
      switch (provider) {
        case 'wikipedia':
          relationships.addAll(_extractFromWikipedia(
            artistName: artistName,
            content: processedContent,
            source: source,
          ));
          break;
        case 'musicbrainz':
          relationships.addAll(_extractFromMusicBrainz(
            artistName: artistName,
            content: processedContent,
            source: source,
          ));
          break;
        case 'youtube_music':
          relationships.addAll(_extractFromYoutubeMusic(
            artistName: artistName,
            content: processedContent,
            source: source,
          ));
          break;
        default:
          // Generic keyword matching for unknown providers
          relationships.addAll(_extractByKeywordMatching(
            artistName: artistName,
            content: processedContent,
            source: source,
          ));
      }
      
    } catch (e, stackTrace) {
      logger.log('Error extracting relationships for $artistName from ${source.url}', 
                error: e, stackTrace: stackTrace);
    }
    
    return relationships;
  }
  
  /// Preprocess content for extraction
  static String _preprocessContent(String content) {
    return content
        .replaceAll(RegExp(r'<[^>]*>'), ' ') // Remove HTML
        .replaceAll(RegExp(r'\s+'), ' ')     // Normalize whitespace
        .trim();
  }
  
  /// Extract relationships from Wikipedia content
  static List<ExtractedRelationship> _extractFromWikipedia({
    required String artistName,
    required String content,
    required EvidenceSource source,
  }) {
    final relationships = <ExtractedRelationship>[];
    
    // Pattern 1: Explicit influence statements
    final influencePatterns = [
      RegExp(r'influenced by\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'inspired by\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'cited\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+as\s+an\s+influence', caseSensitive: false),
      RegExp(r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+was\s+a\s+major\s+influence', caseSensitive: false),
      RegExp(r'listened to\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'grew up listening to\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'favorite\s+(?:artist|band|album|song)\s+(?:is|was)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'recommended\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
    ];
    
    for (final pattern in influencePatterns) {
      final matches = pattern.allMatches(content);
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final targetArtist = match.group(1)?.trim() ?? '';
          final normalizedTarget = targetArtist.toLowerCase();
          final normalizedArtistName = artistName.toLowerCase().trim();
          
          if (targetArtist.isEmpty) continue;
          if (normalizedTarget == normalizedArtistName) continue;
          if (normalizedTarget.contains(normalizedArtistName)) continue;
          
          relationships.add(ExtractedRelationship(
            sourceArtist: artistName,
            targetArtist: targetArtist,
            type: _inferRelationshipType(pattern.pattern),
            confidence: 0.7,
            evidenceText: match.group(0) ?? '',
            extractionDate: DateTime.now(),
            metadata: {
              'sourceUrl': source.url,
              'sourceType': source.type.toString(),
              'matchPattern': pattern.pattern,
            },
          ));
        }
      }
    }
    
    return relationships;
  }
  
  /// Extract relationships from MusicBrainz content
  static List<ExtractedRelationship> _extractFromMusicBrainz({
    required String artistName,
    required String content,
    required EvidenceSource source,
  }) {
    final relationships = <ExtractedRelationship>[];
    final lines = content.split('\n');
    final normalizedArtistName = artistName.toLowerCase().trim();
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // MusicBrainz relation format: "type: target artist"
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        final type = trimmed.substring(0, colonIndex).trim();
        final target = trimmed.substring(colonIndex + 1).trim();
        final normalizedTarget = target.toLowerCase();
        
        if (target.isEmpty) continue;
        if (normalizedTarget == normalizedArtistName) continue;
        if (normalizedTarget.contains(normalizedArtistName)) continue;
        
        final relationshipType = _mapMusicBrainzRelationType(type);
        if (relationshipType == RelationshipType.collaboration) continue;
        
        relationships.add(ExtractedRelationship(
          sourceArtist: artistName,
          targetArtist: target,
          type: relationshipType,
          confidence: 0.8,
          evidenceText: trimmed,
          extractionDate: DateTime.now(),
          metadata: {
            'sourceUrl': source.url,
            'sourceType': source.type.toString(),
            'mbRelationType': type,
          },
        ));
      }
    }
    
    return relationships;
  }
  
  /// Extract relationships from YouTube Music content
  static List<ExtractedRelationship> _extractFromYoutubeMusic({
    required String artistName,
    required String content,
    required EvidenceSource source,
  }) {
    final relationships = <ExtractedRelationship>[];
    
    final name = source.metadata['name'] as String? ?? '';
    if (name.isEmpty) return relationships;
    
    final normalizedName = name.toLowerCase().trim();
    final normalizedArtistName = artistName.toLowerCase().trim();
    
    // Skip the primary artist match; we only want related artists from search results.
    if (normalizedName == normalizedArtistName) return relationships;
    if (normalizedName.contains(normalizedArtistName)) return relationships;
    
    final provider = source.metadata['provider'] as String? ?? 'youtube_music';
    final relationType = source.metadata['relationType'] as String? ?? '';
    
    // Track sources are the artist's own tracks, not influences
    if (provider == 'youtube_music_track') {
      return relationships;
    }
    
    // YouTube Music search results surface artists the platform associates with the
    // queried artist. For fingerprint purposes, treat these as influence signals
    // rather than collaborations or band membership.
    final type = relationType == 'search_result'
        ? RelationshipType.explicitInfluence
        : RelationshipType.admiration;
    
    relationships.add(ExtractedRelationship(
      sourceArtist: artistName,
      targetArtist: name,
      type: type,
      confidence: relationType == 'search_result' ? 0.7 : 0.6,
      evidenceText: content,
      extractionDate: DateTime.now(),
      metadata: {
        'sourceUrl': source.url,
        'sourceType': source.type.toString(),
        'ytRelationType': relationType,
      },
    ));
    
    return relationships;
  }
  
  /// Generic keyword matching for unknown providers
  static List<ExtractedRelationship> _extractByKeywordMatching({
    required String artistName,
    required String content,
    required EvidenceSource source,
  }) {
    final relationships = <ExtractedRelationship>[];
    final lowerContent = content.toLowerCase();
    
    final influenceKeywords = [
      'influenced by', 'inspired by', 'influence',
      'favorite artist', 'favorite band', 'favorite album',
      'listened to', 'listening to', 'recommended', 'recommend',
      'collaborated', 'worked with', 'featured',
    ];
    
    for (final keyword in influenceKeywords) {
      final index = lowerContent.indexOf(keyword);
      if (index >= 0) {
        // Extract surrounding context
        final start = index > 50 ? index - 50 : 0;
        final end = index + keyword.length + 100;
        final context = content.substring(start, end).trim();
        
        // Try to extract artist name from context
        final potentialArtist = _extractArtistFromContext(context, artistName);
        if (potentialArtist != null) {
          relationships.add(ExtractedRelationship(
            sourceArtist: artistName,
            targetArtist: potentialArtist,
            type: _inferRelationshipType(keyword),
            confidence: 0.5,
            evidenceText: context,
            extractionDate: DateTime.now(),
            metadata: {
              'sourceUrl': source.url,
              'sourceType': source.type.toString(),
              'keyword': keyword,
            },
          ));
        }
      }
    }
    
    return relationships;
  }
  
  /// Try to extract an artist name from text context
  static String? _extractArtistFromContext(String context, String originalArtist) {
    // Look for capitalized words that might be artist names
    // This is a simple heuristic - real implementation would use NER
    final words = context.split(RegExp(r'\s+'));
    final candidates = <String>[];
    
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (_looksLikeArtistName(word) && word.toLowerCase() != originalArtist.toLowerCase()) {
        // Check if next words are also capitalized (multi-word artist name)
        final nameParts = <String>[word];
        for (var j = i + 1; j < words.length && j < i + 4; j++) {
          if (_looksLikeArtistName(words[j])) {
            nameParts.add(words[j]);
          } else {
            break;
          }
        }
        candidates.add(nameParts.join(' '));
      }
    }
    
    return candidates.isNotEmpty ? candidates.first : null;
  }
  
  /// Check if a word looks like an artist name
  static bool _looksLikeArtistName(String word) {
    if (word.length < 2) return false;
    if (word.length > 30) return false;
    
    // Must start with capital letter
    if (!word[0].contains(RegExp(r'[A-Z]'))) return false;
    
    // Filter out common non-artist words
    final stopWords = <String>{
      'The', 'And', 'But', 'For', 'Not', 'You', 'All', 'Any', 'Can', 'Was',
      'Were', 'Has', 'Had', 'Did', 'Does', 'Do', 'Is', 'Are', 'Be', 'Been',
      'Being', 'Have', 'He', 'She', 'It', 'They', 'We', 'Us', 'Our', 'Their',
      'His', 'Her', 'Its', 'My', 'Your', 'This', 'That', 'These', 'Those',
      'What', 'When', 'Where', 'Who', 'Why', 'How', 'Which', 'If', 'Or',
      'Because', 'Since', 'While', 'Although', 'Though', 'However',
    };
    
    if (stopWords.contains(word)) return false;
    
    return true;
  }
  
  /// Infer relationship type from keyword
  static RelationshipType _inferRelationshipType(String keyword) {
    final lowerKeyword = keyword.toLowerCase();
    
    if (lowerKeyword.contains('influenc') || lowerKeyword.contains('inspir')) {
      return RelationshipType.explicitInfluence;
    }
    if (lowerKeyword.contains('favorite')) {
      return RelationshipType.favoriteArtist;
    }
    if (lowerKeyword.contains('listen')) {
      return RelationshipType.currentListening;
    }
    if (lowerKeyword.contains('recommend')) {
      return RelationshipType.recommendation;
    }
    if (lowerKeyword.contains('collaborat') || lowerKeyword.contains('work with') || lowerKeyword.contains('featured')) {
      return RelationshipType.collaboration;
    }
    
    return RelationshipType.admiration;
  }
  
  /// Map MusicBrainz relation type to RelationshipType
  static RelationshipType _mapMusicBrainzRelationType(String mbType) {
    final lowerType = mbType.toLowerCase();
    
    if (lowerType.contains('influenced by')) {
      return RelationshipType.explicitInfluence;
    }
    if (lowerType == 'follows' || lowerType.startsWith('follows ')) {
      return RelationshipType.currentListening;
    }
    
    return RelationshipType.collaboration;
  }
}
