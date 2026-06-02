# 2026-06-02 DD Web Routes

`even-codex 0.35` now ships a DD-native connector surface for the phone-side
plugin.

The skill now includes:

- the native DD smart routes under `/app/even-codex/...`,
  `/ajax/even-codex/...`, `/js/even-codex/...`, and `/css/even-codex/...`
- skill-local `dashboards/ajax` handlers for `health`, `bootstrap`, `session`,
  and `prompt`
- a DD-served plugin page at `/app/even-codex/plugin`
- a live DD bootstrap payload that now advertises `/app/even-codex/plugin`
  together with `/ajax/even-codex/bootstrap`, `/ajax/even-codex/session`, and
  `/ajax/even-codex/prompt`
- shared connector logic so the DD route surface and the standalone bridge
  resolve the same pairings, transcript state, and prompt submission behavior
