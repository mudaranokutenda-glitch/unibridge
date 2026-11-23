import 'package:flutter/material.dart';

// ---------------- The app's name and how it is written ----------------
// Change the name here only. The title is drawn in bold capitals with a
// shadow, in Cinzel Decorative Black (assets/fonts, free OFL licence):
// a free look-alike of the "Algerian" font, which may not be put in an app.

const String kAppName = 'AZSA';
// The AZSA circle, shown next to the name.
const String kAppCircleLogo = 'assets/logo/azsa_circle.png';

class AppWordmark extends StatelessWidget {
  final double size;
  // null = the colour of the text around it (for example the top bar).
  final Color? color;
  // false = the name only, without the circle.
  final bool showLogo;
  const AppWordmark({super.key, this.size = 34, this.color, this.showLogo = true});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? DefaultTextStyle.of(context).style.color ?? Colors.white;
    // A light title gets a darker shadow, a dark title a softer one.
    final light = textColor.computeLuminance() > 0.5;
    final name = Text(
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
    if (!showLogo) return name;
    final logoSize = size * 1.25;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center, // centred on the login screen
      children: [
        // A soft shadow under the circle, like the one under the letters.
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: size * 0.15,
                offset: Offset(0, size * 0.05),
              ),
            ],
          ),
          child: Image.asset(
            kAppCircleLogo,
            width: logoSize,
            height: logoSize,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        SizedBox(width: size * 0.3),
        Flexible(child: name),
      ],
    );
  }
}
