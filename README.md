# Poker Table Arranger for macOS

[![CI](https://github.com/cnd173/wptwa/actions/workflows/ci.yml/badge.svg)](https://github.com/cnd173/wptwa/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An unofficial, open-source macOS utility that places supported poker-client windows into configurable screen slots. The current compatibility adapter targets WPT Global.

> **Project status:** experimental and community-maintained. Use it at your own risk. It does not place bets, choose seats, read cards, display player statistics, or provide strategy advice.

[Đọc hướng dẫn tiếng Việt](docs/README.vi.md)

## Safety and scope

- Arrangement is **off by default**. The app never moves a window until the user presses **Start Arranging**.
- Only the exact WPT Global bundle identifier `com.wptglobal.wptg` is accepted. It does not match arbitrary applications containing “poker” or “wpt” in their names.
- Lobby, table, and hand-history windows are positively identified. Unknown WPT windows such as account, cashier, authentication, or security dialogs are ignored.
- The app uses macOS Accessibility APIs to read window titles, positions, and sizes, and to move supported windows.
- The app never writes a window's AX size. Resize a table through WPT itself; arrangement preserves the client-managed size. Slot width/height define layout and drop areas only.
- It does not capture the screen, inspect game pixels, read network payloads, automate gameplay, or hide itself from the poker client.
- It does not inspect poker-client connections, ping poker servers, or collect process-performance statistics.
- Session timing is manual and never starts or stops based on detected poker tables.

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

The Swift compiler and macOS SDK must come from a matching Xcode/Command Line Tools installation. If Swift reports that the SDK is unsupported by the compiler, update or reinstall the developer tools rather than changing the package.

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

Use the session play/pause/stop controls only when you want to keep a local manual record. Closing the main window hides it to the menu bar; choose **Quit** from the menu-bar item to stop the process completely.

Settings and session records remain local under:

```text
~/Library/Application Support/PokerTableArranger/
```

## Release builds

Ad-hoc signatures are not suitable for public binary distribution. Maintainers need an Apple Developer Program membership, a Developer ID Application certificate, Hardened Runtime signing, and Apple notarization. The build script and tag-based release workflow support this flow; see [RELEASING.md](RELEASING.md).

## Legacy Windows version

The original Python/tkinter implementation is preserved in [`legacy/windows`](legacy/windows) for historical reference. It is unsupported, has not been verified against current Windows WPT builds, and is not built by macOS CI beyond Python syntax validation. Its archived UI no longer auto-arranges on launch, automatically tracks sessions, or includes the historical network monitor.

## WPT Global policy and trademarks

As checked on 2026-08-24, WPT Global's Terms and Conditions prohibit automated seating, betting, and table-monitoring software while explicitly stating that “table organization and resizing tools are permitted” in Annex A, item 25. The same Terms separately prohibit access from listed excluded territories; that list currently includes Vietnam. Terms and territorial availability can change, and each user remains responsible for checking the current rules and local law before using WPT Global. This repository is not legal advice.

This project is not affiliated with, endorsed by, or sponsored by WPT Global, World Poker Tour, or their operators. “WPT”, “WPT Global”, related names, and logos are trademarks of their respective owners. No WPT artwork, client code, or proprietary assets are included in this repository.

- [WPT Global Terms and Conditions](https://wptglobal.com/terms-and-conditions)
- [Responsible Gaming](https://wptglobal.com/responsible-gaming)

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

Project source code is available under the [MIT License](LICENSE). The license does not grant rights to third-party trademarks or proprietary poker-client software.
