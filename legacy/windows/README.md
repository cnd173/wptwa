# Legacy Windows implementation

This directory preserves the original Python/tkinter implementation for historical reference.
It is not a supported release target and receives syntax checks only.

Safety changes retained in the archived source:

- arranging is off at launch and requires an explicit user action;
- process matching uses exact WPT Global executable names instead of broad `wpt`/`poker`
  substrings;
- unknown WPT windows are ignored rather than treated as the lobby;
- session timing is manual and has an explicit stop control;
- the historical network/performance monitor has been removed.

The executable names and window-title rules have not been verified against current Windows
WPT Global builds. Do not distribute a Windows binary without testing and reviewing the target
adapter on Windows first.
