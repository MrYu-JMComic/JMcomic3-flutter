# JMComic3 Flutter

[![Release](https://img.shields.io/github/v/release/MrYu-JMComic/JMcomic3-flutter)](https://github.com/MrYu-JMComic/JMcomic3-flutter/releases/latest)

[简体中文](README-zh.md) · English

JMComic3 is a Flutter comic reader with a Rust service backend. This repository
maintains the Flutter app, Android and Windows runners, tests, and local release
tools. The stable release is **v1.7.26+55**.

## Download

Get locally built packages from [GitHub Releases](https://github.com/MrYu-JMComic/JMcomic3-flutter/releases/latest).

| Package | Use |
| --- | --- |
| `Jmcomic3-arm64-v8a-*.apk` | Most current Android devices |
| `Jmcomic3-armeabi-v7a-*.apk` | Devices that require 32-bit ARM |
| `Jmcomic3-android-*.aab` | App Bundle for distribution tooling; cannot be installed directly |
| `Jmcomic3-windows-x64-*.zip` | Extract the entire archive and run `jmcomic3.exe` |
| `SHA256SUMS.txt` / `build-info.json` | Integrity and build provenance |

Keep the Windows executable, DLLs, and `data` directory together. The executable
is unsigned; some systems require the Visual C++ runtime.

Android v1.7.26+55 keeps the signing key used for the published v1.7.25+54.
Install the same ABI package to update that version. Installations signed with
an older key require a data backup and reinstall.

The verified release matrix is **Android ARM64/ARM32 and Windows x64**.
Other platforms are not part of this release.

## Features

- Browse, search, categories, comic details, colored tags, and chapter lists.
- Favorites, reading history, weekly selections, and comments.
- Continuous, zoomable continuous, single-page, and double-page reading, with
  directional navigation and progress saved from the visible page.
- Offline chapters, download management, import/export, and WebDAV sync.
- Responsive navigation, themes, locales, and network route settings.

See [CHANGELOG.md](CHANGELOG.md) for stable release changes.

## Development

Flutter is pinned by [.fvmrc](.fvmrc). The backend is maintained separately in
[jmcomic3-rust-backend](https://github.com/MrYu-JMComic/jmcomic3-rust-backend);
its release revision is pinned in [ci/backend.commit.txt](ci/backend.commit.txt).
Backend checkouts, toolchains, signing keys, and build outputs are ignored.

- [Build and test instructions](docs/BUILDING.md)
- [Branch, PR, and release procedure](docs/RELEASING.md)
- [Android reader regression](integration_test/README.md)

## References and acknowledgments

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine): Flutter reader
  structure and reading interaction reference, pinned to
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470).
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python):
  mobile API protocol, request signing/headers, login, and domain fallback
  reference for the Rust backend. It is not a Python runtime dependency.
- `zoomable_positioned_list` 1.1.0: vendored continuous reader component, with
  original notices and the local patch recorded in
  [PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md).

[REFERENCES.md](REFERENCES.md) records the reference scope and retained notices.
Upstream names and copyrights belong to their authors. This project is
independently maintained.

## Usage

The app accesses third-party services whose availability may vary. Use it for
personal study in accordance with local rules and content rights. The inherited
project policy prohibits commercial use and redistribution of content assets.
Third-party components retain their own license terms.