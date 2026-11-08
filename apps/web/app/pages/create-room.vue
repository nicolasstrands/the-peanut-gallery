<script setup lang="ts">
  useSeoMeta({
    title: "Create Room",
    description:
      "Generate a room code and QR link so your audience can instantly join and send reactions.",
  });

  const roomId = ref("");
  const joinUrl = ref("");
  const copied = ref<"code" | "link" | null>(null);
  const copyError = ref("");
  const qrFailed = ref(false);
  const qrLoaded = ref(false);
  const confirmNewRoom = ref(false);
  const newRoomButton = ref<HTMLButtonElement | null>(null);
  const keepRoomButton = ref<HTMLButtonElement | null>(null);
  const pollToggle = ref<HTMLButtonElement | null>(null);
  const questionInput = ref<HTMLTextAreaElement | null>(null);
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
  const pollOptions = ref([
    { id: crypto.randomUUID(), label: "Yes" },
    { id: crypto.randomUUID(), label: "No" },
  ]);
  const pollDurationSeconds = ref(30);
  const pollError = ref("");
  const showPoll = ref(false);
  const pollPanelRef = ref<HTMLElement | null>(null);
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
    poll.value = null;
    qrFailed.value = false;
    qrLoaded.value = false;
    copyError.value = "";
    roomId.value = generateRoomId(6);
    joinUrl.value = `${window.location.origin}/join/${roomId.value}`;
    copied.value = null;
    connectedCount.value = null;
    reconnectAttempt = 0;
    connectPresence();
  }

  async function copyInvitation(kind: "code" | "link") {
    if (!roomId.value) return;
    try {
      await navigator.clipboard.writeText(
        kind === "code" ? roomId.value : joinUrl.value,
      );
      copied.value = kind;
      copyError.value = "";
      if (copyFeedbackTimer) {
        clearTimeout(copyFeedbackTimer);
      }
      copyFeedbackTimer = setTimeout(() => {
        copied.value = null;
      }, 1600);
    } catch {
      copyError.value = "Could not copy. Select and copy the invitation below.";
      copied.value = null;
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
    if (copyFeedbackTimer) clearTimeout(copyFeedbackTimer);
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
      if (socket.value !== connection) return;
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
        if (message.type === "poll-state") {
          const wasPoll = poll.value;
          const hadPanelFocus = pollPanelRef.value?.contains(
            document.activeElement,
          );
          poll.value = message.poll ?? null;
          if (wasPoll && !poll.value && hadPanelFocus)
            nextTick(() => questionInput.value?.focus());
        }
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
    const options = pollOptions.value.map((option) => ({
      ...option,
      label: option.label.trim(),
    }));
    if (
      !question ||
      question.length > 240 ||
      options.some((option) => !option.label || option.label.length > 80)
    ) {
      pollError.value = "Add a question and fill in every answer.";
      return;
    }
    if (
      !Number.isInteger(pollDurationSeconds.value) ||
      pollDurationSeconds.value < 1 ||
      pollDurationSeconds.value > 86400
    ) {
      pollError.value = "Choose a duration between 1 and 86,400 seconds.";
      return;
    }
    if (!canStartPoll.value || socket.value?.readyState !== WebSocket.OPEN) {
      pollError.value =
        "Connect to the room and wait for a participant before starting.";
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

  async function togglePoll() {
    showPoll.value = !showPoll.value;
    await nextTick();
    if (showPoll.value) {
      if (poll.value) pollPanelRef.value?.focus({ preventScroll: true });
      else questionInput.value?.focus({ preventScroll: true });
      pollPanelRef.value?.scrollIntoView({
        behavior: "instant",
        block: "nearest",
      });
    } else pollToggle.value?.focus({ preventScroll: true });
  }

  async function requestNewRoom() {
    confirmNewRoom.value = true;
    await nextTick();
    keepRoomButton.value?.focus();
  }

  async function cancelNewRoom() {
    confirmNewRoom.value = false;
    await nextTick();
    newRoomButton.value?.focus();
  }

  async function createNewRoom() {
    regenerateRoom();
    confirmNewRoom.value = false;
    await nextTick();
    newRoomButton.value?.focus();
  }

  async function addAnswer() {
    if (pollOptions.value.length >= 12) return;
    const id = crypto.randomUUID();
    pollOptions.value.push({ id, label: "" });
    await nextTick();
    document.getElementById(`answer-${id}`)?.focus();
  }

  async function removeAnswer(index: number) {
    if (pollOptions.value.length <= 2) return;
    pollOptions.value.splice(index, 1);
    await nextTick();
    const next =
      pollOptions.value[Math.min(index, pollOptions.value.length - 1)];
    if (next) document.getElementById(`answer-${next.id}`)?.focus();
  }

  const totalVotes = computed(() =>
    Object.values(poll.value?.tally ?? {}).reduce(
      (sum, count) => sum + count,
      0,
    ),
  );
  function votePercent(optionId: string) {
    return totalVotes.value
      ? Math.round(
          ((poll.value?.tally?.[optionId] ?? 0) / totalVotes.value) * 100,
        )
      : 0;
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

  const pollProgress = computed(() => {
    if (!poll.value) return 0;
    const duration = Math.max(1, poll.value.endAt - poll.value.startAt);
    return Math.max(
      0,
      Math.min(1, (poll.value.endAt - pollNow.value) / duration),
    );
  });

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

  const appRoomUrl = computed(() => {
    if (!roomId.value) return "";
    return `peanutgallery://room/${encodeURIComponent(roomId.value)}`;
  });

  const connectedCountLabel = computed(() => {
    if (presenceState.value !== "connected") {
      return presenceState.value === "connecting"
        ? reconnectAttempt
          ? "Reconnecting…"
          : "Connecting…"
        : "Unable to connect. Retrying…";
    }
    if (connectedCount.value == null) {
      return "Connected · counting participants…";
    }
    return `${connectedCount.value} ${connectedCount.value === 1 ? "person" : "people"} connected`;
  });
</script>

<template>
  <section class="host-page">
    <header class="page-intro">
      <p class="eyebrow">Your audience starts here</p>
      <h1 class="page-heading">Your room is ready.</h1>
      <p>Share the invitation. Watch the reactions roll in.</p>
    </header>
    <div class="host-workspace" :class="{ 'with-poll': showPoll }">
      <div class="sharing-column">
        <div class="share-card">
          <div class="share-top">
            <h2>Invite your audience</h2>
            <span class="status" :class="presenceState" role="status">{{
              connectedCountLabel
            }}</span>
          </div>
          <div class="invitation">
            <div class="qr-block">
              <div class="qr-frame" :aria-busy="!qrLoaded && !qrFailed">
                <img
                  v-if="qrUrl && !qrFailed"
                  :src="qrUrl"
                  :alt="`Scan to join room ${roomId}`"
                  width="240"
                  height="240"
                  @load="qrLoaded = true"
                  @error="qrFailed = true"
                />
                <span v-if="qrFailed" class="qr-fallback"
                  >QR unavailable.<br />Use the invitation link instead.</span
                >
                <span v-else-if="!qrLoaded" class="qr-loading"
                  >Preparing QR…</span
                >
              </div>
              <p class="scan-hint">Scan to join. No sign-up needed.</p>
            </div>
            <div class="room-details">
              <p class="eyebrow">Room code</p>
              <p class="room-code">{{ roomId || "······" }}</p>
              <button
                class="copy-code"
                type="button"
                :disabled="!roomId"
                @click="copyInvitation('code')"
              >
                {{ copied === "code" ? "✓ Code copied" : "Copy room code" }}
              </button>
              <button
                class="button"
                type="button"
                :disabled="!joinUrl"
                @click="copyInvitation('link')"
              >
                {{
                  copied === "link"
                    ? "✓ Invite link copied"
                    : "Copy invite link"
                }}<span aria-hidden="true">↗</span>
              </button>
              <p class="device-hint">Presenting from your Mac?</p>
              <a v-if="appRoomUrl" class="app-link" :href="appRoomUrl"
                >Open Peanut Gallery app ↗</a
              >
            </div>
          </div>
          <div v-if="copyError" class="copy-fallback">
            <p class="error" role="alert">{{ copyError }}</p>
            <label class="field"
              >Invitation link<input
                :value="joinUrl"
                readonly
                @focus="($event.target as HTMLInputElement).select()"
            /></label>
          </div>
          <div class="share-bottom">
            <NuxtLink v-if="roomId" :to="`/join/${roomId}`"
              >Open reaction deck on this device ↗</NuxtLink
            >
          </div>
          <p class="sr-only" role="status">
            {{
              copied
                ? copied === "code"
                  ? "Room code copied"
                  : "Invite link copied"
                : ""
            }}
          </p>
        </div>
        <div class="host-tools">
          <div>
            <h2>Keep the room talking</h2>
            <p>Ask a question and let everyone vote.</p>
          </div>
          <button
            ref="pollToggle"
            class="button secondary"
            type="button"
            :aria-expanded="showPoll"
            aria-controls="poll-panel"
            @click="togglePoll"
          >
            {{ showPoll ? "Hide poll" : poll ? "View poll" : "Create poll" }}
          </button>
        </div>
        <div class="new-room-area">
          <button
            v-if="!confirmNewRoom"
            ref="newRoomButton"
            class="button quiet"
            type="button"
            @click="requestNewRoom"
          >
            Create a new room
          </button>
          <div v-else class="new-room-confirm">
            <p>
              Start fresh? People in this room will need a new invitation. An
              active poll stays in the previous room.
            </p>
            <div>
              <button
                class="button secondary"
                type="button"
                ref="keepRoomButton"
                @click="cancelNewRoom"
              >
                Keep this room</button
              ><button class="button" type="button" @click="createNewRoom">
                Create new room
              </button>
            </div>
          </div>
        </div>
      </div>
      <Transition name="panel">
        <section
          v-if="showPoll"
          id="poll-panel"
          ref="pollPanelRef"
          class="poll-panel"
          tabindex="-1"
          aria-labelledby="poll-heading"
        >
          <div class="poll-header">
            <p class="eyebrow">Audience poll</p>
            <h2 id="poll-heading">
              {{
                poll
                  ? poll.status === "active"
                    ? "The floor is theirs."
                    : "The results are in."
                  : "What do you want to ask?"
              }}
            </h2>
          </div>
          <form v-if="!poll" @submit.prevent="startPoll">
            <label class="field"
              >Question<textarea
                ref="questionInput"
                v-model="pollQuestion"
                maxlength="240"
                rows="2"
                placeholder="What should we do next?"
                required
              />
            </label>
            <fieldset>
              <legend>
                Answers <span>{{ pollOptions.length }}/12</span>
              </legend>
              <div
                v-for="(option, index) in pollOptions"
                :key="option.id"
                class="answer-row"
              >
                <label class="sr-only" :for="`answer-${option.id}`"
                  >Answer {{ index + 1 }}</label
                ><span class="answer-number" aria-hidden="true">{{
                  index + 1
                }}</span>
                <input
                  :id="`answer-${option.id}`"
                  v-model="option.label"
                  maxlength="80"
                  :placeholder="`Answer ${index + 1}`"
                  required
                />
                <button
                  class="remove-answer"
                  type="button"
                  :disabled="pollOptions.length <= 2"
                  :aria-label="`Remove answer ${index + 1}`"
                  @click="removeAnswer(index)"
                >
                  ×
                </button>
              </div>
              <button
                class="add-answer"
                type="button"
                :disabled="pollOptions.length >= 12"
                @click="addAnswer"
              >
                + Add answer
              </button>
            </fieldset>
            <label class="field duration-field"
              >Duration in seconds<input
                v-model.number="pollDurationSeconds"
                type="number"
                min="1"
                max="86400"
                step="1"
                required
            /></label>
            <p v-if="pollError" class="error" role="alert">{{ pollError }}</p>
            <button
              class="button start-poll"
              type="submit"
              :disabled="!canStartPoll"
            >
              Start poll ↗
            </button>
            <p v-if="!canStartPoll" class="waiting-note">
              {{
                presenceState === "connected"
                  ? "Ready when your first participant joins."
                  : "Connect to the room to start a poll."
              }}
            </p>
          </form>
          <div v-else class="poll-results">
            <h3>{{ poll.question }}</h3>
            <div class="poll-meta">
              <span>{{ pollTimeLabel }}</span
              ><span
                >{{ totalVotes }}
                {{ totalVotes === 1 ? "vote" : "votes" }}</span
              >
            </div>
            <div
              v-if="poll.status === 'active'"
              class="time-track"
              aria-hidden="true"
            >
              <span :style="{ transform: `scaleX(${pollProgress})` }" />
            </div>
            <ul>
              <li v-for="option in poll.options" :key="option.id">
                <div class="result-label">
                  <span>{{ option.label }}</span
                  ><strong
                    >{{ poll.tally?.[option.id] ?? 0 }}
                    <small>{{ votePercent(option.id) }}%</small></strong
                  >
                </div>
                <div class="result-track" aria-hidden="true">
                  <span
                    :style="{
                      transform: `scaleX(${votePercent(option.id) / 100})`,
                    }"
                  />
                </div>
              </li>
            </ul>
            <button
              v-if="poll.status === 'complete'"
              class="button secondary"
              type="button"
              :disabled="presenceState !== 'connected'"
              @click="dismissPoll"
            >
              Dismiss results
            </button>
          </div>
        </section>
      </Transition>
    </div>
  </section>
</template>

<style scoped>
  .host-page {
    width: 100%;
  }
  .page-intro {
    text-align: center;
    margin-bottom: 32px;
  }
  .page-heading {
    margin-top: 12px;
  }
  .page-intro > p:last-child {
    color: var(--muted);
    margin-top: 12px;
  }
  .host-workspace {
    display: grid;
    gap: 24px;
    max-width: 620px;
    margin-inline: auto;
    align-items: start;
  }
  .sharing-column {
    min-width: 0;
  }
  .share-card,
  .poll-panel {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 24px;
    box-shadow: 0 16px 40px #00000020;
  }
  .share-top {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 24px 28px 0;
  }
  .share-top h2 {
    font-size: 14px;
    font-weight: 650;
  }
  .invitation {
    display: grid;
    grid-template-columns: 1fr 1fr;
    align-items: center;
    gap: 28px;
    padding: 28px;
  }
  .qr-frame {
    position: relative;
    aspect-ratio: 1;
    width: 100%;
    padding: 12px;
    border-radius: 16px;
    background: #fff;
    display: grid;
    place-items: center;
  }
  .qr-frame img {
    width: 100%;
    height: auto;
    position: relative;
    z-index: 1;
    color: #17130f;
  }
  .qr-loading {
    position: absolute;
    color: #514237;
    font-size: 12px;
  }
  .qr-fallback {
    color: #514237;
    text-align: center;
    font-size: 13px;
  }
  .scan-hint {
    font-size: 11px;
    color: var(--muted);
    margin-top: 12px;
    text-align: center;
  }
  .room-details {
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
  }
  .room-details .eyebrow {
    color: var(--muted);
    font-size: 10px;
  }
  .room-code {
    font-family: ui-monospace, monospace;
    font-size: clamp(24px, 3.3vw, 38px);
    font-weight: 800;
    letter-spacing: 0.04em;
    line-height: 1.4;
    margin-top: 6px;
    color: var(--accent);
    user-select: all;
  }
  .copy-code {
    border: 0;
    background: transparent;
    color: var(--muted);
    min-height: 44px;
    font-size: 12px;
    padding: 0;
    margin-bottom: 12px;
    text-decoration: underline;
    text-underline-offset: 4px;
  }
  .room-details .button {
    width: 100%;
    font-size: 14px;
  }
  .device-hint {
    color: var(--muted);
    font-size: 11px;
    margin-top: 20px;
  }
  .app-link {
    font-size: 12px;
    line-height: 1.6;
    padding-block: 8px;
  }
  .share-bottom {
    padding: 16px 24px;
    border-top: 1px solid var(--border);
    text-align: center;
  }
  .share-bottom a {
    display: inline-block;
    padding: 8px;
    font-size: 12px;
    color: var(--muted);
    text-underline-offset: 4px;
  }
  .copy-fallback {
    display: grid;
    gap: 12px;
    padding: 0 28px 24px;
  }
  .host-tools {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 16px;
    padding: 24px 4px;
  }
  .host-tools h2 {
    font-size: 15px;
    font-weight: 700;
  }
  .host-tools p {
    font-size: 12px;
    color: var(--muted);
    margin-top: 6px;
  }
  .host-tools .button {
    flex: none;
    font-size: 13px;
  }
  .new-room-area {
    border-top: 1px solid var(--border);
    padding-top: 8px;
  }
  .new-room-area > .button {
    font-size: 12px;
  }
  .new-room-confirm {
    padding: 16px 4px;
  }
  .new-room-confirm p {
    font-size: 13px;
    color: var(--muted);
  }
  .new-room-confirm > div {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    margin-top: 16px;
  }
  .poll-panel {
    padding: 28px;
    min-width: 0;
  }
  .poll-header h2 {
    font-size: 23px;
    font-weight: 750;
    line-height: 1.3;
    margin: 10px 0 24px;
    letter-spacing: -0.04em;
  }
  form {
    display: grid;
    gap: 22px;
  }
  fieldset {
    border: 0;
    margin: 0;
    padding: 0;
    min-width: 0;
  }
  legend {
    color: var(--muted);
    font-size: 13px;
    font-weight: 650;
    width: 100%;
    margin-bottom: 10px;
  }
  legend span {
    float: right;
    font-size: 11px;
  }
  .answer-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
  }
  .answer-number {
    color: var(--muted);
    font-size: 12px;
    width: 16px;
    flex: none;
  }
  .answer-row input {
    flex: 1;
  }
  .remove-answer {
    width: 44px;
    min-height: 44px;
    background: transparent;
    border: 0;
    color: var(--muted);
    font-size: 24px;
    flex: none;
    border-radius: 8px;
  }
  .add-answer {
    min-height: 44px;
    color: var(--accent);
    border: 0;
    background: transparent;
    font-size: 13px;
  }
  .duration-field {
    max-width: 180px;
  }
  .start-poll {
    width: 100%;
  }
  .waiting-note {
    font-size: 12px;
    text-align: center;
    color: var(--muted);
    margin-top: -10px;
  }
  .poll-results h3 {
    font-size: 22px;
    overflow-wrap: anywhere;
    margin: 0 0 18px;
    line-height: 1.4;
  }
  .poll-meta {
    display: flex;
    gap: 12px;
    justify-content: space-between;
    color: var(--muted);
    font-size: 12px;
    font-variant-numeric: tabular-nums;
  }
  .time-track,
  .result-track {
    height: 4px;
    background: var(--border);
    border-radius: 8px;
    overflow: hidden;
    margin-top: 12px;
  }
  .time-track > span,
  .result-track > span {
    display: block;
    height: 100%;
    width: 100%;
    background: var(--accent);
    transform-origin: left;
  }
  .poll-results ul {
    padding: 0;
    margin: 24px 0;
    list-style: none;
    display: grid;
    gap: 20px;
  }
  .result-label {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    font-size: 14px;
  }
  .result-label > span {
    overflow-wrap: anywhere;
    min-width: 0;
  }
  .result-label strong {
    flex: none;
    font-variant-numeric: tabular-nums;
  }
  .result-label small {
    color: var(--muted);
    font-size: 11px;
    font-weight: 400;
    margin-left: 6px;
  }
  .result-track {
    height: 6px;
  }
  @media (min-width: 1000px) {
    .host-workspace.with-poll {
      max-width: 1120px;
      grid-template-columns: 620px minmax(0, 1fr);
    }
  }
  @media (max-width: 580px) {
    .share-top {
      padding: 22px 20px 0;
    }
    .invitation {
      grid-template-columns: 1fr;
      padding: 24px 20px;
      gap: 24px;
    }
    .qr-block {
      width: min(240px, 100%);
      margin-inline: auto;
    }
    .room-details {
      align-items: center;
    }
    .room-code {
      font-size: 38px;
    }
    .device-hint {
      margin-top: 18px;
    }
    .room-details .button {
      max-width: 280px;
    }
    .host-tools {
      flex-wrap: wrap;
    }
    .poll-panel {
      padding: 24px 20px;
    }
  }
</style>
