<script setup lang="ts">
  useSeoMeta({
    title: "Create Room",
    description:
      "Generate a room code and QR link so your audience can instantly join and send reactions.",
  });

  const roomId = ref("");
  const joinUrl = ref("");
  const copied = ref(false);
  const presenceState = ref<
    "connecting" | "connected" | "disconnected" | "error"
  >("connecting");
  const connectedCount = ref<number | null>(null);
  const socket = ref<WebSocket | null>(null);
  const poll = ref<{
    id: string;
    question: string;
    options: { id: string; label: string }[];
    startAt: number;
    endAt: number;
    status: "active" | "complete";
    tally?: Record<string, number>;
  } | null>(null);
  const pollQuestion = ref("");
  const pollOptions = ref("Yes\nNo");
  const pollDurationSeconds = ref(30);
  const pollError = ref("");
  const showPoll = ref(false);
  const pollNow = ref(Date.now());
  const config = useRuntimeConfig();
  const realtimeUrl = config.public.realtimeUrl || "ws://localhost:8787";
  const presenceRefreshIntervalMs = 15000;
  const reconnectDelays = [1000, 2000, 5000, 10000, 15000];
  let copyFeedbackTimer: ReturnType<typeof setTimeout> | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let presenceRefreshTimer: ReturnType<typeof setInterval> | null = null;
  let reconnectAttempt = 0;
  let isUnmounted = false;
  let pollTimer: ReturnType<typeof setInterval> | null = null;

  function generateRoomId(length = 6): string {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const bytes = new Uint8Array(length);
    crypto.getRandomValues(bytes);

    return Array.from(bytes, (byte) => chars[byte % chars.length]).join("");
  }

  function regenerateRoom() {
    closePresenceSocket();
    roomId.value = generateRoomId(6);
    joinUrl.value = `${window.location.origin}/join/${roomId.value}`;
    copied.value = false;
    connectedCount.value = null;
    reconnectAttempt = 0;
    connectPresence();
  }

  async function copyRoomCode() {
    if (!roomId.value) return;
    try {
      await navigator.clipboard.writeText(roomId.value);
      copied.value = true;
      if (copyFeedbackTimer) {
        clearTimeout(copyFeedbackTimer);
      }
      copyFeedbackTimer = setTimeout(() => {
        copied.value = false;
      }, 1600);
    } catch {
      copied.value = false;
    }
  }

  onMounted(() => {
    regenerateRoom();
    pollTimer = setInterval(() => {
      pollNow.value = Date.now();
    }, 250);
  });

  onBeforeUnmount(() => {
    isUnmounted = true;
    closePresenceSocket();
    if (pollTimer) clearInterval(pollTimer);
  });

  function connectPresence() {
    if (
      !roomId.value ||
      isUnmounted ||
      socket.value?.readyState === WebSocket.OPEN ||
      socket.value?.readyState === WebSocket.CONNECTING
    ) {
      return;
    }

    presenceState.value = "connecting";
    const url = `${realtimeUrl.replace(/^http/, "ws")}/rooms/${encodeURIComponent(roomId.value)}`;
    const connection = new WebSocket(url);
    socket.value = connection;

    connection.addEventListener("open", () => {
      if (socket.value !== connection) return;
      reconnectAttempt = 0;
      presenceState.value = "connected";
      sendJoinRoom(connection);
      startPresenceRefreshTimer(connection);
    });

    connection.addEventListener("message", (event) => {
      try {
        const message = JSON.parse(String(event.data)) as {
          type?: string;
          connected?: number;
          poll?: typeof poll.value;
        };
        if (
          message.type === "presence" &&
          typeof message.connected === "number"
        ) {
          connectedCount.value = message.connected;
        }
        if (message.type === "poll-state") poll.value = message.poll ?? null;
      } catch {
        // Ignore malformed messages from the server.
      }
    });

    connection.addEventListener("close", () => {
      if (socket.value !== connection) return;
      socket.value = null;
      connectedCount.value = null;
      presenceState.value = "disconnected";
      stopPresenceRefreshTimer();
      scheduleReconnect();
    });

    connection.addEventListener("error", () => {
      if (socket.value !== connection) return;
      connectedCount.value = null;
      presenceState.value = "error";
      stopPresenceRefreshTimer();
      scheduleReconnect();
    });
  }

  function sendJoinRoom(connection: WebSocket) {
    connection.send(
      JSON.stringify({
        type: "join-room",
        roomId: roomId.value,
        clientType: "host",
      }),
    );
  }

  function sendPresenceSync(connection: WebSocket) {
    if (connection.readyState !== WebSocket.OPEN) return;
    connection.send(
      JSON.stringify({
        type: "presence-sync",
      }),
    );
  }

  function startPoll() {
    pollError.value = "";
    const question = pollQuestion.value.trim();
    const options = pollOptions.value
      .split("\n")
      .map((label) => label.trim())
      .filter(Boolean)
      .map((label, index) => ({ id: `option-${index + 1}`, label }));
    if (!question || options.length < 2 || options.length > 12) {
      pollError.value = "Add a question and between 2 and 12 answers.";
      return;
    }
    socket.value?.send(
      JSON.stringify({
        type: "poll-start",
        pollId: crypto.randomUUID(),
        question,
        options,
        durationMs: Math.max(1, pollDurationSeconds.value) * 1000,
      }),
    );
  }

  function dismissPoll() {
    if (!poll.value) return;
    socket.value?.send(
      JSON.stringify({ type: "poll-dismiss", pollId: poll.value.id }),
    );
  }

  const canStartPoll = computed(
    () =>
      presenceState.value === "connected" && (connectedCount.value ?? 0) > 0,
  );

  const pollTimeLabel = computed(() => {
    if (!poll.value || poll.value.status !== "active") return "Poll complete";
    const remaining = Math.max(0, poll.value.endAt - pollNow.value);
    return `${Math.ceil(remaining / 1000)}s remaining`;
  });

  const pollTimeSeconds = computed(() => {
    if (!poll.value || poll.value.status !== "active") return 0;
    return Math.ceil(Math.max(0, poll.value.endAt - pollNow.value) / 1000);
  });

  const pollProgress = computed(() => {
    if (!poll.value) return 0;
    const duration = Math.max(1, poll.value.endAt - poll.value.startAt);
    return Math.max(
      0,
      Math.min(1, (poll.value.endAt - pollNow.value) / duration),
    );
  });

  function resizeQuestionInput(event: Event) {
    const textarea = event.target as HTMLTextAreaElement;
    textarea.style.height = "auto";
    textarea.style.height = `${textarea.scrollHeight}px`;
  }

  function startPresenceRefreshTimer(connection: WebSocket) {
    stopPresenceRefreshTimer();
    presenceRefreshTimer = setInterval(() => {
      if (socket.value !== connection) return;
      sendPresenceSync(connection);
    }, presenceRefreshIntervalMs);
  }

  function stopPresenceRefreshTimer() {
    if (!presenceRefreshTimer) return;
    clearInterval(presenceRefreshTimer);
    presenceRefreshTimer = null;
  }

  function scheduleReconnect() {
    if (isUnmounted || reconnectTimer || !roomId.value) return;

    const delay =
      reconnectDelays[Math.min(reconnectAttempt, reconnectDelays.length - 1)];
    reconnectAttempt += 1;
    presenceState.value = "connecting";
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectPresence();
    }, delay);
  }

  function closePresenceSocket() {
    stopPresenceRefreshTimer();
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    socket.value?.close();
    socket.value = null;
  }

  const qrUrl = computed(() => {
    if (!joinUrl.value) return "";
    return `https://api.qrserver.com/v1/create-qr-code/?size=360x360&data=${encodeURIComponent(joinUrl.value)}`;
  });

  const connectedCountLabel = computed(() => {
    if (presenceState.value !== "connected") {
      return "Room presence unavailable";
    }
    if (connectedCount.value == null) {
      return "Counting people in room...";
    }
    return `${connectedCount.value} ${connectedCount.value === 1 ? "person" : "people"} connected`;
  });
</script>

<template>
  <section>
    <h1>Your room <wbr />is live.</h1>
    <p>Anyone scanning this QR code can open the reaction deck instantly.</p>

    <div class="room-panels" :class="{ 'poll-hidden': !showPoll }">
      <div class="card" v-if="roomId && qrUrl">
        <img class="qrcode" :src="qrUrl" :alt="`QR code for room ${roomId}`" />
        <p class="label">Room code</p>
        <div class="code-row">
          <p class="code">{{ roomId }}</p>
          <div class="actions-stack">
            <button
              type="button"
              class="icon-button"
              @click="copyRoomCode"
              :aria-label="copied ? 'Room code copied' : 'Copy room code'"
              :title="copied ? 'Copied' : 'Copy room code'">
              <svg v-if="!copied" viewBox="0 0 24 24" aria-hidden="true">
                <rect
                  x="9"
                  y="9"
                  width="10"
                  height="10"
                  rx="2"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8" />
                <path
                  d="M7 15H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v1"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round" />
              </svg>
              <svg v-else viewBox="0 0 24 24" aria-hidden="true">
                <path
                  d="M20 7 9 18l-5-5"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round" />
              </svg>
            </button>
            <button
              type="button"
              class="icon-button"
              @click="regenerateRoom"
              aria-label="Regenerate room code"
              title="Regenerate room code">
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path
                  d="M20 12a8 8 0 0 1-13.66 5.66L4 15.32m0 0V19m0-3.68h3.68M4 12a8 8 0 0 1 13.66-5.66L20 8.68m0 0V5m0 3.68h-3.68"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round" />
              </svg>
            </button>
          </div>
        </div>
        <div class="flex flex-col gap-3">
          <div class="status-alert" :class="presenceState">
            <span class="dot" />
            <span class="status-count">{{ connectedCountLabel }}</span>
          </div>
          <NuxtLink :to="`/join/${roomId}`">Open deck on this device</NuxtLink>
          <button
            type="button"
            class="toggle-poll"
            @click="showPoll = !showPoll">
            {{ showPoll ? "Hide Poll" : "Toggle Poll" }}
          </button>
        </div>
      </div>

      <Transition name="poll-panel" appear>
        <div v-if="showPoll" class="poll-panel">
          <h2>
            {{
              poll
                ? poll.status === "active"
                  ? "Poll in progress"
                  : "Poll results"
                : "Start a poll"
            }}
          </h2>
          <template v-if="!poll">
            <label
              >Question
              <textarea
                class="question-input"
                v-model="pollQuestion"
                rows="1"
                placeholder="What should we do next?"
                @input="resizeQuestionInput" />
            </label>
            <label>Answers <textarea v-model="pollOptions" rows="4" /></label>
            <label
              >Duration (seconds)
              <input
                v-model.number="pollDurationSeconds"
                type="number"
                min="1"
                max="86400"
            /></label>
            <p v-if="pollError" class="poll-error">{{ pollError }}</p>
            <button type="button" @click="startPoll" :disabled="!canStartPoll">
              {{ canStartPoll ? "Start poll" : "Waiting for participants.." }}
            </button>
          </template>
          <template v-else>
            <p class="poll-question">{{ poll.question }}</p>
            <div
              class="poll-timer"
              :style="{ '--poll-progress': pollProgress }">
              <strong>{{ pollTimeSeconds }}</strong
              ><span>SECONDS</span>
            </div>
            <ul>
              <li v-for="option in poll.options" :key="option.id">
                {{ option.label }}: {{ poll.tally?.[option.id] ?? 0 }}
              </li>
            </ul>
            <button
              v-if="poll.status === 'complete'"
              type="button"
              @click="dismissPoll">
              Dismiss results
            </button>
          </template>
        </div>
      </Transition>
    </div>
  </section>
</template>

<style scoped>
  @reference "../assets/css/main.css";
  :global(body) {
    margin: 0;
    background: #171310;
    color: #fff4df;
    font-family: Inter, system-ui, sans-serif;
  }
  .room {
    min-height: 100vh;
    max-width: 680px;
    margin: auto;
    padding: 20px;
    box-sizing: border-box;
  }
  header {
    display: flex;
    justify-content: space-between;
    color: #8e8273;
    font-size: 12px;
    letter-spacing: 0.1em;
  }
  header strong {
    color: #f6b73c;
  }
  section {
    @apply w-full;
    text-align: center;
  }
  .eyebrow {
    color: #f6b73c;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    font-size: 12px;
    font-weight: 800;
  }
  .qrcode {
    width: min(280px, 100%);
    height: auto;
    @apply rounded-lg bg-white border-white border-20 mx-auto;
  }
  h1 {
    @apply text-3xl md:text-5xl;
    letter-spacing: -0.06em;
    margin: 16px 0 8px;
  }
  p:not(.eyebrow):not(.label):not(.code) {
    color: #b5a792;
    max-width: 560px;
    margin: 0 auto;
  }
  .card {
    margin: 0;
    width: min(420px, 100%);
    flex: 1 1 420px;
    background: #241e1a;
    border: 1px solid #3b3028;
    border-radius: 22px;
    padding: 20px;
  }
  img {
    width: 100%;
    max-width: 320px;
    border-radius: 14px;
    display: block;
    margin: 0 auto;
    background: #fff;
  }
  .label {
    margin: 18px 0 6px;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    color: #8e8273;
  }
  .code {
    margin: 0;
    min-width: 0;
    font-size: clamp(28px, 7vw, 56px);
    line-height: 1;
    font-weight: 900;
    letter-spacing: 0.08em;
    color: #f6b73c;
  }
  .code-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    margin: 10px auto;
  }
  .presence {
    margin-top: 12px;
    color: #8e8273;
    font-size: 13px;
  }
  .status-alert {
    margin: 0 auto;
    max-width: 320px;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    border: 1px solid #4a3b2f;
    border-radius: 999px;
    padding: 8px 12px;
    background: #171310;
    color: #72d572;
    font-size: 11px;
    font-weight: 800;
    flex: 0 0 auto;
  }
  .status-alert.connecting {
    color: #f6b73c;
  }
  .status-alert.disconnected,
  .status-alert.error {
    color: #e98470;
  }
  .status-alert.connected .dot {
    animation: connected-pulse 1.8s ease-in-out infinite;
  }
  .status-main,
  .status-count {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .status-count {
    color: #b5a792;
    font-weight: 600;
    text-transform: uppercase;
  }
  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }
  @keyframes connected-pulse {
    0%,
    100% {
      box-shadow: 0 0 0 0 rgb(114 213 114 / 45%);
    }
    50% {
      box-shadow: 0 0 0 5px rgb(114 213 114 / 0%);
    }
  }
  .actions-stack {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }
  .icon-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    border: 1px solid #3b3028;
    border-radius: 999px;
    background: #171310;
    color: #fff4df;
    cursor: pointer;
  }
  .room-panels:not(.poll-hidden) .icon-button {
    width: 36px;
    height: 36px;
  }
  .room-panels:not(.poll-hidden) .code-row {
    flex-direction: column;
    gap: 8px;
  }
  .room-panels:not(.poll-hidden) .actions-stack {
    flex-direction: row;
  }
  .room-panels:not(.poll-hidden) .icon-button svg {
    width: 17px;
    height: 17px;
  }
  .icon-button:hover {
    border-color: #f6b73c;
  }
  .icon-button:focus-visible {
    outline: 2px solid #f6b73c;
    outline-offset: 2px;
  }
  .icon-button svg {
    width: 20px;
    height: 20px;
  }
  a {
    display: inline-block;
    color: #f6b73c;
    text-decoration: none;
    font-weight: 700;
  }
  a:hover {
    text-decoration: underline;
  }
  .toggle-poll {
    display: block;
    margin: 0 auto;
    border: 0;
    background: transparent;
    color: #b5a792;
    cursor: pointer;
    font: inherit;
    font-size: 13px;
    font-weight: 700;
  }
  .toggle-poll:hover {
    color: #f6b73c;
  }
  .poll-panel {
    width: min(560px, 100%);
    margin: 0;
    flex: 1 1 560px;
    padding: 24px;
    box-sizing: border-box;
    text-align: left;
    background: linear-gradient(145deg, #2a231e, #211b18);
    border: 1px solid #4a3b2f;
    border-radius: 22px;
    box-shadow: 0 18px 45px rgb(0 0 0 / 18%);
  }
  .room-panels {
    display: flex;
    align-items: stretch;
    justify-content: center;
    gap: 24px;
    width: calc(100%);
    margin: 10px auto 0;
  }
  .room-panels > .card,
  .room-panels > .poll-panel {
    width: 0;
    min-width: 0;
    box-sizing: border-box;
    flex: 1 1 0;
  }
  .room-panels.poll-hidden .card {
    flex: 0 1 520px;
  }
  .room-panels.poll-hidden .qrcode {
    width: min(380px, 100%);
  }

  .poll-panel h2 {
    margin: 0 0 20px;
    color: #fff4df;
    font-size: 22px;
    letter-spacing: -0.03em;
  }
  .poll-timer {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    width: 76px;
    height: 76px;
    margin: -8px 0 18px;
    border-radius: 50%;
    background: conic-gradient(
      #f6b73c calc(var(--poll-progress) * 1turn),
      #4a3b2f 0
    );
    color: #fff4df !important;
    position: relative;
  }
  .poll-timer::before {
    content: "";
    position: absolute;
    inset: 5px;
    border-radius: 50%;
    background: #211b18;
  }
  .poll-timer strong,
  .poll-timer span {
    position: relative;
    z-index: 1;
  }
  .poll-timer strong {
    font-size: 22px;
    line-height: 1;
  }
  .poll-timer span {
    margin-top: 3px;
    color: #b5a792;
    font-size: 7px;
    font-weight: 800;
    letter-spacing: 0.1em;
  }
  .poll-question {
    margin: -4px 0 14px !important;
    color: #fff4df !important;
    font-size: 20px;
    font-weight: 800;
  }
  .poll-panel label {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 16px;
    color: #b5a792;
    font-size: 12px;
    font-weight: 800;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .poll-panel input,
  .poll-panel textarea {
    width: 100%;
    box-sizing: border-box;
    border: 1px solid #4a3b2f;
    border-radius: 12px;
    padding: 12px 14px;
    background: #171310;
    color: #fff4df;
    font: inherit;
    font-size: 15px;
    font-weight: 400;
    letter-spacing: normal;
    text-transform: none;
    resize: vertical;
  }
  .poll-panel .question-input {
    min-height: 46px;
    overflow-y: hidden;
    resize: none;
  }
  .poll-panel input::placeholder,
  .poll-panel textarea::placeholder {
    color: #75695d;
  }
  .poll-panel input:focus,
  .poll-panel textarea:focus {
    border-color: #f6b73c;
    outline: 2px solid rgb(246 183 60 / 18%);
    outline-offset: 1px;
  }
  .poll-panel input[type="number"] {
    max-width: 180px;
  }
  .poll-panel > button,
  .poll-panel button {
    width: 100%;
    margin-top: 22px;
    border: 1px solid #f6b73c;
    border-radius: 12px;
    padding: 13px 18px;
    background: #f6b73c;
    color: #241e1a;
    cursor: pointer;
    font: inherit;
    font-weight: 900;
  }
  .poll-panel button:hover:not(:disabled) {
    background: #ffd16b;
  }
  .poll-panel button:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }
  .poll-error {
    margin-top: 14px !important;
    color: #e98470 !important;
    font-size: 13px;
  }
  .poll-panel ul {
    display: grid;
    gap: 10px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .poll-panel li {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    padding: 12px 14px;
    border: 1px solid #3b3028;
    border-radius: 10px;
    background: #171310;
    color: #fff4df;
  }
  @media (max-width: 520px) {
    .room-panels {
      flex-direction: column;
      align-items: center;
      gap: 20px;
    }
    .room-panels > .card,
    .room-panels > .poll-panel {
      width: 100%;
      flex: none;
    }
    .room-panels.poll-hidden .card {
      flex-basis: auto;
    }
    .poll-panel {
      width: calc(100% - 20px);
      padding: 18px;
    }
  }
</style>
