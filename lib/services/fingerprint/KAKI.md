# KAKI — Artist Fingerprint Pipeline: Audit & Radical Upgrade Plan

## Verdict

The current fingerprint implementation is **non-functional scaffolding**. The 6-stage
pipeline (Evidence Discovery → Content Extraction → Entity Resolution →
Confidence Scoring → Fingerprint Generation → Validation) is architecturally
complete but produces **zero usable output**: every provider returns `[]` and
every extractor returns `''`. The surrounding Hive storage, type model, and UI
are already in place and usable. The fastest constraint-aligned upgrade is to
**replace the inner pipeline** with lightweight evidence sources the app already
talks to, while keeping the existing storage and UI contracts intact.

---

## Critical Findings

### 1. Broken Data Flow
- `_extractSourceContent` in `stage1_orchestrator.dart` always returns `''`.
- Every `EvidenceProvider.discoverSources` returns `[]`.
- `ContentExtractionEngine._extractEntities` returns `[]`.
- All pattern matchers (`_matchExplicitInfluencePatterns`, etc.) are stubs.
- **Result**: `generateArtistFingerprint` always fails at Stage 2 with
  `'No relationships extracted from evidence'`.

### 2. Circular / Duplicate Imports
- `stage1_orchestrator.dart` imports `fingerprint_generation.dart` twice.
- `confidence_scoring.dart` defines its own `FingerprintGenerationEngine`,
  duplicating `stage1/fingerprint_generation.dart`.
- `entity_resolution.dart` duplicates `ArtistHasher` / `ArtistNormalizer`
  from `fingerprint_service.dart` and `stage1/fingerprint_generation.dart`.
- **Impact**: Maintenance hazard. Fixes in one copy do not propagate.

### 3. Architecture vs. Constraint Mismatch
- Project overview demands: **no API keys, no accounts, lightweight, fast**.
- Current design assumes web scraping, podcast transcripts, social-media APIs,
  and NLP-style entity recognition. On-device that is heavy, fragile, and slow.
- The “zero-garbage” promise is undermined by the fact that nothing ever gets
  produced, so there is nothing to persist or discard.

### 4. Storage Model Drift
- Project overview explicitly says fingerprints are **temporary** and permanent
  storage is “optional and limited to small caches.”
- `Stage1Api.generateFingerprint` always writes to permanent Hive storage,
  and `FingerprintPage` loads from permanent storage first. The temporary-only
  model is already violated by the current wiring.

### 5. UI Integration Is Half-Wired
- `FingerprintSearchPage` only searches verified artists; it never triggers
  fingerprint generation.
- `FingerprintPage._resolveArtistName` returns `'Artist $artistId'` — hashes
  are never resolved back to names anywhere.
- `generatePlaylist` in `fingerprint_service.dart` is a stub that returns `[]`.
- **Result**: Even if the pipeline worked, users would see relationships but
  no playable tracks, and artist IDs would not resolve to names.

### 6. Unused / Unfinished Stage 2
- `lib/services/fingerprint/stage2/` exists but is empty.
- Playlist generation, track search by influential artist, and catalog
  integration are all TODO stubs.

---

## Radical Upgrade Plan (Constraint-Aligned)

### Guiding Principle
**Use the internet layer the app already trusts (YouTube Music + Wikipedia +
MusicBrainz) instead of inventing a new scraping/NLP layer on-device.**

### Phase 1 — Make It Work (Minimal Delta)

#### A. Eliminate Duplication
- Remove duplicate `FingerprintGenerationEngine` from `confidence_scoring.dart`.
- Remove duplicate `ArtistHasher` / `ArtistNormalizer` from `entity_resolution.dart`.
- Remove duplicate `import 'fingerprint_generation.dart'` in `stage1_orchestrator.dart`.

#### B. Replace Evidence Discovery With Real, Free Sources
Keep the `EvidenceProvider` interface, but implement three lightweight sources:

1. **YouTube Music Artist Page** (already in deps)
   - Use `ytMusicClient.music.searchArtists` + channel metadata to extract
     related artists from the same label/playlist graph.
   - Cost: zero new deps, reuses existing network layer.

2. **Wikipedia Intro / Influences Section** (free, no key)
   - Fetch `https://en.wikipedia.org/api/rest_v1/page/summary/{Artist}`.
   - Parse the `extract` field for influence keywords.
   - Plain HTTP, no auth, tiny payload.

3. **MusicBrainz API** (free, no key)
   - Use `/ws/2/artist?query=...` to resolve canonical names and aliases.
   - Open API, no key, low bandwidth.

Drop the interview, podcast, social-media, and documentary providers for now.
They are the heaviest, most fragile, and least likely to succeed on-device.

#### C. Simplify Content Extraction
- Replace the NLP/entity-recognition stub with **keyword + proximity matching**
  against the `RelationshipType` patterns already defined in `shared_types.dart`.
- For Wikipedia: scan the `extract` text for patterns like
  `"influenced by X"`, `"cited X as an influence"`, `"listened to X"`.
- For YT Music: use related-artist edges directly as `collaboration` or
  `verifiedPlaylist` style evidence with a fixed credibility weight.

#### D. Fix the Storage Model
- Add a `permanent` flag to `Stage1Api.generateFingerprint` (default `false`).
- When `permanent == false`, write to the existing `cache` box with a TTL
  (e.g., 7 days) instead of the `fingerprints` box.
- `FingerprintPage` should call `Stage1Api.generateFingerprint(artistName,
  permanent: false)` and skip permanent storage unless the user explicitly
  saves.

#### E. Implement Artist Name Resolution
- `FingerprintPage._resolveArtistName` must look up the hash in a local
  reverse map built during fingerprint generation.
- Store `artistId → normalizedName` alongside the fingerprint in cache.
- On load, resolve all relationship `artistId`s before rendering.

#### F. Wire Up Playlist Generation
- Replace `_searchTracksByArtist` with a call to existing Musify search:
  `searchVerifiedArtists(targetArtistName, limit: 5)` to confirm the
  influential artist exists, then fetch their catalog via
  `getArtistCatalog` and pick top tracks.
- Weight tracks by `relationship.confidence`.
- Exclude the original artist’s own tracks explicitly.

---

### Phase 2 — Stabilize

#### A. Batch Processing With Backpressure
- Replace unbounded `Future.wait` in orchestrator with a bounded
  semaphore (max 3–4 concurrent network calls) to avoid overwhelming
  mobile bandwidth.
- Add per-stage timeouts:
  - Evidence discovery: 8 s
  - Content extraction: 10 s
  - Resolution + scoring: 3 s

#### B. Cache Aggressively
- Cache Wikipedia responses in the existing `cache` Hive box with a 3-day TTL.
- Cache YT Music related-artist results per artistId with a 7-day TTL.
- Fingerprint cache key should be versioned (`fp_v1_{artistId}`) so schema
  changes invalidate old entries.

#### C. Add Offline Fallback
- If all network sources fail, return an **empty fingerprint with success=false**
  and a clear error message rather than throwing.
- UI should show “No public influence data found for this artist” instead of
  a generic failure.

#### D. Metrics That Matter
- Add timing breakdown per stage to `FingerprintGenerationResult`.
- Log `evidenceSourcesFound`, `relationshipsExtracted`, `finalRelationships`.
- Surface these in `FingerprintPage` so users understand why some artists
  return few or no influences.

---

### Phase 3 — Scale (Optional, Post-MVP)

#### A. Stage 2 — Influence Playlist
- Convert `stage2/` from empty to a real module:
  - Take top N relationships by confidence.
  - For each, fetch 2–3 tracks from the influential artist’s catalog.
  - Shuffle and present as the influence playlist.
- Uses existing `getArtistCatalog`, no new deps.

#### B. Optional Local Cache Pack
- Offer export/import of precomputed fingerprint JSON blobs for offline access.
- Explicitly listed as a future expansion in the project overview.

#### C. Confidence Tuning
- Replace heuristic multipliers with a small lookup table tuned on
  known artist-influence pairs. No ML required; just calibrated weights.

---

## What Must NOT Change

- **No paid services** — all new sources (Wikipedia, MusicBrainz, YT Music)
  are free.
- **No API keys** — none of the proposed sources require keys.
- **No accounts** — all calls are anonymous.
- **Android 12+ compatible** — all chosen APIs support HTTPS without special
  permissions beyond `INTERNET`.
- **Lightweight** — remove ~200 lines of stub NLP code, add ~150 lines of
  real HTTP + keyword matching. Net reduction in complexity.
- **Fast** — bounded concurrency + aggressive caching keeps wall-clock time
  under 3–5 s for typical artists.

---

## Concrete File Changes

| File | Action |
|---|---|
| `stage1_orchestrator.dart` | Remove duplicate import; replace `_extractSourceContent` with real providers; add timeouts and backpressure |
| `stage1/evidence_discovery.dart` | Implement YT Music + Wikipedia + MusicBrainz providers; drop interview/podcast/social/documentary stubs |
| `stage1/content_extraction.dart` | Replace NLP stub with keyword/proximity matcher |
| `stage1/confidence_scoring.dart` | Remove duplicate `FingerprintGenerationEngine`; import from canonical module |
| `stage1/entity_resolution.dart` | Remove duplicate `ArtistHasher` / `ArtistNormalizer`; import from `fingerprint_service.dart` |
| `stage1/fingerprint_generation.dart` | Keep as canonical; add TTL-aware merge logic |
| `fingerprint_service.dart` | Add `permanent` flag; route to `cache` box when `false`; implement playlist generation using existing `getArtistCatalog` |
| `stage1/stage1_api.dart` | Pass `permanent` through to service; surface timing metrics |
| `screens/fingerprint_page.dart` | Implement `_resolveArtistName` from fingerprint metadata; show stage timing; fix playlist wiring |
| `screens/fingerprint_search_page.dart` | Optionally add “Generate Fingerprint” CTA after artist selection |

---

## Verification Checklist

- [ ] `dart analyze` passes with no new warnings.
- [ ] Fingerprint generation returns non-empty relationships for a known artist
      (e.g., “Kurt Cobain” should return Pixies, Lead Belly, Black Flag).
- [ ] Artist IDs resolve to readable names in `FingerprintPage`.
- [ ] Playlist view shows tracks from influential artists, excluding the
      original artist.
- [ ] Cache TTL works: after forced expiry, a fresh fingerprint is generated.
- [ ] Offline mode shows graceful “no data” state, no crashes.
- [ ] No new dependencies added beyond what is already in `pubspec.yaml`.

---

## Bottom Line

The current pipeline is a sophisticated skeleton. Do not invest in making the
6-stage NLP architecture work on-device. Instead, **reuse the YouTube Music
and Wikipedia layers the app already talks to**, drop to 2–3 real stages, fix
the duplication and circular imports, and align storage with the project’s
own “temporary fingerprint” requirement. That gets a working feature in the
smallest delta while preserving every constraint.
