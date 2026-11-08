<script setup lang="ts">
  import FingerprintJS from "@fingerprintjs/fingerprintjs";
  import emojiRegex from "emoji-regex";

  useSeoMeta({
    title: "Join Room",
    description:
      "Join a Peanut Gallery room and send live reactions with one tap.",
  });

  const route = useRoute();
  const reactions = [
    { emoji: "🔥", label: "fire" },
    { emoji: "👏", label: "applause" },
    { emoji: "😂", label: "laughter" },
    { emoji: "❤️", label: "love" },
    { emoji: "👀", label: "eyes" },
    { emoji: "💀", label: "skull" },
    { emoji: "🎉", label: "celebration" },
  ];
  const showEmojiEditor = ref(false);
  const emojiDraft = ref("");
  const emojiError = ref("");
  const emojiInput = ref<HTMLInputElement | null>(null);
  const customButton = ref<HTMLButtonElement | null>(null);
  const voteMessage = ref("");
  const customEmojiStorageKey = "peanut-gallery:custom-emoji";
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
    const localDeviceId =
      localStorage.getItem(deviceKey) ?? crypto.randomUUID();
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
      if (socket.value !== connection) return;
      try {
        const message = JSON.parse(String(event.data)) as {
          type?: string;
          emoji?: string;
          connected?: number;
          poll?: typeof poll.value;
        };
        if (
          message.type === "presence" &&
          typeof message.connected === "number"
        ) {
          connectedCount.value = message.connected;
        }
        if (message.type === "poll-state") {
          const nextPoll = message.poll ?? null;
          const modeChanged = nextPoll?.id !== poll.value?.id;
          if (modeChanged) {
            selectedOptionId.value = null;
            voteMessage.value = "";
          }
          poll.value = nextPoll;
          if (modeChanged) {
            const hadControlFocus = document.activeElement?.closest(
              ".reaction-deck, .voting-deck",
            );
            showEmojiEditor.value = false;
            if (hadControlFocus)
              nextTick(() => document.getElementById("deck-heading")?.focus());
          }
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
    if (
      !poll.value ||
      poll.value.status !== "active" ||
      !deviceFingerprint.value ||
      socket.value?.readyState !== WebSocket.OPEN ||
      pollTimeSeconds.value <= 0
    )
      return;
    socket.value.send(
      JSON.stringify({
        type: "poll-vote",
        pollId: poll.value.id,
        optionId,
        fingerprint: deviceFingerprint.value,
      }),
    );
    selectedOptionId.value = optionId;
    voteMessage.value =
      "Vote sent. You can change your choice while voting is open.";
  }

  async function openEmojiEditor() {
    emojiDraft.value = customEmoji.value;
    emojiError.value = "";
    showEmojiEditor.value = true;
    await nextTick();
    emojiInput.value?.focus();
  }

  function useCustomReaction() {
    if (customEmoji.value) react(customEmoji.value);
    else void openEmojiEditor();
  }

  async function closeEmojiEditor() {
    showEmojiEditor.value = false;
    await nextTick();
    customButton.value?.focus();
  }

  function saveCustomEmoji() {
    const emoji = emojiDraft.value.trim();
    if (!isSingleEmoji(emoji)) {
      emojiError.value = "Choose a single emoji, like 🥳 or ❤️.";
      emojiInput.value?.focus();
      return;
    }
    customEmoji.value = emoji;
    localStorage.setItem(customEmojiStorageKey, emoji);
    void closeEmojiEditor();
  }

  function resetCustomReaction() {
    customEmoji.value = "";
    emojiDraft.value = "";
    localStorage.removeItem(customEmojiStorageKey);
    void closeEmojiEditor();
  }

  function isSingleEmoji(value: string) {
    emojiPattern.lastIndex = 0;
    const match = value.match(emojiPattern);
    return match?.[0] === value;
  }

  const connectedCountLabel = computed(() => {
    if (connectionState.value !== "connected") {
      return connectionState.value === "connecting"
        ? reconnectAttempt
          ? "Reconnecting…"
          : "Connecting…"
        : "Unable to connect. Retrying…";
    }
    if (connectedCount.value == null) {
      return "Connected · counting participants…";
    }
    return `${connectedCount.value} ${connectedCount.value === 1 ? "person" : "people"} in room`;
  });

  const pollTimeLabel = computed(() => {
    if (!poll.value || poll.value.status !== "active") return "Voting closed";
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
    return Math.max(
      0,
      Math.min(1, (poll.value.endAt - pollNow.value) / duration),
    );
  });
</script>

<template>
  <section class="audience-page">
    <div class="room-bar">
      <span class="room-label"
        >Room <strong>{{ roomId }}</strong></span
      ><span class="status" :class="connectionState" role="status">{{
        connectedCountLabel
      }}</span>
    </div>
    <header class="deck-intro">
      <p class="eyebrow">
        {{ poll ? "Your voice counts" : "You’re in the peanut gallery" }}
      </p>
      <h1 id="deck-heading" class="page-heading" tabindex="-1">
        {{
          poll
            ? poll.status === "active" && pollTimeSeconds > 0
              ? "Cast your vote."
              : "Voting closed."
            : "Make some noise!"
        }}
      </h1>
      <p v-if="!poll">Tap a reaction. Spam responsibly.</p>
    </header>
    <div class="deck-stage">
      <Transition
        name="panel"
        @before-leave="(element) => element.setAttribute('inert', '')"
      >
        <div v-if="poll" :key="poll.id" class="voting-deck">
          <p class="poll-question">{{ poll.question }}</p>
          <div class="poll-meta">
            <span>{{ pollTimeLabel }}</span
            ><span v-if="nickname"
              >You are <strong>{{ nickname }}</strong></span
            >
          </div>
          <div
            v-if="poll.status === 'active' && pollTimeSeconds > 0"
            class="time-track"
            aria-hidden="true"
          >
            <span :style="{ transform: `scaleX(${pollProgress})` }" />
          </div>
          <div class="poll-options" role="group" aria-label="Poll answers">
            <button
              v-for="(option, index) in poll.options"
              :key="option.id"
              class="vote-option"
              :disabled="
                connectionState !== 'connected' ||
                poll.status !== 'active' ||
                pollTimeSeconds <= 0
              "
              :aria-pressed="selectedOptionId === option.id"
              @click="vote(option.id)"
            >
              <span class="option-number" aria-hidden="true">{{
                index + 1
              }}</span
              ><span class="option-label">{{ option.label }}</span
              ><span
                v-if="selectedOptionId === option.id"
                class="selected-mark"
                aria-hidden="true"
                >✓</span
              >
            </button>
          </div>
          <p class="vote-feedback" role="status">
            {{
              poll.status === "complete" || pollTimeSeconds <= 0
                ? "Thanks for taking part. Your host will share what’s next."
                : voteMessage ||
                  "Choose an answer. You can change it until voting closes."
            }}
          </p>
        </div>
        <div v-else key="reactions" class="reaction-deck">
          <div class="reaction-grid" role="group" aria-label="Send a reaction">
            <button
              v-for="reaction in reactions"
              :key="reaction.emoji"
              class="reaction-tile"
              :disabled="connectionState !== 'connected'"
              :aria-label="`Send ${reaction.label}`"
              @click="react(reaction.emoji)"
            >
              <span aria-hidden="true">{{ reaction.emoji }}</span>
            </button>
            <button
              ref="customButton"
              class="reaction-tile custom-tile"
              :class="{ empty: !customEmoji }"
              :disabled="connectionState !== 'connected'"
              :aria-label="
                customEmoji ? `Send ${customEmoji}` : 'Choose a custom emoji'
              "
              :aria-expanded="showEmojiEditor"
              aria-controls="emoji-editor"
              @click="useCustomReaction"
            >
              <span aria-hidden="true">{{ customEmoji || "+" }}</span
              ><small v-if="!customEmoji" aria-hidden="true">Custom</small>
            </button>
          </div>
          <div class="deck-bottom">
            <span>Live on your host’s screen.</span
            ><button
              v-if="customEmoji && !showEmojiEditor"
              type="button"
              @click="openEmojiEditor"
            >
              Edit custom emoji
            </button>
          </div>
          <Transition name="panel">
            <form
              v-if="showEmojiEditor"
              id="emoji-editor"
              class="emoji-editor"
              @submit.prevent="saveCustomEmoji"
              @keydown.esc.stop.prevent="closeEmojiEditor"
            >
              <label class="field" for="custom-emoji"
                >Make it your own<span class="editor-hint"
                  >Paste one emoji from your keyboard.</span
                ></label
              >
              <input
                id="custom-emoji"
                ref="emojiInput"
                v-model="emojiDraft"
                placeholder="🥳"
                autocomplete="off"
                :aria-invalid="!!emojiError"
                :aria-describedby="emojiError ? 'emoji-error' : undefined"
              />
              <p v-if="emojiError" id="emoji-error" class="error" role="alert">
                {{ emojiError }}
              </p>
              <div class="editor-actions">
                <button class="button" type="submit">Save emoji</button
                ><button
                  class="button secondary"
                  type="button"
                  @click="closeEmojiEditor"
                >
                  Cancel</button
                ><button
                  v-if="customEmoji"
                  class="button quiet"
                  type="button"
                  @click="resetCustomReaction"
                >
                  Reset
                </button>
              </div>
            </form>
          </Transition>
        </div>
      </Transition>
    </div>
    <p v-if="connectionState !== 'connected'" class="connection-note">
      Reactions and voting will be available when you’re connected.
    </p>
  </section>
</template>

<style scoped>
  .audience-page {
    width: min(100%, 520px);
    margin-inline: auto;
  }
  .room-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 12px;
    border-bottom: 1px solid var(--border);
    padding-bottom: 20px;
    margin-bottom: 36px;
  }
  .room-label {
    color: var(--muted);
    font-size: 12px;
  }
  .room-label strong {
    font-family: ui-monospace, monospace;
    color: var(--text);
    letter-spacing: 0.06em;
    margin-left: 6px;
  }
  .room-bar .status {
    font-size: 12px;
  }
  .deck-intro {
    text-align: center;
  }
  .deck-intro .eyebrow {
    font-size: 10px;
  }
  .page-heading {
    margin-top: 12px;
    font-size: clamp(27px, 6vw, 38px);
  }
  .deck-intro > p:last-child:not(.eyebrow) {
    color: var(--muted);
    font-size: 15px;
    margin-top: 12px;
  }
  .reaction-deck {
    margin-top: 32px;
  }
  .reaction-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }
  .reaction-tile {
    width: 100%;
    aspect-ratio: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 20px;
    background: var(--surface);
    box-shadow: 0 5px 0 #0d0a08;
    font-size: clamp(28px, 8vw, 48px);
    line-height: 1;
    user-select: none;
    transition: transform 120ms var(--ease-out);
  }
  .reaction-tile:active:not(:disabled) {
    transform: translateY(3px) scale(0.98);
  }
  .custom-tile.empty {
    background: transparent;
    border-style: dashed;
    color: var(--muted);
    box-shadow: none;
    gap: 6px;
  }
  .custom-tile small {
    font-size: 10px;
    font-weight: 600;
  }
  .deck-bottom {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    color: var(--muted);
    font-size: 11px;
    min-height: 44px;
    margin-top: 16px;
  }
  .deck-bottom button {
    min-height: 44px;
    color: var(--accent);
    border: 0;
    background: transparent;
    font-size: 11px;
    padding: 0 4px;
    border-radius: 6px;
  }
  .emoji-editor {
    margin-top: 16px;
    padding: 24px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 18px;
    display: grid;
    gap: 16px;
  }
  .emoji-editor .field {
    color: var(--text);
    font-size: 15px;
  }
  .editor-hint {
    color: var(--muted);
    font-size: 12px;
    font-weight: 400;
  }
  .emoji-editor input {
    font-size: 28px;
    text-align: center;
  }
  .editor-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .editor-actions .button {
    font-size: 13px;
  }
  .connection-note {
    color: var(--muted);
    font-size: 12px;
    text-align: center;
    margin-top: 24px;
  }
  .voting-deck {
    margin-top: 28px;
  }
  .poll-question {
    text-align: center;
    font-size: 23px;
    font-weight: 700;
    color: var(--text);
    overflow-wrap: anywhere;
    text-wrap: pretty;
  }
  .poll-meta {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 12px;
    color: var(--muted);
    font-size: 11px;
    margin-top: 24px;
    font-variant-numeric: tabular-nums;
  }
  .poll-meta strong {
    color: var(--text);
  }
  .time-track {
    margin-top: 12px;
    height: 4px;
    border-radius: 8px;
    overflow: hidden;
    background: var(--border);
  }
  .time-track span {
    display: block;
    width: 100%;
    height: 100%;
    background: var(--accent);
    transform-origin: left;
  }
  .poll-options {
    display: grid;
    gap: 12px;
    margin-top: 24px;
  }
  .vote-option {
    display: flex;
    align-items: center;
    gap: 14px;
    text-align: left;
    width: 100%;
    min-height: 64px;
    padding: 14px 18px;
    background: var(--surface);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 14px;
  }
  .vote-option[aria-pressed="true"] {
    border-color: var(--accent);
    background: #3b2d1a;
  }
  .option-number {
    flex: none;
    color: var(--muted);
    font-size: 12px;
  }
  .option-label {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
    font-size: 16px;
    line-height: 1.4;
  }
  .selected-mark {
    color: var(--accent);
  }
  .vote-option:disabled[aria-pressed="true"] {
    opacity: 1;
  }
  .vote-feedback {
    color: var(--muted);
    text-align: center;
    font-size: 12px;
    margin-top: 20px;
  }
  @media (hover: hover) and (pointer: fine) {
    .reaction-tile:hover:not(:disabled),
    .vote-option:hover:not(:disabled) {
      background: var(--surface-raised);
      border-color: var(--accent);
    }
  }
  @media (max-width: 360px) {
    .reaction-grid {
      gap: 8px;
    }
    .reaction-tile {
      border-radius: 14px;
    }
    .room-bar {
      margin-bottom: 28px;
    }
  }
  :global(html[data-input="keyboard"]) .reaction-tile:active:not(:disabled) {
    transform: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .reaction-tile:active:not(:disabled) {
      transform: none;
    }
  }
</style>
