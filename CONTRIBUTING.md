# Contributing

Contributions are welcome when they preserve the project's narrow scope: explicit user-controlled window organization without gameplay automation or poker-data collection.

## Development

Requirements: macOS 13+, Swift 5.9+, and Xcode Command Line Tools or Xcode. Full Xcode is required to run XCTest on systems where the standalone Command Line Tools package omits it.

```bash
cd macos/WPTTableArranger
swift build
swift test
bash -n build_app.sh
```

The legacy Windows source can be syntax-checked with:

```bash
PYTHONPYCACHEPREFIX=.build/python-cache python3 -m py_compile legacy/windows/*.py
```

## Pull requests

- Keep arrangement opt-in; never start moving windows automatically.
- Match supported clients by an explicit bundle identifier, not a broad process-name substring.
- Do not add screen scraping, HUDs, strategy aids, automated seating, automated betting, or hidden process behavior.
- Add or update tests for pure logic.
- Document new permissions, subprocesses, network access, and persisted data.
- Keep commits focused and explain user-visible behavior in the pull request.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
