# 2026-06-02 transcript live-follow

`even-codex` now treats the glasses transcript as a live-follow stream with an
explicit manual-review state.

## What changed

- the default transcript view now shows the newest bottom lines instead of
  resetting the operator back to the top during each background refresh
- transcript-only refreshes now use in-place text upgrades instead of rebuilding
  the full glasses page container
- when the operator swipes up on the closed transcript surface, the app stops
  auto-following and preserves the manual review position
- when the operator returns to the latest bottom line with `Down`, live-follow
  resumes and new transcript lines become visible again

## Why it changed

The earlier glasses refresh path rebuilt the page container every time the
background bridge poll updated the transcript. That reset the Even text
container state and made the newest lines hard to reach during live streaming.
The governed fix keeps the latest lines visible by default without stealing
control from an operator who intentionally scrolls up.
