<script setup lang="ts">
  function useKeyboard() {
    document.documentElement.dataset.input = "keyboard";
  }
  function usePointer() {
    document.documentElement.dataset.input = "pointer";
  }
  onMounted(() => {
    document.addEventListener("keydown", useKeyboard);
    document.addEventListener("pointerdown", usePointer);
  });
  onBeforeUnmount(() => {
    document.removeEventListener("keydown", useKeyboard);
    document.removeEventListener("pointerdown", usePointer);
  });
  const siteTitle = "The Peanut Gallery";
  const siteDescription =
    "Live audience reactions in real time. Create a room, share a link, and let your crowd react instantly.";

  useHead({
    titleTemplate: (titleChunk) => {
      if (!titleChunk || titleChunk === siteTitle) return siteTitle;
      return `${titleChunk} | ${siteTitle}`;
    },
  });

  useSeoMeta({
    applicationName: siteTitle,
    description: siteDescription,
    ogSiteName: siteTitle,
    ogDescription: siteDescription,
    twitterCard: "summary",
  });
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
