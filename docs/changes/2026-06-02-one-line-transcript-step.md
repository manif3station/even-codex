# 2026-06-02 one-line transcript step

`even-codex` now moves the glasses transcript review window one rendered line at
a time.

## What changed

- the first transcript `Up` gesture no longer jumps to the top of a larger
  retained review buffer
- each transcript `Up` gesture increases a wrapped-line review offset by one
  rendered line
- each transcript `Down` gesture moves that wrapped-line review offset back
  down by one rendered line
- live-follow resumes only when the wrapped-line review offset returns to zero

## Why it changed

The previous live-follow fix removed the worst jump-to-top behavior caused by a
full transcript rewrite, but on the current Even simulator path the app could
not rely on native one-line scroll once the text container was capturing the
gesture. The governed fix now makes one-line transcript review explicit in app
state so the simulator and shipped glasses path both move predictably.
