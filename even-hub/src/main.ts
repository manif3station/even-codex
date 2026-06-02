import './style.css';
import { buildTranscriptRenderLines } from './transcript-view.js';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  RebuildPageContainer,
  TextContainerUpgrade,
  TextContainerProperty,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

type InputAction = 'send' | 'retry' | 'cancel';
type GlassesSurfaceMode = 'transcript' | 'input';
type VoiceInputState = 'idle' | 'starting' | 'listening' | 'captured' | 'phone' | 'error';

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
  transcriptLiveFollow: boolean;
  voiceInputState: VoiceInputState;
  voiceSupported: boolean;
  voiceStatus: string;
};

type SpeechRecognitionResultLike = {
  isFinal?: boolean;
  0?: { transcript?: string };
  [index: number]: { transcript?: string } | undefined;
};

type SpeechRecognitionEventLike = {
  resultIndex?: number;
  results?: SpeechRecognitionResultLike[];
};

type SpeechRecognitionLike = {
  continuous?: boolean;
  interimResults?: boolean;
  lang?: string;
  onstart?: (() => void) | null;
  onresult?: ((event: SpeechRecognitionEventLike) => void) | null;
  onerror?: ((event: { error?: string }) => void) | null;
  onend?: (() => void) | null;
  start: () => void;
  stop: () => void;
  abort?: () => void;
};

type EvenCodexBridgeLike = Awaited<ReturnType<typeof waitForEvenAppBridge>>;

type TestWindow = Window &
  typeof globalThis & {
    webkitSpeechRecognition?: new () => SpeechRecognitionLike;
    SpeechRecognition?: new () => SpeechRecognitionLike;
    __evenCodexWaitForBridge?: () => Promise<EvenCodexBridgeLike>;
    __evenCodexSpeechRecognitionFactory?: () => SpeechRecognitionLike;
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
const GLASSES_POPUP_CONTAINER_ID = 2;
const GLASSES_POPUP_CONTAINER_NAME = 'd2-codex-popup';
const GLASSES_TRANSCRIPT_HEIGHT = 184;
const GLASSES_POPUP_Y = 188;
const GLASSES_POPUP_HEIGHT = 96;
const CAN_USE_DOM_SPEECH_RECOGNITION = typeof window !== 'undefined';
const app = document.querySelector<HTMLDivElement>('#app');
const testWindow = window as TestWindow;
const runtime = {
  recognition: null as SpeechRecognitionLike | null,
  glassesLayoutMode: null as GlassesSurfaceMode | null,
};

if (!app) {
  throw new Error('Missing app container');
}

void boot();

async function boot() {
  const bridge = await loadBridge();
  const config = await loadStoredConfig(bridge);
  const state = createInitialState(config);
  state.voiceSupported = speechRecognitionSupported();
  state.voiceStatus = state.voiceSupported
    ? 'Voice query capture is ready when the webview exposes speech recognition.'
    : 'Voice query capture is unavailable in this webview. Use the phone composer text area instead.';

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
    const isGlassesContainer =
      textEvent?.containerID === GLASSES_TRANSCRIPT_CONTAINER_ID ||
      textEvent?.containerID === GLASSES_POPUP_CONTAINER_ID;
    const isTextContainerClick =
      isGlassesContainer &&
      (textEvent.eventType === undefined || textEvent.eventType === OsEventTypeList.CLICK_EVENT);
    const isTextContainerDoubleClick =
      isGlassesContainer &&
      textEvent.eventType === OsEventTypeList.DOUBLE_CLICK_EVENT;

    if (sysEventType === OsEventTypeList.DOUBLE_CLICK_EVENT || isTextContainerDoubleClick) {
      state.glassesSurfaceMode = 'transcript';
      state.transcriptLiveFollow = true;
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
        state.lastMessage = hasActionableDraft(state)
          ? 'Glasses press opened the staged query popup.'
          : 'Glasses press opened the popup and armed the voice query path.';
        await startVoiceInput(bridge, state, { source: 'glasses-click' });
      }
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (isGlassesContainer) {
      if (textEvent.eventType === OsEventTypeList.SCROLL_TOP_EVENT) {
        if (state.glassesSurfaceMode === 'input') {
          cycleInputAction(state, -1);
          state.lastMessage = `Glasses swipe up selected ${state.selectedInputAction.toUpperCase()}.`;
          renderPhoneUi(state);
          await syncGlassesPage(bridge, state);
        } else {
          state.transcriptLiveFollow = false;
          state.lastMessage = 'Transcript review is pinned in place until you scroll back to the live bottom line.';
          renderPhoneUi(state);
          await syncGlassesPage(bridge, state, { forceTranscript: true });
        }
        return;
      }

      if (textEvent.eventType === OsEventTypeList.SCROLL_BOTTOM_EVENT) {
        if (state.glassesSurfaceMode === 'input') {
          cycleInputAction(state, 1);
          state.lastMessage = `Glasses swipe down selected ${state.selectedInputAction.toUpperCase()}.`;
          renderPhoneUi(state);
          await syncGlassesPage(bridge, state);
        } else {
          state.transcriptLiveFollow = true;
          state.lastMessage = 'Transcript live-follow resumed at the newest bottom line.';
          renderPhoneUi(state);
          await syncGlassesPage(bridge, state, { forceTranscript: true });
        }
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
      state.voiceInputState = 'idle';
      state.voiceStatus = query
        ? 'Typed query staged. Swipe to another action or click to apply.'
        : state.voiceSupported
          ? 'Type or speak a query before staging it.'
          : 'Type a query before staging it.';
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
      state.stagedQuery = normalizeDraftQuery(state.draftQuery);
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

    if (role === 'start-voice-query-button') {
      await startVoiceInput(bridge, state, { source: 'phone-button' });
      renderPhoneUi(state);
      await syncGlassesPage(bridge, state);
      return;
    }

    if (role === 'stop-voice-query-button') {
      await stopVoiceInput(bridge, state, { keepDraft: true, reason: 'manual stop' });
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

  app.addEventListener('input', async (inputEvent) => {
    const target = inputEvent.target;
    if (!(target instanceof HTMLTextAreaElement)) {
      return;
    }

    if (target.id !== 'draftQuery') {
      return;
    }

    state.draftQuery = normalizeDraftQuery(target.value || '');
    state.stagedQuery = state.draftQuery;
    if (state.draftQuery) {
      state.selectedInputAction = 'send';
    }
    await syncGlassesPage(bridge, state);
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
    transcriptLiveFollow: true,
    voiceInputState: 'idle',
    voiceSupported: false,
    voiceStatus: 'Voice query capture has not been initialized yet.',
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
            <p class="label">Voice Query</p>
            <p class="value">${escapeHtml(state.voiceInputState.toUpperCase())}</p>
            <p class="hint">${escapeHtml(state.voiceStatus)}</p>
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
          <p class="copy">The current Even SDK does not document a native hold-to-dictate sheet, so this app uses a hybrid flow: glasses clicks open the popup, the companion webview speech-recognition session fills the draft when available, and any query that starts with <code>Slash</code> or <code>slash</code> is normalized to <code>/</code>.</p>
          <form class="form" data-role="query-form">
            <label class="label" for="draftQuery">Draft Query</label>
            <textarea class="input input-area" id="draftQuery" name="draftQuery" rows="4" placeholder="Type or paste the next Codex query here.">${normalizedDraft}</textarea>
            <p class="hint">Stage the query first, or use the voice controls to fill it from speech. Then choose Send, Retry, or Cancel. The live simulator review checks this state visually.</p>
            <div class="action-row">
              <button class="button" type="button" data-role="load-slash-sample-button">Load Slash Sample</button>
              <button class="button" type="button" data-role="load-latest-prompt-button">Reuse Latest Prompt</button>
            </div>
            <div class="action-row">
              <button class="button" type="button" data-role="start-voice-query-button">Start Voice</button>
              <button class="button" type="button" data-role="stop-voice-query-button">Stop Voice</button>
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
            <li>The transcript follows the live bottom line until you scroll up to inspect older text.</li>
            <li>Click opens the staged query popup over the transcript and starts a companion voice-input attempt when speech recognition is available.</li>
            <li>Recognised speech is mirrored into the popup draft so the next click can send it through the existing action flow.</li>
            <li>Double-click closes the popup and returns to the live transcript.</li>
            <li>Hold-to-dictate is not documented by the current Even SDK, so this remains a hybrid glasses-plus-webview implementation instead of a native glasses dictation sheet.</li>
          </ul>
          <p class="status">${escapeHtml(state.lastMessage)}</p>
        </section>
      </div>
    </section>
  `;

  if (state.voiceInputState === 'phone') {
    focusDraftComposerSoon();
  }
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
    containerTotalNum: buildTextObjects(state).length,
    textObject: buildTextObjects(state),
  });
}

async function syncGlassesPage(
  bridge: Awaited<ReturnType<typeof waitForEvenAppBridge>>,
  state: PluginState,
  options: { forceTranscript?: boolean } = {},
) {
  if (runtime.glassesLayoutMode !== state.glassesSurfaceMode) {
    await bridge.rebuildPageContainer(
      new RebuildPageContainer({
        containerTotalNum: buildTextObjects(state).length,
        textObject: buildTextObjects(state),
      }),
    );
    runtime.glassesLayoutMode = state.glassesSurfaceMode;
    return;
  }

  if (state.glassesSurfaceMode === 'transcript') {
    if (!state.transcriptLiveFollow && !options.forceTranscript) {
      return;
    }

    await bridge.textContainerUpgrade(
      new TextContainerUpgrade({
        containerID: GLASSES_TRANSCRIPT_CONTAINER_ID,
        containerName: GLASSES_TRANSCRIPT_CONTAINER_NAME,
        content: buildTranscriptText(state),
      }),
    );
    return;
  }

  await bridge.textContainerUpgrade(
    new TextContainerUpgrade({
      containerID: GLASSES_TRANSCRIPT_CONTAINER_ID,
      containerName: GLASSES_TRANSCRIPT_CONTAINER_NAME,
      content: buildTranscriptText(state),
    }),
  );
  await bridge.textContainerUpgrade(
    new TextContainerUpgrade({
      containerID: GLASSES_POPUP_CONTAINER_ID,
      containerName: GLASSES_POPUP_CONTAINER_NAME,
      content: buildInputText(state),
    }),
  );
}

function buildTextObjects(state: PluginState) {
  const objects = [
    new TextContainerProperty({
      xPosition: 0,
      yPosition: 0,
      width: 576,
      height: state.glassesSurfaceMode === 'input' ? GLASSES_TRANSCRIPT_HEIGHT : 288,
      borderWidth: 0,
      borderColor: 0,
      paddingLength: 8,
      containerID: GLASSES_TRANSCRIPT_CONTAINER_ID,
      containerName: GLASSES_TRANSCRIPT_CONTAINER_NAME,
      content: buildTranscriptText(state),
      isEventCapture: state.glassesSurfaceMode === 'input' ? 0 : 1,
    }),
  ];

  if (state.glassesSurfaceMode === 'input') {
    objects.push(
      new TextContainerProperty({
        xPosition: 20,
        yPosition: GLASSES_POPUP_Y,
        width: 536,
        height: GLASSES_POPUP_HEIGHT,
        borderWidth: 1,
        borderColor: 15,
        paddingLength: 8,
        containerID: GLASSES_POPUP_CONTAINER_ID,
        containerName: GLASSES_POPUP_CONTAINER_NAME,
        content: buildInputText(state),
        isEventCapture: 1,
      }),
    );
  }

  return objects;
}

function buildTranscriptText(state: PluginState) {
  const lines = buildTranscriptLines(state);
  return buildTranscriptRenderLines(lines, {
    follow: state.transcriptLiveFollow,
    popup: state.glassesSurfaceMode === 'input',
  }).join('\n');
}

function buildTranscriptLines(state: PluginState) {
  const connector = getActiveConnector(state);
  const turns = connector.recentTurns.slice(-(state.glassesSurfaceMode === 'input' ? 3 : 4));
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

  return lines;
}

function buildInputText(state: PluginState) {
  const query = truncateForGlasses(
    state.stagedQuery ||
      state.draftQuery ||
      (state.voiceInputState === 'phone' ? 'Use phone mic or type.' : 'No staged query.'),
  );
  return [
    'Prompt Box',
    `Draft ${query}`,
    `Voice ${state.voiceInputState.toUpperCase()}`,
    truncateForGlasses(state.voiceStatus || 'Voice query status unavailable.'),
    `Action ${state.selectedInputAction.toUpperCase()}`,
    'Up/down choose action',
    'Click apply',
    'Double-click close',
  ].join('\n');
}

function hasActionableDraft(state: PluginState) {
  return normalizeDraftQuery(state.stagedQuery || state.draftQuery || state.lastSubmittedQuery) !== '';
}

function voiceCaptureActive(state: PluginState) {
  return state.voiceInputState === 'listening' || state.voiceInputState === 'starting';
}

function speechRecognitionSupported() {
  if (!CAN_USE_DOM_SPEECH_RECOGNITION) {
    return false;
  }

  if (typeof testWindow.__evenCodexSpeechRecognitionFactory === 'function') {
    return true;
  }

  return !!(testWindow.SpeechRecognition || testWindow.webkitSpeechRecognition);
}

async function loadBridge() {
  if (typeof testWindow.__evenCodexWaitForBridge === 'function') {
    return testWindow.__evenCodexWaitForBridge();
  }

  return waitForEvenAppBridge();
}

function focusDraftComposer() {
  const composer = document.querySelector<HTMLTextAreaElement>('#draftQuery');
  if (!composer) {
    return false;
  }

  composer.focus();
  const draft = composer.value || '';
  const cursor = draft.length;
  if (typeof composer.setSelectionRange === 'function') {
    composer.setSelectionRange(cursor, cursor);
  }
  return document.activeElement === composer;
}

function focusDraftComposerSoon() {
  window.setTimeout(() => {
    focusDraftComposer();
  }, 0);
}

function activatePhoneComposerFallback(state: PluginState, message?: string) {
  state.voiceInputState = 'phone';
  state.voiceStatus = message || 'Phone composer fallback is ready. Use the phone keyboard microphone or type into the composer.';
  state.lastMessage = state.voiceStatus;
  focusDraftComposerSoon();
}

function speechRecognitionFactory(): (() => SpeechRecognitionLike) | null {
  if (!speechRecognitionSupported()) {
    return null;
  }

  if (typeof testWindow.__evenCodexSpeechRecognitionFactory === 'function') {
    return testWindow.__evenCodexSpeechRecognitionFactory;
  }

  const NativeRecognition = testWindow.SpeechRecognition || testWindow.webkitSpeechRecognition;
  if (!NativeRecognition) {
    return null;
  }

  return () => new NativeRecognition();
}

async function startVoiceInput(
  bridge: EvenCodexBridgeLike,
  state: PluginState,
  options: { source: 'glasses-click' | 'phone-button' },
) {
  if (state.voiceInputState === 'listening' || state.voiceInputState === 'starting') {
    state.lastMessage = 'Voice query capture is already active.';
    return;
  }

  const factory = speechRecognitionFactory();
  if (!factory) {
    activatePhoneComposerFallback(state);
    return;
  }

  state.voiceInputState = 'starting';
  state.voiceStatus = options.source === 'glasses-click'
    ? 'Opening the voice query path from the glasses popup.'
    : 'Opening the voice query path from the phone controls.';
  state.lastMessage = state.voiceStatus;
  const recognition = factory();
  recognition.continuous = false;
  recognition.interimResults = true;
  recognition.lang = 'en-GB';
  runtime.recognition = recognition;

  recognition.onstart = () => {
    state.voiceInputState = 'listening';
    state.voiceStatus = 'Listening for a voice query.';
    state.lastMessage = 'Listening for a voice query.';
    renderPhoneUi(state);
    void syncGlassesPage(bridge, state);
  };

  recognition.onresult = (event) => {
    const fragments: string[] = [];
    for (let index = event.resultIndex || 0; index < (event.results || []).length; index += 1) {
      const result = event.results?.[index];
      const transcript = typeof result?.[0]?.transcript === 'string' ? result[0].transcript : '';
      if (transcript) {
        fragments.push(transcript);
      }
    }

    const recognized = normalizeDraftQuery(fragments.join(' ').trim());
    if (!recognized) {
      return;
    }

    state.draftQuery = recognized;
    state.stagedQuery = recognized;
    state.selectedInputAction = 'send';
    state.voiceInputState = 'captured';
    state.voiceStatus = `Captured voice query: ${recognized}`;
    state.lastMessage = 'Voice query captured. Swipe to another action or click to apply.';
    renderPhoneUi(state);
    void syncGlassesPage(bridge, state);
  };

  recognition.onerror = (event) => {
    const errorCode = event.error || 'unknown error';
    if (errorCode === 'not-allowed' || errorCode === 'service-not-allowed' || errorCode === 'audio-capture') {
      activatePhoneComposerFallback(
        state,
        'Phone composer fallback is ready. Use the phone keyboard microphone or type into the composer.',
      );
    } else {
      state.voiceInputState = 'error';
      state.voiceStatus = `Voice query capture failed: ${errorCode}`;
      state.lastMessage = state.voiceStatus;
    }
    void bridge.audioControl(false).catch(() => {});
    renderPhoneUi(state);
    void syncGlassesPage(bridge, state);
  };

  recognition.onend = () => {
    runtime.recognition = null;
    void bridge.audioControl(false).catch(() => {});
    if (state.voiceInputState === 'listening' || state.voiceInputState === 'starting') {
      state.voiceInputState = hasActionableDraft(state) ? 'captured' : 'idle';
      state.voiceStatus = hasActionableDraft(state)
        ? 'Voice query captured. Ready to send.'
        : 'Voice query capture ended without recognised text.';
      state.lastMessage = state.voiceStatus;
      renderPhoneUi(state);
      void syncGlassesPage(bridge, state);
    }
  };

  try {
    await bridge.audioControl(true);
  } catch (error) {
    state.voiceStatus = `Glasses microphone request failed: ${formatError(error)}`;
    state.lastMessage = state.voiceStatus;
  }

  try {
    recognition.start();
  } catch (error) {
    runtime.recognition = null;
    activatePhoneComposerFallback(
      state,
      `Phone composer fallback is ready. Use the phone keyboard microphone or type into the composer.`,
    );
  }
}

async function stopVoiceInput(
  bridge: EvenCodexBridgeLike,
  state: PluginState,
  options: { keepDraft: boolean; reason: string },
) {
  if (runtime.recognition) {
    runtime.recognition.stop();
    runtime.recognition = null;
  }
  await bridge.audioControl(false).catch(() => undefined);
  state.voiceInputState = options.keepDraft && hasActionableDraft(state) ? 'captured' : 'idle';
  state.voiceStatus = options.keepDraft && hasActionableDraft(state)
    ? 'Voice query capture stopped. The recognised draft is still staged.'
    : `Voice query capture stopped: ${options.reason}.`;
  state.lastMessage = state.voiceStatus;
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
  let normalized = normalizeDraftQuery(state.stagedQuery || state.draftQuery || state.lastSubmittedQuery);

  if (state.selectedInputAction === 'cancel') {
    await stopVoiceInput(bridge, state, { keepDraft: false, reason: 'cancelled' });
    state.draftQuery = '';
    state.stagedQuery = '';
    state.glassesSurfaceMode = 'transcript';
    state.lastMessage = 'Cancelled the staged query.';
    return;
  }

  if (state.selectedInputAction === 'retry') {
    await stopVoiceInput(bridge, state, { keepDraft: true, reason: 'retry' });
    state.draftQuery = normalized;
    state.stagedQuery = normalized;
    state.glassesSurfaceMode = 'input';
    state.lastMessage = 'Retry selected. Speak again or update the draft and stage it again.';
    if (state.voiceSupported) {
      await startVoiceInput(bridge, state, { source: 'glasses-click' });
    }
    return;
  }

  if (state.selectedInputAction === 'send' && voiceCaptureActive(state)) {
    await stopVoiceInput(bridge, state, { keepDraft: true, reason: 'submit intent' });
    normalized = normalizeDraftQuery(state.stagedQuery || state.draftQuery || state.lastSubmittedQuery);
    if (!normalized) {
      state.glassesSurfaceMode = 'input';
      if (state.voiceInputState === 'phone' || !state.voiceSupported) {
        focusDraftComposerSoon();
        state.lastMessage = 'Use the phone mic or type in the composer, then click again to send or close.';
        state.voiceStatus = 'Phone composer fallback is still open. Use the phone mic or type into the composer.';
      } else {
        state.lastMessage = 'Voice capture stopped without recognised text. Click again to close or speak again.';
        state.voiceStatus = 'Voice query capture stopped without recognised text.';
      }
      return;
    }
  }

  if (!normalized) {
    state.glassesSurfaceMode = 'transcript';
    state.lastMessage = 'Closed the popup because there is no staged query yet.';
    state.voiceStatus = state.voiceInputState === 'phone' || !state.voiceSupported
      ? 'Popup closed with no staged query. Use the phone mic or type in the composer first.'
      : 'Popup closed with no staged query. Click again to reopen voice standby.';
    return;
  }

  state.lastSubmittedQuery = normalized;
  state.stagedQuery = normalized;
  state.draftQuery = normalized;
  await stopVoiceInput(bridge, state, { keepDraft: true, reason: 'submit' });
  state.glassesSurfaceMode = 'transcript';
  state.voiceStatus = 'Voice query ready for submission.';
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
    typeof bootstrap.last_assistant_progress_message === 'string'
      ? bootstrap.last_assistant_progress_message
      : connector.lastAssistantProgressMessage;
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
  connector.lastUserMessage =
    typeof session.last_user_message === 'string' ? session.last_user_message : connector.lastUserMessage;
  connector.lastAssistantProgressMessage =
    typeof session.last_assistant_progress_message === 'string'
      ? session.last_assistant_progress_message
      : connector.lastAssistantProgressMessage;
  connector.lastAssistantMessage =
    typeof session.last_assistant_message === 'string'
      ? session.last_assistant_message
      : connector.lastAssistantMessage;
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

function truncateForGlasses(value: string) {
  return truncate(value, 56);
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
