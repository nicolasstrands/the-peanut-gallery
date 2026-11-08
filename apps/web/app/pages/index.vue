<script setup lang="ts">
  const requestURL = useRequestURL();
  const showStrandsLogo = computed(
    () => requestURL.hostname === "peanutgallery.arcodelabs.com",
  );
  useSeoMeta({
    title: "The Peanut Gallery",
    description:
      "Create a live reaction room in seconds and let your audience send emoji to your screen in real time.",
  });
</script>

<template>
  <section class="home">
    <img
      v-if="showStrandsLogo"
      class="strands-logo"
      src="/strands.svg"
      alt="Strands"
      width="100"
      height="32"
    />
    <p class="eyebrow">Give your audience a voice</p>
    <h1><span class="welcome">Welcome to</span><Wordmark hero /></h1>
    <p class="lede">
      Open a room. Share the link. Let your audience throw a little energy
      across your screen.
    </p>
    <NuxtLink class="button create-room" to="/create-room"
      >Create a room <span aria-hidden="true">↗</span></NuxtLink
    >
    <p class="hint">No audience sign-up. Just scan and react.</p>
    <div class="preview" aria-hidden="true">
      <span>🔥</span><span>👏</span><span>😂</span><span>❤️</span>
    </div>
    <p class="how">One shared link. Every reaction, live on your Mac.</p>
  </section>
</template>

<style scoped>
  .strands-logo {
    display: block;
    width: 100px;
    height: auto;
    margin: 0 auto 24px;
  }
  .home {
    text-align: center;
    max-width: 850px;
    margin-inline: auto;
  }
  h1 {
    display: grid;
    gap: 12px;
    margin: 24px 0;
  }
  .welcome {
    font-family: "Balsamiq Sans", sans-serif;
    font-size: clamp(24px, 4vw, 32px);
    color: var(--text);
  }
  .lede {
    max-width: 470px;
    margin-inline: auto;
    color: var(--muted);
    font-size: 18px;
    text-wrap: pretty;
  }
  .create-room {
    margin-top: 28px;
    padding-inline: 28px;
    box-shadow: 0 4px 0 #92601c;
  }
  .hint {
    color: var(--muted);
    font-size: 12px;
    margin-top: 18px;
  }
  .preview {
    display: flex;
    justify-content: center;
    gap: 12px;
    margin-top: 48px;
  }
  .preview span {
    display: grid;
    place-items: center;
    width: 58px;
    height: 58px;
    font-size: 30px;
    border-radius: 16px;
    background: var(--surface);
    border: 1px solid var(--border);
    box-shadow: 0 4px 0 #0d0a08;
  }
  .preview span:nth-child(odd) {
    transform: rotate(-5deg);
  }
  .preview span:nth-child(even) {
    transform: rotate(5deg);
  }
  .how {
    color: var(--muted);
    font-size: 12px;
    margin-top: 18px;
  }
</style>
