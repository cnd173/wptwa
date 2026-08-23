# Poker Table Arranger for macOS

[![CI](https://github.com/cnd173/wptwa/actions/workflows/ci.yml/badge.svg)](https://github.com/cnd173/wptwa/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An unofficial, open-source macOS utility that places supported poker-client windows into configurable screen slots. The current compatibility adapter targets WPT Global.

> **Project status:** experimental and community-maintained. Use it at your own risk. It does not place bets, choose seats, read cards, display player statistics, or provide strategy advice.

[Đọc hướng dẫn tiếng Việt](docs/README.vi.md)

## Safety and scope

- Arrangement is **off by default**. The app never moves a window until the user presses **Start Arranging**.
- Only the exact WPT Global bundle identifier `com.wptglobal.wptg` is accepted. It does not match arbitrary applications containing “poker” or “wpt” in their names.
- The app uses macOS Accessibility APIs to read window titles, positions, and sizes, and to move supported windows.
- It does not capture the screen, inspect game pixels, read network payloads, automate gameplay, or hide itself from the poker client.
- Network monitoring is optional UI functionality. It inspects the target process's established connection endpoints locally with `lsof` and sends ICMP pings to the detected endpoint or `wptglobal.com`.

See [PRIVACY.md](PRIVACY.md) for the complete data-handling description.

## Compatibility

- macOS 13 or later
- Apple Silicon or Intel Mac
- WPT Global bundle identifier: `com.wptglobal.wptg`
- Swift 5.9 or later for source builds

Poker-client updates can change window titles, resize constraints, bundle identifiers, or Accessibility behavior. Compatibility is therefore best effort.

## Build from source

Install Xcode Command Line Tools or Xcode, then run:

```bash
cd macos/WPTTableArranger
./build_app.sh
open "Poker Table Arranger.app"
```

Running the unit test suite requires full Xcode on systems whose standalone Command Line Tools package does not include XCTest:

```bash
swift test
```

The default build is native-architecture and ad-hoc signed for development. Rebuilding an ad-hoc-signed app may require removing and granting its Accessibility permission again.

For a universal development build:

```bash
UNIVERSAL=1 ./build_app.sh
```

Move a stable build to `/Applications` before granting Accessibility permission. Open **System Settings → Privacy & Security → Accessibility**, enable Poker Table Arranger, then fully quit and reopen it if macOS does not refresh the permission immediately.

## Usage

1. Open the app and grant Accessibility permission.
2. Configure or load a slot layout.
3. Open WPT Global.
4. Press **Start Arranging**.
5. Press **Stop Arranging** before manually reorganizing unrelated workspace layouts.

Settings and session records remain local under:

```text
~/Library/Application Support/PokerTableArranger/
```

## Release builds

Ad-hoc signatures are not suitable for public binary distribution. Maintainers need an Apple Developer Program membership, a Developer ID Application certificate, Hardened Runtime signing, and Apple notarization. The build script and tag-based release workflow support this flow; see [RELEASING.md](RELEASING.md).

## Legacy Windows version

The original Python/tkinter implementation is preserved in [`legacy/windows`](legacy/windows). It uses Windows-only APIs and is not built by the macOS CI job beyond Python syntax validation.

## WPT Global policy and trademarks

At the time of writing, WPT Global's Terms and Conditions prohibit automated seating, betting, and table-monitoring software while explicitly stating that “table organization and resizing tools are permitted” in Annex A, item 25. Terms can change, and users remain responsible for reviewing the current rules.

This project is not affiliated with, endorsed by, or sponsored by WPT Global, World Poker Tour, or their operators. “WPT”, “WPT Global”, related names, and logos are trademarks of their respective owners. No WPT artwork, client code, or proprietary assets are included in this repository.

- [WPT Global Terms and Conditions](https://wptglobal.com/terms-and-conditions)
- [Responsible Gaming](https://wptglobal.com/responsible-gaming)

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

Project source code is available under the [MIT License](LICENSE). The license does not grant rights to third-party trademarks or proprietary poker-client software.
