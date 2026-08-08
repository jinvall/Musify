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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/services/artist_service.dart';
import 'package:musify/widgets/custom_search_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

class FingerprintSearchPage extends StatefulWidget {
  const FingerprintSearchPage({super.key});

  @override
  State<FingerprintSearchPage> createState() => _FingerprintSearchPageState();
}

class _FingerprintSearchPageState extends State<FingerprintSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Fingerprint Search'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              labelText: 'Enter artist name to generate fingerprint...',
              onSubmitted: _performSearch,
            ),
          ),
          _buildSearchResults(),
          const MiniPlayerBottomSpace(),
        ],
      ),
    );
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      // Search for verified artists using existing service
      final artists = await searchVerifiedArtists(query, limit: 10);
      
      setState(() {
        _searchResults = artists;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Expanded(
        child: Center(
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
                'No artists found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Expanded(
        child: Center(
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
                'Artist Fingerprint Search',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Discover what music artists actually listen to',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Enter an artist name to generate their musical fingerprint\n'
                'based on interviews, autobiographies, and documented influences',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final artist = _searchResults[index];
          return _buildArtistResult(artist);
        },
      ),
    );
  }

  Widget _buildArtistResult(Map<String, dynamic> artist) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: artist['image'] != null
            ? CircleAvatar(
                backgroundImage: NetworkImage(artist['image']),
                radius: 20,
              )
            : const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(FluentIcons.person_24_regular, color: Colors.white),
                radius: 20,
              ),
        title: Text(
          artist['title']?.toString() ?? 'Unknown Artist',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        subtitle: Text(
          'Verified Artist',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(FluentIcons.fingerprint_24_regular),
          onPressed: () {
            _navigateToFingerprint(artist);
          },
        ),
        onTap: () {
          _navigateToFingerprint(artist);
        },
      ),
    );
  }

  void _navigateToFingerprint(Map<String, dynamic> artist) {
    final artistName = artist['title']?.toString() ?? 'Unknown Artist';
    context.go('/influences/artist/$artistName');
  }
}
