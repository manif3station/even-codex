(function () {
  const fields = {
    workspaceRef: document.querySelector('[data-field="workspace-ref"]'),
    codexSessionId: document.querySelector('[data-field="codex-session-id"]'),
    bindHost: document.querySelector('[data-field="bind-host"]'),
    bootstrapUrl: document.querySelector('[data-field="bootstrap-url"]'),
    status: document.getElementById('even-codex-status')
  };

  function setText(node, text) {
    if (node) node.textContent = text;
  }

  fetch('/bootstrap')
    .then((response) => response.json())
    .then((payload) => {
      setText(fields.workspaceRef, payload.workspace_ref || 'unknown');
      setText(fields.codexSessionId, payload.codex_session_id || 'unknown');
      setText(fields.bindHost, (payload.advertised_host || payload.bind_host || 'unknown') + ':' + String(payload.port || ''));
      setText(fields.bootstrapUrl, payload.bootstrap_url || '/bootstrap');
      setText(fields.status, 'Connector ready for the paired workspace and Codex session.');
    })
    .catch((error) => {
      setText(fields.status, 'Unable to load connector bootstrap: ' + String(error && error.message || error));
    });
})();
