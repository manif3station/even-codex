import './style.css';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  RebuildPageContainer,
  TextContainerProperty,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

type DetailMode = 'summary' | 'network' | 'steps';

type PluginState = {
  bridgeOrigin: string;
  lifecycle: string;
  bridgeStatus: 'connected' | 'offline';
  detailMode: DetailMode;
  lastMessage: string;
  lastCheckedAt: string;
  workspaceRef: string;
  codexSessionId: string;
  bindHost: string;
  advertisedHost: string;
  port: number;
  healthUrl: string;
  bootstrapUrl: string;
  pluginUrl: string;
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

const STORAGE_KEY = 'd2_codex.bridge_origin';
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
  const storedOrigin = await bridge.getLocalStorage(STORAGE_KEY);
  const state = createInitialState(storedOrigin || DEFAULT_BRIDGE_ORIGIN);

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
        await refreshBootstrap(bridge, state, {
          successMessage: 'Refreshed from glasses footer.',
          failureMessage: 'Refresh from glasses footer failed.',
        });
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
    if (!(form instanceof HTMLFormElement) || form.dataset.role !== 'bridge-form') {
      return;
    }

    submitEvent.preventDefault();
    const formData = new FormData(form);
    const candidate = normalizeOrigin(String(formData.get('bridgeOrigin') || ''));
    await bridge.setLocalStorage(STORAGE_KEY, candidate);
    state.bridgeOrigin = candidate;
    state.lastMessage = 'Stored bridge origin for the next app launch.';
    renderPhoneUi(state);
    await syncGlassesPage(bridge, state);
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

    if (button.dataset.role === 'refresh-button') {
      await refreshBootstrap(bridge, state, {
        successMessage: 'Refreshed from the phone plugin.',
        failureMessage: 'Phone-side refresh failed.',
      });
      return;
    }

    if (button.dataset.role === 'reset-button') {
      await bridge.setLocalStorage(STORAGE_KEY, DEFAULT_BRIDGE_ORIGIN);
      state.bridgeOrigin = DEFAULT_BRIDGE_ORIGIN;
      state.lastMessage = 'Reset bridge origin to the default packaging host.';
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (button.dataset.role === 'cycle-button') {
      state.detailMode = nextDetailMode(state.detailMode);
      state.lastMessage = `Phone-side detail view switched to ${state.detailMode}.`;
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
    }
  });
}

function createInitialState(origin: string): PluginState {
  return {
    bridgeOrigin: normalizeOrigin(origin),
    lifecycle: 'ready',
    bridgeStatus: 'offline',
    detailMode: 'summary',
    lastMessage: 'Waiting for the D2-Codex bridge bootstrap.',
    lastCheckedAt: 'Not checked yet',
    workspaceRef: 'Unpaired',
    codexSessionId: 'Unknown',
    bindHost: 'Unknown',
    advertisedHost: 'Unknown',
    port: 6789,
    healthUrl: `${normalizeOrigin(origin)}/health`,
    bootstrapUrl: `${normalizeOrigin(origin)}/bootstrap`,
    pluginUrl: `${normalizeOrigin(origin)}/plugin/`,
  };
}

async function refreshBootstrap(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
  messages: { successMessage: string; failureMessage: string },
) {
  state.lastCheckedAt = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

  try {
    const [health, bootstrap] = await Promise.all([
      fetchJson<HealthPayload>(`${state.bridgeOrigin}/health`),
      fetchJson<BootstrapPayload>(`${state.bridgeOrigin}/bootstrap`),
    ]);

    state.bridgeStatus = health.ok ? 'connected' : 'offline';
    state.workspaceRef = bootstrap.workspace_ref;
    state.codexSessionId = bootstrap.codex_session_id;
    state.bindHost = bootstrap.bind_host;
    state.advertisedHost = bootstrap.advertised_host;
    state.port = bootstrap.port;
    state.healthUrl = bootstrap.health_url;
    state.bootstrapUrl = bootstrap.bootstrap_url;
    state.pluginUrl = bootstrap.plugin_url;
    state.lastMessage = `${messages.successMessage} Paired ${bootstrap.workspace_ref} to ${bootstrap.codex_session_id}.`;
  } catch (error) {
    state.bridgeStatus = 'offline';
    state.lastMessage = `${messages.failureMessage} ${formatError(error)}`;
  }

  renderPhoneUi(state);
  await syncGlassesPage(bridge, state);
}

function renderPhoneUi(state: PluginState) {
  app!.innerHTML = `
    <section class="shell">
      <div class="stack">
        <header class="hero">
          <div class="hero-copy stack">
            <p class="eyebrow">Even Plugin</p>
            <h1 class="title">D2-Codex</h1>
            <p class="copy">Turn the paired Codex workspace into a readable glasses companion without making the user decipher raw bridge details.</p>
          </div>
          <div class="panel status-panel">
            <p class="label">Connection</p>
            <p class="status-chip">${escapeHtml(state.bridgeStatus.toUpperCase())}</p>
            <p class="hint">Last check ${escapeHtml(state.lastCheckedAt)}</p>
          </div>
        </header>

        <section class="metric-grid">
          <article class="panel">
            <p class="label">Workspace</p>
            <p class="value">${escapeHtml(state.workspaceRef)}</p>
          </article>
          <article class="panel">
            <p class="label">Codex Session</p>
            <p class="value">${escapeHtml(state.codexSessionId)}</p>
          </article>
          <article class="panel">
            <p class="label">Advertised Host</p>
            <p class="value">${escapeHtml(state.advertisedHost)}</p>
          </article>
          <article class="panel">
            <p class="label">Lifecycle</p>
            <p class="value">${escapeHtml(state.lifecycle)}</p>
          </article>
        </section>

        <section class="action-row">
          <button class="button" type="button" data-role="refresh-button">Refresh Connection</button>
          <button class="button" type="button" data-role="cycle-button">Cycle Glasses Detail</button>
          <button class="button" type="button" data-role="reset-button">Reset Origin</button>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Connection Checklist</h2>
          <ol class="list">
            <li>Run <code>dashboard workspace foobar</code> in the project you want on glasses.</li>
            <li>Copy the Codex session id from <code>/status</code>.</li>
            <li>Save the pairing with <code>dashboard even-codex.start add &lt;codex-session-id&gt;</code>.</li>
            <li>Start the bridge with <code>dashboard even-codex.start</code> so the phone can reach port 6789.</li>
          </ol>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Pairing Flow</h2>
          <p class="copy">The phone plugin chooses the laptop bridge origin. The glasses page then reads paired workspace data from that bridge and keeps a compact status view visible.</p>
          <form class="form" data-role="bridge-form">
            <label class="label" for="bridgeOrigin">Bridge Origin</label>
            <input class="input" id="bridgeOrigin" name="bridgeOrigin" type="url" value="${escapeHtml(
              state.bridgeOrigin,
            )}" />
            <p class="hint">Use a LAN-reachable host such as <code>http://192.168.1.20:6789</code>. Port 6789 is the default bridge port.</p>
            <button class="button" type="submit">Store Bridge Origin</button>
          </form>
        </section>

        <section class="metric-grid">
          <article class="panel">
            <p class="label">Health URL</p>
            <p class="value">${escapeHtml(state.healthUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Bootstrap URL</p>
            <p class="value">${escapeHtml(state.bootstrapUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Plugin URL</p>
            <p class="value">${escapeHtml(state.pluginUrl)}</p>
          </article>
          <article class="panel">
            <p class="label">Port 6789</p>
            <p class="value">Default bridge listener for phone-to-laptop pairing.</p>
          </article>
        </section>

        <section class="panel stack">
          <h2 class="section-title">Glasses Controls</h2>
          <ul class="list">
            <li>Tap header to refresh.</li>
            <li>Tap detail to cycle.</li>
            <li>Double-click to exit.</li>
          </ul>
          <p class="status">${escapeHtml(state.lastMessage)}</p>
        </section>
      </div>
    </section>
  `;
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
  return [
    'D2-Codex',
    `${state.bridgeStatus.toUpperCase()}  ${state.workspaceRef}`,
    'Tap header to refresh',
  ].join('\n');
}

function buildDetailText(state: PluginState) {
  if (state.detailMode === 'network') {
    return [
      'Network',
      truncate(`Host ${state.advertisedHost}:${state.port}`, 34),
      truncate(`Health ${state.healthUrl}`, 34),
      'Tap detail to cycle',
    ].join('\n');
  }

  if (state.detailMode === 'steps') {
    return [
      'Pairing Steps',
      '1 Add session id',
      '2 Start bridge 6789',
      'Tap detail to cycle',
    ].join('\n');
  }

  return [
    'Summary',
    truncate(`Session ${state.codexSessionId}`, 34),
    truncate(state.lastMessage, 34),
    'Tap detail to cycle',
  ].join('\n');
}

function buildFooterText(state: PluginState) {
  return [
    `State ${state.lifecycle}`,
    `Checked ${state.lastCheckedAt}`,
    'Tap footer or header to refresh',
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
