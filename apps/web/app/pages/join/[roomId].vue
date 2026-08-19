<script setup lang="ts">
  import FingerprintJS from "@fingerprintjs/fingerprintjs";
  import emojiRegex from "emoji-regex";

  useSeoMeta({
    title: "Join Room",
    description:
      "Join a Peanut Gallery room and send live reactions with one tap.",
  });

  const route = useRoute();
  const reactions = ["🔥", "👏", "😂", "❤️", "👀", "💀", "🎉"];
  const customEmojiStorageKey = "peanut-gallery:custom-emoji";
  const sent = ref<string[]>([]);
  const customEmoji = ref("");
  const emojiPattern = emojiRegex();
  const connectionState = ref<
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
  } | null>(null);
  const selectedOptionId = ref<string | null>(null);
  const deviceFingerprint = ref("");
  const pollNow = ref(Date.now());
  const nickname = ref("");
  const adjectives = [
    "Brave",
    "Clever",
    "Cosmic",
    "Dazzling",
    "Fierce",
    "Golden",
    "Jolly",
    "Lucky",
    "Mighty",
    "Nimble",
    "Quiet",
    "Swift",
  ];
  const animalsAndColors = [
    "Badger",
    "Bear",
    "Blue",
    "Cardinal",
    "Coral",
    "Crimson",
    "Dolphin",
    "Fox",
    "Green",
    "Jaguar",
    "Koala",
    "Lynx",
    "Otter",
    "Panther",
    "Purple",
    "Raven",
    "Red",
    "Tiger",
    "Wolf",
    "Yellow",
  ];

  const roomId = computed(() => String(route.params.roomId ?? ""));
  const config = useRuntimeConfig();
  const realtimeUrl = config.public.realtimeUrl || "ws://localhost:8787";
  const presenceRefreshIntervalMs = 15000;
  const reconnectDelays = [1000, 2000, 5000, 10000, 15000];
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let presenceRefreshTimer: ReturnType<typeof setInterval> | null = null;
  let reconnectAttempt = 0;
  let isUnmounted = false;
  let pollTimer: ReturnType<typeof setInterval> | null = null;

  onMounted(() => {
    const storedEmoji = localStorage.getItem(customEmojiStorageKey) ?? "";
    customEmoji.value = isSingleEmoji(storedEmoji) ? storedEmoji : "";
    if (storedEmoji && !customEmoji.value) {
      localStorage.removeItem(customEmojiStorageKey);
    }

    const deviceKey = "peanut-gallery:device-id";
    const localDeviceId = localStorage.getItem(deviceKey) ?? crypto.randomUUID();
    localStorage.setItem(deviceKey, localDeviceId);
    deviceFingerprint.value = localDeviceId;
    nickname.value = nicknameFromFingerprint(localDeviceId);

    if (!roomId.value) {
      connectionState.value = "error";
      return;
    }

    pollTimer = setInterval(() => {
      pollNow.value = Date.now();
    }, 250);
    void loadFingerprint().finally(connect);
  });

  async function loadFingerprint() {
    try {
      const agent = await FingerprintJS.load();
      deviceFingerprint.value = (await agent.get()).visitorId;
      nickname.value = nicknameFromFingerprint(deviceFingerprint.value);
    } catch {
      // A local fallback preserves voting if fingerprint collection fails.
      // Keep using the local identity initialized before connecting.
    }
  }

  function nicknameFromFingerprint(fingerprint: string) {
    let hash = 2166136261;
    for (const character of fingerprint) {
      hash ^= character.charCodeAt(0);
      hash = Math.imul(hash, 16777619);
    }
    const unsignedHash = hash >>> 0;
    return `${adjectives[unsignedHash % adjectives.length]}${animalsAndColors[Math.floor(unsignedHash / adjectives.length) % animalsAndColors.length]}`;
  }

  onBeforeUnmount(() => {
    isUnmounted = true;
    stopPresenceRefreshTimer();
    if (reconnectTimer) clearTimeout(reconnectTimer);
    socket.value?.close();
    socket.value = null;
    if (pollTimer) clearInterval(pollTimer);
  });

  function connect() {
    if (
      isUnmounted ||
      socket.value?.readyState === WebSocket.OPEN ||
      socket.value?.readyState === WebSocket.CONNECTING
    ) {
      return;
    }

    connectionState.value = "connecting";
    const url = `${realtimeUrl.replace(/^http/, "ws")}/rooms/${encodeURIComponent(roomId.value)}`;
    const connection = new WebSocket(url);
    socket.value = connection;

    connection.addEventListener("open", () => {
      if (socket.value !== connection) return;
      reconnectAttempt = 0;
      connectionState.value = "connected";
      sendJoinRoom(connection);
      startPresenceRefreshTimer(connection);
    });

    connection.addEventListener("message", (event) => {
      try {
        const message = JSON.parse(String(event.data)) as {
          type?: string;
          emoji?: string;
          connected?: number;
          poll?: typeof poll.value;
        };
        if (message.type === "reaction" && typeof message.emoji === "string") {
          sent.value.unshift(message.emoji);
          if (sent.value.length > 8) sent.value.pop();
        }
        if (
          message.type === "presence" &&
          typeof message.connected === "number"
        ) {
          connectedCount.value = message.connected;
        }
        if (message.type === "poll-state") {
          poll.value = message.poll ?? null;
          if (!poll.value) selectedOptionId.value = null;
        }
      } catch {
        // Ignore malformed messages from the server.
      }
    });

    connection.addEventListener("close", () => {
      if (socket.value !== connection) return;
      socket.value = null;
      connectionState.value = "disconnected";
      connectedCount.value = null;
      stopPresenceRefreshTimer();
      scheduleReconnect();
    });

    connection.addEventListener("error", () => {
      if (socket.value !== connection) return;
      connectionState.value = "error";
      connectedCount.value = null;
      stopPresenceRefreshTimer();
      scheduleReconnect();
    });
  }

  function sendJoinRoom(connection: WebSocket) {
    connection.send(
      JSON.stringify({
        type: "join-room",
        roomId: roomId.value,
        clientType: "web",
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
    if (isUnmounted || reconnectTimer) return;

    const delay =
      reconnectDelays[Math.min(reconnectAttempt, reconnectDelays.length - 1)];
    reconnectAttempt += 1;
    connectionState.value = "connecting";
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connect();
    }, delay);
  }

  function react(emoji: string) {
    if (poll.value || socket.value?.readyState !== WebSocket.OPEN) return;

    socket.value.send(
      JSON.stringify({
        type: "reaction",
        reactionId: crypto.randomUUID(),
        emoji,
        sentAt: Date.now(),
      }),
    );
  }

  function vote(optionId: string) {
    if (!poll.value || poll.value.status !== "active" || !deviceFingerprint.value) return;
    selectedOptionId.value = optionId;
    socket.value?.send(JSON.stringify({
      type: "poll-vote",
      pollId: poll.value.id,
      optionId,
      fingerprint: deviceFingerprint.value,
    }));
  }

  function useCustomReaction() {
    if (customEmoji.value) {
      react(customEmoji.value);
      return;
    }

    const emoji = window.prompt("Enter a custom emoji")?.trim() ?? "";
    if (isSingleEmoji(emoji)) {
      customEmoji.value = emoji;
      localStorage.setItem(customEmojiStorageKey, emoji);
      return;
    }

    if (emoji) {
      window.alert("Only a single emoji is allowed.");
    }
  }

  function resetCustomReaction() {
    customEmoji.value = "";
    localStorage.removeItem(customEmojiStorageKey);
  }

  function isSingleEmoji(value: string) {
    emojiPattern.lastIndex = 0;
    const match = value.match(emojiPattern);
    return match?.[0] === value;
  }

  const connectedCountLabel = computed(() => {
    if (connectionState.value !== "connected") {
      return "Room presence unavailable";
    }
    if (connectedCount.value == null) {
      return "Counting people in room...";
    }
    return `${connectedCount.value} ${connectedCount.value === 1 ? "person" : "people"} in room`;
  });

  const pollTimeLabel = computed(() => {
    if (!poll.value || poll.value.status !== "active") return "Poll complete";
    const remaining = Math.max(0, poll.value.endAt - pollNow.value);
    const seconds = Math.ceil(remaining / 1000);
    return `${seconds}s remaining`;
  });

  const pollTimeSeconds = computed(() => {
    if (!poll.value || poll.value.status !== "active") return 0;
    return Math.ceil(Math.max(0, poll.value.endAt - pollNow.value) / 1000);
  });

  const pollProgress = computed(() => {
    if (!poll.value) return 0;
    const duration = Math.max(1, poll.value.endAt - poll.value.startAt);
    return Math.max(0, Math.min(1, (poll.value.endAt - pollNow.value) / duration));
  });
</script>

<template>
  <section>
    <div class="alerts-row">
      <div v-if="poll && nickname" class="nickname-alert">You are <strong>{{ nickname }}</strong></div>
      <div class="status-alert" :class="connectionState">
        <span class="dot" />
        <span class="status-count">{{ connectedCountLabel }}</span>
      </div>
    </div>
    <h1>{{ poll ? "Cast your vote" : "Make some noise!" }}</h1>
    <p v-if="poll" class="poll-question">{{ poll.question }}</p>
    <p v-else class="subtitle">Tap a reaction. Spam responsibly.</p>
    <div v-if="poll" class="poll-timer" :style="{ '--poll-progress': pollProgress }">
      <strong>{{ pollTimeSeconds }}</strong><span>SECONDS</span>
    </div>
    <div v-if="poll" class="grid poll-options">
      <button
        v-for="option in poll.options"
        :key="option.id"
        :disabled="connectionState !== 'connected' || poll.status !== 'active'"
        :class="{ selected: selectedOptionId === option.id }"
        @click="vote(option.id)">
        {{ option.label }}
      </button>
    </div>
    <div v-else class="grid">
      <button
        v-for="emoji in reactions"
        :key="emoji"
        :disabled="connectionState !== 'connected'"
        @click="react(emoji)">
        {{ emoji }}
      </button>
      <div class="custom-reaction-slot">
        <button
          class="custom-reaction"
          :class="{ empty: !customEmoji }"
          :disabled="connectionState !== 'connected'"
          :aria-label="
            customEmoji ? `React with ${customEmoji}` : 'Choose a custom emoji'
          "
          @click="useCustomReaction">
          {{ customEmoji }}
        </button>
        <button
          v-if="customEmoji"
          class="reset-custom-reaction"
          type="button"
          aria-label="Reset custom emoji"
          title="Reset custom emoji"
          @click="resetCustomReaction">
          ×
        </button>
      </div>
    </div>
    <div class="recent">
      <span v-for="(emoji, index) in sent" :key="`${emoji}-${index}`">{{
        emoji
      }}</span>
    </div>
  </section>
</template>

<style scoped>
  @reference "../../assets/css/main.css";
  .eyebrow {
    color: #f6b73c;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    font-size: 12px;
    font-weight: 800;
  }
  h1 {
    @apply text-3xl md:text-5xl;
    letter-spacing: -0.06em;
    margin: 16px 0 8px;
  }
  p:not(.eyebrow) {
    color: #b5a792;
  }
  .connection {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    margin-top: 24px;
  }
  .connection.connected {
    color: #72d572;
  }
  .connection.connecting {
    color: #f6b73c;
  }
  .connection.disconnected,
  .connection.error {
    color: #e98470;
  }
  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: currentColor;
  }
  .presence {
    margin-top: 10px;
    font-size: 13px;
    color: #8e8273;
  }
  .nickname {
    margin-top: 18px;
    color: #f6b73c !important;
    font-size: 14px;
  }
  .nickname strong {
    color: #fff4df;
  }
  .poll-timer {
    margin-top: 12px;
    color: #f6b73c !important;
    font-size: 14px;
    font-weight: 800;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
    margin-top: 32px;
    justify-items: center;
    justify-content: center;
  }
  button {
    transition: all 0.1s ease-in-out;
    aspect-ratio: 1;
    border: 1px solid #3b3028;
    border-bottom-width: 6px;
    border-radius: 18px;
    background: #241e1a;
    font-size: 42px;
    cursor: pointer;
    @apply max-w-17.5 max-h-17.5 md:max-w-20 md:max-h-20;
    transition:
      transform 0.1s,
      background 0.1s;
    -webkit-user-select: none;
    user-select: none;
  }
  button:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }
  .custom-reaction.empty:not(:disabled) {
    border-width: 1px;
    opacity: 0.45;
  }
  .custom-reaction-slot {
    position: relative;
    aspect-ratio: 1;
    @apply max-w-17.5 max-h-17.5 md:max-w-20 md:max-h-20;
  }
  .custom-reaction {
    width: 100%;
    height: 100%;
  }
  .reset-custom-reaction {
    position: absolute;
    z-index: 1;
    top: -9px;
    right: -9px;
    width: 24px;
    height: 24px;
    aspect-ratio: auto;
    border: 2px solid #241e1a;
    border-radius: 50%;
    background: #dc3f3f;
    color: #ffffff;
    font-size: 18px;
    font-weight: 700;
    line-height: 1;
  }
  button:active {
    transform: scale(0.98) translateY(2px);
    border-bottom-width: 1px;
  }
  .poll-options button {
    aspect-ratio: auto;
    width: 100%;
    max-width: 280px;
    min-height: 72px;
    padding: 16px;
    font-size: 20px;
  }
  .poll-options {
    grid-template-columns: repeat(auto-fit, minmax(180px, 280px));
  }
  .poll-options button.selected {
    border-color: #f6b73c;
    background: #49351d;
  }
  .recent {
    display: none;
    gap: 10px;
    margin-top: 32px;
    min-height: 36px;
    font-size: 24px;
  }
  .subtitle {
    color: #b5a792;
  }
  .nickname-alert,
  .status-alert {
    display: flex;
    width: fit-content;
    align-items: center;
    justify-content: center;
    gap: 10px;
    border: 1px solid #4a3b2f;
    border-radius: 999px;
    padding: 9px 16px;
    background: #241e1a;
    color: #f6b73c;
    font-size: 13px;
    font-weight: 800;
  }
  .alerts-row {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-wrap: wrap;
    gap: 12px;
    margin: 8px auto 18px;
  }
  .nickname-alert {
    margin: 0;
  }
  .nickname-alert strong {
    color: #fff4df;
  }
  .poll-question {
    margin: 12px auto 10px;
    text-align: center;
    color: #fff4df !important;
    font-size: clamp(22px, 5vw, 32px);
    font-weight: 800;
    letter-spacing: -0.03em;
  }
  .poll-timer {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    width: 86px;
    height: 86px;
    margin: 14px auto 18px;
    border-radius: 50%;
    background: conic-gradient(#f6b73c calc(var(--poll-progress) * 1turn), #4a3b2f 0);
    color: #fff4df;
    position: relative;
  }
  .poll-timer::before {
    content: "";
    position: absolute;
    inset: 6px;
    border-radius: 50%;
    background: #171310;
  }
  .poll-timer strong,
  .poll-timer span {
    position: relative;
    z-index: 1;
  }
  .poll-timer strong {
    font-size: 24px;
    line-height: 1;
  }
  .poll-timer span {
    margin-top: 4px;
    color: #b5a792;
    font-size: 8px;
    font-weight: 800;
    letter-spacing: 0.1em;
  }
  .status-alert {
    margin: 0;
    color: #72d572;
  }
  .status-alert.connecting { color: #f6b73c; }
  .status-alert.disconnected,
  .status-alert.error { color: #e98470; }
  .status-alert.connected .dot {
    animation: connected-pulse 1.8s ease-in-out infinite;
  }
  .status-main,
  .status-count {
    display: inline-flex;
    align-items: center;
    gap: 7px;
  }
  .status-count {
    color: #b5a792;
    font-weight: 600;
    text-transform: uppercase;
  }
  @media (max-width: 520px) {
    .alerts-row {
      gap: 8px;
    }
  }
  @keyframes connected-pulse {
    0%,
    100% { box-shadow: 0 0 0 0 rgb(114 213 114 / 45%); }
    50% { box-shadow: 0 0 0 5px rgb(114 213 114 / 0%); }
  }
</style>
