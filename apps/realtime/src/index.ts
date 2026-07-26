import { DurableObject } from 'cloudflare:workers'
import type { ClientMessage, LeaderboardMessage, ReactionMessage } from '@peanut-gallery/protocol'

export interface Env { ROOMS: DurableObjectNamespace<ReactionRoom> }

export class ReactionRoom extends DurableObject<Env> {
  private counts: Record<string, number> = {}
  private readonly countsLoaded: Promise<void>

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env)
    this.countsLoaded = ctx.storage.get<Record<string, number>>('leaderboard').then((counts) => {
      if (counts) this.counts = counts
    })
  }

  async fetch(request: Request) {
    if (request.headers.get('Upgrade') !== 'websocket') return new Response('Expected WebSocket', { status: 426 })
    const pair = new WebSocketPair()
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket]
    this.ctx.acceptWebSocket(server)
    return new Response(null, { status: 101, webSocket: client })
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    await this.countsLoaded
    if (typeof message !== 'string') return

    let parsed: ClientMessage
    try {
      parsed = JSON.parse(message) as ClientMessage
    } catch {
      return
    }

    if (parsed.type === 'join-room') {
      this.sendLeaderboard(ws)
      return
    }

    if (parsed.type !== 'reaction' || !this.isValidReaction(parsed)) return

    this.counts[parsed.emoji] = (this.counts[parsed.emoji] ?? 0) + 1
    await this.ctx.storage.put('leaderboard', this.counts)

    // getWebSockets() is hibernation-safe; an in-memory Set would be reset
    // when Cloudflare hibernates this Durable Object.
    for (const session of this.ctx.getWebSockets()) {
      session.send(message)
      this.sendLeaderboard(session)
    }
  }

  webSocketClose(_ws: WebSocket) {}

  private sendLeaderboard(ws: WebSocket) {
    const message: LeaderboardMessage = { type: 'leaderboard', counts: this.counts }
    ws.send(JSON.stringify(message))
  }

  private isValidReaction(message: ClientMessage): message is ReactionMessage {
    return message.type === 'reaction' &&
      typeof message.emoji === 'string' &&
      message.emoji.trim().length > 0 &&
      message.emoji.length <= 32
  }
}

export default {
  async fetch(request: Request, env: Env) {
    const roomId = new URL(request.url).pathname.split('/').filter(Boolean).pop() ?? 'default'
    const id = env.ROOMS.idFromName(roomId)
    return env.ROOMS.get(id).fetch(request)
  }
}
