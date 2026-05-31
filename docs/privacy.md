# Privacy

`D2-Codex` requests network access so the phone-side Even plugin can reach the paired local bridge.

Current network use:

- the phone-side Even WebView fetches the configured bridge origin
- the bridge serves health and bootstrap metadata to the plugin

What the current app does not do:

- it does not upload the paired Codex session data to a third-party cloud service from the packaged Hub app
- it does not request camera, microphone, album, or location permissions

Submission note:

- private or public submission should update this policy if additional remote services or permissions are introduced later
