<template>
  <header class="site-header">
    <NuxtLink to="/" class="brand-link" aria-label="Peanut Gallery home"
      ><Wordmark
    /></NuxtLink>
  </header>
</template>

<style scoped>
  .site-header {
    display: flex;
    justify-content: center;
    padding-block: 28px;
  }
  .brand-link {
    display: inline-flex;
    text-decoration: none;
    border-radius: 8px;
  }
  @media (max-width: 520px) {
    .site-header {
      padding-block: 24px;
    }
  }
</style>
