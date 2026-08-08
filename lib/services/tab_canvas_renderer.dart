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

import 'package:flutter/material.dart' hide Tab;
import 'package:musify/models/tab_models.dart';

/// Paints a single tab measure onto a canvas.
class _TabMeasurePainter extends CustomPainter {
  _TabMeasurePainter({
    required this.measure,
    required this.tuning,
    required this.isActive,
    required this.activeColor,
    required this.stringColor,
    required this.fretColor,
    required this.barColor,
    required this.labelColor,
    required this.backgroundColor,
    required this.capo,
  });

  final TabMeasure measure;
  final List<int> tuning;
  final bool isActive;
  final Color activeColor;
  final Color stringColor;
  final Color fretColor;
  final Color barColor;
  final Color labelColor;
  final Color backgroundColor;
  final int? capo;

  @override
  void paint(Canvas canvas, Size size) {
    final background = backgroundColor;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final stringCount = tuning.length;
    final stringSpacing = size.height / (stringCount + 1);
    final margin = size.width * 0.05;
    const barWidth = 2.0;

    // Draw string lines.
    for (var i = 0; i < stringCount; i++) {
      final y = stringSpacing * (i + 1);
      final isThick = tuning[i] <= 45; // Low strings thicker visually.
      final width = isThick ? 2.5 : 1.2;
      canvas.drawLine(
        Offset(margin, y),
        Offset(size.width - margin, y),
        Paint()
          ..color = stringColor
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }

    // Draw capo indicator.
    if (capo != null && capo! > 0) {
      final y = stringSpacing * 0.5;
      final capoText = 'Capo $capo';
      final span = TextSpan(
        text: capoText,
        style: TextStyle(color: labelColor, fontSize: 11, fontWeight: FontWeight.w600),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(margin, y));
    }

    // Draw measure section label if present.
    if (measure.sectionLabel != null && measure.sectionLabel!.isNotEmpty) {
      final label = measure.sectionLabel!.toUpperCase();
      final span = TextSpan(
        text: label,
        style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      final labelY = size.height * 0.15;
      tp.paint(canvas, Offset(margin, labelY));
    }

    // Draw measure separators.
    final barX = size.width - margin;
    canvas.drawLine(
      Offset(barX, stringSpacing * 0.5),
      Offset(barX, size.height - stringSpacing * 0.5),
      Paint()
        ..color = barColor
        ..strokeWidth = barWidth
        ..style = PaintingStyle.stroke,
    );

    // Draw frets/notes from rendered lines if available.
    final renderedLines = measure.lines;
    if (renderedLines.isNotEmpty) {
      final effectiveLines = renderedLines.length == stringCount
          ? renderedLines
          : List.generate(stringCount, (i) => i < renderedLines.length ? renderedLines[i] : '');
      for (var stringIndex = 0; stringIndex < stringCount; stringIndex++) {
        final line = effectiveLines[stringCount - 1 - stringIndex];
        final y = stringSpacing * (stringIndex + 1);
        _drawLine(canvas, line, y, margin, size.width - margin, fretColor, labelColor);
      }
    }
  }

  void _drawLine(Canvas canvas, String line, double y, double left, double right, Color fretColor, Color labelColor) {
    // Simplified ASCII-style fret rendering on canvas.
    // Each segment between '|' markers represents a beat area.
    final segments = line.split('|');
    if (segments.isEmpty) return;

    final segmentWidth = (right - left) / segments.length;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;

      final cx = left + segmentWidth * (i + 0.5);
      final span = TextSpan(
        text: trimmed,
        style: TextStyle(color: fretColor, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      final rect = Rect.fromCenter(center: Offset(cx, y), width: tp.width + 10, height: tp.height + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = backgroundColor,
      );
      tp.paint(canvas, Offset(cx - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TabMeasurePainter old) {
    return old.isActive != isActive ||
        old.measure != measure ||
        old.tuning != tuning ||
        old.capo != capo;
  }
}

/// Paints a chord diagram box.
class _ChordBoxPainter extends CustomPainter {
  _ChordBoxPainter({
    required this.chordName,
    required this.frets,
    required this.strings,
    required this.colorScheme,
  });

  final String chordName;
  final List<int> frets;
  final int strings;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 12.0;
    final boxWidth = size.width - padding * 2;
    final boxHeight = size.height - padding * 2 - 16;
    if (boxWidth <= 0 || boxHeight <= 0) return;

    final rect = Rect.fromLTWH(padding, padding + 16, boxWidth, boxHeight);
    final paint = Paint()
      ..color = colorScheme.surfaceContainerHighest
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), paint);

    final border = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), border);

    // Nut line.
    final nutY = padding + 20;
    canvas.drawLine(
      Offset(padding, nutY),
      Offset(padding + boxWidth, nutY),
      Paint()
        ..color = colorScheme.onSurface
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // String lines.
    final stringSpacing = boxWidth / (strings - 1);
    for (var i = 0; i < strings; i++) {
      final x = padding + stringSpacing * i;
      canvas.drawLine(
        Offset(x, nutY),
        Offset(x, padding + 16 + boxHeight),
        Paint()
          ..color = colorScheme.outlineVariant
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // Fret lines.
    const fretCount = 4;
    final fretSpacing = boxHeight / fretCount;
    for (var i = 0; i <= fretCount; i++) {
      final y = nutY + fretSpacing * i;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + boxWidth, y),
        Paint()
          ..color = colorScheme.outlineVariant
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // Finger positions.
    for (var i = 0; i < frets.length && i < strings; i++) {
      final fret = frets[i];
      if (fret <= 0) continue;
      final x = padding + stringSpacing * i;
      final y = nutY + fretSpacing * (fret - 0.5);
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()
          ..color = colorScheme.primary
          ..style = PaintingStyle.fill,
      );
    }

    // Chord label.
    final labelSpan = TextSpan(
      text: chordName,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
    );
    final labelPainter = TextPainter(text: labelSpan, textDirection: TextDirection.ltr);
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(padding, 2));
  }

  @override
  bool shouldRepaint(_ChordBoxPainter old) => false;
}

/// Renders Musify's internal [Tab] representation onto a canvas.
///
/// This produces a draw-based tab view instead of ASCII text.
class TabCanvasRenderer {
  const TabCanvasRenderer();

  /// Paint a single measure widget.
  Widget buildMeasure({
    required Tab tab,
    required TabMeasure measure,
    required int index,
    required bool isActive,
    required ColorScheme colorScheme,
  }) {
    return CustomPaint(
      painter: _TabMeasurePainter(
        measure: measure,
        tuning: tab.tuning,
        isActive: isActive,
        activeColor: colorScheme.primary,
        stringColor: colorScheme.onSurface,
        fretColor: colorScheme.primary,
        barColor: colorScheme.outlineVariant,
        labelColor: colorScheme.primary,
        backgroundColor: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerHighest,
        capo: tab.capo,
      ),
      child: SizedBox(
        height: _measureHeight(tab.tuning.length),
        width: double.infinity,
      ),
    );
  }

  /// Paint a chord box widget.
  Widget buildChordBox({
    required String chordName,
    required List<int> frets,
    required int strings,
    required ColorScheme colorScheme,
    double width = 72,
    double height = 96,
  }) {
    return CustomPaint(
      painter: _ChordBoxPainter(
        chordName: chordName,
        frets: frets,
        strings: strings,
        colorScheme: colorScheme,
      ),
      child: SizedBox(width: width, height: height),
    );
  }

  double _measureHeight(int stringCount) {
    const baseHeight = 80.0;
    const perString = 18.0;
    return baseHeight + stringCount * perString;
  }
}
