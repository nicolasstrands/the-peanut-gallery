<script setup lang="ts">
  useSeoMeta({
    title: "Create Room",
    description:
      "Generate a room code and QR link so your audience can instantly join and send reactions.",
  });

  const roomId = ref("");
  const joinUrl = ref("");
  const copied = ref(false);
  let copyFeedbackTimer: ReturnType<typeof setTimeout> | null = null;

  function generateRoomId(length = 6): string {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const bytes = new Uint8Array(length);
    crypto.getRandomValues(bytes);

    return Array.from(bytes, (byte) => chars[byte % chars.length]).join("");
  }

  function regenerateRoom() {
    roomId.value = generateRoomId(6);
    joinUrl.value = `${window.location.origin}/join/${roomId.value}`;
    copied.value = false;
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
  });

  const qrUrl = computed(() => {
    if (!joinUrl.value) return "";
    return `https://api.qrserver.com/v1/create-qr-code/?size=360x360&data=${encodeURIComponent(joinUrl.value)}`;
  });
</script>

<template>
  <section>
    <h1>Your room <wbr />is live.</h1>
    <p>Anyone scanning this QR code can open the reaction deck instantly.</p>

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
      <NuxtLink :to="`/join/${roomId}`">Open deck on this device</NuxtLink>
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
    @apply w-70 h-auto rounded-lg bg-white border-white border-20 mx-auto;
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
    margin: 32px auto 0;
    width: min(420px, 100%);
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
    font-size: clamp(34px, 9vw, 56px);
    line-height: 1;
    font-weight: 900;
    letter-spacing: 0.12em;
    color: #f6b73c;
  }
  .code-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    margin-top: 6px;
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
    margin-top: 18px;
    color: #f6b73c;
    text-decoration: none;
    font-weight: 700;
  }
  a:hover {
    text-decoration: underline;
  }
</style>
