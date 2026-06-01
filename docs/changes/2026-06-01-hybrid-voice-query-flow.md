# 2026-06-01 Hybrid Voice Query Flow

## Summary

`even-codex` now ships a governed hybrid voice-query flow for the `D2-Codex`
Even Hub app. The glasses popup remains a custom SDK container layout, but a
glasses click can now arm speech recognition in the companion WebView when the
runtime exposes a supported DOM speech-recognition implementation.

## What changed

- added the documented `g2-microphone` manifest permission
- added a bridge and speech-recognition override hook so the runtime can be
  proven in governed browser checks
- added explicit phone-side `Start Voice` and `Stop Voice` controls
- mirrored recognised text into both the popup draft and phone-side composer
- kept the existing `Send`, `Retry`, and `Cancel` flow for submission
- closed the popup cleanly on an empty standby click instead of surfacing a
  dead-end send error

## Alignment

The attached modal-flow research and PDF review both pointed to the same
practical reading of the current Even SDK:

- no native glasses-side editable text field exists
- microphone audio and click gestures are supported
- the strongest shippable flow is a hybrid glasses popup plus companion-WebView
  text state

The current implementation follows that model directly.
