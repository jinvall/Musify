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
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show logger, audioHandler;
import 'package:musify/services/fingerprint/fingerprint_service.dart';
import 'package:musify/services/fingerprint/stage1/shared_types.dart';
import 'package:musify/services/fingerprint/stage1/evidence_discovery.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/spinner.dart';

class FingerprintPage extends StatefulWidget {
  const FingerprintPage({super.key, required this.artistName});

  final String artistName;

  @override
  State<FingerprintPage> createState() => _FingerprintPageState();
}

class _FingerprintPageState extends State<FingerprintPage> {
  late Future<ArtistFingerprint?> _fingerprintFuture;
  late Future<List<Map<String, dynamic>>> _playlistFuture;
  
  ArtistFingerprint? _currentFingerprint;
  bool _isGenerating = false;
  bool _showPlaylist = false;
  bool _webScrapeEnabled = false;

  @override
  void initState() {
    super.initState();
    _fingerprintFuture = _loadOrGenerateFingerprint();
  }

  Future<ArtistFingerprint?> _loadOrGenerateFingerprint() async {
    try {
      final service = FingerprintService();
      final artistId = FingerprintService.hashArtistName(widget.artistName);
      final cached = await service.loadFingerprint(artistId);
      
      if (cached != null) {
        _currentFingerprint = cached;
        _playlistFuture = service.generatePlaylist(cached);
        return cached;
      }
      
      // Auto-generate fingerprint for non-group artists
      return await _generateFingerprint();
    } catch (e, stackTrace) {
      logger.log('Error loading/generating fingerprint for ${widget.artistName}', 
                error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<ArtistFingerprint?> _generateFingerprint() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final service = FingerprintService();
      final fingerprint = await service.generateFingerprint(widget.artistName);
      
      if (fingerprint != null) {
        _currentFingerprint = fingerprint;
        _playlistFuture = service.generatePlaylist(fingerprint);
      }
      
      setState(() {
        _isGenerating = false;
        _fingerprintFuture = Future.value(fingerprint);
      });
      
      return fingerprint;
    } catch (e, stackTrace) {
      logger.log('Error generating fingerprint for ${widget.artistName}', 
                error: e, stackTrace: stackTrace);
      setState(() {
        _isGenerating = false;
      });
      return null;
    }
  }

  void _togglePlaylistView() {
    setState(() {
      _showPlaylist = !_showPlaylist;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Artist Fingerprint: ${widget.artistName}'),
        actions: [
          if (_currentFingerprint != null)
            IconButton(
              icon: const Icon(FluentIcons.play_24_regular),
              onPressed: _togglePlaylistView,
              tooltip: _showPlaylist ? 'Show Relationships' : 'Show Playlist',
            ),
          IconButton(
            icon: Icon(
              _webScrapeEnabled
                ? FluentIcons.globe_24_filled
                : FluentIcons.globe_24_regular,
            ),
            onPressed: () {
              setState(() {
                _webScrapeEnabled = !_webScrapeEnabled;
                WebScrapeEvidenceProvider.enabled = _webScrapeEnabled;
              });
            },
            tooltip: _webScrapeEnabled
                ? 'Web scraping enabled'
                : 'Enable web scraping',
          ),
        ],
      ),
      body: FutureBuilder<ArtistFingerprint?>(
        future: _fingerprintFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !_isGenerating) {
            return const Center(child: Spinner());
          }

          final fingerprint = snapshot.data;
          
          if (fingerprint == null && !_isGenerating) {
            return _buildGeneratePrompt();
          }

          if (_isGenerating) {
            return _buildGeneratingState();
          }

          if (_showPlaylist) {
            return _buildPlaylistView(fingerprint!);
          }

          return _buildFingerprintView(fingerprint!);
        },
      ),
    );
  }

  Widget _buildGeneratePrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.fingerprint_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No fingerprint found for ${widget.artistName}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Generate a fingerprint by crawling evidence of this artist\'s musical influences',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generateFingerprint,
            icon: const Icon(FluentIcons.fingerprint_24_filled),
            label: const Text('Generate Fingerprint'),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spinner(),
          const SizedBox(height: 16),
          Text(
            'Generating fingerprint for ${widget.artistName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Crawling interviews, articles, and other evidence sources...',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFingerprintView(ArtistFingerprint fingerprint) {
    final relationships = fingerprint.getTopRelationships();
    
    return Column(
      children: [
        _buildFingerprintHeader(fingerprint),
        Expanded(
          child: relationships.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: relationships.length,
                  itemBuilder: (context, index) {
                    final relationship = relationships[index];
                    return _buildRelationshipCard(relationship);
                  },
                ),
        ),
        const MiniPlayerBottomSpace(),
      ],
    );
  }

  Widget _buildFingerprintHeader(ArtistFingerprint fingerprint) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.fingerprint_24_filled,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Artist Fingerprint',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${fingerprint.evidenceCount} evidence sources analyzed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${fingerprint.relationships.length} verified relationships',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Last updated: ${_formatDate(fingerprint.lastUpdated)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _togglePlaylistView,
                icon: const Icon(FluentIcons.music_note_2_24_regular),
                label: const Text('View Influence Playlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelationshipCard(FingerprintRelationship relationship) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getConfidenceColor(relationship.confidence),
          child: Text(
            '${(relationship.confidence * 100).toInt()}%',
            style: const TextStyle(fontSize: 12, color: Colors.black),
          ),
        ),
        title: FutureBuilder<String>(
          future: _resolveArtistName(relationship.artistId),
          builder: (context, snapshot) {
            return Text(
              snapshot.data ?? 'Unknown Artist',
              style: Theme.of(context).textTheme.bodyLarge,
            );
          },
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: relationship.confidence,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getConfidenceColor(relationship.confidence),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${relationship.sources.length} sources • ${_formatDate(relationship.lastUpdated)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        onTap: () async {
          final name = await _resolveArtistName(relationship.artistId);
          if (name.isEmpty || name == 'Unknown Artist') return;
          if (!mounted) return;
          context.go('/influences/artist/$name');
        },
        trailing: IconButton(
          icon: const Icon(FluentIcons.play_24_regular),
          onPressed: () async {
            final name = await _resolveArtistName(relationship.artistId);
            if (name.isEmpty || name == 'Unknown Artist') return;
            if (!mounted) return;
            context.go('/influences/artist/$name');
          },
        ),
      ),
    );
  }

  Widget _buildPlaylistView(ArtistFingerprint fingerprint) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _playlistFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Spinner());
        }

        final playlist = snapshot.data ?? [];
        
        return Column(
          children: [
            _buildPlaylistHeader(fingerprint, playlist.length),
            Expanded(
              child: playlist.isEmpty
                  ? _buildEmptyPlaylistState()
                  : ListView.builder(
                      itemCount: playlist.length,
                      itemBuilder: (context, index) {
                        final track = playlist[index];
                        return _buildPlaylistTrack(track, index);
                      },
                    ),
            ),
            const MiniPlayerBottomSpace(),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistHeader(ArtistFingerprint fingerprint, int trackCount) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.music_note_2_24_filled,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Influence Playlist',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Generated from ${fingerprint.relationships.length} verified influences',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '$trackCount tracks • Weighted by influence confidence',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final tracks = await _playlistFuture;
                  
                  if (tracks.isEmpty) {
                    if (context.mounted) {
                      showToast(context, context.l10n!.noSongsInPlaylist);
                    }
                    return;
                  }
                  
                  final playlistName = 'Influences: ${widget.artistName}';
                  final result = createCustomPlaylist(playlistName, null, context);
                  final playlistId = result.$2;
                  
                  for (final track in tracks) {
                    final ytid = track['ytid']?.toString();
                    if (ytid != null && ytid.isNotEmpty) {
                      addSongInCustomPlaylist(context, playlistId, track);
                    }
                  }
                  
                  if (context.mounted) {
                    showToast(context, result.$1);
                  }
                },
                icon: const Icon(FluentIcons.save_24_regular),
                label: const Text('Save Playlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistTrack(Map<String, dynamic> track, int index) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getWeightColor(track['fingerprintWeight'] as double),
        child: Text(
          '${index + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      title: Text(
        track['title']?.toString() ?? 'Unknown Track',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: FutureBuilder<String>(
        future: _resolveArtistName(track['influentialArtist'] as String),
        builder: (context, snapshot) {
          final artistName = snapshot.data ?? 'Unknown Artist';
          final weight = (track['fingerprintWeight'] as double) * 100;
          return Text(
            'By $artistName • ${weight.toStringAsFixed(0)}% influence',
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
      trailing: IconButton(
        icon: const Icon(FluentIcons.play_24_regular),
        onPressed: () async {
          final ytid = track['ytid']?.toString();
          if (ytid != null && ytid.isNotEmpty) {
            await audioHandler.playSong(track);
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.search_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No public influence data found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This artist\'s influences are not documented in public sources yet. Try a more well-known artist.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaylistState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.music_note_2_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No tracks found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'The influential artists may not have available tracks in the current catalog',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.blue;
    if (confidence >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Color _getWeightColor(double weight) {
    return _getConfidenceColor(weight);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} weeks ago';
    return '${(difference.inDays / 30).floor()} months ago';
  }

  Future<String> _resolveArtistName(String artistId) async {
    if (_currentFingerprint?.artistNameMap == null) {
      return 'Unknown Artist';
    }
    
    final name = _currentFingerprint!.artistNameMap![artistId];
    if (name != null && name.isNotEmpty) {
      return name;
    }
    
    return 'Unknown Artist';
  }
}
