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

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/models/tab_models.dart';
import 'package:musify/services/tab_providers/songsterr_provider.dart';
import 'package:musify/services/tab_providers/tab_provider.dart';

/// Manages tab resolution, caching, and async loading.
///
/// Listens to the current [MediaItem] and automatically resolves
/// the corresponding tab whenever the active track changes.
class TabManager {
  TabManager._internal() {
    _currentQuery = null;
  }

  static final TabManager _instance = TabManager._internal();

  static TabManager get instance => _instance;

  static const _cacheBoxName = 'tabCache';
  static const _memoryCacheSize = 50;
  static const _diskTtl = Duration(days: 30);

  TabProvider? _provider;
  final Map<String, Tab> _memoryCache = <String, Tab>{};
  final List<String> _memoryCacheKeys = <String>[];

  TabSearchQuery? _currentQuery;
  String? _currentTrackId;
  final ValueNotifier<Tab?> currentTab = ValueNotifier<Tab?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _provider = SongsterrProvider();
    _initialized = true;
  }

  /// Call this whenever the active track changes.
  Future<void> onTrackChanged(MediaItem? mediaItem) async {
    if (!_initialized) await initialize();
    if (mediaItem == null) {
      currentTab.value = null;
      error.value = null;
      _currentQuery = null;
      _currentTrackId = null;
      return;
    }

    final trackId = mediaItem.id;
    if (trackId == _currentTrackId) return;

    _currentTrackId = trackId;
    currentTab.value = null;
    error.value = null;

    final query = _buildQuery(mediaItem);
    _currentQuery = query;

    // Try memory cache first.
    final cached = _memoryCache[query.cacheKey];
    if (cached != null) {
      currentTab.value = cached;
      return;
    }

    // Try disk cache.
    final diskCached = await _loadFromDisk(query.cacheKey);
    if (diskCached != null) {
      _memoryCache[query.cacheKey] = diskCached;
      _trimMemoryCache();
      currentTab.value = diskCached;
      return;
    }

    // Async network lookup. Music playback must not wait.
    isLoading.value = true;
    _fireAndForget(_resolveAsync(query));
  }

  void _fireAndForget(Future<void> future) {
    // Intentionally not awaiting background tasks.
    future.catchError((_) {});
  }

  Future<void> _resolveAsync(TabSearchQuery query) async {
    try {
      final provider = _provider;
      if (provider == null) {
        error.value = 'Tab provider not initialized';
        isLoading.value = false;
        return;
      }

      final available = await provider.isAvailable();
      if (!available) {
        error.value = null; // Silently fail; no tabs available.
        isLoading.value = false;
        return;
      }

      final result = await provider.resolve(query);
      if (result == null) {
        error.value = null; // No tabs found.
        isLoading.value = false;
        return;
      }

      final tab = await provider.getTab(result);
      if (tab == null) {
        error.value = null; // Tab unavailable.
        isLoading.value = false;
        return;
      }

      // Cache the result.
      _memoryCache[query.cacheKey] = tab;
      _trimMemoryCache();
      _fireAndForget(_saveToDisk(query.cacheKey, tab));

      // Only update if this is still the current query.
      if (_currentQuery?.cacheKey == query.cacheKey) {
        currentTab.value = tab;
      }
    } catch (e, stackTrace) {
      logger.log('TabManager resolve error', error: e, stackTrace: stackTrace);
      if (_currentQuery?.cacheKey == query.cacheKey) {
        error.value = null; // Don't show errors to user.
      }
    } finally {
      if (_currentQuery?.cacheKey == query.cacheKey) {
        isLoading.value = false;
      }
    }
  }

  TabSearchQuery _buildQuery(MediaItem mediaItem) {
    final extras = mediaItem.extras ?? <String, dynamic>{};
    return TabSearchQuery(
      artist: mediaItem.artist?.toString().trim(),
      title: mediaItem.title.trim(),
      album: mediaItem.album?.toString().trim(),
      duration: mediaItem.duration?.inSeconds,
      musicBrainzRecordingId: extras['musicBrainzRecordingId'] as String?,
      isrc: extras['isrc'] as String?,
      ytid: extras['ytid'] as String?,
      instrument: 'guitar',
    );
  }

  Future<Tab?> _loadFromDisk(String cacheKey) async {
    try {
      final box = await Hive.openBox(_cacheBoxName);
      final raw = box.get(cacheKey);
      if (raw == null) return null;

      final map = raw as Map;
      final timestamp = map['ts'] as int? ?? 0;
      if (timestamp == 0) return null;

      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > _diskTtl.inMilliseconds) {
        await box.delete(cacheKey);
        return null;
      }

      return Tab.fromJson(Map<String, dynamic>.from(map['tab'] as Map));
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveToDisk(String cacheKey, Tab tab) async {
    try {
      final box = await Hive.openBox(_cacheBoxName);
      await box.put(cacheKey, {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'tab': tab.toJson(),
      });
    } catch (e) {
      // Ignore disk write failures.
    }
  }

  void _trimMemoryCache() {
    while (_memoryCacheKeys.length >= _memoryCacheSize) {
      final oldest = _memoryCacheKeys.removeAt(0);
      _memoryCache.remove(oldest);
    }
  }

  /// Manually trigger a refresh for the current track.
  Future<void> refresh() async {
    if (_currentQuery == null) return;
    currentTab.value = null;
    error.value = null;
    await _resolveAsync(_currentQuery!);
  }

  void dispose() {
    currentTab.dispose();
    isLoading.dispose();
    error.dispose();
  }
}
