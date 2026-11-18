import 'package:flutter/material.dart';
import 'app_theme.dart';

// A sky-blue gradient with soft white clouds, drawn in code (no image files).
// Used by the login / sign-up screens and the start-up intro.

class SkyBackground extends StatelessWidget {
  final Widget child;
  const SkyBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6BB0FF), AppColors.sky, AppColors.skyDark],
        ),
      ),
      child: CustomPaint(
        painter: _CloudsPainter(),
        child: child,
      ),
    );
  }
}

class _CloudsPainter extends CustomPainter {
  // One cloud = a flat base and a few overlapping circles. Positions are fractions
  // of the screen so it looks the same on every phone.
  void _cloud(Canvas canvas, Size size, double x, double y, double width, double alpha) {
    final paint = Paint()..color = Colors.white.withValues(alpha: alpha);
    final cx = size.width * x;
    final cy = size.height * y;
    final w = size.width * width;
    final h = w * 0.34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
        Radius.circular(h / 2),
      ),
      paint,
    );
    canvas.drawCircle(Offset(cx - w * 0.18, cy - h * 0.38), h * 0.62, paint);
    canvas.drawCircle(Offset(cx + w * 0.08, cy - h * 0.62), h * 0.78, paint);
    canvas.drawCircle(Offset(cx + w * 0.28, cy - h * 0.28), h * 0.5, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _cloud(canvas, size, 0.18, 0.12, 0.46, 0.22);
    _cloud(canvas, size, 0.86, 0.22, 0.38, 0.16);
    _cloud(canvas, size, 0.12, 0.52, 0.34, 0.12);
    _cloud(canvas, size, 0.9, 0.78, 0.5, 0.18);
    _cloud(canvas, size, 0.3, 0.93, 0.56, 0.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
