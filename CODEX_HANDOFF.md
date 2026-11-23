# Codex handoff: Cloud Photo Vault Android MVP

Use the files in this directory as the existing project; do not start from scratch.

Tasks in order:

1. Install/locate Flutter and Android SDK and run `python3 scripts/setup_android.py`.
2. Run `flutter pub get`, `flutter analyze`, `flutter test` and resolve all compile/runtime issues against the installed versions of googleapis/google_sign_in/photo_manager/workmanager.
3. Configure an OAuth Android client matching `com.example.cloud_photo_vault` and the debug SHA-1 plus a Web client ID. Do not commit real secrets or any personal photos.
4. Build and test Android 11, 13, 14/15/16 with full and partial gallery access.
5. Verify a never-delete-before-confirmed-upload invariant. No permanent-delete API. Ensure cloud checks and local hashes are re-evaluated at clean-up time.
6. Test interrupted uploads, repeated uploads, token expiration, missing Drive files, quota errors, zero-length files, video uploads >100 MB, multi-account sign-in and Android OS dialog denials.
7. Package a debug APK, include build logs and a short checklist of passed tests. Do not claim production readiness before device tests.

Product requirements: Android first, Google Drive first, both manual and best-effort auto backup, auto backup never auto deletes, user-confirmed Move to Bin only after live re-verification.
