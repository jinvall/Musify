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

 import 'package:audio_service/audio_service.dart';
 import 'package:fluentui_system_icons/fluentui_system_icons.dart';
 import 'package:flutter/material.dart' hide Tab;
 import 'package:flutter_flip_card/flutter_flip_card.dart';
 import 'package:musify/extensions/l10n.dart';
 import 'package:musify/main.dart';
 import 'package:musify/models/position_data.dart';
 import 'package:musify/models/tab_models.dart';
 import 'package:musify/services/tab_manager.dart';
 import 'package:musify/services/tab_renderer.dart';
 import 'package:musify/services/tab_canvas_renderer.dart';
 import 'package:musify/services/settings_manager.dart';
 import 'package:musify/widgets/position_slider.dart';

class TabViewerPage extends StatefulWidget {
  const TabViewerPage({super.key});

  @override
  State<TabViewerPage> createState() => _TabViewerPageState();
}

class _TabViewerPageState extends State<TabViewerPage> {
  static const double _measureLineHeight = 14.0;
  static const double _measureTextHeight = 1.4;
  static const double _sectionHeaderHeight = 24.0;
  static const double _measurePadding = 24.0;
  static const int _controlsTimeoutSeconds = 4;

  final TabRenderer _renderer = const TabRenderer();
  final TabCanvasRenderer _canvasRenderer = const TabCanvasRenderer();
  final FlipCardController _flipController = FlipCardController();
  final ScrollController _scrollController = ScrollController();

  bool _controlsVisible = true;
  Timer? _controlsTimer;
  int _activeMeasureIndex = -1;

  List<String> _availableInstruments = <String>[];
  String? _selectedInstrument;
  bool _isTabsFace = true;

  @override
  void initState() {
    super.initState();
    _loadInstruments();
    _startControlsTimer();
    TabManager.instance.currentTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    TabManager.instance.currentTab.removeListener(_onTabChanged);
    _controlsTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      _activeMeasureIndex = -1;
    });
    _scrollController.jumpTo(0);
  }

  void _showControls() {
    setState(() {
      _controlsVisible = true;
    });
    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: _controlsTimeoutSeconds), () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  Future<void> _loadInstruments() async {
    final instruments = await TabManager.instance.getAvailableInstruments();
    if (!mounted) return;
    final currentTab = TabManager.instance.currentTab.value;
    final selected = currentTab?.instrument ?? tabDefaultInstrument.value ?? 'Guitar';
    setState(() {
      _availableInstruments = instruments;
      _selectedInstrument = _availableInstruments.contains(selected) ? selected : _availableInstruments.firstOrNull;
    });
  }

  Future<void> _selectInstrument(String instrument) async {
    if (_selectedInstrument == instrument) return;
    setState(() {
      _selectedInstrument = instrument;
      _activeMeasureIndex = -1;
    });
    await TabManager.instance.refreshForInstrument(instrument);
    _scrollController.jumpTo(0);
  }

  void _toggleFace() {
    setState(() {
      _isTabsFace = !_isTabsFace;
    });
    _flipController.flipcard();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _showControls,
          child: Column(
            children: [
              _buildAppBar(context, colorScheme),
              Expanded(
                child: ValueListenableBuilder<Tab?>(
                  valueListenable: TabManager.instance.currentTab,
                  builder: (context, tab, _) {
                    final isLoading = TabManager.instance.isLoading.value;

                    if (isLoading && tab == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (tab == null) {
                      return Center(
                        child: Text(
                          l10n.tabNotAvailable,
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    }

                    return FlipCard(
                      rotateSide: RotateSide.right,
                      controller: _flipController,
                      frontWidget: _buildChordsFace(tab, colorScheme),
                      backWidget: _buildTabsFace(tab, colorScheme),
                    );
                  },
                ),
              ),
              _buildFadingControls(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    final l10n = context.l10n!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.chevron_down_24_regular),
            iconSize: 26,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          Text(
            l10n.tab,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isTabsFace
                  ? FluentIcons.text_quote_24_regular
                  : FluentIcons.document_24_regular,
              color: colorScheme.onSurfaceVariant,
            ),
            iconSize: 24,
            onPressed: _toggleFace,
            tooltip: _isTabsFace ? l10n.chords : l10n.tab,
          ),
        ],
      ),
    );
  }

  Widget _buildChordsFace(Tab tab, ColorScheme colorScheme) {
    final l10n = context.l10n!;
    final chordsText = _renderer.renderChords(tab);
    return Container(
      color: colorScheme.surface,
      child: chordsText.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.text_quote_24_regular,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.chordsNotAvailable,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                chordsText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
    );
  }

  Widget _buildTabsFace(Tab tab, ColorScheme colorScheme) {
    final l10n = context.l10n!;
    final measured = tab.measuredMeasures;

    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      builder: (context, snapshot) {
        final position = snapshot.data?.position ?? Duration.zero;

        int activeIndex = -1;
        if (tab.tempo != null && tab.tempo! > 0) {
          for (var i = 0; i < measured.length; i++) {
            final m = measured[i];
            if (m.startTime != null && m.duration != null) {
              if (position >= m.startTime! && position < m.startTime! + m.duration!) {
                activeIndex = i;
                break;
              }
            }
          }
        }

        if (activeIndex != _activeMeasureIndex) {
          _activeMeasureIndex = activeIndex;
          _scrollToActiveMeasure(activeIndex, tab, measured);
        }

        if (measured.isEmpty) {
          return Center(
            child: Text(
              l10n.tabNotAvailable,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: measured.length,
          itemBuilder: (context, index) {
            final measure = measured[index];
            final isActive = index == activeIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: isActive
                    ? Border.all(color: colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: _canvasRenderer.buildMeasure(
                tab: tab,
                measure: measure,
                index: index,
                isActive: isActive,
                colorScheme: colorScheme,
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToActiveMeasure(int activeIndex, Tab tab, List<TabMeasure> measured) {
    if (activeIndex < 0 || !_scrollController.hasClients) return;

    final estimatedItemHeight = _estimateItemHeight(tab, measured[activeIndex]);
    final targetOffset = (activeIndex * estimatedItemHeight) - (MediaQuery.of(context).size.height / 3);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if ((clampedOffset - _scrollController.offset).abs() > estimatedItemHeight) {
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  double _estimateItemHeight(Tab tab, TabMeasure measure) {
    final lines = measure.lines.length;
    final headerHeight = (measure.sectionLabel != null && tab.measures.indexOf(measure) > 0) ? _sectionHeaderHeight : 0;
    final textHeight = lines * _measureLineHeight * _measureTextHeight + _measurePadding;
    return headerHeight + textHeight + 24; // margin
  }

  Widget _buildFadingControls(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _showControls,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width,
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_availableInstruments.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _availableInstruments.map((instrument) {
                            final isSelected = _selectedInstrument == instrument;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) _selectInstrument(instrument);
                                },
                                label: Text(instrument),
                                backgroundColor: colorScheme.surfaceContainerHighest,
                                selectedColor: colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (_availableInstruments.length > 1) const SizedBox(height: 8),
                    const PositionSlider(),
                    const SizedBox(height: 6),
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (context, snapshot) {
                        final playbackState = snapshot.data;
                        final isPlaying = playbackState?.playing ?? false;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildControlIcon(
                              colorScheme: colorScheme,
                              icon: isPlaying ? FluentIcons.pause_24_regular : FluentIcons.play_24_regular,
                              onPressed: () {
                                if (isPlaying) {
                                  audioHandler.pause();
                                } else {
                                  audioHandler.play();
                                }
                              },
                            ),
                            const SizedBox(width: 24),
                            _buildControlIcon(
                              colorScheme: colorScheme,
                              icon: FluentIcons.next_24_regular,
                              onPressed: audioHandler.skipToNext,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlIcon({
    required ColorScheme colorScheme,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, color: colorScheme.onSurfaceVariant),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
