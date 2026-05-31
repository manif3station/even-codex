# 2026-05-31 Live Query Loop

This release closes the last fake part of the Even-to-Codex flow.

The bridge now accepts `POST /prompt`, resolves the paired Codex TUI tty, and
writes the staged query into the real resumed session. The transcript parser now
surfaces both assistant progress text and recent turns, which lets the phone
plugin show live progress and lets the glasses focus view show the last two
query and reply pairs instead of only the latest prompt and reply.

The same release also records a reusable skill-local release rule:

- screenshot capture may be automated
- screenshot interpretation must stay outside the Perl `.t` suite
- simulator E2E acceptance still requires fresh human or LLM review
