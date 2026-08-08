import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/widgets/custom_search_bar.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  _DiscoverPageState createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Musify'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomSearchBar(
              controller: _searchController,
              hintText: 'Enter artist name...',
              onSubmitted: _performSearch,
            ),
          ),
          _buildSearchResults(),
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
      // Navigate to the fingerprint search page with the artist name
      if (context.mounted) {
        context.go('/fingerprint/${Uri.encodeComponent(query)}');
      }
    } catch (e, stackTrace) {
      // If navigation fails, try searching for the artist directly
      _searchForArtist(query);
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _searchForArtist(String query) async {
    try {
      // Search for verified artists using the artist service
      final artists = await searchVerifiedArtists(query, limit: 10);
      
      setState(() {
        _searchResults = artists;
      });
    } catch (e) {
      // If search fails, keep empty results
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
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No artists found'),
              SizedBox(height: 8),
              Text('Try a different search term'),
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
              Icon(Icons.disc_full, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Discover Musical Fingerprints',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Find what music shaped your favorite artists',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter an artist name to generate their musical fingerprint\n'
                'based on interviews, autobiographies, and documented influences',
                style: TextStyle(fontSize: 14),
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
                child: Icon(Icons.person, color: Colors.white),
                radius: 20,
              ),
        title: Text(
          artist['title']?.toString() ?? 'Unknown Artist',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          'Verified Artist',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(
          Icons.fingerprint,
          color: Colors.blue,
        ),
        onTap: () {
          _navigateToFingerprint(artist);
        },
      ),
    );
  }

  void _navigateToFingerprint(Map<String, dynamic> artist) {
    final artistName = artist['title']?.toString() ?? 'Unknown Artist';
    if (context.mounted) {
      context.go('/fingerprint/${Uri.encodeComponent(artistName)}');
    }
  }
}