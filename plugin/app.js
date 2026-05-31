(function () {
  const fields = {
    workspaceRef: document.querySelector('[data-field="workspace-ref"]'),
    codexSessionId: document.querySelector('[data-field="codex-session-id"]'),
    bindHost: document.querySelector('[data-field="bind-host"]'),
    bootstrapUrl: document.querySelector('[data-field="bootstrap-url"]'),
    lastUserMessage: document.querySelector('[data-field="last-user-message"]'),
    lastAssistantMessage: document.querySelector('[data-field="last-assistant-message"]'),
    status: document.getElementById('even-codex-status')
  };

  function setText(node, text) {
    if (node) node.textContent = text;
  }

  Promise.all([
    fetch('/bootstrap').then((response) => response.json()),
    fetch('/session').then((response) => response.json())
  ])
    .then(([bootstrap, session]) => {
      setText(fields.workspaceRef, bootstrap.workspace_ref || 'unknown');
      setText(fields.codexSessionId, bootstrap.codex_session_id || 'unknown');
      setText(fields.bindHost, (bootstrap.advertised_host || bootstrap.bind_host || 'unknown') + ':' + String(bootstrap.port || ''));
      setText(fields.bootstrapUrl, bootstrap.bootstrap_url || '/bootstrap');
      setText(fields.lastUserMessage, session.last_user_message || bootstrap.last_user_message || 'No prompt yet.');
      setText(fields.lastAssistantMessage, session.last_assistant_message || bootstrap.last_assistant_message || 'No reply yet.');
      setText(fields.status, 'Connector ready for the paired workspace, Codex session, and latest transcript.');
    })
    .catch((error) => {
      setText(fields.status, 'Unable to load connector transcript: ' + String(error && error.message || error));
    });
})();
