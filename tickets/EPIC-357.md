# EPIC-357

## Title

Eliminate the simulator Codex self-update startup branch.

## Goal

Make the Dockerized `even-codex` simulator launch the packaged native Codex
binary directly so the xterm startup path no longer falls into a non-root
`npm install -g @openai/codex@latest` failure.

## Ticket

- `DD-357` Launch the packaged native Codex binary in the simulator xterm.
