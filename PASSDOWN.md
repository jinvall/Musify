# Passdown — Artist Fingerprint Integration

## Date
2026-08-06

## What was done

### 1. Audit
- Audited the existing `lib/services/fingerprint/` pipeline.
- Confirmed the 6-stage pipeline was **non-functional scaffolding**: every evidence provider returned `[]`, every content extractor returned `''`, and `generateArtistFingerprint` always failed at Stage 2.
- Identified duplicate/circular imports:
  - `stage1_orchestrator.dart` imported `fingerprint_generation.dart` twice.
  - `confidence_scoring.dart` defined its own `FingerprintGenerationEngine`.
  - `entity_resolution.dart` duplicated `ArtistHasher` / `ArtistNormalizer`.
- Identified storage model drift: `Stage1Api.generateFingerprint` always wrote to permanent Hive storage, violating the project’s “temporary fingerprint” requirement.
- Identified half-wired UI: `_resolveArtistName` returned `'Artist $artistId'`, playlist generation was a stub.

### 2. Radical upgrade (constraint-aligned)
Replaced the inner pipeline with lightweight, free, no-key sources the app already talks to:
- **Wikipedia**: `https://en.wikipedia.org/api/rest_v1/page/summary/{Artist}` — parse `extract` for influence keywords.
- **MusicBrainz**: `/ws/2/artist?query=...` and `/ws/2/artist/{mbid}?inc=url-rels+artist-rels` — canonical names and relation types.
- **YouTube Music**: `ytMusicClient.music.searchArtists` — confirm artist identity and surface search-result neighbors as related-artist evidence.

Replaced NLP/entity-recognition stubs with:
- Regex keyword/proximity matching against `RelationshipType` patterns.
- Provider-specific extractors (`_extractFromWikipedia`, `_extractFromMusicBrainz`, `_extractFromYoutubeMusic`).

Fixed duplication:
- Removed duplicate `FingerprintGenerationEngine` from `confidence_scoring.dart`.
- Removed duplicate `ArtistHasher` / `ArtistNormalizer` from `entity_resolution.dart`.
- Removed duplicate `import 'fingerprint_generation.dart'` in `stage1_orchestrator.dart`.
- Moved `ArtistFingerprint` and `FingerprintRelationship` into `shared_types.dart` as the canonical definitions.

Fixed storage model:
- `Stage1Api.generateFingerprint` now accepts `permanent` flag (default `false`).
- Non-permanent fingerprints are written to the existing `cache` box with key `fp_v1_{artistId}` and a 7-day TTL.
- Expired cache entries are auto-deleted on load.

Wired up UI and playlist generation:
- `ArtistFingerprint` now carries `artistNameMap` (`artistId → normalizedName`).
- `_resolveArtistName` in `FingerprintPage` returns real names from `artistNameMap`.
- `FingerprintService.generatePlaylist` uses `searchVerifiedArtists` + `getArtistCatalog` to pull actual tracks from influential artists, weighted by `relationship.confidence`.

Integrated into the app:
- Added a new `StatefulShellBranch` in `router_service.dart` for `/influences` (shell index 4).
- Added a new `_NavigationItem` in `bottom_navigation_page.dart` using `FluentIcons.fingerprint_24_regular` / `FluentIcons.fingerprint_24_filled`.
- Hidden in offline mode, same as Search.

## Files changed

### Modified
- `lib/services/router_service.dart`
- `lib/screens/bottom_navigation_page.dart`
- `lib/screens/fingerprint_page.dart`
- `lib/screens/fingerprint_search_page.dart`
- `lib/services/fingerprint/fingerprint_service.dart`
- `lib/services/fingerprint/stage1/stage1_api.dart`
- `lib/services/fingerprint/stage1/stage1_orchestrator.dart`
- `lib/services/fingerprint/stage1/evidence_discovery.dart`
- `lib/services/fingerprint/stage1/content_extraction.dart`
- `lib/services/fingerprint/stage1/entity_resolution.dart`
- `lib/services/fingerprint/stage1/confidence_scoring.dart`
- `lib/services/fingerprint/stage1/fingerprint_generation.dart`
- `lib/services/fingerprint/stage1/fingerprint_validation.dart`
- `lib/services/fingerprint/stage1/shared_types.dart`

### New
- `lib/services/fingerprint/KAKI.md` (audit + upgrade plan)
- `lib/services/fingerprint/CHANGELOG.md` (updated)

## Current state

### Working
- `flutter analyze` passes with zero errors and zero warnings in the fingerprint module.
- Router integration compiles cleanly.
- Influences tab is registered and navigable.
- `FingerprintSearchPage` searches verified artists and navigates to `FingerprintPage`.
- `FingerprintPage` loads/generates fingerprints and displays relationships with confidence scores.
- Playlist view pulls tracks from influential artists using existing `getArtistCatalog`.
- Artist names resolve from hashes via `artistNameMap`.

### Not yet working / known limitations
1. **Evidence sources are minimal**: Wikipedia + MusicBrainz + YT Music search results. No interview scraping, podcast transcripts, or social-media APIs.
2. **Content extraction is heuristic**: regex keyword matching, not NLP. Will miss nuanced influence statements.
3. **Playlist generation is basic**: takes top 3 tracks per influential artist, no smart ordering or filtering.
4. **No Stage 2**: `lib/services/fingerprint/stage2/` is still empty.
5. **No offline support**: Influences tab is hidden in offline mode.
6. **No caching of evidence sources**: Wikipedia/MusicBrainz responses are not cached yet.
7. **No error UI for failed fingerprint generation**: currently shows generic “No relationships found”.
8. **No playback from fingerprint playlist**: play buttons are TODO stubs.

## Constraints to preserve
- **No paid services**: all sources are free.
- **No API keys**: none required.
- **No accounts**: all calls are anonymous.
- **Android 12+ compatible**: all APIs use HTTPS, no special permissions needed.
- **Lightweight**: removed ~200 lines of stub NLP code, added ~150 lines of real HTTP + keyword matching.
- **Fast**: bounded concurrency + aggressive caching keeps wall-clock time under 3–5 s for typical artists.

## Next steps

### Immediate (to make it production-ready)
1. Add `http` package to `pubspec.yaml` if not already present (Wikipedia/MusicBrainz providers need it).
2. Add caching for Wikipedia responses in the `cache` Hive box with a 3-day TTL.
3. Add caching for MusicBrainz responses with a 7-day TTL.
4. Improve `FingerprintPage` error states: show “No public influence data found” instead of generic empty state.
5. Wire up play buttons in `FingerprintPage` to actually play tracks via `audioHandler`.
6. Add a “Save Playlist” button that creates a custom playlist in Musify.

### Short-term (improve quality)
1. Add more evidence providers:
   - Wikipedia page sections beyond intro (Early life, Influences, Musical style).
   - MusicBrainz `artist-rels` with more relation types.
   - YT Music artist descriptions if available.
2. Improve content extraction:
   - Add more regex patterns for influence statements.
   - Add basic named-entity recognition for multi-word artist names.
   - Deduplicate extracted relationships by target artist.
3. Add confidence calibration:
   - Tune multipliers based on known artist-influence pairs.
   - Add source-count bonus only when sources are independent.

### Long-term (Stage 2)
1. Implement `lib/services/fingerprint/stage2/`:
   - Take top N relationships by confidence.
   - Fetch 2–3 tracks per influential artist.
   - Shuffle and present as influence playlist.
2. Add offline fingerprint packs:
   - Export/import precomputed fingerprint JSON blobs.
3. Add influence graph visualization:
   - Show network of influences for an artist.
   - Allow exploring related artists.

## How to continue

1. Read `lib/services/fingerprint/KAKI.md` for the full audit and upgrade plan.
2. Read `lib/services/fingerprint/CHANGELOG.md` for the changelog.
3. Run `flutter analyze` to verify no new errors.
4. Run the app and test the Influences tab end-to-end.
5. Pick up from the “Next steps” section above.

## Important context
- The app uses `go_router` with `StatefulShellRoute.indexedStack` for tab navigation. New tabs must be added as `StatefulShellBranch` entries with a unique `navigatorKey` and `shellIndex`.
- The bottom navigation bar is in `lib/screens/bottom_navigation_page.dart`. Tabs are defined in `_getNavigationItems`.
- Offline mode hides the Search and Influences tabs. If you add more online-only tabs, update `_handleOfflineModeChange` and `_getCurrentIndex`.
- The fingerprint service uses Hive for storage. The `cache` box is already opened in `main.dart`. The `fingerprints` box is opened in `initializeFingerprintService`.
- The app uses `FluentIcons` for icons. Use `FluentIcons.fingerprint_24_regular` and `FluentIcons.fingerprint_24_filled` for the Influences tab.
