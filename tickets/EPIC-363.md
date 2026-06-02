# EPIC-363

## Title

Add a governed DD compile wrapper for the Even Hub package.

## Goal

Let the operator package `D2-Codex` through `dashboard even-codex.compile`
without needing a global `evenhub` install, while reusing the existing
skill-owned Hub build flow, honoring the shared Node dependencies that
`dashboard skills install` already merges into `$HOME/node_modules`, and
reporting the generated `.ehpk` artifact path.

## Tickets

- `DD-363` Add the `dashboard even-codex.compile` package wrapper.

## Status

done
