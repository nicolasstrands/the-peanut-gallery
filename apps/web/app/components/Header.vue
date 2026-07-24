<script setup lang="ts">
  const route = useRoute();
</script>

<template>
  <header class="header-shell">
    <NuxtLink v-if="route.path !== '/'" to="/" class="logo" view-transition>
      <h1>
        <span
          class="title-letters gallery-title-shared"
          aria-label="The Peanut Gallery"
          ><span class="letter">T</span><span class="letter">h</span
          ><span class="letter">e</span>
          <span class="letter letter-white">P</span
          ><span class="letter letter-white">e</span
          ><span class="letter letter-white">a</span
          ><span class="letter letter-white">n</span
          ><span class="letter letter-white">u</span
          ><span class="letter letter-white">t</span>
          <span class="letter">G</span><span class="letter">a</span
          ><span class="letter">l</span><span class="letter">l</span
          ><span class="letter">e</span><span class="letter">r</span
          ><span class="letter">y</span></span
        >
      </h1>
    </NuxtLink>
    <!-- <nav class="header-nav" aria-label="Primary">
      <NuxtLink to="/create-room">Create Room</NuxtLink>
    </nav> -->
  </header>
</template>

<style>
  @reference "../assets/css/main.css";
  .header-shell {
    @apply mx-auto max-w-190 px-4 pt-4 pb-1 flex items-center justify-center gap-5;
  }
  h1 {
    @apply my-0 font-display text-3xl leading-[0.95] tracking-[-0.06em] text-center;
  }
  h1 .title-letters {
    @apply inline-block;
    paint-order: stroke fill;
    letter-spacing: -0.12ch;
    -webkit-text-stroke: 3px black;
    text-shadow: 4px 4px black;
  }
  h1 .letter {
    @apply inline-block;
    transform-origin: 50% 70%;
    @apply text-peanut-gallery;
  }

  h1 .letter.letter-white {
    @apply text-white;
  }
  h1 .letter:nth-child(odd) {
    transform: rotate(-2deg);
  }
  h1 .letter:nth-child(even) {
    transform: rotate(2deg);
  }
  .header-nav {
    @apply flex items-center gap-2.5;
  }
  .header-nav a {
    @apply text-sm text-[#fff4df] no-underline font-bold border border-[#3b3028] rounded-full px-4 py-2;
    background: #241e1a;
  }
  .header-nav a:hover,
  .header-nav a.router-link-active {
    @apply text-black;
    background: #f6b73c;
    border-color: #f6b73c;
  }
</style>
