import './style.css';

import {
  CreateStartUpPageContainer,
  OsEventTypeList,
  TextContainerProperty,
  TextContainerUpgrade,
  waitForEvenAppBridge,
} from '@evenrealities/even_hub_sdk';

const STORAGE_KEY = 'd2_codex.bridge_origin';
const DEFAULT_BRIDGE_ORIGIN =
  import.meta.env.VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN || 'http://192.168.1.20:6789';
const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('Missing app container');
}

void boot();

async function boot() {
  const bridge = await waitForEvenAppBridge();
  const storedOrigin = await bridge.getLocalStorage(STORAGE_KEY);
  const bridgeOrigin = normalizeOrigin(storedOrigin || DEFAULT_BRIDGE_ORIGIN);
  const state = {
    bridgeOrigin,
    lifecycle: 'ready',
    lastMessage: 'Waiting for the D2-Codex bridge bootstrap.',
  };

  renderPhoneUi(state);

  await bridge.createStartUpPageContainer(
    new CreateStartUpPageContainer({
      containerTotalNum: 1,
      textObject: [
        new TextContainerProperty({
          xPosition: 0,
          yPosition: 0,
          width: 576,
          height: 288,
          borderWidth: 1,
          borderColor: 5,
          paddingLength: 8,
          containerID: 1,
          containerName: 'd2-codex-main',
          content: buildDisplayText(state),
          isEventCapture: 1,
        }),
      ],
    }),
  );

  bridge.onEvenHubEvent(async (event) => {
    const eventType = event.sysEvent?.eventType;
    if (eventType === OsEventTypeList.DOUBLE_CLICK_EVENT) {
      await bridge.shutDownPageContainer(1);
      return;
    }

    if (eventType === OsEventTypeList.FOREGROUND_ENTER_EVENT) {
      state.lifecycle = 'foreground';
    } else if (eventType === OsEventTypeList.FOREGROUND_EXIT_EVENT) {
      state.lifecycle = 'background';
    } else if (eventType === OsEventTypeList.ABNORMAL_EXIT_EVENT) {
      state.lifecycle = 'abnormal-exit';
    } else if (eventType === OsEventTypeList.SYSTEM_EXIT_EVENT) {
      state.lifecycle = 'system-exit';
    } else {
      return;
    }

    state.lastMessage = `Lifecycle event: ${state.lifecycle}`;
    renderPhoneUi(state);
    await bridge.textContainerUpgrade(
      new TextContainerUpgrade({
        containerID: 1,
        containerName: 'd2-codex-main',
        content: buildDisplayText(state),
      }),
    );
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
    await bridge.textContainerUpgrade(
      new TextContainerUpgrade({
        containerID: 1,
        containerName: 'd2-codex-main',
        content: buildDisplayText(state),
      }),
    );
  });

  try {
    const bootstrap = await fetch(`${state.bridgeOrigin}/bootstrap`).then((response) => {
      if (!response.ok) {
        throw new Error(`Bootstrap returned ${response.status}`);
      }

      return response.json() as Promise<{
        workspace_ref: string;
        codex_session_id: string;
        plugin_url: string;
      }>;
    });

    state.lastMessage = `Paired ${bootstrap.workspace_ref} to ${bootstrap.codex_session_id}.`;
  } catch (error) {
    state.lastMessage = `Bridge fetch failed: ${formatError(error)}`;
  }

  renderPhoneUi(state);
  await bridge.textContainerUpgrade(
    new TextContainerUpgrade({
      containerID: 1,
      containerName: 'd2-codex-main',
      content: buildDisplayText(state),
    }),
  );
}

function renderPhoneUi(state: { bridgeOrigin: string; lifecycle: string; lastMessage: string }) {
  app!.innerHTML = `
    <section class="shell">
      <div class="frame stack">
        <h1 class="title">D2-Codex</h1>
        <p class="copy">Package this app for the same LAN origin your laptop bridge serves on port 6789.</p>
        <div class="grid">
          <div class="field">
            <p class="label">Bridge Origin</p>
            <p class="value">${escapeHtml(state.bridgeOrigin)}</p>
          </div>
          <div class="field">
            <p class="label">Lifecycle</p>
            <p class="value">${escapeHtml(state.lifecycle)}</p>
          </div>
          <div class="field">
            <p class="label">Status</p>
            <p class="status">${escapeHtml(state.lastMessage)}</p>
          </div>
        </div>
        <form class="form" data-role="bridge-form">
          <label class="label" for="bridgeOrigin">Bridge Origin</label>
          <input class="input" id="bridgeOrigin" name="bridgeOrigin" type="url" value="${escapeHtml(
            state.bridgeOrigin,
          )}" />
          <button class="button" type="submit">Store Origin</button>
        </form>
        <p class="hint">Glasses exit: root double-click triggers the system confirmation dialog.</p>
      </div>
    </section>
  `;
}

function buildDisplayText(state: { bridgeOrigin: string; lifecycle: string; lastMessage: string }) {
  const trimmedStatus = state.lastMessage.slice(0, 220);
  return [
    'D2-Codex',
    '',
    `Bridge: ${state.bridgeOrigin}`,
    `State: ${state.lifecycle}`,
    '',
    trimmedStatus,
    '',
    'Double-click to exit.',
  ].join('\n');
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
