# Cloud Photo Vault · Android + Google Drive

**Status** · Android 11+ personal-testing MVP for Google Drive backup and verified cleanup.

## What works in the source

- Google account sign-in with the official `google_sign_in` 7.x plugin
- Permission-based scanning of phone photos and videos, including Android 14+ limited access
- Gallery selection or **Back up all new photos** button
- Original-quality file upload to the user's own Google Drive (folder: `Cloud Photo Vault / YYYY / MM`)
- Streaming file hashing (MD5) to avoid loading large videos into RAM
- Duplicate detection using Google Drive `appProperties`, plus SQLite backup history
- File size + MD5 verification from Google Drive before marking any file safe
- A separate fresh Drive re-verification **and fresh local file checksum** before Move to Bin
- Android 11+ **system** Move to Trash approval (`photo_manager`); no permanent-delete API
- Background schedule using Android WorkManager, every ~6 hours (best effort); no automatic trashing
- Wi-Fi-only toggle, progress, optional stop after current file, backup history counts
- Simple unit tests for verification safety rules

## You need

- Flutter SDK, Android SDK + Android Studio, Java 17+ (a recent Flutter installation includes integration)
- Physical Android 11+ phone with Google Play Services
- Google Cloud account to create an OAuth application
- No paid developer/server hosting required for personal device testing (Google quotas and platform terms still apply)

## Set up the Android project

Use Flutter 3.44.0, a full JDK 17 or newer, and Android SDK Platforms 35 and 36. This repository includes the Android host. To generate it from the original source-only archive, run `python3 scripts/setup_android.py`.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

## Set up persistent signing for GitHub Actions

Create a dedicated personal-testing PKCS#12 keystore once, outside the checkout. The command prompts for a password. Keep a protected copy of the keystore and its password so future APKs can update the installed app and use the same OAuth fingerprint.

```bash
keytool -genkeypair -storetype PKCS12 -keystore /path/outside/repo/vault-debug.p12 \
  -alias vault-debug -keyalg RSA -keysize 2048 -validity 10000 \
  -dname 'CN=Cloud Photo Vault Debug'
keytool -list -v -storetype PKCS12 -keystore /path/outside/repo/vault-debug.p12 -alias vault-debug
```

In the GitHub repository, open **Settings → Secrets and variables → Actions → Secrets** and add `ANDROID_DEBUG_KEYSTORE_BASE64` and `ANDROID_DEBUG_KEYSTORE_PASSWORD`. With GitHub CLI on Linux or macOS, you can stream the keystore into the secret without writing a base64 file:

```bash
base64 < /path/outside/repo/vault-debug.p12 | gh secret set ANDROID_DEBUG_KEYSTORE_BASE64 --repo OWNER/REPO
gh secret set ANDROID_DEBUG_KEYSTORE_PASSWORD --repo OWNER/REPO
```

The second command prompts for the password. Both values are private. Reuse the same keystore across runs.

## Configure Google Drive API and OAuth

1. In [Google Cloud Console](https://console.cloud.google.com/), create or select one project and enable **Google Drive API**.
2. Under **Google Auth Platform**, configure Branding and Audience. Choose **External** and keep the app in **Testing** for personal Gmail use. Add your Google account under **Test users**. In **Data Access**, add `https://www.googleapis.com/auth/drive.file`.
3. Under **Clients**, create an **Android** client with package name `com.example.cloud_photo_vault` and the SHA-1 shown by `keytool`. You can also use the certificate SHA-1 in the Actions run summary or its `signing-certificate.txt` artifact file. If the APK report omits the colons, insert one between each pair of hex digits.
4. In the same project, create a **Web application** OAuth client. Copy its ID ending in `.apps.googleusercontent.com`.
5. In GitHub repository **Settings → Secrets and variables → Actions → Variables**, create `GOOGLE_WEB_CLIENT_ID` with that Web client ID. You can also enter the public ID in the workflow’s optional input when running it manually. The workflow compiles it into the APK through `--dart-define`. The client ID is public. Keep the Web client secret out of the app, repository, and build.

## Build and install on an Android phone

1. On GitHub, open **Actions → Android debug APK → Run workflow** and run it from the default branch. Open the completed run and download **cloud-photo-vault-android-debug** under **Artifacts**. When the Web client ID is missing, the workflow produces an installation-check APK with Drive sign-in unavailable.
2. Extract the artifact ZIP. On an Android 11+ phone with Google Play Services, copy or download `cloud-photo-vault-debug.apk` and open it in Files.
3. If Android prompts you, open **Settings** from the prompt and enable **Allow from this source** for the app opening the APK. Return to the installer and tap **Install**, then **Open**. You can turn off **Allow from this source** afterward.
4. Open Cloud Photo Vault, connect Google Drive with the account you added as a test user, and grant access. Back up a throwaway photo before trying cleanup.
5. For updates, install the newly built APK over the existing app using the same signing certificate. If Android reports a different signer, first check that CI is using the original keystore. Uninstalling clears local backup history.

For USB installation, enable USB debugging, approve the computer on the phone, then run `adb install -r cloud-photo-vault-debug.apk`.

## Setup: 3. Test safely

**Do not start with your real camera roll.** On a non-critical test phone, create a few throwaway images and one small test video.

1. Connect Google Drive in the app and approve permissions.
2. Scan gallery, select **one test image**, and Back up selected.
3. Open the Google Drive app/web and check `Cloud Photo Vault / YYYY / MM` has the original file.
4. Open **Clean up**, select that single test image, and confirm; approve Android's system dialog.
5. Check the phone's gallery Bin/Trash and check the Drive file is still intact and downloadable.
6. Repeat for a video, no-Wi-Fi case, quota-full case, login expiry, interrupted upload, and a cloud file intentionally deleted after backup (it should **not** be moved to Bin).
7. On Android 14+, test full and limited photo access separately.

## Build an APK for personal testing

```bash
flutter build apk --debug --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com
```

Expected local output **after a successful build on your computer**: `build/app/outputs/flutter-apk/app-debug.apk`.

For an APK signed with the same certificate as GitHub Actions, set `VAULT_DEBUG_STORE_FILE` to the absolute keystore path and `VAULT_DEBUG_STORE_PASSWORD` to the password before running the build. When both variables are absent, local Gradle uses the usual Android debug keystore. Register that certificate separately if testing local sign-in with it.

## Background mode reality

Android WorkManager will **try** periodic backup approximately every 6 hours if Automatic backup is on, the network constraint is met, Android allows work, previously authorised Google credentials are available, and the device has sufficient battery. WorkManager is **not** an exact timer, the OS can defer/interrupt jobs, and big libraries may require several runs. Each run is capped at 50 items. If silent Google authorisation is unavailable, the job pauses until you re-open the app and reconnect; never force a login prompt from the background worker.

The app *never* moves a file to Bin in a background task. Moving to Bin requires a user action and Android's confirmation.

For production, consider a visible foreground service for very large user-started uploads, a resumable upload session store, retries/backoff, user-visible failure reports and more instrumentation.

## Safety caveats

- This MVP is for personal testing. The unit tests exercise the verification predicate. Use the device checklist above to exercise OAuth, MediaStore confirmation and WorkManager.
- Google Drive is **not** Google Photos; files go into Drive folders and won't appear in Google Photos unless uploaded separately.
- The local SQLite history is private app data; uninstalling the app clears the local history. The Drive file metadata still supports duplicate recovery by MD5 when a new backup is run.
- If a local media ID is recycled, the app recomputes the original checksum and Drive checksum before clean-up.
- Photos synced with another gallery/cloud provider may have additional delete sync semantics. Check those providers separately.
- Android Bin/Trash may still consume phone storage until emptied, and recovery duration varies by Android/gallery implementation.
- The Drive `drive.file` scope is deliberately narrow. This app cannot scan unrelated existing Drive files or assume that it has access to arbitrary Drive folders.
- Large video uploads stream data, but the Google API client's upload session is not persisted across app restarts; an interrupted file may upload again on the next run. The app checks its Drive file metadata and appProperties to reduce duplicates.
- Materially changed photos are treated as new contents and uploaded again. The older cloud copy is not removed.
- Repeated, huge photo libraries will need performance optimisation and on-device reliability trials.
- Store policies and OAuth verification need review before Play Store publication, especially for broad photo/video access. You will need a privacy policy and app information disclosures.

## Security model

The app uses OAuth in the mobile app, but never stores the user's Google password, uses no third-party photo upload server, never hardcodes OAuth secrets, and never permanently deletes media. The SQLite database only stores file references and checksum metadata locally. Network traffic goes directly to Google Drive API over HTTPS.

## Project layout

```
lib/
  main.dart                       app shell
  core/
    drive_gateway.dart            Google OAuth + Drive API upload / verification
    backup_database.dart          SQLite backup records and run lock
    media_backup.dart             safe backup + verify + trash flow
    auto_backup.dart              WorkManager scheduling and prefs
    vault_controller.dart         UI orchestration
    models.dart                   backup records + safety predicate
  ui/
    vault_home.dart               Dashboard / Photos / Clean up / Settings
test/
  safety_rules_test.dart          checks that verification gates trash
scripts/
  setup_android.py                generates Android host with required permissions
```

## Suggested next milestones

Before public release: real-device APK testing, Google OAuth release verification, better background upload mechanism, notification status, richer backup log, recovery flow to download files back from Drive, accessibility and localisation, performance tests with 50k+ photos, app icon and privacy policy.
