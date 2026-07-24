import { DurableObject } from 'cloudflare:workers'

export interface Env { ROOMS: DurableObjectNamespace<ReactionRoom> }

export class ReactionRoom extends DurableObject<Env> {
  async fetch(request: Request) {
    if (request.headers.get('Upgrade') !== 'websocket') return new Response('Expected WebSocket', { status: 426 })
    const pair = new WebSocketPair()
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket]
    this.ctx.acceptWebSocket(server)
    return new Response(null, { status: 101, webSocket: client })
  }

  webSocketMessage(_ws: WebSocket, message: string | ArrayBuffer) {
    // TODO: validate against packages/protocol, rate-limit, then broadcast.
    // getWebSockets() is hibernation-safe; an in-memory Set would be reset
    // when Cloudflare hibernates this Durable Object.
    for (const session of this.ctx.getWebSockets()) session.send(message)
  }

  webSocketClose(_ws: WebSocket) {}
}

export default {
  async fetch(request: Request, env: Env) {
    const roomId = new URL(request.url).pathname.split('/').filter(Boolean).pop() ?? 'default'
    const id = env.ROOMS.idFromName(roomId)
    return env.ROOMS.get(id).fetch(request)
  }
}
