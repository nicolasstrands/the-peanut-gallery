# Peanut Gallery

Realtime emoji reactions from a shareable web reaction deck to a native macOS desktop overlay.

## Monorepo

- `apps/web` — Nuxt 4 reaction deck and host UI
- `apps/realtime` — Cloudflare Worker + one Durable Object per room
- `apps/macos-overlay` — native Swift/AppKit menu-bar app scaffold
- `packages/protocol` — shared realtime message contract

## Getting started

```bash
pnpm install
pnpm dev:web
```

From the repository root, you can run:

```bash
pnpm dev:web        # Nuxt reaction deck
pnpm dev:realtime   # Cloudflare Worker locally
pnpm deploy:realtime # Deploy the realtime Worker
pnpm build:web      # Build the Nuxt app
pnpm deploy:web     # Build and deploy the Nuxt app to Cloudflare Workers
pnpm build:macos   # Build the SwiftPM macOS app
pnpm run:macos     # Run the native overlay
pnpm package:macos # Create an unsigned .app and ZIP in dist/
pnpm clean:macos   # Remove SwiftPM build artifacts
```

The web app runs without a backend in local demo mode. The realtime Worker can be developed with Wrangler once Cloudflare bindings are configured. `pnpm dev` still runs the JavaScript workspace tasks through Turborepo.

Production URLs:

- Web reaction deck: `https://peanutgallery.arcodelabs.com`
- Realtime WebSocket: `wss://gallerybutter.arcodelabs.com`

The current deployed realtime endpoint is:

```text
wss://gallerybutter.arcodelabs.com
```

Set `NUXT_PUBLIC_REALTIME_URL` to override it for local development or another deployment.

## Cloudflare setup

Create a D1 database and configure the IDs in `apps/realtime/wrangler.jsonc`. Deploy with `wrangler deploy` from `apps/realtime`.

## macOS overlay

The overlay has no endpoint compiled into it. It asks for a realtime server on
first launch, and the same dialog stays available from the menu bar under **Set
Realtime Server…**, so one machine can point at any deployment without a rebuild.

Paste either the `wss://` endpoint or the `https://` URL Wrangler prints on
deploy — the scheme is normalised for you. Bare hosts (`my-worker.example.workers.dev`)
and `localhost:8787` work too, the latter defaulting to `ws://` rather than `wss://`.

The address is stored in `UserDefaults` under `peanutGallery.realtimeURL`. Saving
a new server reconnects the current room immediately. The menu bar shows the
active server and connection state, abbreviating `workers.dev` addresses to their
account subdomain to keep the menu narrow; the full address is in the dialog.

For local development, an environment variable takes precedence over the saved
value:

```bash
PEANUT_GALLERY_REALTIME_URL=ws://localhost:8787 pnpm run:macos
```

While it is set the dialog is read-only and says the environment is in control,
rather than silently discarding what you type.

## GitHub Actions

The repository includes three workflows under `.github/workflows/`:

- `deploy-realtime.yml` deploys the realtime Worker when relevant changes land on `main`.
- `deploy-web.yml` builds and deploys the Nuxt app when relevant changes land on `main`.
- `macos-release.yml` packages the unsigned macOS app and publishes it to a GitHub Release for tags such as `v0.1.0`.

Create a GitHub Actions environment named `production`, then add these environment secrets:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
```

The Cloudflare token should be scoped to the account and have permission to deploy Workers. macOS releases are currently unsigned and do not require Apple credentials. To publish one:

```bash
git tag v0.1.0
git push origin v0.1.0
```
