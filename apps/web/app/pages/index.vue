<script setup lang="ts">
  useSeoMeta({
    title: "The Peanut Gallery",
    description:
      "Create a live reaction room in seconds and let your audience send emoji to your screen in real time.",
  });
  const isHomeHeroMounted = useState<boolean>("home-hero-mounted", () => false);
  const requestURL = useRequestURL();
  const showStrandsLogo = computed(
    () => requestURL.hostname === "peanutgallery.arcodelabs.com",
  );

  onMounted(() => {
    isHomeHeroMounted.value = true;
  });

  onBeforeUnmount(() => {
    isHomeHeroMounted.value = false;
  });
</script>

<template>
  <img
    v-if="showStrandsLogo"
    class="h-auto w-30"
    src="/strands.svg"
    alt="strands-logo" />
  <h1>
    Welcome to<br />
    <span
      class="title-letters gallery-title-shared"
      aria-label="The Peanut Gallery"
      ><span class="letter">T</span><span class="letter">h</span
      ><span class="letter">e</span> <span class="letter">P</span
      ><span class="letter">e</span><span class="letter">a</span
      ><span class="letter">n</span><span class="letter">u</span
      ><span class="letter">t</span> <span class="letter">G</span
      ><span class="letter">a</span><span class="letter">l</span
      ><span class="letter">l</span><span class="letter">e</span
      ><span class="letter">r</span><span class="letter">y</span></span
    >
  </h1>
  <p class="lede">
    Open a room, share the link, and let your audience<wbr /> throw reactions
    across your screen.
  </p>
  <NuxtLink class="create-room" to="/create-room" view-transition>
    Create a room
  </NuxtLink>
</template>

<style scoped>
  @reference "../assets/css/main.css";
  :global(body) {
    @apply m-0 bg-[#17130f] text-[#fff4df] font-sans;
  }
  .shell {
    @apply mx-auto max-w-190 flex flex-col items-center justify-center;
  }
  .eyebrow {
    @apply text-xs font-extrabold uppercase tracking-[0.18em] text-peanut-gallery;
  }
  h1 {
    @apply my-6 font-display text-3xl md:text-7xl leading-[0.95] tracking-[-0.06em] text-center;
  }
  h1 span {
    @apply text-peanut-gallery;
  }
  h1 .title-letters {
    @apply inline-block;
    paint-order: stroke fill;
    letter-spacing: -0.12ch;
    -webkit-text-stroke: 5px black;
    text-shadow: 4px 4px black;
  }
  h1 .letter {
    @apply inline-block;
    transform-origin: 50% 70%;
  }
  h1 .letter:nth-child(odd) {
    transform: rotate(-2deg);
  }
  h1 .letter:nth-child(even) {
    transform: rotate(2deg);
  }
  .lede {
    @apply max-w-120 text-[19px] leading-normal text-center;
  }
  .create-room {
    @apply transition-all duration-200 ease-in-out;
    @apply rounded-2xl px-6 py-4 text-base;
    @apply mt-9.5;
    @apply cursor-pointer bg-peanut-gallery font-extrabold text-black border-b-amber-700 border-b-8;
    @apply active:border-b-0 active:translate-y-1.5;
    @apply inline-block no-underline;
  }
  .hint {
    @apply mt-4.5 text-[#8e8273];
  }
  a {
    @apply text-peanut-gallery;
  }
</style>
