# Privacy

This policy describes the current macOS application. The archived Windows source is unsupported; review it independently before use.

Poker Table Arranger has no analytics, advertising, user accounts, cloud storage, or telemetry.

## Data accessed

With macOS Accessibility permission, the app can access the following information for explicitly supported poker clients:

- application process identifier;
- window title;
- window position, size, minimized state, and window lifetime.

The app uses this information only to classify supported windows and change their positions. Unknown client windows are ignored, and the app does not write window sizes. It does not capture screen pixels, inspect cards, collect player identities, read chat, or access poker-account credentials.

The macOS app does not inspect poker-client network connections, run network probes, or collect process-performance statistics.

## Data stored

Configuration, presets, language settings, and manually entered session/bankroll records are stored locally in:

```text
~/Library/Application Support/PokerTableArranger/
```

No stored data is transmitted by the app. Removing that directory deletes the app's local data.

## Permissions

Accessibility permission is required to enumerate and move another application's windows. Screen Recording permission is not requested. Permission can be revoked at any time in **System Settings → Privacy & Security → Accessibility**.
