#!/usr/bin/env python3
"""Regression tests for the generated Android Gradle patch (Kotlin DSL + Groovy)."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("patch_build_gradle.py")

KTS_TEMPLATE = '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        applicationId = "com.example.app"
        minSdk = flutter.minSdkVersion
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
}
'''

GROOVY_TEMPLATE = '''plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
    id 'dev.flutter.flutter-gradle-plugin'
}

android {
    namespace 'com.example.app'
    compileSdkVersion flutter.compileSdkVersion
    defaultConfig {
        applicationId 'com.example.app'
        minSdkVersion flutter.minSdkVersion
    }
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}

dependencies {
}
'''


class GradlePatchTests(unittest.TestCase):
    def _run_patch(self, path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            check=False,
            capture_output=True,
            text=True,
        )

    def _assert_common(self, path: Path, *, kts: bool) -> str:
        source = path.read_text(encoding="utf-8")
        plugins_at = source.index("plugins {")
        self.assertLess(source.index("import java.util.Properties"), plugins_at)
        self.assertLess(source.index("import java.io.FileInputStream"), plugins_at)
        self.assertEqual(source.count("val cobraKeystoreProperties = Properties()") if kts else source.count("def cobraKeystoreProperties = new Properties()"), 1)
        self.assertIn("minSdk = 24" if kts else "minSdkVersion 24", source)
        self.assertIn("proguard-rules.pro", source)
        self.assertEqual(source.count("tesseract4android:tesseract4android:4.9.0"), 1)
        self.assertIn("https://jitpack.io", source)
        self.assertEqual(source.count("signingConfigs {"), 1)
        android_at = source.index("android {")
        signing_at = source.index("signingConfigs {")
        self.assertGreater(signing_at, android_at)
        plugin_close = source.index("\n}\n", plugins_at) + 3
        loader_at = source.index("cobraKeystoreProperties =")
        self.assertGreater(loader_at, plugin_close)
        return source

    def test_kotlin_dsl_import_order_signing_and_idempotence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "build.gradle.kts"
            path.write_text(KTS_TEMPLATE, encoding="utf-8")

            first = self._run_patch(path)
            self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
            source = self._assert_common(path, kts=True)
            self.assertIn('signingConfig = if (cobraKeystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', source)
            self.assertEqual(source.count('implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")'), 1)

            first_output = path.read_text(encoding="utf-8")
            second = self._run_patch(path)
            self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
            self.assertEqual(path.read_text(encoding="utf-8"), first_output)

    def test_groovy_import_order_signing_and_idempotence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "build.gradle"
            path.write_text(GROOVY_TEMPLATE, encoding="utf-8")

            first = self._run_patch(path)
            self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
            source = self._assert_common(path, kts=False)
            self.assertIn('(cobraKeystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug)', source)
            self.assertEqual(source.count("implementation 'cz.adaptech.tesseract4android:tesseract4android:4.9.0'"), 1)

            first_output = path.read_text(encoding="utf-8")
            second = self._run_patch(path)
            self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
            self.assertEqual(path.read_text(encoding="utf-8"), first_output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
