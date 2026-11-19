UniBridge logo (optional)
=========================

Put your logo here with this exact name:

  logo.png

Format: PNG, 1024 x 1024 pixels, transparent background.
Keep the drawing inside the middle 600 x 600 pixels (empty space around it).
The empty border is needed because Android 12 and newer cut the splash logo to a circle.

Used by:
  1. the start-up intro in the app (lib/intro.dart): the logo fades and scales in.
     Without this file the app shows a white circle with a school icon instead.
  2. the native splash screen (the very first screen, before the app starts).
     This one needs two extra steps, see below.

Steps to add your logo
  1. Copy your file to assets/logo/logo.png
  2. Open pubspec.yaml, go to the end, find the block "flutter_native_splash:" and delete ONLY
     the "#" character in front of the two lines
         #image: assets/logo/logo.png
     (one is near the top of the block, one is under "android_12:").
     Do not change the spaces at the start of the lines.
  3. In the terminal, in the project folder, run:
         dart run flutter_native_splash:create
  4. Stop the app and run "flutter run" again (a hot reload does not change the splash).

Without a logo the native splash is simply plain sky blue.
To remove the generated splash again: dart run flutter_native_splash:remove
