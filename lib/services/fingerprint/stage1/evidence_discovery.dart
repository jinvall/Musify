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
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/main.dart' show logger;
import 'package:musify/services/artist_service.dart';

import 'package:musify/services/fingerprint/stage1/shared_types.dart';

/// Evidence Discovery Engine - Stage 1 Core Component
/// 
/// Discovers authoritative public sources containing documented musical relationships.
/// Operates with zero-garbage architecture: temporary data discarded after processing.

class EvidenceDiscoveryEngine {
  static final List<EvidenceProvider> _providers = [
    WikipediaEvidenceProvider(),
    MusicBrainzEvidenceProvider(),
    YoutubeMusicEvidenceProvider(),
  ];

  /// Discover evidence sources for a given artist
  static Future<List<EvidenceSource>> discoverEvidence(String artistName) async {
    final sources = <EvidenceSource>[];
    final discoveryTasks = <Future<List<EvidenceSource>>>[];

    // Parallel discovery across all providers
    for (final provider in _providers) {
      discoveryTasks.add(provider.discoverSources(artistName));
    }
    
    // Add web scraping provider if enabled
    if (WebScrapeEvidenceProvider.enabled) {
      discoveryTasks.add(WebScrapeEvidenceProvider().discoverSources(artistName));
    }

    try {
      final results = await Future.wait(discoveryTasks);
      for (final result in results) {
        sources.addAll(result);
      }
    } catch (e, stackTrace) {
      logger.log('Error during evidence discovery for $artistName', 
                error: e, stackTrace: stackTrace);
    }

    // Deduplicate sources by hash
    final seenHashes = <String>{};
    return sources.where((source) => seenHashes.add(_generateSourceHash(source))).toList();
  }

  /// Filter sources by credibility threshold
  static List<EvidenceSource> filterByCredibility(
    List<EvidenceSource> sources, 
    double minCredibility
  ) {
    return sources.where((source) => source.credibilityWeight >= minCredibility).toList();
  }

  /// Sort sources by recency and credibility
  static List<EvidenceSource> prioritizeSources(List<EvidenceSource> sources) {
    return sources
      ..sort((a, b) {
        final dateComparison = b.publishedDate.compareTo(a.publishedDate);
        if (dateComparison != 0) return dateComparison;
        return b.credibilityWeight.compareTo(a.credibilityWeight);
      });
  }

  static String _generateSourceHash(EvidenceSource source) {
    final data = '${source.type}:${source.url}:${source.publishedDate.millisecondsSinceEpoch}';
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString();
  }

  static Future<Box> _getCacheBox() async {
    if (Hive.isBoxOpen('cache')) {
      return Hive.box('cache');
    }
    return Hive.openBox('cache');
  }

  static Future<T?> _getCached<T>(String key, Duration ttl) async {
    try {
      final box = await _getCacheBox();
      final cached = box.get(key);
      if (cached is Map) {
        final cachedAt = cached['cachedAt'] as DateTime?;
        if (cachedAt != null && DateTime.now().difference(cachedAt) < ttl) {
          return cached['data'] as T;
        }
      }
    } catch (e) {
      logger.log('Cache read error for $key', error: e);
    }
    return null;
  }

  static Future<void> _setCache<T>(String key, T data) async {
    try {
      final box = await _getCacheBox();
      await box.put(key, {'data': data, 'cachedAt': DateTime.now()});
    } catch (e) {
      logger.log('Cache write error for $key', error: e);
    }
  }
  
  static Future<Set<String>> fetchAssociatedActs(String artistName) async {
    final associatedActs = <String>{};
    final normalizedName = artistName.replaceAll(' ', '_');
    final cacheKey = 'fp_wiki_associated_acts_$normalizedName';
    
    try {
      // Check cache first
      final cached = await _getCached<Map<String, dynamic>>(cacheKey, const Duration(days: 7));
      if (cached != null) {
        final acts = cached['acts'] as List<dynamic>? ?? [];
        return acts.cast<String>().toSet();
      }
      
      final uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php'
        '?action=query'
        '&prop=revisions'
        '&rvprop=content'
        '&format=json'
        '&titles=$normalizedName'
        '&rvslots=main',
      );
      
      final response = await http.get(uri, headers: {'User-Agent': 'Musify/1.0'}).timeout(
        const Duration(seconds: 8),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pages = data['query']?['pages'] as Map<String, dynamic>? ?? {};
        
        for (final page in pages.values) {
          final pageData = page as Map<String, dynamic>;
          final revisions = pageData['revisions'] as List<dynamic>? ?? [];
          
          if (revisions.isEmpty) continue;
          
          final firstRevision = revisions.first as Map<String, dynamic>;
          final content = firstRevision['slots']?['main']?['*'] as String? ?? '';
          
          if (content.isEmpty) continue;
          
          // Extract infobox
          final infoboxMatch = RegExp(r'\{\{Infobox[^}]+', caseSensitive: false).firstMatch(content);
          if (infoboxMatch == null) continue;
          
          final infobox = infoboxMatch.group(0) ?? '';
          
          // Extract Associated_acts field
          final associatedActsMatch = RegExp(
            r'[|]\s*Associated_acts\s*=\s*([^\n]+)',
            caseSensitive: false,
          ).firstMatch(infobox);
          
          if (associatedActsMatch != null) {
            final actsText = associatedActsMatch.group(1)?.trim() ?? '';
            
            // Parse wiki-linked acts: [[Act Name]] or [[Act Name|Display Name]]
            final linkPattern = RegExp(r'\[\[([^|\]]+)(?:\|[^\]]+)?\]\]');
            final linkMatches = linkPattern.allMatches(actsText);
            
            for (final match in linkMatches) {
              final actName = match.group(1)?.trim() ?? '';
              if (actName.isNotEmpty) {
                associatedActs.add(actName);
              }
            }
            
            // Also parse plain text entries separated by commas or line breaks
            final plainText = actsText.replaceAll(RegExp(r'\[\[[^\]]+\]\]'), '');
            final entries = plainText.split(RegExp(r'[,;\n]+'));
            
            for (final entry in entries) {
              final actName = entry.trim();
              if (actName.isNotEmpty && !actName.startsWith('[') && !actName.endsWith(']')) {
                associatedActs.add(actName);
              }
            }
          }
        }
        
        // Cache the result
        await _setCache(cacheKey, {
          'acts': associatedActs.toList(),
        });
      }
    } catch (e, stackTrace) {
      logger.log('Error fetching Wikipedia associated acts for $artistName', 
                  error: e, stackTrace: stackTrace);
    }
    
    return associatedActs;
  }
}

/// Base class for evidence providers
abstract class EvidenceProvider {
  EvidenceSourceType get type;
  double get baseCredibility;
  
  Future<List<EvidenceSource>> discoverSources(String artistName);
  Future<String> extractContent(EvidenceSource source);
}

/// Wikipedia evidence provider - free, no key, lightweight
class WikipediaEvidenceProvider implements EvidenceProvider {
  @override
  EvidenceSourceType get type => EvidenceSourceType.article;
  
  @override
  double get baseCredibility => 0.8;

  @override
  Future<List<EvidenceSource>> discoverSources(String artistName) async {
    final sources = <EvidenceSource>[];
    
    try {
      final normalizedName = artistName.replaceAll(' ', '_');
      final cacheKey = 'fp_wiki_$normalizedName';
      final cachedData = await EvidenceDiscoveryEngine._getCached<Map<String, dynamic>>(cacheKey, const Duration(days: 3));
      
      String extract;
      String title;
      String url;
      
      if (cachedData != null) {
        extract = cachedData['extract'] as String? ?? '';
        title = cachedData['title'] as String? ?? artistName;
        url = cachedData['url'] as String? ?? '';
      } else {
        final uri = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$normalizedName');
        
        final response = await http.get(uri, headers: {'User-Agent': 'Musify/1.0'}).timeout(
          const Duration(seconds: 8),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          extract = data['extract'] as String? ?? '';
          title = data['title'] as String? ?? artistName;
          url = data['content_urls']?['desktop']?['page'] as String? ?? uri.toString();
          
          await EvidenceDiscoveryEngine._setCache(cacheKey, {
            'extract': extract,
            'title': title,
            'url': url,
          });
        } else {
          return sources;
        }
      }
      
      if (extract.isNotEmpty) {
        sources.add(EvidenceSource(
          id: _generateId('wikipedia', title),
          type: type,
          url: url,
          title: 'Wikipedia: $title',
          publishedDate: DateTime.now(),
          credibilityWeight: baseCredibility,
          category: EvidenceSourceCategory.web,
          subCategory: EvidenceSourceSubCategory.musicRecommendations,
          metadata: {
            'extract': extract,
            'provider': 'wikipedia',
          },
        ));
      }
      
      // Also fetch the full page to extract the Influences section directly
      final influences = await _fetchWikipediaInfluences(normalizedName);
      if (influences.isNotEmpty) {
        sources.add(EvidenceSource(
          id: _generateId('wikipedia_influences', title),
          type: type,
          url: '$url#Influences',
          title: 'Wikipedia Influences: $title',
          publishedDate: DateTime.now(),
          credibilityWeight: baseCredibility,
          category: EvidenceSourceCategory.interviews,
          subCategory: EvidenceSourceSubCategory.whatAreYouListeningTo,
          metadata: {
            'extract': influences.join('\n'),
            'provider': 'wikipedia_influences',
            'influences': influences,
          },
        ));
      }
    } catch (e, stackTrace) {
      logger.log('Wikipedia discovery failed for $artistName', 
                error: e, stackTrace: stackTrace);
    }
    
    return sources;
  }
  
  static Future<List<String>> _fetchWikipediaInfluences(String normalizedName) async {
    final influences = <String>[];
    
    try {
      final cacheKey = 'fp_wiki_influences_$normalizedName';
      final cached = await EvidenceDiscoveryEngine._getCached<List<String>>(cacheKey, const Duration(days: 7));
      if (cached != null) return cached;
      
      final uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php'
        '?action=query'
        '&prop=extracts'
        '&exintro=false'
        '&explaintext=true'
        '&format=json'
        '&titles=$normalizedName',
      );
      
      final response = await http.get(uri, headers: {'User-Agent': 'Musify/1.0'}).timeout(
        const Duration(seconds: 8),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pages = data['query']?['pages'] as Map<String, dynamic>? ?? {};
        
        for (final page in pages.values) {
          final pageData = page as Map<String, dynamic>;
          final extract = pageData['extract'] as String? ?? '';
          
          if (extract.isEmpty) continue;
          
          // Look for influence-related sections
          final sections = _splitWikiSections(extract);
          
          for (final entry in sections.entries) {
            final sectionName = entry.key;
            if (_isInfluenceSection(sectionName)) {
              influences.addAll(_extractArtistsFromText(entry.value));
            }
          }
        }
      }
      
      if (influences.isNotEmpty) {
        await EvidenceDiscoveryEngine._setCache(cacheKey, influences);
      }
    } catch (e, stackTrace) {
      logger.log('Error fetching Wikipedia influences for $normalizedName', 
                  error: e, stackTrace: stackTrace);
    }
    
    return influences;
  }
  
  static Map<String, String> _splitWikiSections(String extract) {
    final sections = <String, String>{};
    final lines = extract.split('\n');
    String currentSection = 'intro';
    StringBuffer currentContent = StringBuffer();
    
    for (final line in lines) {
      if (line.startsWith('== ') && line.endsWith(' ==')) {
        sections[currentSection] = currentContent.toString().trim();
        currentSection = line.replaceAll(RegExp(r'^=+\s*|\s*=+$'), '').trim();
        currentContent = StringBuffer();
      } else {
        currentContent.writeln(line);
      }
    }
    
    sections[currentSection] = currentContent.toString().trim();
    return sections;
  }
  
  static bool _isInfluenceSection(String sectionName) {
    const influenceKeywords = [
      'influence',
      'influences',
      'artistry',
      'musical style',
      'style',
      'sound',
      'background',
      'early life',
    ];
    
    return influenceKeywords.any((keyword) => sectionName.contains(keyword));
  }
  
  static List<String> _extractArtistsFromText(String text) {
    final artists = <String>{};
    
    // Look for common influence patterns
    final patterns = [
      RegExp(r'influenced by\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'inspired by\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'cited\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+as\s+an\s+influence', caseSensitive: false),
      RegExp(r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+was\s+a\s+(?:major\s+)?influence', caseSensitive: false),
      RegExp(r'listened to\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'favorite\s+(?:artist|band|album|song)\s+(?:is|was)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final artist = match.group(1)?.trim() ?? '';
          if (artist.isNotEmpty && artist.length > 2) {
            artists.add(artist);
          }
        }
      }
    }
    
    return artists.toList();
  }
  
  @override
  Future<String> extractContent(EvidenceSource source) async {
    return source.metadata['extract'] as String? ?? '';
  }
  
  static String _generateId(String provider, String title) {
    final bytes = utf8.encode('$provider:$title');
    final digest = sha256.convert(bytes);
    return digest.bytes.take(4).map((b) => b.toRadixString(16).padLeft(2)).join('');
  }
}

/// MusicBrainz evidence provider - free, no key, low bandwidth
class MusicBrainzEvidenceProvider implements EvidenceProvider {
  @override
  EvidenceSourceType get type => EvidenceSourceType.article;
  
  @override
  double get baseCredibility => 0.75;

  @override
  Future<List<EvidenceSource>> discoverSources(String artistName) async {
    final sources = <EvidenceSource>[];
    
    try {
      final query = Uri.encodeComponent(artistName);
      final cacheKey = 'fp_mb_search_$query';
      final cachedData = await EvidenceDiscoveryEngine._getCached<List<dynamic>>(cacheKey, const Duration(days: 7));
      
      List<dynamic> artists;
      if (cachedData != null) {
        artists = cachedData;
      } else {
        final uri = Uri.parse('https://musicbrainz.org/ws/2/artist?query=$query&fmt=json&limit=5');
        
        final response = await http.get(uri, headers: {'User-Agent': 'Musify/1.0 (contact@example.com)'}).timeout(
          const Duration(seconds: 8),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          artists = data['artists'] as List<dynamic>? ?? [];
          await EvidenceDiscoveryEngine._setCache(cacheKey, artists);
        } else {
          return sources;
        }
      }
      
      for (final artist in artists.take(3)) {
        final artistData = artist as Map<String, dynamic>;
        final name = artistData['name'] as String? ?? artistName;
        final id = artistData['id'] as String? ?? '';
        final disambiguation = artistData['disambiguation'] as String? ?? '';
        
        if (id.isNotEmpty) {
          sources.add(EvidenceSource(
            id: 'mb_$id',
            type: type,
            url: 'https://musicbrainz.org/artist/$id',
            title: 'MusicBrainz: $name${disambiguation.isNotEmpty ? " ($disambiguation)" : ""}',
            publishedDate: DateTime.now(),
            credibilityWeight: baseCredibility,
            category: EvidenceSourceCategory.web,
            subCategory: EvidenceSourceSubCategory.favoriteArtists,
            metadata: {
              'mbid': id,
              'name': name,
              'disambiguation': disambiguation,
              'provider': 'musicbrainz',
            },
          ));
        }
      }
    } catch (e, stackTrace) {
      logger.log('MusicBrainz discovery failed for $artistName', 
                error: e, stackTrace: stackTrace);
    }
    
    return sources;
  }

  @override
  Future<String> extractContent(EvidenceSource source) async {
    final mbid = source.metadata['mbid'] as String? ?? '';
    if (mbid.isEmpty) return '';
    
    try {
      final cacheKey = 'fp_mb_rels_$mbid';
      final cachedContent = await EvidenceDiscoveryEngine._getCached<String>(cacheKey, const Duration(days: 7));
      
      if (cachedContent != null) {
        return cachedContent;
      }
      
      final uri = Uri.parse('https://musicbrainz.org/ws/2/artist/$mbid?fmt=json&inc=url-rels+artist-rels');
      
      final response = await http.get(uri, headers: {'User-Agent': 'Musify/1.0 (contact@example.com)'}).timeout(
        const Duration(seconds: 8),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final relations = data['relations'] as List<dynamic>? ?? [];
        
        final buffer = StringBuffer();
        for (final rel in relations) {
          final relation = rel as Map<String, dynamic>;
          final type = relation['type'] as String? ?? '';
          final target = relation['artist']?['name'] as String? ?? '';
          
          if (type.isNotEmpty && target.isNotEmpty) {
            buffer.writeln('$type: $target');
          }
        }
        
        final content = buffer.toString();
        await EvidenceDiscoveryEngine._setCache(cacheKey, content);
        return content;
      }
    } catch (e, stackTrace) {
      logger.log('MusicBrainz content extraction failed for ${source.url}', 
                error: e, stackTrace: stackTrace);
    }
    
    return '';
  }
}

/// YouTube Music evidence provider - uses existing ytMusicClient
class YoutubeMusicEvidenceProvider implements EvidenceProvider {
  @override
  EvidenceSourceType get type => EvidenceSourceType.verifiedPlaylist;
  
  @override
  double get baseCredibility => 0.9;

  @override
  Future<List<EvidenceSource>> discoverSources(String artistName) async {
    final sources = <EvidenceSource>[];
    
    try {
      // Search for the artist to get their channel ID and related artists
      final artists = await ytMusicClient.music
          .searchArtists(artistName)
          .timeout(const Duration(seconds: 10));
      
      if (artists.isNotEmpty) {
        // Use the first verified artist result as primary source
        final artist = artists.first;
        final channelId = artist.id;
        
        sources.add(EvidenceSource(
          id: 'yt_$channelId',
          type: type,
          url: 'https://music.youtube.com/channel/$channelId',
          title: 'YouTube Music: ${artist.name}',
          publishedDate: DateTime.now(),
          credibilityWeight: baseCredibility,
          category: EvidenceSourceCategory.youtube,
          subCategory: EvidenceSourceSubCategory.publicPlaylists,
          metadata: {
            'ytChannelId': channelId,
            'name': artist.name,
            'thumbnailUrl': artist.thumbnailUrl ?? '',
            'provider': 'youtube_music',
          },
        ));
        
        // Try to get artist's top tracks for radio/mix signals
        try {
          final topTracks = await ytMusicClient.music
              .getArtistTopTracks(channelId, author: artist.name, limit: 10)
              .timeout(const Duration(seconds: 10));
          
          for (final track in topTracks.take(5)) {
            sources.add(EvidenceSource(
              id: 'yt_track_${track.id.value}',
              type: type,
              url: 'https://music.youtube.com/watch?v=${track.id.value}',
              title: 'YouTube Music Track: ${track.title}',
              publishedDate: DateTime.now(),
              credibilityWeight: baseCredibility * 0.9,
              category: EvidenceSourceCategory.youtube,
              subCategory: EvidenceSourceSubCategory.publicPlaylists,
              metadata: {
                'ytVideoId': track.id.value,
                'name': artist.name,
                'trackTitle': track.title,
                'provider': 'youtube_music_track',
              },
            ));
          }
        } catch (e) {
          logger.log('Failed to get top tracks for $artistName', error: e);
        }
        
        // Add additional search results as related artist evidence
        for (final relatedArtist in artists.skip(1).take(5)) {
          sources.add(EvidenceSource(
            id: 'yt_${relatedArtist.id}',
            type: type,
            url: 'https://music.youtube.com/channel/${relatedArtist.id}',
            title: 'YouTube Music: ${relatedArtist.name}',
            publishedDate: DateTime.now(),
            credibilityWeight: baseCredibility * 0.8, // Slightly lower for search results
            category: EvidenceSourceCategory.youtube,
            subCategory: EvidenceSourceSubCategory.publicPlaylists,
            metadata: {
              'ytChannelId': relatedArtist.id,
              'name': relatedArtist.name,
              'thumbnailUrl': relatedArtist.thumbnailUrl ?? '',
              'provider': 'youtube_music',
              'relationType': 'search_result',
            },
          ));
        }
      }
    } catch (e, stackTrace) {
      logger.log('YouTube Music discovery failed for $artistName', 
                error: e, stackTrace: stackTrace);
    }
    
    return sources;
  }

  @override
  Future<String> extractContent(EvidenceSource source) async {
    // For YouTube Music, the source itself is the evidence (artist/channel match)
    final ytChannelId = source.metadata['ytChannelId'] as String? ?? '';
    final name = source.metadata['name'] as String? ?? '';
    final relationType = source.metadata['relationType'] as String? ?? 'primary';
    final trackTitle = source.metadata['trackTitle'] as String? ?? '';
    final ytVideoId = source.metadata['ytVideoId'] as String? ?? '';
    
    if (ytChannelId.isNotEmpty && name.isNotEmpty) {
      if (relationType == 'search_result') {
        return 'Related artist found in YouTube Music search: $name ($ytChannelId)';
      }
      if (ytVideoId.isNotEmpty && trackTitle.isNotEmpty) {
        return 'Track by $name on YouTube Music: $trackTitle ($ytVideoId)';
      }
      return 'Artist found on YouTube Music: $name ($ytChannelId)';
    }
    
    return '';
  }
}

/// Web evidence provider - scrapes interview/article pages for influence mentions
class WebScrapeEvidenceProvider implements EvidenceProvider {
  @override
  EvidenceSourceType get type => EvidenceSourceType.interview;
  
  @override
  double get baseCredibility => 0.85;
  
  static bool enabled = false;

  @override
  Future<List<EvidenceSource>> discoverSources(String artistName) async {
    final sources = <EvidenceSource>[];
    
    if (!enabled) return sources;
    
    try {
      final query = Uri.encodeComponent('$artistName interview influences');
      final cacheKey = 'fp_web_$query';
      final cachedData = await EvidenceDiscoveryEngine._getCached<List<dynamic>>(cacheKey, const Duration(days: 7));
      
      List<dynamic> urls;
      if (cachedData != null) {
        urls = cachedData;
      } else {
        // Use a simple search engine query to find relevant pages
        final searchUri = Uri.parse('https://html.duckduckgo.com/html/?q=$query');
        
        final response = await http.get(searchUri, headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; Musify/1.0)',
        }).timeout(const Duration(seconds: 10));
        
        if (response.statusCode != 200) return sources;
        
        urls = _extractUrls(response.body);
        await EvidenceDiscoveryEngine._setCache(cacheKey, urls);
      }
      
      for (final url in urls.take(5)) {
        final content = await _fetchPageContent(url);
        if (content.isEmpty) continue;
        
        sources.add(EvidenceSource(
          id: 'web_${Uri.parse(url).host}_${Uri.parse(url).pathSegments.last}',
          type: type,
          url: url,
          title: 'Web: ${Uri.parse(url).host}',
          publishedDate: DateTime.now(),
          credibilityWeight: baseCredibility,
          category: EvidenceSourceCategory.web,
          subCategory: EvidenceSourceSubCategory.musicRecommendations,
          metadata: {
            'content': content,
            'provider': 'web_scrape',
            'url': url,
          },
        ));
      }
    } catch (e, stackTrace) {
      logger.log('Web scraping discovery failed for $artistName', 
                error: e, stackTrace: stackTrace);
    }
    
    return sources;
  }
  
  static List<String> _extractUrls(String html) {
    final urls = <String>[];
    final regex = RegExp(r'href="(https?://[^"]+)"');
    final matches = regex.allMatches(html);
    
    for (final match in matches) {
      final url = match.group(1) ?? '';
      if (url.isNotEmpty && 
          !url.contains('duckduckgo.com') && 
          !url.contains('google.com') &&
          !url.contains('bing.com')) {
        urls.add(url);
      }
    }
    
    return urls;
  }
  
  static Future<String> _fetchPageContent(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; Musify/1.0)',
      }).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      logger.log('Failed to fetch page content from $url', error: e);
    }
    
    return '';
  }

  @override
  Future<String> extractContent(EvidenceSource source) async {
    return source.metadata['content'] as String? ?? '';
  }
}

/// Evidence source credibility calculator
class CredibilityCalculator {
  static double calculateSourceCredibility(EvidenceSource source) {
    var credibility = _getBaseWeight(source.type);
    
    // Adjust based on publication date
    final daysSincePublication = DateTime.now().difference(source.publishedDate).inDays;
    if (daysSincePublication <= 30) credibility += 0.1;
    else if (daysSincePublication <= 365) credibility += 0.05;
    
    // Adjust based on source metadata
    if (source.metadata['isVerified'] == true) credibility += 0.1;
    if (source.metadata['hasTranscript'] == true) credibility += 0.05;
    if (source.metadata['isOfficial'] == true) credibility += 0.15;
    
    return credibility.clamp(0.0, 1.0);
  }

  static double _getBaseWeight(EvidenceSourceType type) {
    switch (type) {
      case EvidenceSourceType.autobiography:
        return 1;
      case EvidenceSourceType.verifiedPlaylist:
        return 0.95;
      case EvidenceSourceType.interview:
        return 0.9;
      case EvidenceSourceType.documentary:
        return 0.85;
      case EvidenceSourceType.podcast:
        return 0.8;
      case EvidenceSourceType.radioAppearance:
        return 0.75;
      case EvidenceSourceType.article:
        return 0.7;
      case EvidenceSourceType.biography:
        return 0.7;
      case EvidenceSourceType.socialMedia:
        return 0.6;
    }
  }
}
