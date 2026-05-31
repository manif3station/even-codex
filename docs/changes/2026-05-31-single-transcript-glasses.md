# 2026-05-31 Single Transcript Glasses Update

`D2-Codex` now keeps the glasses surface on one full-screen transcript window.

What changed:

- swipe up and swipe down stay on the native Even text-scroll path
- the glasses page no longer swaps into summary, network, or input panes
- click is treated only as a transcript refresh hint in the current simulator
- staged query `Send`, `Retry`, and `Cancel` controls remain on the phone-side plugin

Why:

- the current Even docs say one capture container should own input
- the native glasses scroll path is stronger than app-side pane switching for transcript reading
- the current Even docs do not document a native hold-to-dictate popup flow
