"""Every Java/Kotlin class the Dart code looks up by name over JNI must exist in the
APK's dex under that exact name, or the app throws ClassNotFoundException at run time
(v0.13.0-0.13.2: R8 removed classes that package:jni and shared_preferences reach by
name, and Google sign-in failed). The release workflow runs this on every APK.

Usage: python -I tool/check_jni_classes.py <app.apk>   (exit 1 when a class is missing)
"""
import re
import sys
import zipfile

apk = zipfile.ZipFile(sys.argv[1])
dex = b''.join(apk.read(n) for n in apk.namelist() if re.fullmatch(r'classes\d*\.dex', n))
libs = [n for n in apk.namelist() if n.endswith('/libapp.so')]
so = apk.read(libs[0])

# Class names as JNI wants them: slash-separated, in the packages JNI code reaches.
pattern = rb'(?:kotlin|io/flutter/plugins|com/github/dart_lang|androidx)/[A-Za-z0-9_/$]+'
wanted = sorted({m.decode() for m in re.findall(pattern, so)})
missing = []
for name in wanted:
    if name.endswith('/'):
        continue
    if b'L' + name.encode() + b';' not in dex:
        missing.append(name)

print(f'{libs[0]}: {len(wanted)} JNI class names referenced from Dart')
for name in wanted:
    print(('  MISSING ' if name in missing else '  ok      ') + name)
print('RESULT:', 'FAIL' if missing else 'PASS', f'({len(missing)} missing)')
sys.exit(1 if missing else 0)
