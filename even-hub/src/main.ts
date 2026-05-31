import './style.css';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  RebuildPageContainer,
  TextContainerProperty,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

type DetailMode = 'summary' | 'network' | 'conversation' | 'input';
type GlassesLayoutMode = 'split' | 'focus';
type InputAction = 'send' | 'retry' | 'cancel';

type SessionRecord = {
  id: string;
  label: string;
  lastSeenAt: string;
};

type ConnectorProfile = {
  id: string;
  name: string;
  origin: string;
  activeSessionId: string;
  sessions: SessionRecord[];
  workspaceRef: string;
  currentSessionId: string;
  bindHost: string;
  advertisedHost: string;
  port: number;
  healthUrl: string;
  bootstrapUrl: string;
  pluginUrl: string;
  lastSeenAt: string;
  lastUserMessage: string;
  lastAssistantMessage: string;
};

type StoredConfig = {
  activeConnectorId: string;
  connectors: ConnectorProfile[];
};

type PluginState = {
  config: StoredConfig;
  lifecycle: string;
  bridgeStatus: 'connected' | 'offline';
  detailMode: DetailMode;
  glassesLayoutMode: GlassesLayoutMode;
  selectedInputAction: InputAction;
  lastMessage: string;
  lastCheckedAt: string;
  draftQuery: string;
  stagedQuery: string;
  lastSubmittedQuery: string;
};

type BootstrapPayload = {
  workspace_ref: string;
  codex_session_id: string;
  bind_host: string;
  advertised_host: string;
  port: number;
  health_url: string;
  bootstrap_url: string;
  plugin_url: string;
};

type HealthPayload = {
  ok: boolean;
  service: string;
  workspace_ref: string;
  codex_session_id: string;
  port: number;
};

type SessionPayload = {
  ok: boolean;
  session_id: string;
  session_file: string;
  title: string;
  last_user_message: string;
  last_assistant_message: string;
};

const CONFIG_STORAGE_KEY = 'd2_codex.config';
const LEGACY_ORIGIN_STORAGE_KEY = 'd2_codex.bridge_origin';
const DEFAULT_BRIDGE_ORIGIN =
  import.meta.env.VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN || 'http://192.168.1.20:6789';
const AUTO_REFRESH_INTERVAL_MS = 3000;
const GLASSES_CONTAINER = {
  header: 1,
  detail: 2,
  footer: 3,
} as const;
const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('Missing app container');
}

void boot();

async function boot() {
  const bridge = await waitForEvenAppBridge();
  const config = await loadStoredConfig(bridge);
  const state = createInitialState(config);

  renderPhoneUi(state);
  await bridge.createStartUpPageContainer(buildStartupPage(state));
  await refreshBootstrap(bridge, state, {
    successMessage: 'Bridge check complete.',
    failureMessage: 'Bridge check failed.',
  });
  startAutoRefresh(bridge, state);

  bridge.onEvenHubEvent(async (event) => {
    const sysEventType = event.sysEvent?.eventType;
    if (sysEventType === OsEventTypeList.DOUBLE_CLICK_EVENT && state.glassesLayoutMode === 'focus') {
      state.glassesLayoutMode = 'split';
      state.lastMessage = 'Glasses layout restored to the three-pane view.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (sysEventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
      await bridge.shutDownPageContainer(1);
      return;
    }

    if (sysEventType === OsEventTypeList.CLICK_EVENT) {
      if (handleDetailClick(state)) {
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }
    }

    const textEvent = event.textEvent;
    if (textEvent?.eventType === OsEventTypeList.CLICK_EVENT) {
      if (textEvent.containerID === GLASSES_CONTAINER.detail && handleDetailClick(state)) {
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }
    }

    if (textEvent?.containerID === GLASSES_CONTAINER.detail) {
      if (textEvent.eventType === OsEventTypeList.SCROLL_TOP_EVENT) {
        if (state.detailMode === 'input') {
          state.selectedInputAction = previousInputAction(state.selectedInputAction);
          state.lastMessage = `Selected ${state.selectedInputAction} for the staged query.`;
        } else {
          state.detailMode = previousDetailMode(state.detailMode);
          state.lastMessage = `Showing ${state.detailMode} view on glasses.`;
        }
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }

      if (textEvent.eventType === OsEventTypeList.SCROLL_BOTTOM_EVENT) {
        if (state.detailMode === 'input') {
          state.selectedInputAction = nextInputAction(state.selectedInputAction);
          state.lastMessage = `Selected ${state.selectedInputAction} for the staged query.`;
        } else {
          state.detailMode = nextDetailMode(state.detailMode);
          state.lastMessage = `Showing ${state.detailMode} view on glasses.`;
        }
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }
    }

    if (sysEventType === OsEventTypeList.FOREGROUND_ENTER_EVENT) {
      state.lifecycle = 'foreground';
    } else if (sysEventType === OsEventTypeList.FOREGROUND_EXIT_EVENT) {
      state.lifecycle = 'background';
    } else if (sysEventType === OsEventTypeList.ABNORMAL_EXIT_EVENT) {
      state.lifecycle = 'abnormal-exit';
    } else if (sysEventType === OsEventTypeList.SYSTEM_EXIT_EVENT) {
      state.lifecycle = 'system-exit';
    } else {
      return;
    }

    state.lastMessage = `Lifecycle event: ${state.lifecycle}`;
    renderPhoneUi(state);
    await syncGlassesPage(bridge, state);
  });

  app.addEventListener('submit', async (submitEvent) => {
    const form = submitEvent.target;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    if (form.dataset.role === 'connector-form') {
      submitEvent.preventDefault();
      const formData = new FormData(form);
      const name = String(formData.get('connectorName') || '').trim();
      const origin = normalizeOrigin(String(formData.get('bridgeOrigin') || ''));
      saveConnectorProfile(state, {
        name: name || deriveConnectorName(origin, state.config.connectors.length + 1),
        origin,
      });
      await persistConfig(bridge, state.config);
      state.lastMessage = `Saved connector ${getActiveConnector(state)?.name || origin}.`;
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (form.dataset.role === 'session-form') {
      submitEvent.preventDefault();
      const formData = new FormData(form);
      const sessionId = String(formData.get('sessionId') || '').trim();
      if (!sessionId) {
        state.lastMessage = 'Session id is required before saving a session.';
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }
      addSessionToActiveConnector(state, sessionId);
      await persistConfig(bridge, state.config);
      state.lastMessage = `Saved session ${sessionId} on ${getActiveConnector(state)?.name || 'the active connector'}.`;
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (form.dataset.role === 'query-form') {
      submitEvent.preventDefault();
      const formData = new FormData(form);
      const query = normalizeDraftQuery(String(formData.get('draftQuery') || ''));
      state.draftQuery = query;
      state.stagedQuery = query;
      state.detailMode = 'input';
      state.selectedInputAction = 'send';
      state.lastMessage = query
        ? `Staged query ready. Use Send, Retry, or Cancel.`
        : 'Type or dictate a query before staging it.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
    }
  });

  app.addEventListener('click', async (clickEvent) => {
    const target = clickEvent.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const button = target.closest<HTMLElement>('[data-role]');
    if (!button) {
      return;
    }

    const role = button.dataset.role || '';

    if (role === 'refresh-button') {
      await refreshBootstrap(bridge, state, {
        successMessage: 'Refreshed from the phone plugin.',
        failureMessage: 'Phone-side refresh failed.',
      });
      return;
    }

    if (role === 'save-connector-button') {
      const form = app.querySelector<HTMLFormElement>('form[data-role="connector-form"]');
      form?.requestSubmit();
      return;
    }

    if (role === 'save-session-button') {
      const form = app.querySelector<HTMLFormElement>('form[data-role="session-form"]');
      form?.requestSubmit();
      return;
    }

    if (role === 'cycle-button') {
      state.detailMode = nextDetailMode(state.detailMode);
      state.lastMessage = `Phone-side detail view switched to ${state.detailMode}.`;
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'stage-query-button') {
      const form = app.querySelector<HTMLFormElement>('form[data-role="query-form"]');
      form?.requestSubmit();
      return;
    }

    if (role === 'load-slash-sample-button') {
      state.draftQuery = 'slash ship status';
      state.lastMessage = 'Loaded a slash-prefixed sample query for simulator verification.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'load-latest-prompt-button') {
      const activeConnector = getActiveConnector(state);
      state.draftQuery = activeConnector.lastUserMessage || state.lastSubmittedQuery || '';
      state.lastMessage = state.draftQuery
        ? 'Loaded the latest prompt into the draft composer.'
        : 'There is no latest prompt to reuse yet.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'send-query-button') {
      const input = app.querySelector<HTMLTextAreaElement>('#draftQuery');
      state.draftQuery = normalizeDraftQuery(input?.value || state.draftQuery);
      state.stagedQuery = state.draftQuery;
      state.selectedInputAction = 'send';
      applyInputAction(state);
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'retry-query-button') {
      const input = app.querySelector<HTMLTextAreaElement>('#draftQuery');
      state.draftQuery = normalizeDraftQuery(input?.value || state.draftQuery || state.lastSubmittedQuery);
      state.stagedQuery = state.draftQuery;
      state.selectedInputAction = 'retry';
      applyInputAction(state);
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'cancel-query-button') {
      state.selectedInputAction = 'cancel';
      applyInputAction(state);
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'cycle-session-button') {
      cycleSession(state);
      await persistConfig(bridge, state.config);
      state.lastMessage = `Phone-side session switched to ${getActiveSession(state)?.label || 'the next session'}.`;
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'activate-connector') {
      const connectorId = String(button.dataset.connectorId || '');
      if (connectorId) {
        state.config.activeConnectorId = connectorId;
        await persistConfig(bridge, state.config);
        state.lastMessage = `Active connector switched to ${getActiveConnector(state)?.name || 'the selected connector'}.`;
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
      }
      return;
    }

    if (role === 'remove-connector') {
      const connectorId = String(button.dataset.connectorId || '');
      if (connectorId) {
        removeConnectorProfile(state, connectorId);
        await persistConfig(bridge, state.config);
        state.lastMessage = 'Removed the selected connector profile.';
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
      }
      return;
    }

    if (role === 'activate-session') {
      const sessionId = String(button.dataset.sessionId || '');
      const connector = getActiveConnector(state);
      if (connector && sessionId) {
        connector.activeSessionId = sessionId;
        await persistConfig(bridge, state.config);
        state.lastMessage = `Active session switched to ${sessionId}.`;
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
      }
      return;
    }

    if (role === 'remove-session') {
      const sessionId = String(button.dataset.sessionId || '');
      if (sessionId) {
        removeSessionFromActiveConnector(state, sessionId);
        await persistConfig(bridge, state.config);
        state.lastMessage = `Removed session ${sessionId} from the active connector.`;
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
      }
    }
  });
}

function createInitialState(config: StoredConfig): PluginState {
  return {
    config,
    lifecycle: 'ready',
    bridgeStatus: 'offline',
    detailMode: 'summary',
    glassesLayoutMode: 'split',
    selectedInputAction: 'send',
    lastMessage: 'Waiting for the D2-Codex bridge bootstrap.',
    lastCheckedAt: 'Not checked yet',
    draftQuery: '',
    stagedQuery: '',
    lastSubmittedQuery: '',
  };
}

async function refreshBootstrap(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
  messages: { successMessage: string; failureMessage: string; quiet?: boolean },
) {
  state.lastCheckedAt = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const connector = getActiveConnector(state);

  try {
    const [health, bootstrap, session] = await Promise.all([
      fetchJson<HealthPayload>(`${connector.origin}/health`),
      fetchJson<BootstrapPayload>(`${connector.origin}/bootstrap`),
      fetchJson<SessionPayload>(`${connector.origin}/session`),
    ]);

    state.bridgeStatus = health.ok ? 'connected' : 'offline';
    mergeBootstrapIntoConnector(connector, bootstrap);
    mergeSessionIntoConnector(connector, session);
    await persistConfig(bridge, state.config);
    if (!messages.quiet) {
      state.lastMessage = `${messages.successMessage} ${connector.name} paired ${bootstrap.workspace_ref} to ${bootstrap.codex_session_id}.`;
    }
  } catch (error) {
    state.bridgeStatus = 'offline';
    if (!messages.quiet) {
      state.lastMessage = `${messages.failureMessage} ${formatError(error)}`;
    }
  }

  renderPhoneUi(state);
  await syncGlassesPage(bridge, state);
}

function startAutoRefresh(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
) {
  let refreshInFlight = false;
  window.setInterval(() => {
    if (refreshInFlight) {
      return;
    }

    refreshInFlight = true;
    void refreshBootstrap(bridge, state, {
      successMessage: '',
      failureMessage: '',
      quiet: true,
    }).finally(() => {
      refreshInFlight = false;
    });
  }, AUTO_REFRESH_INTERVAL_MS);
}

function renderPhoneUi(state: PluginState) {
  const connector = getActiveConnector(state);
  const activeSession = getActiveSession(state);
  const sessionCount = connector.sessions.length;
  const normalizedDraft = escapeHtml(state.draftQuery);
  const stagedQuery = escapeHtml(state.stagedQuery || 'No staged query.');
  const submittedQuery = escapeHtml(state.lastSubmittedQuery || 'No query sent from the plugin yet.');

  app!.innerHTML = `
    <section class="shell">
      <div class="stack">
        <header class="hero">
          <div class="hero-copy stack">
            <p class="eyebrow">Even Plugin</p>
            <h1 class="title">D2-Codex</h1>
            <p class="copy">Manage local DD connectors and Codex sessions from one Even plugin, then switch only the session from glasses when you need to change context quickly.</p>
          </div>
          <div class="panel status-panel">
            <p class="label">Connection</p>
            <p class="status-chip">${escapeHtml(state.bridgeStatus.toUpperCase())}</p>
            <p class="hint">Last check ${escapeHtml(state.lastCheckedAt)}</p>
          </div>
        </header>

        <section class="metric-grid">
          <article class="panel">
            <p class="label">Active Connector</p>
            <p class="value">${escapeHtml(connector.name)}</p>
          </article>
          <article class="panel">
            <p class="label">Workspace</p>
            <p class="value">${escapeHtml(connector.workspaceRef)}</p>
          </article>
          <article class="panel">
            <p class="label">Active Codex Session</p>
            <p class="value">${escapeHtml(activeSession?.label || connector.currentSessionId || 'Unknown')}</p>
          </article>
          <article class="panel">
            <p class="label">Lifecycle</p>
            <p class="value">${escapeHtml(state.lifecycle)}</p>
          </article>
        </section>

        <section class="metric-grid">
          <article class="panel">
            <p class="label">Latest Prompt</p>
            <p class="value">${escapeHtml(connector.lastUserMessage || 'No prompt yet.')}</p>
          </article>
          <article class="panel">
            <p class="label">Latest Reply</p>
            <p class="value">${escapeHtml(connector.lastAssistantMessage || 'No reply yet.')}</p>
          </article>
          <article class="panel">
            <p class="label">Staged Query</p>
            <p class="value">${stagedQuery}</p>
          </article>
          <article class="panel">
            <p class="label">Last Sent From Plugin</p>
            <p class="value">${submittedQuery}</p>
          </article>
        </section>

        <section class="action-row">
          <button class="button" type="button" data-role="refresh-button">Refresh Connection</button>
          <button class="button" type="button" data-role="cycle-button">Cycle Glasses Detail</button>
          <button class="button" type="button" data-role="cycle-session-button">Next Glasses Session</button>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Query Composer</h2>
          <p class="copy">The current Even SDK does not document a native hold-to-dictate sheet, so the simulator flow stages input in the phone plugin first. Any query that starts with <code>Slash</code> or <code>slash</code> is normalized to <code>/</code>.</p>
          <form class="form" data-role="query-form">
            <label class="label" for="draftQuery">Draft Query</label>
            <textarea class="input input-area" id="draftQuery" name="draftQuery" rows="4" placeholder="Type or paste the next Codex query here.">${normalizedDraft}</textarea>
            <p class="hint">Stage the query first, then choose Send, Retry, or Cancel. The live simulator review checks this state visually.</p>
            <div class="action-row">
              <button class="button" type="button" data-role="load-slash-sample-button">Load Slash Sample</button>
              <button class="button" type="button" data-role="load-latest-prompt-button">Reuse Latest Prompt</button>
            </div>
            <div class="action-row">
              <button class="button" type="button" data-role="stage-query-button">Stage Query</button>
              <button class="button" type="button" data-role="send-query-button">Send</button>
              <button class="button" type="button" data-role="retry-query-button">Retry</button>
              <button class="button" type="button" data-role="cancel-query-button">Cancel</button>
            </div>
          </form>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Connection Checklist</h2>
          <ol class="list">
            <li>Run <code>dashboard workspace foobar</code> in the project you want on glasses.</li>
            <li>Copy the Codex session id from <code>/status</code>.</li>
            <li>Save the pairing with <code>dashboard even-codex.start add &lt;codex-session-id&gt;</code>.</li>
            <li>Start the full local flow with <code>dashboard even-codex.e2e start</code> or start the bridge with <code>dashboard even-codex.start</code>.</li>
          </ol>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Connector Profiles</h2>
          <p class="copy">Save and switch between different local network DD connector origins from the phone plugin. Glasses stay on the active connector and only switch sessions.</p>
          <form class="form" data-role="connector-form">
            <label class="label" for="connectorName">Connector Name</label>
            <input class="input" id="connectorName" name="connectorName" type="text" value="${escapeHtml(connector.name)}" />
            <label class="label" for="bridgeOrigin">Bridge Origin</label>
            <input class="input" id="bridgeOrigin" name="bridgeOrigin" type="url" value="${escapeHtml(connector.origin)}" />
            <p class="hint">Use a LAN-reachable host such as <code>http://192.168.1.20:6789</code>. Port 6789 is the default DD connector port.</p>
            <button class="button" type="button" data-role="save-connector-button">Save Connector</button>
          </form>
          <div class="profile-list">${renderConnectorProfiles(state)}</div>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Session Library</h2>
          <p class="copy">Each connector keeps its own saved Codex session list. Refresh captures the current bootstrap session automatically, and you can pin or remove saved sessions from the phone plugin.</p>
          <form class="form" data-role="session-form">
            <label class="label" for="sessionId">Add Codex Session</label>
            <input class="input" id="sessionId" name="sessionId" type="text" value="${escapeHtml(connector.currentSessionId || '')}" />
            <p class="hint">${sessionCount} saved session${sessionCount === 1 ? '' : 's'} on this connector.</p>
            <button class="button" type="button" data-role="save-session-button">Save Session</button>
          </form>
          <div class="session-list">${renderSessions(state)}</div>
        </section>

        <section class="metric-grid">
          <article class="panel">
            <p class="label">Health URL</p>
            <p class="value">${escapeHtml(connector.healthUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Bootstrap URL</p>
            <p class="value">${escapeHtml(connector.bootstrapUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Plugin URL</p>
            <p class="value">${escapeHtml(connector.pluginUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Port 6789</p>
            <p class="value">Default bridge listener for phone-to-laptop pairing.</p>
          </article>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Glasses Controls</h2>
          <ul class="list">
            <li>Up and Down cycle the focused detail pane, or change the selected input action while the input pane is open.</li>
            <li>Click focuses the current detail pane, and clicking the input pane applies the selected action.</li>
            <li>Double-click restores the split layout, or exits when already in split view.</li>
          </ul>
          <p class="status">${escapeHtml(state.lastMessage)}</p>
        </section>
      </div>
    </section>
  `;
}

function renderConnectorProfiles(state: PluginState) {
  return state.config.connectors
    .map((connector) => {
      const isActive = connector.id === state.config.activeConnectorId;
      return `
        <article class="panel profile-card">
          <div class="stack">
            <p class="label">${isActive ? 'Active Connector' : 'Saved Connector'}</p>
            <p class="value">${escapeHtml(connector.name)}</p>
            <p class="hint">${escapeHtml(connector.origin)}</p>
            <div class="button-row">
              <button class="button" type="button" data-role="activate-connector" data-connector-id="${escapeHtml(connector.id)}">Use Connector</button>
              <button class="button" type="button" data-role="remove-connector" data-connector-id="${escapeHtml(connector.id)}">Remove Connector</button>
            </div>
          </div>
        </article>
      `;
    })
    .join('');
}

function renderSessions(state: PluginState) {
  const connector = getActiveConnector(state);
  if (!connector.sessions.length) {
    return `<article class="panel"><p class="value">No saved sessions yet. Refresh the connector or save one manually.</p></article>`;
  }

  return connector.sessions
    .map((session) => {
      const isActive = session.id === connector.activeSessionId;
      return `
        <article class="panel session-card">
          <div class="stack">
            <p class="label">${isActive ? 'Active Session' : 'Saved Session'}</p>
            <p class="value">${escapeHtml(session.label)}</p>
            <p class="hint">Last seen ${escapeHtml(session.lastSeenAt)}</p>
            <div class="button-row">
              <button class="button" type="button" data-role="activate-session" data-session-id="${escapeHtml(session.id)}">Use Session</button>
              <button class="button" type="button" data-role="remove-session" data-session-id="${escapeHtml(session.id)}">Remove Session</button>
            </div>
          </div>
        </article>
      `;
    })
    .join('');
}

function buildStartupPage(state: PluginState) {
  return new CreateStartUpPageContainer({
    containerTotalNum: 3,
    textObject: buildTextObjects(state),
  });
}

async function syncGlassesPage(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
) {
  await bridge.rebuildPageContainer(
    new RebuildPageContainer({
      containerTotalNum: 3,
      textObject: buildTextObjects(state),
    }),
  );
}

function buildTextObjects(state: PluginState) {
  const detailHeight = state.glassesLayoutMode === 'focus' ? 210 : 136;
  const footerY = state.glassesLayoutMode === 'focus' ? 0 : 220;
  const footerHeight = state.glassesLayoutMode === 'focus' ? 0 : 68;

  return [
    new TextContainerProperty({
      xPosition: 0,
      yPosition: 0,
      width: 576,
      height: 72,
      borderWidth: 1,
      borderColor: 5,
      paddingLength: 8,
      containerID: GLASSES_CONTAINER.header,
      containerName: 'd2-codex-header',
      content: buildHeaderText(state),
      isEventCapture: 0,
    }),
    new TextContainerProperty({
      xPosition: 0,
      yPosition: 78,
      width: 576,
      height: detailHeight,
      borderWidth: 1,
      borderColor: 5,
      paddingLength: 8,
      containerID: GLASSES_CONTAINER.detail,
      containerName: 'd2-codex-detail',
      content: buildDetailText(state),
      isEventCapture: 1,
    }),
    new TextContainerProperty({
      xPosition: 0,
      yPosition: footerY,
      width: 576,
      height: footerHeight,
      borderWidth: 1,
      borderColor: 5,
      paddingLength: 8,
      containerID: GLASSES_CONTAINER.footer,
      containerName: 'd2-codex-footer',
      content: state.glassesLayoutMode === 'focus' ? '' : buildFooterText(state),
      isEventCapture: 0,
    }),
  ];
}

function buildHeaderText(state: PluginState) {
  const connector = getActiveConnector(state);
  return [
    'D2-Codex',
    `${state.bridgeStatus.toUpperCase()}  ${truncate(connector.name, 20)}`,
    truncate(`Layout ${state.glassesLayoutMode} · ${connector.workspaceRef}`, 28),
  ].join('\n');
}

function buildDetailText(state: PluginState) {
  const connector = getActiveConnector(state);

  if (state.detailMode === 'network') {
    return [
      'Network',
      truncate(`Host ${connector.advertisedHost}:${connector.port}`, 34),
      truncate(`Origin ${connector.origin}`, 34),
      'Up/down changes pane · click focus',
    ].join('\n');
  }

  if (state.detailMode === 'conversation') {
    return [
      'Conversation',
      truncate(`Prompt ${connector.lastUserMessage || 'No prompt yet.'}`, 34),
      truncate(`Reply ${connector.lastAssistantMessage || 'No reply yet.'}`, 34),
      'Up/down changes pane · click focus',
    ].join('\n');
  }

  if (state.detailMode === 'input') {
    return [
      'Input',
      truncate(`Draft ${state.stagedQuery || state.lastSubmittedQuery || 'No staged query.'}`, 34),
      truncate(`Action ${state.selectedInputAction.toUpperCase()}`, 34),
      'Up/down action · click apply',
    ].join('\n');
  }

  return [
    'Summary',
    truncate(`Reply ${connector.lastAssistantMessage || 'No reply yet.'}`, 34),
    truncate(`Workspace ${connector.workspaceRef}`, 34),
    'Up/down changes pane · click focus',
  ].join('\n');
}

function buildFooterText(state: PluginState) {
  const connector = getActiveConnector(state);
  return [
    `Prompt ${truncate(connector.lastUserMessage || 'No prompt yet.', 25)}`,
    `Checked ${state.lastCheckedAt}`,
    `Staged ${truncate(state.stagedQuery || 'No staged query.', 22)}`,
    'Double-click restore or exit',
  ].join('\n');
}

async function fetchJson<T>(url: string) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${url} returned ${response.status}`);
  }

  return (await response.json()) as T;
}

function nextDetailMode(current: DetailMode): DetailMode {
  if (current === 'summary') {
    return 'network';
  }

  if (current === 'network') {
    return 'conversation';
  }

  if (current === 'conversation') {
    return 'input';
  }

  return 'summary';
}

function previousDetailMode(current: DetailMode): DetailMode {
  if (current === 'summary') {
    return 'input';
  }

  if (current === 'network') {
    return 'summary';
  }

  if (current === 'conversation') {
    return 'network';
  }

  return 'conversation';
}

function nextInputAction(current: InputAction): InputAction {
  if (current === 'send') {
    return 'retry';
  }

  if (current === 'retry') {
    return 'cancel';
  }

  return 'send';
}

function previousInputAction(current: InputAction): InputAction {
  if (current === 'send') {
    return 'cancel';
  }

  if (current === 'retry') {
    return 'send';
  }

  return 'retry';
}

function handleDetailClick(state: PluginState) {
  if (state.detailMode === 'input') {
    applyInputAction(state);
    return true;
  }

  state.glassesLayoutMode = state.glassesLayoutMode === 'split' ? 'focus' : 'split';
  state.lastMessage = state.glassesLayoutMode === 'focus'
    ? `Focused the ${state.detailMode} pane on glasses.`
    : 'Glasses layout restored to the three-pane view.';
  return true;
}

function applyInputAction(state: PluginState) {
  const normalized = normalizeDraftQuery(state.stagedQuery || state.draftQuery || state.lastSubmittedQuery);

  if (state.selectedInputAction === 'cancel') {
    state.draftQuery = '';
    state.stagedQuery = '';
    state.detailMode = 'summary';
    state.glassesLayoutMode = 'split';
    state.lastMessage = 'Cancelled the staged query.';
    return;
  }

  if (state.selectedInputAction === 'retry') {
    state.draftQuery = normalized;
    state.stagedQuery = normalized;
    state.detailMode = 'input';
    state.glassesLayoutMode = 'split';
    state.lastMessage = 'Retry selected. Update the draft and stage it again.';
    return;
  }

  if (!normalized) {
    state.lastMessage = 'Cannot send an empty staged query.';
    return;
  }

  state.lastSubmittedQuery = normalized;
  state.stagedQuery = normalized;
  state.draftQuery = normalized;
  state.detailMode = 'conversation';
  state.glassesLayoutMode = 'split';
  state.lastMessage = `Queued query from the plugin: ${normalized}`;
}

function cycleSession(state: PluginState) {
  const connector = getActiveConnector(state);
  if (connector.sessions.length < 2) {
    return;
  }

  const currentIndex = connector.sessions.findIndex((session) => session.id === connector.activeSessionId);
  const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % connector.sessions.length : 0;
  connector.activeSessionId = connector.sessions[nextIndex]?.id || connector.activeSessionId;
}

function getActiveConnector(state: PluginState) {
  return (
    state.config.connectors.find((connector) => connector.id === state.config.activeConnectorId) ||
    state.config.connectors[0]
  );
}

function getActiveSession(state: PluginState) {
  const connector = getActiveConnector(state);
  return connector.sessions.find((session) => session.id === connector.activeSessionId) || connector.sessions[0];
}

function addSessionToActiveConnector(state: PluginState, sessionId: string) {
  const connector = getActiveConnector(state);
  const existing = connector.sessions.find((session) => session.id === sessionId);
  const stamp = createTimestamp();

  if (existing) {
    existing.lastSeenAt = stamp;
    existing.label = sessionId;
  } else {
    connector.sessions.unshift({
      id: sessionId,
      label: sessionId,
      lastSeenAt: stamp,
    });
  }

  connector.activeSessionId = sessionId;
}

function removeSessionFromActiveConnector(state: PluginState, sessionId: string) {
  const connector = getActiveConnector(state);
  connector.sessions = connector.sessions.filter((session) => session.id !== sessionId);
  if (!connector.sessions.length) {
    connector.activeSessionId = '';
    return;
  }

  if (connector.activeSessionId === sessionId) {
    connector.activeSessionId = connector.sessions[0].id;
  }
}

function saveConnectorProfile(state: PluginState, connectorInput: { name: string; origin: string }) {
  const existing = state.config.connectors.find((connector) => connector.origin === connectorInput.origin);
  if (existing) {
    existing.name = connectorInput.name;
    state.config.activeConnectorId = existing.id;
    return;
  }

  const connector = createConnectorProfile(connectorInput.name, connectorInput.origin, state.config.connectors.length + 1);
  state.config.connectors.unshift(connector);
  state.config.activeConnectorId = connector.id;
}

function removeConnectorProfile(state: PluginState, connectorId: string) {
  state.config.connectors = state.config.connectors.filter((connector) => connector.id !== connectorId);
  if (!state.config.connectors.length) {
    const fallback = createConnectorProfile('Primary Connector', DEFAULT_BRIDGE_ORIGIN, 1);
    state.config.connectors = [fallback];
    state.config.activeConnectorId = fallback.id;
    return;
  }

  if (state.config.activeConnectorId === connectorId) {
    state.config.activeConnectorId = state.config.connectors[0].id;
  }
}

function mergeBootstrapIntoConnector(connector: ConnectorProfile, bootstrap: BootstrapPayload) {
  connector.workspaceRef = bootstrap.workspace_ref;
  connector.currentSessionId = bootstrap.codex_session_id;
  connector.bindHost = bootstrap.bind_host;
  connector.advertisedHost = bootstrap.advertised_host;
  connector.port = bootstrap.port;
  connector.healthUrl = `${connector.origin}/health`;
  connector.bootstrapUrl = bootstrap.bootstrap_url;
  connector.pluginUrl = bootstrap.plugin_url;
  connector.lastSeenAt = createTimestamp();

  const existing = connector.sessions.find((session) => session.id === bootstrap.codex_session_id);
  if (existing) {
    existing.lastSeenAt = connector.lastSeenAt;
    existing.label = bootstrap.codex_session_id;
  } else {
    connector.sessions.unshift({
      id: bootstrap.codex_session_id,
      label: bootstrap.codex_session_id,
      lastSeenAt: connector.lastSeenAt,
    });
  }

  if (!connector.activeSessionId) {
    connector.activeSessionId = bootstrap.codex_session_id;
  }
}

function mergeSessionIntoConnector(connector: ConnectorProfile, session: SessionPayload) {
  connector.lastUserMessage = session.last_user_message || connector.lastUserMessage;
  connector.lastAssistantMessage = session.last_assistant_message || connector.lastAssistantMessage;
}

function createConnectorProfile(name: string, origin: string, index: number): ConnectorProfile {
  const normalizedOrigin = normalizeOrigin(origin);
  return {
    id: `connector-${Date.now()}-${index}`,
    name,
    origin: normalizedOrigin,
    activeSessionId: '',
    sessions: [],
    workspaceRef: 'Unpaired',
    currentSessionId: 'Unknown',
    bindHost: 'Unknown',
    advertisedHost: 'Unknown',
    port: 6789,
    healthUrl: `${normalizedOrigin}/health`,
    bootstrapUrl: `${normalizedOrigin}/bootstrap`,
    pluginUrl: `${normalizedOrigin}/plugin/`,
    lastSeenAt: 'Not checked yet',
    lastUserMessage: 'No prompt yet.',
    lastAssistantMessage: 'No reply yet.',
  };
}

function createDefaultConfig(origin: string): StoredConfig {
  const connector = createConnectorProfile('Primary Connector', origin, 1);
  return {
    activeConnectorId: connector.id,
    connectors: [connector],
  };
}

async function loadStoredConfig(bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>) {
  const storedConfig = await bridge.getLocalStorage(CONFIG_STORAGE_KEY);
  if (storedConfig) {
    try {
      const parsed = JSON.parse(storedConfig) as StoredConfig;
      return normalizeStoredConfig(parsed);
    } catch {
      return createDefaultConfig(DEFAULT_BRIDGE_ORIGIN);
    }
  }

  const legacyOrigin = await bridge.getLocalStorage(LEGACY_ORIGIN_STORAGE_KEY);
  return createDefaultConfig(legacyOrigin || DEFAULT_BRIDGE_ORIGIN);
}

async function persistConfig(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  config: StoredConfig,
) {
  await bridge.setLocalStorage(CONFIG_STORAGE_KEY, JSON.stringify(config));
}

function normalizeStoredConfig(config: StoredConfig) {
  const connectors = Array.isArray(config.connectors) && config.connectors.length
    ? config.connectors.map((connector, index) => ({
        ...createConnectorProfile(
          connector.name || deriveConnectorName(connector.origin, index + 1),
          connector.origin || DEFAULT_BRIDGE_ORIGIN,
          index + 1,
        ),
        ...connector,
        origin: normalizeOrigin(connector.origin || DEFAULT_BRIDGE_ORIGIN),
        sessions: Array.isArray(connector.sessions)
          ? connector.sessions.filter((session) => session && session.id).map((session) => ({
              id: session.id,
              label: session.label || session.id,
              lastSeenAt: session.lastSeenAt || 'Unknown',
            }))
          : [],
      }))
    : createDefaultConfig(DEFAULT_BRIDGE_ORIGIN).connectors;

  const activeConnectorId =
    connectors.find((connector) => connector.id === config.activeConnectorId)?.id || connectors[0].id;

  return {
    activeConnectorId,
    connectors,
  };
}

function deriveConnectorName(origin: string, index: number) {
  const parsed = new URL(origin);
  return `Connector ${index} · ${parsed.hostname}`;
}

function createTimestamp() {
  return new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

function truncate(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength - 1)}…`;
}

function normalizeOrigin(value: string) {
  const parsed = new URL(value);
  if (!/^https?:$/.test(parsed.protocol)) {
    throw new Error('Bridge origin must use http or https.');
  }

  return parsed.origin;
}

function normalizeDraftQuery(value: string) {
  const trimmed = value.trim().replace(/\s+/g, ' ');
  return trimmed.replace(/^(slash)\s+/i, '/');
}

function formatError(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
