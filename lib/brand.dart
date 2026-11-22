import 'package:flutter/material.dart';

// ---------------- The app's name and how it is written ----------------
// Change the name here only. The title is drawn in bold capitals with a
// shadow, in Cinzel Decorative Black (assets/fonts, free OFL licence):
// a free look-alike of the "Algerian" font, which may not be put in an app.

const String kAppName = 'AZSA';

class AppWordmark extends StatelessWidget {
  final double size;
  // null = the colour of the text around it (for example the top bar).
  final Color? color;
  const AppWordmark({super.key, this.size = 34, this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? DefaultTextStyle.of(context).style.color ?? Colors.white;
    // A light title gets a darker shadow, a dark title a softer one.
    final light = textColor.computeLuminance() > 0.5;
    return Text(
      kAppName,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        fontFamily: 'CinzelDecorative',
        fontWeight: FontWeight.w900,
        fontSize: size,
        color: textColor,
        letterSpacing: size * 0.03,
        height: 1.1,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: light ? 0.45 : 0.30),
            offset: Offset(size * 0.04, size * 0.07),
            blurRadius: size * 0.12,
          ),
        ],
      ),
    );
  }
}
