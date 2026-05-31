import './style.css';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  TextContainerUpgrade,
  TextContainerProperty,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

type InputAction = 'send' | 'retry' | 'cancel';
type GlassesSurfaceMode = 'transcript' | 'input';

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
  promptUrl: string;
  lastSeenAt: string;
  lastUserMessage: string;
  lastAssistantProgressMessage: string;
  lastAssistantMessage: string;
  recentTurns: ConversationTurn[];
};

type ConversationTurn = {
  prompt: string;
  progress: string;
  reply: string;
};

type StoredConfig = {
  activeConnectorId: string;
  connectors: ConnectorProfile[];
};

type PluginState = {
  config: StoredConfig;
  lifecycle: string;
  bridgeStatus: 'connected' | 'offline';
  glassesSurfaceMode: GlassesSurfaceMode;
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
  prompt_url: string;
  last_assistant_progress_message: string;
  recent_turns: ConversationTurn[];
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
  last_assistant_progress_message: string;
  last_assistant_message: string;
  recent_turns: ConversationTurn[];
};

const CONFIG_STORAGE_KEY = 'd2_codex.config';
const LEGACY_ORIGIN_STORAGE_KEY = 'd2_codex.bridge_origin';
const DEFAULT_BRIDGE_ORIGIN =
  import.meta.env.VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN || 'http://192.168.1.20:6789';
const AUTO_REFRESH_INTERVAL_MS = 3000;
const GLASSES_TRANSCRIPT_CONTAINER_ID = 1;
const GLASSES_TRANSCRIPT_CONTAINER_NAME = 'd2-codex-transcript';
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
    const isSimulatorBareClick = sysEventType === undefined && event.sysEvent?.eventSource === 1;
    const textEvent = event.textEvent;
    const isTextContainerClick =
      textEvent?.containerID === GLASSES_TRANSCRIPT_CONTAINER_ID &&
      (textEvent.eventType === undefined || textEvent.eventType === OsEventTypeList.CLICK_EVENT);
    const isTextContainerDoubleClick =
      textEvent?.containerID === GLASSES_TRANSCRIPT_CONTAINER_ID &&
      textEvent.eventType === OsEventTypeList.DOUBLE_CLICK_EVENT;

    if (sysEventType === OsEventTypeList.DOUBLE_CLICK_EVENT || isTextContainerDoubleClick) {
      state.glassesSurfaceMode = 'transcript';
      state.lastMessage = 'Glasses double press restored the live transcript view.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (isSimulatorBareClick || sysEventType === OsEventTypeList.CLICK_EVENT || isTextContainerClick) {
      if (state.glassesSurfaceMode === 'input') {
        await applyInputAction(bridge, state);
      } else {
        state.glassesSurfaceMode = 'input';
        state.selectedInputAction = 'send';
        state.lastMessage = 'Glasses press opened the staged query input view.';
      }
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (textEvent?.containerID === GLASSES_TRANSCRIPT_CONTAINER_ID) {
      if (textEvent.eventType === OsEventTypeList.SCROLL_TOP_EVENT) {
        if (state.glassesSurfaceMode === 'input') {
          cycleInputAction(state, -1);
          state.lastMessage = `Glasses swipe up selected ${state.selectedInputAction.toUpperCase()}.`;
        } else {
          state.lastMessage = 'Glasses swipe up reached the transcript top.';
        }
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }

      if (textEvent.eventType === OsEventTypeList.SCROLL_BOTTOM_EVENT) {
        if (state.glassesSurfaceMode === 'input') {
          cycleInputAction(state, 1);
          state.lastMessage = `Glasses swipe down selected ${state.selectedInputAction.toUpperCase()}.`;
        } else {
          state.lastMessage = 'Glasses swipe down reached the transcript bottom.';
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
      await refreshBootstrap(bridge, state, {
        successMessage: 'Phone-side refresh pushed the latest transcript to glasses.',
        failureMessage: 'Phone-side refresh failed.',
        quiet: true,
      });
      state.lastMessage = 'Phone-side refresh pushed the latest transcript to glasses.';
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
      await applyInputAction(bridge, state);
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'retry-query-button') {
      const input = app.querySelector<HTMLTextAreaElement>('#draftQuery');
      state.draftQuery = normalizeDraftQuery(input?.value || state.draftQuery || state.lastSubmittedQuery);
      state.stagedQuery = state.draftQuery;
      state.selectedInputAction = 'retry';
      await applyInputAction(bridge, state);
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'cancel-query-button') {
      state.selectedInputAction = 'cancel';
      await applyInputAction(bridge, state);
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
    glassesSurfaceMode: 'transcript',
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
            <p class="label">Latest Progress</p>
            <p class="value">${escapeHtml(connector.lastAssistantProgressMessage || 'No progress yet.')}</p>
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
          <button class="button" type="button" data-role="cycle-button">Refresh Glasses Transcript</button>
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
            <li>Start the full local flow with <code>dashboard even-codex.simulator start</code> or start the bridge with <code>dashboard even-codex.start</code>.</li>
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
            <li>Up and Down use the native Even transcript scroll path on the single glasses text window.</li>
            <li>Click opens the staged query input view, and click again applies the selected action.</li>
            <li>Double-click closes the input view and returns to the live transcript.</li>
            <li>Hold-to-dictate is not documented by the current Even SDK, so query entry stays in the phone-side composer.</li>
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
    containerTotalNum: 1,
    textObject: buildTextObjects(state),
  });
}

async function syncGlassesPage(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
) {
  await bridge.textContainerUpgrade(
    new TextContainerUpgrade({
      containerID: GLASSES_TRANSCRIPT_CONTAINER_ID,
      containerName: GLASSES_TRANSCRIPT_CONTAINER_NAME,
      content: buildTranscriptText(state),
    }),
  );
}

function buildTextObjects(state: PluginState) {
  return [
    new TextContainerProperty({
      xPosition: 0,
      yPosition: 0,
      width: 576,
      height: 288,
      borderWidth: 0,
      borderColor: 0,
      paddingLength: 8,
      containerID: GLASSES_TRANSCRIPT_CONTAINER_ID,
      containerName: GLASSES_TRANSCRIPT_CONTAINER_NAME,
      content: buildTranscriptText(state),
      isEventCapture: 1,
    }),
  ];
}

function buildTranscriptText(state: PluginState) {
  if (state.glassesSurfaceMode === 'input') {
    return buildInputText(state);
  }

  const connector = getActiveConnector(state);
  const turns = connector.recentTurns.slice(-4);
  const lines: string[] = [];

  if (!turns.length) {
    if (connector.lastUserMessage) {
      lines.push(`Prompt ${connector.lastUserMessage}`);
    }
    if (connector.lastAssistantProgressMessage) {
      lines.push(`Progress ${connector.lastAssistantProgressMessage}`);
    }
    if (connector.lastAssistantMessage) {
      lines.push(`Reply ${connector.lastAssistantMessage}`);
    }
  }

  for (const turn of turns) {
    if (turn.prompt) {
      lines.push(`Prompt ${turn.prompt}`);
    }
    if (turn.progress) {
      lines.push(`Progress ${turn.progress}`);
    }
    if (turn.reply) {
      lines.push(`Reply ${turn.reply}`);
    }
  }

  if (!lines.length) {
    lines.push('Waiting for the first Codex transcript.');
  }

  return lines.join('\n');
}

function buildInputText(state: PluginState) {
  const query = state.stagedQuery || state.draftQuery || 'No staged query.';
  return [
    'Input',
    `Draft ${query}`,
    `Action ${state.selectedInputAction.toUpperCase()}`,
    'Up/down choose action',
    'Click apply',
    'Double-click close',
  ].join('\n');
}

async function fetchJson<T>(url: string) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${url} returned ${response.status}`);
  }

  return (await response.json()) as T;
}

async function applyInputAction(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
) {
  const normalized = normalizeDraftQuery(state.stagedQuery || state.draftQuery || state.lastSubmittedQuery);

  if (state.selectedInputAction === 'cancel') {
    state.draftQuery = '';
    state.stagedQuery = '';
    state.glassesSurfaceMode = 'transcript';
    state.lastMessage = 'Cancelled the staged query.';
    return;
  }

  if (state.selectedInputAction === 'retry') {
    state.draftQuery = normalized;
    state.stagedQuery = normalized;
    state.glassesSurfaceMode = 'input';
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
  state.glassesSurfaceMode = 'transcript';
  state.lastMessage = `Submitting query to Codex: ${normalized}`;

  const connector = getActiveConnector(state);
  connector.lastUserMessage = normalized;
  connector.lastAssistantProgressMessage = 'Waiting for Codex response...';
  try {
    await submitPrompt(bridge, state, normalized);
  } catch (error) {
    state.lastMessage = `Query submit failed: ${formatError(error)}`;
  }
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

function cycleInputAction(state: PluginState, delta: number) {
  const actions: InputAction[] = ['send', 'retry', 'cancel'];
  const currentIndex = actions.indexOf(state.selectedInputAction);
  const nextIndex = (currentIndex + delta + actions.length) % actions.length;
  state.selectedInputAction = actions[nextIndex];
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
  connector.promptUrl = bootstrap.prompt_url;
  connector.lastSeenAt = createTimestamp();
  connector.lastAssistantProgressMessage =
    bootstrap.last_assistant_progress_message || connector.lastAssistantProgressMessage;
  connector.recentTurns = Array.isArray(bootstrap.recent_turns) ? bootstrap.recent_turns : connector.recentTurns;

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
  connector.lastAssistantProgressMessage =
    session.last_assistant_progress_message || connector.lastAssistantProgressMessage;
  connector.lastAssistantMessage = session.last_assistant_message || connector.lastAssistantMessage;
  connector.recentTurns = Array.isArray(session.recent_turns) ? session.recent_turns : connector.recentTurns;
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
    promptUrl: `${normalizedOrigin}/prompt`,
    lastSeenAt: 'Not checked yet',
    lastUserMessage: 'No prompt yet.',
    lastAssistantProgressMessage: 'No progress yet.',
    lastAssistantMessage: 'No reply yet.',
    recentTurns: [],
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

async function submitPrompt(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
  query: string,
) {
  const connector = getActiveConnector(state);
  const response = await fetch(connector.promptUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query }),
  });

  if (!response.ok) {
    throw new Error(`Prompt submit failed with ${response.status}`);
  }

  state.lastMessage = `Submitted query to Codex on ${connector.name}.`;
  await refreshBootstrap(bridge, state, {
    successMessage: 'Codex prompt submitted.',
    failureMessage: 'Prompt submit refresh failed.',
    quiet: true,
  });

  for (const delay of [900, 2200]) {
    window.setTimeout(() => {
      void refreshBootstrap(bridge, state, {
        successMessage: '',
        failureMessage: '',
        quiet: true,
      });
    }, delay);
  }
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
