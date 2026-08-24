# Changelog

All notable user-facing changes will be documented here. This project follows Semantic Versioning once the first public release is tagged.

## Unreleased

- Prepared the project for open-source publication under the MIT License.
- Made window arrangement explicitly opt-in.
- Replaced broad process-name matching with an exact supported-client bundle ID allowlist.
- Added unit tests, continuous integration, privacy/security documentation, and release tooling.
- Renamed the public app display identity to Poker Table Arranger and documented its unofficial status.
- Changed window classification to ignore unknown WPT dialogs.
- Counted only real table windows in arrangement status.
- Made session timing fully manual and added an explicit stop/log control.
- Stopped writing AX window sizes; arrangement now preserves WPT-managed natural sizes.
- Removed network/process monitoring from the macOS app.
- Added slot validation and hardened the archived Windows adapter.
- Serialized magnet-setting changes and hardened slot hit-testing against integer overflow.
- Pinned GitHub Actions and synchronized release bundle versions with tags.
- Added SHA-256 checksums to the signed-release workflow.
