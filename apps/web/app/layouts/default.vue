<template>
  <div class="layout-root">
    <a class="skip-link" href="#main">Skip to content</a>
    <Header />
    <main id="main" class="layout-body" tabindex="-1"><slot /></main>
    <footer class="site-footer">A little audience energy.</footer>
  </div>
</template>

<style scoped>
  .layout-root {
    min-height: 100svh;
    display: flex;
    flex-direction: column;
    padding-inline: max(20px, env(safe-area-inset-left))
      max(20px, env(safe-area-inset-right));
  }
  .layout-body {
    width: 100%;
    max-width: 1120px;
    margin: auto;
    padding-block: clamp(24px, 5vh, 64px);
    flex: 1;
    display: grid;
    align-content: center;
    min-width: 0;
  }
  .site-footer {
    text-align: center;
    color: var(--muted);
    font-size: 12px;
    padding: 24px 0 max(24px, env(safe-area-inset-bottom));
  }
  .skip-link {
    position: fixed;
    top: 8px;
    left: 8px;
    transform: translateY(-150%);
    z-index: 100;
    padding: 12px;
    background: var(--accent);
    color: var(--canvas);
    border-radius: 8px;
  }
  .skip-link:focus {
    transform: none;
  }
</style>
