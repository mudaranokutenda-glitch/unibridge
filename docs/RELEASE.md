# Release checklist (Google Play)

Work through this list from top to bottom. Steps marked **(you)** need your accounts or
secrets, so Claude cannot do them.

---

## 1. App ID  (decide once, it can never change after the first upload)

The app ID is still `com.example.unibridge_app`. Google Play refuses IDs that start with
`com.example`. When the new ID is chosen, these must all use it:

- `android/app/build.gradle.kts` → `namespace` and `applicationId`
- `android/app/src/main/kotlin/.../MainActivity.kt` → `package` line and folder
- **(you)** Firebase: add a new Android app with the new ID, download its
  `google-services.json`, and replace `android/app/google-services.json`.
  Then run `flutterfire configure` again (it rewrites `lib/firebase_options.dart`).
- **(you)** Google Sign-In: in Google Cloud Console → APIs & Services → Credentials,
  create an **Android** OAuth client for the new ID with your SHA-1 fingerprints (step 3).
  The Web client used in `lib/config.dart` stays the same.

## 2. Signing key  (you)

Create the key once and keep it **forever**. If you lose it, you can never update the app.
Back up the `.jks` file and its passwords somewhere safe (not in this project).

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\unibridge-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create the file `android/key.properties` (it is ignored by git, never commit it):

```
storePassword=THE_PASSWORD_YOU_CHOSE
keyPassword=THE_PASSWORD_YOU_CHOSE
keyAlias=upload
storeFile=C:/Users/Prof/unibridge-upload.jks
```

`android/app/build.gradle.kts` already reads this file. Without it, release builds fall back
to the debug key.

## 3. SHA-1 fingerprints for Google Sign-In  (you)

```powershell
keytool -list -v -keystore $env:USERPROFILE\unibridge-upload.jks -alias upload
```

Add the SHA-1 to the Android OAuth client (step 1) **and** to the Firebase Android app.
After the first upload, Play Console → Test and release → App integrity shows the
**App signing key** SHA-1. Add that one too, or Google login fails for Play Store installs.

## 4. App icon

1. Put a square PNG (1024×1024, no transparency) at `assets/icon/icon.png`.
2. Run:
   ```powershell
   flutter pub get
   dart run flutter_launcher_icons
   ```

## 5. Version

`pubspec.yaml` → `version: 1.0.0+1`. Increase the number after `+` for every upload
(`1.0.1+2`, `1.0.2+3`, ...).

## 6. Build the file for Play

```powershell
flutter build appbundle --release
```

The file is `build/app/outputs/bundle/release/app-release.aab`.

## 7. Privacy policy page  (you)

Google Play needs a public link. Easiest free options:
- **GitHub Pages:** push this repo to GitHub, Settings → Pages → deploy from the `docs`
  folder. The link becomes `https://YOUR_NAME.github.io/REPO/privacy-policy.html`.
- **Google Sites:** paste the text of `docs/privacy-policy.html` into a new site.

## 8. Play Console  (you)

1. Create the app (one-time $25 developer fee).
2. Store listing: texts in `docs/play-store-listing.md`, the icon, at least 2 phone
   screenshots, a 1024×500 feature graphic.
3. App content: privacy policy URL, data safety (answers in `docs/play-store-listing.md`),
   content rating, target audience 18+, account deletion URL
   (`.../privacy-policy.html#delete-account`).
4. Start with **Internal testing** → upload the `.aab` → add your testers' emails.
   New personal developer accounts must run a **closed test with at least 12 testers for
   14 days** before production.

## Before going public

- Have a native speaker check the French and Arabic texts (`lib/l10n.dart`).
- Have the Terms and Privacy text checked (`lib/legal.dart`), ideally by someone who
  knows Algerian law, especially the rules on foreign currency exchange.
- Run every SQL file in `sql/` and deploy every function in `supabase/functions/`.
