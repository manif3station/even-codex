import './style.css';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  RebuildPageContainer,
  TextContainerProperty,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

type DetailMode = 'summary' | 'network' | 'steps';

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
  lastMessage: string;
  lastCheckedAt: string;
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

const CONFIG_STORAGE_KEY = 'd2_codex.config';
const LEGACY_ORIGIN_STORAGE_KEY = 'd2_codex.bridge_origin';
const DEFAULT_BRIDGE_ORIGIN =
  import.meta.env.VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN || 'http://192.168.1.20:6789';
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

  bridge.onEvenHubEvent(async (event) => {
    const sysEventType = event.sysEvent?.eventType;
    if (sysEventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
      await bridge.shutDownPageContainer(1);
      return;
    }

    const textEvent = event.textEvent;
    if (textEvent?.eventType === OsEventTypeList.CLICK_EVENT) {
      if (textEvent.containerID === GLASSES_CONTAINER.header) {
        await refreshBootstrap(bridge, state, {
          successMessage: 'Refreshed from glasses header.',
          failureMessage: 'Refresh from glasses header failed.',
        });
        return;
      }

      if (textEvent.containerID === GLASSES_CONTAINER.detail) {
        state.detailMode = nextDetailMode(state.detailMode);
        state.lastMessage = `Showing ${state.detailMode} view on glasses.`;
        renderPhoneUi(state);
        await syncGlassesPage(bridge, state);
        return;
      }

      if (textEvent.containerID === GLASSES_CONTAINER.footer) {
        cycleSession(state);
        state.lastMessage = `Glasses switched to ${getActiveSession(state)?.label || 'the next session'}.`;
        await persistConfig(bridge, state.config);
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
    lastMessage: 'Waiting for the D2-Codex bridge bootstrap.',
    lastCheckedAt: 'Not checked yet',
  };
}

async function refreshBootstrap(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
  messages: { successMessage: string; failureMessage: string },
) {
  state.lastCheckedAt = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const connector = getActiveConnector(state);

  try {
    const [health, bootstrap] = await Promise.all([
      fetchJson<HealthPayload>(`${connector.origin}/health`),
      fetchJson<BootstrapPayload>(`${connector.origin}/bootstrap`),
    ]);

    state.bridgeStatus = health.ok ? 'connected' : 'offline';
    mergeBootstrapIntoConnector(connector, bootstrap);
    await persistConfig(bridge, state.config);
    state.lastMessage = `${messages.successMessage} ${connector.name} paired ${bootstrap.workspace_ref} to ${bootstrap.codex_session_id}.`;
  } catch (error) {
    state.bridgeStatus = 'offline';
    state.lastMessage = `${messages.failureMessage} ${formatError(error)}`;
  }

  renderPhoneUi(state);
  await syncGlassesPage(bridge, state);
}

function renderPhoneUi(state: PluginState) {
  const connector = getActiveConnector(state);
  const activeSession = getActiveSession(state);
  const sessionCount = connector.sessions.length;

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

        <section class="action-row">
          <button class="button" type="button" data-role="refresh-button">Refresh Connection</button>
          <button class="button" type="button" data-role="cycle-button">Cycle Glasses Detail</button>
          <button class="button" type="button" data-role="cycle-session-button">Next Glasses Session</button>
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
            <li>Tap header to refresh the active connector.</li>
            <li>Tap detail to cycle between summary, network, and setup views.</li>
            <li>Tap footer to switch session inside the active connector only.</li>
            <li>Double-click to exit.</li>
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
      isEventCapture: 1,
    }),
    new TextContainerProperty({
      xPosition: 0,
      yPosition: 78,
      width: 576,
      height: 136,
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
      yPosition: 220,
      width: 576,
      height: 68,
      borderWidth: 1,
      borderColor: 5,
      paddingLength: 8,
      containerID: GLASSES_CONTAINER.footer,
      containerName: 'd2-codex-footer',
      content: buildFooterText(state),
      isEventCapture: 1,
    }),
  ];
}

function buildHeaderText(state: PluginState) {
  const connector = getActiveConnector(state);
  return [
    'D2-Codex',
    `${state.bridgeStatus.toUpperCase()}  ${truncate(connector.name, 20)}`,
    'Tap header to refresh',
  ].join('\n');
}

function buildDetailText(state: PluginState) {
  const connector = getActiveConnector(state);
  const session = getActiveSession(state);

  if (state.detailMode === 'network') {
    return [
      'Network',
      truncate(`Host ${connector.advertisedHost}:${connector.port}`, 34),
      truncate(`Origin ${connector.origin}`, 34),
      'Tap detail to cycle',
    ].join('\n');
  }

  if (state.detailMode === 'steps') {
    return [
      'Session Switching',
      truncate(`Connector ${connector.name}`, 34),
      'Phone swaps connectors',
      'Tap detail to cycle',
    ].join('\n');
  }

  return [
    'Summary',
    truncate(`Session ${session?.label || connector.currentSessionId}`, 34),
    truncate(`Workspace ${connector.workspaceRef}`, 34),
    'Tap detail to cycle',
  ].join('\n');
}

function buildFooterText(state: PluginState) {
  const connector = getActiveConnector(state);
  const session = getActiveSession(state);
  return [
    `Session ${truncate(session?.label || connector.currentSessionId || 'Unknown', 24)}`,
    `Checked ${state.lastCheckedAt}`,
    'Tap footer to switch session',
    'Double-click to exit',
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
    return 'steps';
  }

  return 'summary';
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
