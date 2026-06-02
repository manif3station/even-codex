(function () {
  const fields = {
    workspaceRef: document.querySelector('[data-field="workspace-ref"]'),
    codexSessionId: document.querySelector('[data-field="codex-session-id"]'),
    bindHost: document.querySelector('[data-field="bind-host"]'),
    bootstrapUrl: document.querySelector('[data-field="bootstrap-url"]'),
    lastUserMessage: document.querySelector('[data-field="last-user-message"]'),
    lastAssistantMessage: document.querySelector('[data-field="last-assistant-message"]'),
    status: document.getElementById('even-codex-status'),
    query: document.getElementById('even-codex-query'),
    form: document.getElementById('even-codex-prompt-form')
  };

  function setText(node, text) {
    if (node) {
      node.textContent = text;
    }
  }

  function endpoint(name) {
    const url = new URL('/ajax/even-codex/' + name, window.location.origin);
    const params = new URLSearchParams(window.location.search);
    if (params.get('workspace_ref')) {
      url.searchParams.set('workspace_ref', params.get('workspace_ref'));
    }
    return url.toString();
  }

  function updateFromPayload(bootstrap, session) {
    setText(fields.workspaceRef, bootstrap.workspace_ref || session.workspace_ref || 'unknown');
    setText(fields.codexSessionId, bootstrap.codex_session_id || session.session_id || 'unknown');
    setText(fields.bindHost, (bootstrap.advertised_host || bootstrap.bind_host || 'dashboard-serve') + ':' + String(bootstrap.port || 'web'));
    setText(fields.bootstrapUrl, bootstrap.bootstrap_url || endpoint('bootstrap'));
    setText(fields.lastUserMessage, session.last_user_message || bootstrap.last_user_message || 'No prompt yet.');
    setText(fields.lastAssistantMessage, session.last_assistant_message || bootstrap.last_assistant_message || 'No reply yet.');
  }

  function refresh() {
    return Promise.all([
      fetch(endpoint('bootstrap')).then((response) => response.json()),
      fetch(endpoint('session')).then((response) => response.json())
    ]).then(([bootstrap, session]) => {
      updateFromPayload(bootstrap, session);
      setText(fields.status, 'DD ajax connector ready for the paired Codex session.');
    });
  }

  fields.form.addEventListener('submit', function (event) {
    event.preventDefault();
    const query = (fields.query.value || '').trim();
    if (!query) {
      setText(fields.status, 'Enter a query before sending it to Codex.');
      return;
    }

    const body = new URLSearchParams();
    body.set('query', query);
    const params = new URLSearchParams(window.location.search);
    if (params.get('workspace_ref')) {
      body.set('workspace_ref', params.get('workspace_ref'));
    }

    setText(fields.status, 'Submitting prompt through the DD ajax connector...');

    fetch(endpoint('prompt'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
      body: body.toString()
    })
      .then((response) => response.json())
      .then(() => refresh())
      .then(() => {
        fields.query.value = '';
        setText(fields.status, 'Prompt submitted through the DD ajax connector.');
      })
      .catch((error) => {
        setText(fields.status, 'Unable to submit the Codex prompt: ' + String(error && error.message || error));
      });
  });

  refresh().catch((error) => {
    setText(fields.status, 'Unable to load DD connector transcript: ' + String(error && error.message || error));
  });
})();
