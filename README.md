<div align="center">
  <h1 align="center">
    JMcomic3 Flutter

[![license](https://img.shields.io/github/license/QwQqwqsss/JMcomic3-flutter)](https://raw.githubusercontent.com/QwQqwqsss/JMcomic3-flutter/main/LICENSE)
[![releases](https://img.shields.io/github/v/release/QwQqwqsss/JMcomic3-flutter)](https://github.com/QwQqwqsss/JMcomic3-flutter/releases)
  </h1>
</div>

A comic browser, support Android / iOS / macOS / Windows / Linux.

1. This APP has restricted content
2. Please know local laws before using these codes
3. The owner of the repo will not release these codes and its assets to the community outside GitHub

## Features

- [x] Comics
  - [x] Comic categories
  - [x] Comic reader
  - [x] Comic search
  - [x] Comic favours
  - [x] Histories
  - [x] Cache comic
- [ ] Games
- [x] Community
  - [x] List comments
  - [x] Send comments
- [x] User
  - [x] Login / Register
- [x] Devices adaptation
  - [x] Android's high frequency screen

## Technical architecture

Flutter: high-performance UI

Rust: high performance service

![](images/technologies.png)

## Android release (32/64-bit split + smaller package)

1. Build and sync Rust JNI `.so` for Android ABIs (`arm64-v8a`, `armeabi-v7a`):

```bash
RUST_ANDROID_ABIS="arm64-v8a armeabi-v7a" ./scripts/build_android_rust_jnilibs.sh
```

2. Build split APKs (recommended when distributing APK files directly):

```bash
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

3. Use the PowerShell helper script (build APK split + AAB together):

```powershell
.\scripts\build_android_release_split.ps1
# only split APK:
.\scripts\build_android_release_split.ps1 -ApkOnly
# only AAB:
.\scripts\build_android_release_split.ps1 -AabOnly
```

4. Build App Bundle (`.aab`) for store delivery:

```bash
flutter build appbundle --release --target-platform android-arm,android-arm64
```

Notes:
- `release` already enables `minifyEnabled true` + `shrinkResources true`.
- Use `--target-platform android-arm,android-arm64` to avoid packaging unnecessary ABI outputs.
- `scripts/sign-apk-github-actions.sh` now signs all `*-release.apk` outputs (including split APKs).

## Configuration compatibility

- Integer and boolean settings are parsed through shared helpers so old local properties, WebDAV snapshots, and manual migrations can use integer-like decimal strings, `true/false`, `yes/no`, `on/off`, `1/0`, or up to two JSON string layers without breaking app startup. Invalid values still fall back instead of being guessed.
- WebDAV, proxy, and export-path string settings unwrap up to two JSON string layers. URL, username, proxy, and path values are trimmed, while passwords preserve meaningful leading/trailing spaces.
- Enum settings accept both `EnumType.value` and bare `value`, ignore case and surrounding whitespace, and unwrap up to two JSON string layers before falling back to the configured default.
- Locale and theme settings normalize common legacy aliases such as `en_US`, `zh-Hans-CN`, `auto`, `light`, and `dark` into the current app protocol values before startup applies them.
- Homepage category order accepts JSON arrays and up to two JSON string layers, then filters duplicate, non-positive, or invalid category IDs while preserving the saved order.
- Auto-clean interval settings accept JSON-wrapped integer-like values only when they match the supported UI intervals; unknown or negative values fall back to the default weekly cleanup instead of silently disabling cleanup.
- API/CDN routing settings normalize URL-like input into `host[:port]` before displaying, pinging, or saving; full URLs, protocol-relative URLs, accidentally pasted userinfo, and up to two JSON string layers are stripped to the actual host authority. Host lists also split newline/semicolon-separated values and comma-separated values when the next token is clearly another URL/host, then dedupe case-insensitively.
- Android refresh-rate mode unpacks old JSON-wrapped cache values but only keeps modes reported by the current device, so stale values fall back to the system default mode.
- Recommended links from `config_links` are trimmed, empty labels/URLs are dropped, the legacy follow-channel entry is forced to the current channel URL, and the displayed map is immutable so UI code cannot mutate global config state.
- Download metadata fields such as author, tags, and works tolerate plain text, arrays, JSON string arrays, and one extra JSON string layer while filtering empty items.
- Backend list/map responses are decoded through shared helpers; if older Rust/MethodChannel bridges wrap `response_data` as JSON strings containing a list or object, the Flutter side unwraps up to two extra layers before validating the expected shape. List responses can also unwrap nested known object payload keys such as `data`, `items`, `list`, `hosts`, and `servers` with a bounded object depth; string-list APIs additionally accept a single scalar inside those trusted shells, and a matched `data:null` remains an explicit empty list instead of falling through to later keys.
- Reader image true-size lookups cache the in-flight backend `image_size` future per page image, so dual-page rendering and preloading share the same bridge request. String numeric width/height values are still accepted for old bridge/test responses.

## Runtime behavior

- 下载列表页使用惰性 `ListView.builder` 构建可见卡片，并在导入、导出、删除和详情页返回后检查页面仍挂载再刷新，避免大量下载记录时进入页面一次性创建所有卡片。

## Please follow the rules

- These codes can only be learned and used, and are prohibited for commercial use
- Do not send assets to anyone
