# 2026-06-02 Plugin Auto-Refresh Proof

`even-codex` now records an explicit proof that the phone-side `D2-Codex`
plugin updates live session status without a manual refresh click.

What changed:

- made the phone-side status merge treat the bridge payload as authoritative for
  latest prompt, progress, and reply values
- prevented stale progress text from lingering after the live session no longer
  reports an in-flight assistant update
- added a browser-level Playwright proof that changes the live session payload
  after the plugin has already loaded and verifies the UI updates on its own
