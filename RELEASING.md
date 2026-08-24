# Releasing

Public binaries must be signed with a stable Developer ID Application certificate and notarized by Apple. Ad-hoc builds are for local development only.

## Prerequisites

- Apple Developer Program membership
- Developer ID Application certificate installed in the signing keychain
- Full Xcode with `notarytool` and `stapler`
- A notary credential profile created with `xcrun notarytool store-credentials`

## Local release

```bash
cd macos/WPTTableArranger
UNIVERSAL=1 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="poker-table-arranger-notary" \
./build_app.sh
```

Verify the result before publishing:

```bash
codesign --verify --deep --strict --verbose=2 "Poker Table Arranger.app"
spctl --assess --type execute --verbose=4 "Poker Table Arranger.app"
xcrun stapler validate "Poker Table Arranger.app"
```

The distributable ZIP is written to `macos/WPTTableArranger/release/`. For a
manual release, publish a SHA-256 checksum alongside it:

```bash
cd macos/WPTTableArranger/release
shasum -a 256 "Poker Table Arranger.zip" > SHA256SUMS
```

## GitHub tag release

The release workflow runs for tags matching `v*`. Configure these repository secrets first:

- `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `DEVELOPER_ID_APPLICATION`: complete signing identity name
- `APPLE_ID`: Apple developer account email
- `APPLE_TEAM_ID`: Apple Developer team identifier
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password used by `notarytool`

Then update `CHANGELOG.md`, commit, and create a SemVer tag such as `v0.1.0`. Never place certificates, passwords, API keys, or notary credentials in the repository.

The tag version is injected into `CFBundleShortVersionString` and the GitHub run number into `CFBundleVersion` during the release build. The checked-in development version remains `0.1.0`. The workflow publishes both the notarized ZIP and `SHA256SUMS`.
