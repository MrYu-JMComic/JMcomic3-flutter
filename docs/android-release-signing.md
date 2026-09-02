# Android Release Signing

The local release build is configured through the ignored `android/key.properties` file. Keep the keystore and its passwords outside the repository and back them up together; neither file should be committed.

The current local release/upload keystore is stored outside the repository. Its certificate is:

- Alias: `upload`
- Algorithm: RSA 4096 / SHA256withRSA
- SHA-256 certificate fingerprint: `43:EA:CE:CF:C5:81:C5:18:7B:73:22:C3:E6:95:8A:AE:7F:F0:0E:28:FA:B0:FA:52:14:B8:DA:AA:9D:37:26:23`

Build signed artifacts after restoring the local `android/key.properties`:

```powershell
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
flutter build appbundle --release --target-platform android-arm,android-arm64
```

Verify an APK with Android Build Tools:

```powershell
& "$env:ANDROID_HOME\build-tools\35.0.0\apksigner.bat" verify --verbose --print-certs .\build\app\outputs\flutter-apk\app-release.apk
```

The verified local artifacts are:

- `build/app/outputs/flutter-apk/app-release.apk` (v2 signature verified)
- `build/app/outputs/bundle/release/app-release.aab` (JAR signature verified; a self-signed local certificate produces the expected trust warning)

This certificate is newly generated for this checkout. It cannot update an app already signed with a different certificate. For Google Play, register it as the upload key only if the Play Console application is configured for a new upload certificate; never replace an existing app-signing key casually. The GitHub Actions release workflow continues to use its own `KEY_FILE_BASE64` and `KEY_PASSWORD` secrets and must be updated separately if this certificate is intended for CI releases.
