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

For simulator-launcher or Codex-startup tickets, the release gate must also
prove the exact `dashboard even-codex.simulator start` path against a real
paired workspace before the ticket closes. Source-only checks, container-only
checks, or direct `docker run` proof are not enough on their own for that
slice.

Before trusting that launcher proof, the installed skill copy under
`~/.developer-dashboard/skills/even-codex` must be current with the repo under
test. If the installed skill is stale, refresh it first, restart the simulator,
and then repeat the launcher proof against the live stack.
