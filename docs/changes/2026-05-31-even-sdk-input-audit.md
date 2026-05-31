# 2026-05-31 Even SDK Input Audit

This release re-checked the current Even docs for glasses input behavior.

Current documented glasses input:

- click
- double-click
- swipe up
- swipe down

Current documented SDK constraints:

- one container should own `isEventCapture: 1`
- text scrolling is native to the glasses text container
- the current public docs do not document a glasses `hold` gesture
- the current public docs do not document a native hold-to-dictate popup with `Send`, `Retry`, and `Cancel`

Official references checked on 2026-05-31:

- https://hub.evenrealities.com/docs/guides/input-events
- https://hub.evenrealities.com/docs/guides/display
- https://hub.evenrealities.com/docs/guides/device-apis
