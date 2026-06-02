# DD Runtime API Auth

`even-codex 0.47` removes the rejected skill-repo `config/api.json`
placeholder and switches the DD machine-auth story to the production-safe DD
runtime contract.

What changed:

- the skill repo no longer ships a shared DD API client or shared secret
- DD API-key auth is documented and tested only through runtime
  `config/api.json` layers such as `~/.developer-dashboard/config/api.json`
- the simulator API-mode path now writes a disposable runtime `api.json`
  inside the container from provided or generated credentials
- the Even Hub app now documents that API-key mode depends on runtime DD
  credentials rather than any repo-owned secret
