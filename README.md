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

Set `NUXT_PUBLIC_REALTIME_URL` to override the realtime endpoint for local development or another deployment.

## Cloudflare setup

Everything runs on two Workers in a single Cloudflare account. The Workers free plan
is enough: Durable Objects here use the SQLite backend, which is free-tier eligible.

### 1. Authenticate

```bash
npx wrangler login
```

### 2. Create the D1 database

```bash
npx wrangler d1 create peanut-gallery
```

The binding in `apps/realtime/wrangler.jsonc` deliberately omits `database_id`,
so Wrangler resolves it against your own account on deploy and no one's database
ID has to live in the repository. The binding is declared but not yet read by the
Worker — it exists so room persistence can be added without a config change.

### 3. Deploy the realtime Worker

```bash
pnpm deploy:realtime
```

Wrangler prints the deployed URL, e.g.
`https://peanut-gallery-realtime.<your-subdomain>.workers.dev`. The WebSocket
endpoint is the same host with the `wss://` scheme.

### 4. Point the web app at your realtime Worker

Copy `apps/web/.env.example` to `apps/web/.env` and set that `wss://` URL:

```bash
NUXT_PUBLIC_REALTIME_URL=wss://peanut-gallery-realtime.<your-subdomain>.workers.dev
```

Nuxt reads `.env` at build time, and `.env` is gitignored, so your endpoint
never reaches a versioned file. Point it at `ws://localhost:8787` to develop
against a local `pnpm dev:realtime`.

CI does not read `.env`. Set `NUXT_PUBLIC_REALTIME_URL` in the workflow
environment, or the build falls back to the default in `nuxt.config.ts`.

### 5. Deploy the web app

```bash
pnpm deploy:web
```

A first deploy to a fresh `workers.dev` subdomain can return `error code: 1042`
for up to a minute while the route propagates. Retry before debugging.

### 6. Point the macOS overlay at your realtime Worker

Nothing to configure at build time. The macOS app defaults to the production
Arcodelabs endpoints, and self-hosting lives behind a developer toggle in
Settings — see [macOS overlay](#macos-overlay) below.

### Custom domains (optional)

With the zone on the same Cloudflare account, add a route in each Worker's
config, then redeploy:

```jsonc
// apps/realtime/wrangler.jsonc
"routes": [{ "pattern": "realtime.example.com", "custom_domain": true }]
```

Update `NUXT_PUBLIC_REALTIME_URL` to match, and set the new address in the
overlay's **Set Realtime Server…** dialog.

deploy — the scheme is normalised for you. Bare hosts (`my-worker.example.workers.dev`)

## macOS overlay

The overlay now ships with the production endpoints built in:

- Web reaction deck: `https://peanutgallery.arcodelabs.com`
- Realtime WebSocket: `wss://gallerybutter.arcodelabs.com`

That means a normal install can launch and join a room immediately without any
manual setup. If you need local development or a self-hosted deployment, open
**Settings…** from the menu bar and enable **Developer mode** to reveal the
custom realtime server and web UI overrides.

Paste either the `wss://` endpoint or the `https://` URL Wrangler prints on
deploy — the scheme is normalised for you. Bare hosts (`my-worker.example.workers.dev`)
and `localhost:8787` work too, the latter defaulting to `ws://` rather than `wss://`.

Developer overrides are stored in `UserDefaults` under `peanutGallery.realtimeURL`
and `peanutGallery.webURL`. Turning developer mode off switches back to the
Arcodelabs defaults without deleting the saved self-hosted values. The menu bar
shows the active server and connection state, abbreviating `workers.dev`
addresses to their account subdomain to keep the menu narrow; the full address
is in the dialog.

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

Because the macOS app is currently unsigned and un-notarized, Gatekeeper may block it on first launch. After unzipping the release artifact, run:

```bash
xattr -dr com.apple.quarantine PeanutGallery.app
```
