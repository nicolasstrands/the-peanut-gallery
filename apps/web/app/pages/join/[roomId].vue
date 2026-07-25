<script setup lang="ts">
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
  const connectionState = ref<
    "connecting" | "connected" | "disconnected" | "error"
  >("connecting");
  const socket = ref<WebSocket | null>(null);

  const roomId = computed(() => String(route.params.roomId ?? ""));
  const config = useRuntimeConfig();
  const realtimeUrl = config.public.realtimeUrl || "ws://localhost:8787";

  onMounted(() => {
    customEmoji.value = localStorage.getItem(customEmojiStorageKey) ?? "";

    if (!roomId.value) {
      connectionState.value = "error";
      return;
    }

    const url = `${realtimeUrl.replace(/^http/, "ws")}/rooms/${encodeURIComponent(roomId.value)}`;
    const connection = new WebSocket(url);
    socket.value = connection;

    connection.addEventListener("open", () => {
      connectionState.value = "connected";
      connection.send(
        JSON.stringify({
          type: "join-room",
          roomId: roomId.value,
          clientType: "web",
        }),
      );
    });

    connection.addEventListener("message", (event) => {
      try {
        const message = JSON.parse(String(event.data)) as {
          type?: string;
          emoji?: string;
        };
        if (message.type === "reaction" && typeof message.emoji === "string") {
          sent.value.unshift(message.emoji);
          if (sent.value.length > 8) sent.value.pop();
        }
      } catch {
        // Ignore malformed messages from the server.
      }
    });

    connection.addEventListener("close", () => {
      connectionState.value = "disconnected";
    });

    connection.addEventListener("error", () => {
      connectionState.value = "error";
    });
  });

  onBeforeUnmount(() => {
    socket.value?.close();
    socket.value = null;
  });

  function react(emoji: string) {
    if (socket.value?.readyState !== WebSocket.OPEN) return;

    socket.value.send(
      JSON.stringify({
        type: "reaction",
        reactionId: crypto.randomUUID(),
        emoji,
        sentAt: Date.now(),
      }),
    );
  }

  function useCustomReaction() {
    if (customEmoji.value) {
      react(customEmoji.value);
      return;
    }

    const emoji = window.prompt("Enter a custom emoji")?.trim();
    if (emoji) {
      customEmoji.value = emoji;
      localStorage.setItem(customEmojiStorageKey, emoji);
    }
  }

  function resetCustomReaction() {
    customEmoji.value = "";
    localStorage.removeItem(customEmojiStorageKey);
  }
</script>

<template>
  <section>
    <h1>Make some noise!</h1>
    <p>Tap a reaction. Spam responsibly.</p>
    <p class="connection" :class="connectionState">
      <span class="dot" />
      {{
        connectionState === "connected"
          ? "Connected"
          : connectionState === "connecting"
            ? "Connecting…"
            : connectionState === "error"
              ? "Unable to connect"
              : "Disconnected"
      }}
    </p>
    <div class="grid">
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
  .grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
    margin-top: 32px;
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
  .recent {
    display: none;
    gap: 10px;
    margin-top: 32px;
    min-height: 36px;
    font-size: 24px;
  }
</style>
