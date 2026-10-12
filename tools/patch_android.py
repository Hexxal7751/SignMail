#!/usr/bin/env python3
"""Customises the Android project that `flutter create` generates in CI.

Run from anywhere after `flutter create`. It:
  * copies the launcher icon and notification icons from branding/android/res
  * adds the permissions the app needs and names the app "SignMail"
  * enables core-library desugaring (needed by flutter_local_notifications)
  * switches MainActivity to FlutterFragmentActivity (needed by local_auth)

Every step is safe to run twice.

Options:
  --builtin-kotlin   switch the project to Android's built-in Kotlin support
  --legacy-kotlin    switch back to the Flutter template defaults
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "android" / "app"
BRANDING = ROOT / "branding" / "android" / "res"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.USE_BIOMETRIC",
]


def fail(message: str) -> None:
    print(f"patch_android: {message}", file=sys.stderr)
    sys.exit(1)


def copy_resources() -> None:
    if not BRANDING.is_dir():
        fail(f"missing {BRANDING}")
    target = APP / "src" / "main" / "res"
    count = 0
    for source in BRANDING.rglob("*"):
        if source.is_file():
            destination = target / source.relative_to(BRANDING)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            count += 1
    print(f"copied {count} branding resources")


def patch_manifest() -> None:
    path = APP / "src" / "main" / "AndroidManifest.xml"
    text = path.read_text()

    missing = [
        f'    <uses-permission android:name="{name}"/>\n'
        for name in PERMISSIONS
        if name not in text
    ]
    if missing:
        if "<application" not in text:
            fail("AndroidManifest.xml has no <application> element")
        text = text.replace("<application", "".join(missing) + "    <application", 1)

    text = re.sub(r'android:label="[^"]*"', 'android:label="SignMail"', text, count=1)
    path.write_text(text)
    print("patched AndroidManifest.xml")


def patch_gradle() -> None:
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"

    if kts.exists():
        text = kts.read_text()
        if "isCoreLibraryDesugaringEnabled" not in text:
            patched, n = re.subn(
                r"(compileOptions\s*\{)",
                r"\1\n        isCoreLibraryDesugaringEnabled = true",
                text,
                count=1,
            )
            if n != 1:
                fail("could not find compileOptions in build.gradle.kts")
            text = patched
        if "desugar_jdk_libs" not in text:
            text += (
                "\ndependencies {\n"
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
                "}\n"
            )
        kts.write_text(text)
    elif groovy.exists():
        text = groovy.read_text()
        if "coreLibraryDesugaringEnabled" not in text:
            patched, n = re.subn(
                r"(compileOptions\s*\{)",
                r"\1\n        coreLibraryDesugaringEnabled true",
                text,
                count=1,
            )
            if n != 1:
                fail("could not find compileOptions in build.gradle")
            text = patched
        if "desugar_jdk_libs" not in text:
            text += (
                "\ndependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
                "}\n"
            )
        groovy.write_text(text)
    else:
        fail("no app/build.gradle(.kts) found")
    print("patched app Gradle file")


def patch_activity() -> None:
    files = list((APP / "src" / "main").rglob("MainActivity.*"))
    if not files:
        fail("MainActivity not found")
    for path in files:
        text = path.read_text()
        text = text.replace(
            "io.flutter.embedding.android.FlutterActivity",
            "io.flutter.embedding.android.FlutterFragmentActivity",
        )
        text = re.sub(r"\bFlutterActivity\b", "FlutterFragmentActivity", text)
        path.write_text(text)
    print("patched MainActivity")


def set_kotlin_mode(builtin: bool) -> None:
    path = ROOT / "android" / "gradle.properties"
    value = "true" if builtin else "false"
    lines = path.read_text().splitlines() if path.exists() else []
    wanted = {"android.builtInKotlin": value, "android.newDsl": value}
    out = []
    for line in lines:
        key = line.split("=", 1)[0].strip()
        if key in wanted:
            line = f"{key}={wanted.pop(key)}"
        out.append(line)
    out.extend(f"{key}={val}" for key, val in wanted.items())
    path.write_text("\n".join(out) + "\n")
    print(f"gradle.properties: builtInKotlin/newDsl = {value}")


if __name__ == "__main__":
    if not APP.is_dir():
        fail("android/ not found; run `flutter create` first")
    if "--builtin-kotlin" in sys.argv:
        set_kotlin_mode(True)
    elif "--legacy-kotlin" in sys.argv:
        set_kotlin_mode(False)
    else:
        copy_resources()
        patch_manifest()
        patch_gradle()
        patch_activity()
