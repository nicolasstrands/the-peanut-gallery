<template>
  <div class="layout-root">
    <Header class="layout-header" />
    <section class="layout-body">
      <main class="shell">
        <slot />
      </main>
    </section>
  </div>
</template>

<style scoped>
  @reference "../assets/css/main.css";
  :global(body) {
    @apply m-0 bg-[#17130f] text-[#fff4df] font-sans;
  }
  .layout-root {
    @apply min-h-screen relative px-6;
  }
  .layout-header {
    @apply absolute top-0 left-0 right-0 z-50;
  }
  .layout-body {
    @apply w-full min-h-screen flex items-center justify-center;
  }
  .shell {
    @apply mx-auto max-w-190 flex flex-col items-center justify-center;
  }
</style>
