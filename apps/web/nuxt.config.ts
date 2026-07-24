import tailwindcss from "@tailwindcss/vite";

export default defineNuxtConfig({
  compatibilityDate: "2026-07-24",
  devtools: { enabled: true },
  typescript: { strict: true },
  app: {
    viewTransition: true,
    head: {
      meta: [
        {
          name: "viewport",
          content:
            "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no",
        },
      ],
      link: [{ rel: "icon", type: "image/png", href: "/favicon.png" }],
    },
  },
  css: ["~/assets/css/main.css"],
  runtimeConfig: {
    public: {
      realtimeUrl:
        process.env.NUXT_PUBLIC_REALTIME_URL ||
        "wss://gallerybutter.arcodelabs.com",
    },
  },
  nitro: {
    preset: "cloudflare_module",
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
