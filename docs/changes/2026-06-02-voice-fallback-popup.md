# 2026-06-02 Voice Fallback Popup

`even-codex` now replaces the glasses popup `Voice UNSUPPORTED` dead-end with a
usable phone-composer fallback.

What changed:

- when browser speech recognition is unavailable, a glasses click no longer
  marks the popup as unsupported
- the popup now guides the user into the companion phone composer path instead
- the companion textarea is focused automatically so the phone keyboard
  microphone or typed input can continue the flow immediately
- the empty-close guidance now points back to the phone mic or composer instead
  of leaving the popup in a dead-end unsupported state
