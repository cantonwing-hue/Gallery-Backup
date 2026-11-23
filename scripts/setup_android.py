#!/usr/bin/env python3
"""Generate standard Android Flutter host project and patch required MediaStore permissions.

Must be run from the project's root after Flutter SDK is installed.
This script never writes app credentials or private user data.
"""
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
if not shutil.which('flutter'):
    raise SystemExit('Flutter SDK not found on PATH. Install Flutter before running this script.')

# Flutter creates a counter-app test if this path is absent.
template_test = ROOT / 'test/widget_test.dart'
had_widget_test = template_test.exists()

subprocess.run([
    'flutter', 'create', '--platforms=android', '--org', 'com.example',
    '--project-name=cloud_photo_vault', '.',
], cwd=ROOT, check=True)

if not had_widget_test:
    template_test.unlink(missing_ok=True)

manifest = ROOT / 'android/app/src/main/AndroidManifest.xml'
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
ns = '{http://schemas.android.com/apk/res/android}'
root = ET.parse(manifest).getroot()
permission_names = {
    element.get(ns + 'name') for element in root.findall('uses-permission')
}
permissions = [
    ('android.permission.INTERNET', None),
    ('android.permission.ACCESS_NETWORK_STATE', None),
    ('android.permission.READ_MEDIA_IMAGES', None),
    ('android.permission.READ_MEDIA_VIDEO', None),
    ('android.permission.READ_MEDIA_VISUAL_USER_SELECTED', None),
    ('android.permission.READ_EXTERNAL_STORAGE', '32'),
]
for name, max_sdk in permissions:
    if name in permission_names:
        continue
    element = ET.Element('uses-permission', {ns + 'name': name})
    if max_sdk:
        element.set(ns + 'maxSdkVersion', max_sdk)
    root.insert(0, element)
app = root.find('application')
if app is not None:
    app.set(ns + 'label', 'Cloud Photo Vault')
ET.indent(root, space='    ')
ET.ElementTree(root).write(manifest, encoding='utf-8', xml_declaration=True)

build_kts = ROOT / 'android/app/build.gradle.kts'
build_groovy = ROOT / 'android/app/build.gradle'
if build_kts.exists():
    text = build_kts.read_text()
    new = re.sub(r'\bminSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 30', text)
    if text == new and not re.search(r'\bminSdk(?:Version)?\s*(?:=\s*|\s+)30\b', text):
        raise SystemExit('Please check minSdk is 30 in android/app/build.gradle.kts')
    build_kts.write_text(new)
elif build_groovy.exists():
    text = build_groovy.read_text()
    new = re.sub(r'\bminSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 30', text)
    if text == new and not re.search(r'\bminSdk(?:Version)?\s*(?:=\s*|\s+)30\b', text):
        raise SystemExit('Please check minSdk is 30 in android/app/build.gradle')
    build_groovy.write_text(new)
else:
    raise SystemExit('Flutter create did not generate Android Gradle project.')

print('Android project created. Minimum Android version: 11 (API 30).')
print('Next: flutter pub get && flutter test')
print('Then configure Google OAuth and run flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=...')
