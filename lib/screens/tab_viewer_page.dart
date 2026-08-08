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
import 'package:flutter/material.dart' hide Tab;
import 'package:musify/extensions/l10n.dart';
import 'package:musify/models/tab_models.dart';
import 'package:musify/services/tab_manager.dart';
import 'package:musify/services/tab_renderer.dart';

class TabViewerPage extends StatefulWidget {
  const TabViewerPage({super.key});

  @override
  State<TabViewerPage> createState() => _TabViewerPageState();
}

class _TabViewerPageState extends State<TabViewerPage> {
  final TabRenderer _renderer = const TabRenderer();
  String? _selectedInstrument;
  final List<String> _availableInstruments = <String>[];

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  Future<void> _loadInstruments() async {
    final tab = TabManager.instance.currentTab.value;
    if (tab == null) return;
    // For now, instruments are determined by the current tab.
    // In a full implementation, we'd fetch all tracks and let the user switch.
    setState(() {
      _availableInstruments.clear();
      _availableInstruments.add(tab.instrument);
      _selectedInstrument = tab.instrument;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, colorScheme),
             Expanded(
               child: ValueListenableBuilder<Tab?>(
                 valueListenable: TabManager.instance.currentTab,
                 builder: (context, tab, _) {
                   final isLoading = TabManager.instance.isLoading.value;

                   if (isLoading) {
                     return const Center(child: CircularProgressIndicator());
                   }

                   if (tab == null) {
                     return Center(
                       child: Text(l10n.tabNotAvailable),
                     );
                   }

                   final rendered = _renderer.render(tab);

                   return SingleChildScrollView(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.stretch,
                       children: [
                         // Instrument selector chips.
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
                                       setState(() {
                                         _selectedInstrument = instrument;
                                       });
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
                         const SizedBox(height: 16),

                         // Tab text.
                         Container(
                           width: double.infinity,
                           padding: const EdgeInsets.all(16),
                           decoration: BoxDecoration(
                             color: colorScheme.surfaceContainerHighest,
                             borderRadius: BorderRadius.circular(16),
                           ),
                           child: SelectableText(
                             rendered,
                             style: const TextStyle(
                               fontFamily: 'monospace',
                               fontSize: 12,
                               height: 1.4,
                             ),
                           ),
                         ),
                       ],
                     ),
                   );
                 },
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
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
        ],
      ),
    );
  }
}
