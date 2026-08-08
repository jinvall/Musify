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

import 'package:musify/models/tab_models.dart';

/// Renders Musify's internal [Tab] representation as ASCII tablature.
class TabRenderer {
  const TabRenderer();

  /// Render a full tab to a displayable string.
  String render(Tab tab) {
    final buffer = StringBuffer();

    // Header.
    buffer.writeln(tab.artist.toUpperCase());
    buffer.writeln(tab.song.toUpperCase());
    buffer.writeln();

    // Instrument and tuning info.
    final instrumentLabel = tab.instrument.split('(').first.trim();
    final tuningName = _tuningName(tab.tuning);
    buffer.writeln('$instrumentLabel \u2022 $tuningName');
    if (tab.capo != null && tab.capo! > 0) {
      buffer.writeln('Capo: ${tab.capo}');
    }
    if (tab.tempo != null && tab.tempo! > 0) {
      buffer.writeln('Tempo: ${tab.tempo} BPM');
    }
    buffer.writeln();

    if (tab.measures.isEmpty) {
      buffer.writeln('(No notation data available)');
      return buffer.toString();
    }

    // Render measures.
    for (var i = 0; i < tab.measures.length; i++) {
      final measure = tab.measures[i];
      if (measure.sectionLabel != null && i > 0) {
        buffer.writeln();
        buffer.writeln(measure.sectionLabel!.toUpperCase());
        buffer.writeln();
      }
      buffer.writeln(_renderMeasure(tab.tuning, measure));
    }

    return buffer.toString();
  }

  /// Render a single measure as ASCII tab lines.
  String _renderMeasure(List<int> tuning, TabMeasure measure) {
    if (measure.lines.isEmpty) return '';

    // Use the rendered lines from the tab data if available.
    if (measure.lines.length == tuning.length) {
      return measure.lines.join('\n');
    }

    // Fallback: generate placeholder lines.
    final strings = <String>[];
    for (var i = 0; i < tuning.length; i++) {
      final noteName = _midiNoteName(tuning[i]);
      strings.add('$noteName|${'-' * 20}|');
    }
    return strings.join('\n');
  }

  String _tuningName(List<int> tuning) {
    if (_listsEqual(tuning, <int>[64, 59, 55, 50, 45, 40])) return 'Standard Tuning';
    if (_listsEqual(tuning, <int>[62, 57, 53, 48, 43, 38])) return 'Drop D';
    if (_listsEqual(tuning, <int>[43, 38, 33, 28])) return 'Standard Bass';
    if (_listsEqual(tuning, <int>[69, 64, 60, 67])) return 'C Tuning';
    return _formatTuning(tuning);
  }

  String _formatTuning(List<int> tuning) {
    final names = tuning.map(_midiNoteName).join(' - ');
    return names;
  }

  String _midiNoteName(int midi) {
    const noteNames = <String>[
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = (midi ~/ 12) - 1;
    final note = noteNames[midi % 12];
    return '$note$octave';
  }

  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
