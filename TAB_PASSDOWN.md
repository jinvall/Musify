# TAB_PASSDOWN.md

## Current State

### Working
- Chords appear on the chords face of the FlipCard
- Canvas renderer draws measures via `CustomPainter`
- Fading bottom controls with instrument chips
- Playback-synced highlighting/scrolling
- Songsterr search, meta fetch, CDN structured-tab fetch, and parser all implemented and logged
- Revision-aware caching
- Build succeeds; APKs are produced under `build/app/outputs/flutter-apk/`

### Not Working
- Tabs do not appear in the tab viewer despite chords working
- The parser/canvas path is not producing visible tab notation

## Root Cause Hypotheses
1. `measure.lines` is empty or malformed after parsing the structured JSON
2. `_TabMeasurePainter._drawLine` is receiving empty strings, so nothing is drawn
3. `TabViewerPage._buildTabsFace` may be calling the canvas renderer but the measure data has no content
4. Track selection may be resolving to a vocal/no-content track before the CDN fetch
5. The active-measure highlight may be drawing, but inactive measures have no content either

## Next Session Todo
- Inspect runtime logs for `Songsterr parser` and `TabManager` to confirm measures are being parsed and cached
- Add a debug dump of the first few `TabMeasure.lines` entries after parsing
- If `measure.lines` is empty, fix `_parseStructuredTab()` to populate lines from `beats[].notes[]`
- If lines exist but canvas draws nothing, fix `_TabMeasurePainter._drawLine()` and ensure painter receives valid data
- Ensure track selection in `getTab()` prefers guitar/bass/drums over vocal tracks when the user setting requests guitar
- Verify the tab viewer is reading from `currentTab` and not an empty cached entry

## Key Files
- `lib/services/tab_providers/songsterr_provider.dart`
- `lib/services/tab_canvas_renderer.dart`
- `lib/screens/tab_viewer_page.dart`
- `lib/services/tab_manager.dart`
- `lib/models/tab_models.dart`

## Verification
- Run the app, open tabs for Olivia Rodrigo — the cure
- Expected: both chords and tab notation visible
- Current: chords visible, tabs missing
