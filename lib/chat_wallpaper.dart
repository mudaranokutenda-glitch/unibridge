import 'dart:math' as math;
import 'package:flutter/material.dart';

// ---------------- Chat wallpaper ----------------
// Drawn by code (no image file): small flowers and leaves, the currency
// signs \$ € DA and the name AZSA, repeated like WhatsApp's doodles.
// Dark lines on the light chat background, light lines in dark mode.

class ChatWallpaper extends StatelessWidget {
  final Widget child;
  const ChatWallpaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _WallpaperPainter(
        dark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF14233B).withValues(alpha: 0.17),
      ),
      child: child,
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  final Color ink;
  _WallpaperPainter(this.ink);

  static const double tile = 240.0;
  // (centre x, centre y, size, petals)
  static const List<(double, double, double, int)> flowers = [
    (42.0, 46.0, 14.0, 5),
    (172.0, 30.0, 10.0, 6),
    (122.0, 132.0, 16.0, 5),
    (30.0, 192.0, 11.0, 6),
    (212.0, 184.0, 13.0, 5),
  ];
  // (x, y, angle, length)
  static const List<(double, double, double, double)> leaves = [
    (60.0, 60.0, 0.6, 22.0),
    (26.0, 34.0, -2.5, 18.0),
    (142.0, 150.0, 0.9, 24.0),
    (102.0, 118.0, -2.3, 20.0),
    (186.0, 42.0, 0.5, 16.0),
    (228.0, 200.0, 1.3, 18.0),
    (44.0, 206.0, 0.4, 16.0),
    (196.0, 172.0, -2.4, 16.0),
  ];
  // (text, x, y, font size, angle)
  static const List<(String, double, double, double, double)> texts = [
    ('\$', 96.0, 44.0, 24.0, -0.3),
    ('€', 206.0, 106.0, 24.0, 0.25),
    ('DA', 58.0, 124.0, 19.0, -0.2),
    ('AZSA', 150.0, 222.0, 15.0, -0.12),
    ('\$', 16.0, 112.0, 17.0, 0.3),
    ('€', 112.0, 200.0, 17.0, -0.2),
    ('DA', 172.0, 84.0, 14.0, 0.2),
  ];
  // (x, y, size)
  static const List<(double, double, double)> sparkles = [
    (132.0, 72.0, 5.0),
    (78.0, 172.0, 4.0),
    (226.0, 66.0, 4.0),
    (10.0, 152.0, 3.0),
    (238.0, 132.0, 3.0),
  ];

  List<TextPainter>? _labels;

  List<TextPainter> _makeLabels() => [
        for (final t in texts)
          TextPainter(
            text: TextSpan(
              text: t.$1,
              style: TextStyle(
                color: ink,
                fontSize: t.$4,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ];

  void _drawTile(Canvas canvas, Offset o, Paint line, Paint fill,
      List<TextPainter> labels) {
    for (final (cx, cy, r, n) in flowers) {
      for (var i = 0; i < n; i++) {
        canvas.save();
        canvas.translate(o.dx + cx, o.dy + cy);
        canvas.rotate(2 * math.pi * i / n);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(r * 0.9, 0), width: r * 1.2, height: r * 0.66),
            line);
        canvas.restore();
      }
      canvas.drawCircle(Offset(o.dx + cx, o.dy + cy), r * 0.3, fill);
    }
    for (final (x, y, angle, len) in leaves) {
      canvas.save();
      canvas.translate(o.dx + x, o.dy + y);
      canvas.rotate(angle);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(len / 2, -len * 0.3, len, 0)
        ..quadraticBezierTo(len / 2, len * 0.3, 0, 0);
      canvas.drawPath(leaf, line);
      canvas.drawLine(Offset.zero, Offset(len * 0.8, 0), line);
      canvas.restore();
    }
    for (final (x, y, s) in sparkles) {
      canvas.drawLine(
          Offset(o.dx + x - s, o.dy + y), Offset(o.dx + x + s, o.dy + y), line);
      canvas.drawLine(
          Offset(o.dx + x, o.dy + y - s), Offset(o.dx + x, o.dy + y + s), line);
    }
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      final label = labels[i];
      canvas.save();
      canvas.translate(o.dx + t.$2, o.dy + t.$3);
      canvas.rotate(t.$5);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()..color = ink;
    final labels = _labels ??= _makeLabels();

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    var row = 0;
    for (var y = -tile; y < size.height + tile; y += tile) {
      // Every second row is shifted by half a tile, so it doesn't look like a grid.
      final shift = row.isOdd ? tile / 2 : 0.0;
      for (var x = -tile; x < size.width + tile; x += tile) {
        _drawTile(canvas, Offset(x + shift, y), line, fill, labels);
      }
      row++;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter oldDelegate) =>
      oldDelegate.ink != ink;
}
