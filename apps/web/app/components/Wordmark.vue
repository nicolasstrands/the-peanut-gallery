<script setup lang="ts">
  defineProps<{ hero?: boolean }>();
  const words = ["The", "Peanut", "Gallery"];
</script>

<template>
  <span
    class="wordmark"
    :class="{ hero }"
    role="img"
    aria-label="The Peanut Gallery"
  >
    <span v-for="word in words" :key="word" class="word" aria-hidden="true">
      <span v-for="(letter, index) in word" :key="index" class="letter">{{
        letter
      }}</span>
    </span>
  </span>
</template>

<style scoped>
  .wordmark {
    display: inline-flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 0.22em;
    color: var(--accent);
    font-family: var(--font-display);
    font-size: clamp(18px, 4.6vw, 27px);
    line-height: 1.25;
    letter-spacing: -0.09em;
  }
  .word {
    white-space: nowrap;
  }
  .word:nth-child(2) {
    color: var(--text);
  }
  .letter {
    display: inline-block;
    paint-order: stroke fill;
    -webkit-text-stroke: 3px #090705;
    text-shadow: 2px 3px #090705;
  }
  .letter:nth-child(odd) {
    transform: rotate(-2deg);
  }
  .letter:nth-child(even) {
    transform: rotate(2deg);
  }
  .hero {
    font-size: clamp(38px, 8vw, 82px);
    column-gap: 0.25em;
    row-gap: 0;
    line-height: 1.05;
  }
  .hero .letter {
    -webkit-text-stroke-width: 5px;
    text-shadow: 3px 5px #090705;
  }
</style>
