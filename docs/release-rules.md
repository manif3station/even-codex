# Release Rules

`even-codex` keeps one simulator-specific release rule that must be reused on
every future ticket:

- screenshot capture may be automated
- screenshot interpretation must stay outside the Perl `.t` suite
- a human or LLM must review fresh simulator screenshots before the release
  gate closes

For this skill, the visual acceptance review must confirm the rendered Codex
TUI, the phone-side Even plugin, and the glasses view from the same live run.
If a ticket changes glasses interactions or prompt flow, the review must also
confirm the changed controls in the rendered simulator state rather than only in
source code.
